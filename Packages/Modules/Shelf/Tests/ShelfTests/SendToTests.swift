import Foundation
import ModuleKit
import Synchronization
import Testing
import UniformTypeIdentifiers
import VigieUI

@testable import Shelf

@MainActor @Suite struct SendToTests {
    /// An Ask AI-like zone of another module (the shape `agents.sessions` declares).
    static func askSummary(enabled: Bool = true, module: ModuleID = "agents.sessions") -> DropZoneSummary {
        let zone = DropZone(
            id: "agents.sessions.ask", label: "ASK AI", glyph: "plus", accentToken: "iris-2", role: .secondary,
            cell: DropCell(preferredColumn: 3, preferredRow: 1, span: .init(columns: 1, rows: 2)), order: 10,
            accepts: [.item], handler: { _ in .accepted }, releaseLine: "RELEASE TO ASK",
            modifierHint: DropModifierHint(modifiers: .option, idle: "⌥ ALT FOLDER", active: "ALT FOLDER"),
            style: .target, isEnabled: enabled,
            details: [
                DropZoneDetail(id: "agent", label: "AGENT", value: "Claude Code"),
                DropZoneDetail(id: "folder", label: "FOLDER", value: "File's folder", emphasis: .dimmedWhile(.option)),
                DropZoneDetail(id: "alt_folder", label: "⌥ FOLDER", value: "~/Code", emphasis: .litWhile(.option)),
            ])
        return DropZoneSummary(zone, moduleID: module)
    }

    static func harness(airdrop: Bool = true, imageToText: Bool = false) async throws -> ShelfHarness {
        let h = ShelfHarness(settings: ["airdrop": airdrop, "image_to_text": imageToText])
        try await h.start()
        return h
    }

    @Test func defaultsShowAskAIAndTheEnabledMiniZones() async throws {
        let h = try await Self.harness()
        h.context.fakeDropZones.summaries =
            [Self.askSummary()]
            + h.module.dropZones.map {
                DropZoneSummary($0, moduleID: "shelf")
            }
        let model = h.module.sendToCardModel()
        #expect(model.meta == "DEFAULTS")
        #expect(model.askZone?.id == "agents.sessions.ask")
        #expect(
            model.askZone?.summary.details.map(\.label).map { String(localized: $0) } == [
                "AGENT", "FOLDER", "⌥ FOLDER",
            ])
        #expect(model.miniZones.map(\.id) == ["shelf.airdrop"], "Image to Text is off by default: not drawn")
        #expect(model.miniZones.first?.zone.meta.map { String(localized: $0) } == "SHARE")
        #expect(!model.isEmpty)
    }

    @Test func lastImageToTextMeta() async throws {
        let h = try await Self.harness(imageToText: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        h.module.lastImageToText = ImageToTextRun(lines: 3, at: Date(timeIntervalSince1970: 14 * 3600 + 48 * 60))
        #expect(h.module.sendToMeta(calendar: calendar) == "LAST · 3 LINES · 14:48")
        h.module.lastImageToText = ImageToTextRun(lines: 1, at: Date(timeIntervalSince1970: 9 * 3600 + 5 * 60))
        #expect(h.module.sendToMeta(calendar: calendar) == "LAST · 1 LINE · 09:05")
        #expect(h.module.sendToCardModel(zones: []).miniZones.map(\.id) == ["shelf.airdrop", "shelf.image_to_text"])
    }

    @Test func disabledZonesAreOmittedAndAskAIIsGoneWithAgentsSessionsOff() async throws {
        let h = try await Self.harness(airdrop: false, imageToText: true)
        #expect(h.module.sendToCardModel(zones: [Self.askSummary(enabled: false)]).askZone == nil)
        #expect(h.module.sendToCardModel(zones: []).askZone == nil, "agents.sessions off: no zone listed")
        #expect(h.module.sendToCardModel(zones: [Self.askSummary(module: "shelf")]).askZone == nil)
        #expect(h.module.sendToCardModel(zones: []).miniZones.map(\.id) == ["shelf.image_to_text"])
        let off = try await Self.harness(airdrop: false)
        #expect(off.module.sendToCardModel(zones: []).isEmpty, "NO TARGETS")
        await off.module.stop()
        #expect(off.module.sendToCardModel(zones: [Self.askSummary()]).miniZones.isEmpty)
    }

    @Test func hoverGatingFollowsTheZonesAccepts() async throws {
        let h = try await Self.harness(imageToText: true)
        let model = h.module.sendToCardModel(zones: [Self.askSummary()])
        let ask = try #require(model.askZone)
        let image = try #require(model.target("shelf.image_to_text"))
        let airdrop = try #require(model.target("shelf.airdrop"))
        #expect(ask.accepts([.plainText]) && airdrop.accepts([.plainText]))
        #expect(!image.accepts([.plainText]))
        #expect(image.accepts([.png]) && image.accepts([.pdf]))
        #expect(!SendToTarget(summary: Self.askSummary(enabled: false)).accepts([.png]))
        let hover = SendToHover(zoneID: image.id, contentTypes: [.plainText])
        #expect(hover.phase(of: image) == .disabled)
        #expect(hover.phase(of: ask) == .idle)
        #expect(SendToHover(zoneID: ask.id, contentTypes: [.plainText]).phase(of: ask) == .hovered)
    }

    @Test func theDraggedStashItemGivesItsType() async throws {
        let h = try await Self.harness()
        #expect(h.module.internalDragTypes == nil, "no drag in flight: a Finder drag")
        await h.stash(makeFile("shot.png"))
        let id = try #require(h.module.items.first?.id)
        _ = h.module.beginDrag(id)
        #expect(h.module.internalDragTypes == [.png])
        await h.module.endDrag(id, .copy)
        #expect(h.module.internalDragTypes == nil)
    }

    @Test func aStashItemDropPerformsTheZoneWithStashItemSourceModifiersAndScopeHeld() async throws {
        let h = try await Self.harness()
        let file = makeFile("notes.txt")
        await h.stash(file)
        let id = try #require(h.module.items.first?.id)
        let scope = h.scope
        let open = Mutex(0)
        h.context.fakeDropZones.onPerform = { open.withLock { $0 = scope.starts - scope.stops } }
        _ = h.module.beginDrag(id)
        let before = scope.starts - scope.stops
        let result = await h.module.sendToDrop(zoneID: "agents.sessions.ask", drop: .stashItem, modifiers: .option)
        #expect(result.isAccepted)
        let call = try #require(h.context.fakeDropZones.performed.first)
        #expect(call.zoneID == "agents.sessions.ask")
        #expect(call.payload.source == .stashItem)
        #expect(call.payload.modifiers == .option)
        #expect(call.payload.urls.map(\.standardizedFileURL.path) == [file.standardizedFileURL.path])
        #expect(open.withLock { $0 } == before + 1, "the item's scope is held while the handler runs")
        #expect(scope.starts - scope.stops == before, "and released after")
        await h.module.endDrag(id, .copy)
        #expect(h.module.items.count == 1, "a drop on a zone keeps the item")
    }

    @Test func aFinderDropOnTheCardIsShelfTabSource() async throws {
        let h = try await Self.harness()
        let file = makeFile("a.pdf")
        await h.module.sendToDrop(zoneID: "shelf.airdrop", drop: .files([file]), modifiers: [])
        let call = try #require(h.context.fakeDropZones.performed.first)
        #expect(call.payload.source == .shelfTab)
        #expect(call.payload.urls == [file])
    }

    @Test func aStashItemDropWithoutADragInFlightRunsNothing() async throws {
        let h = try await Self.harness()
        let result = await h.module.sendToDrop(zoneID: "shelf.airdrop", drop: .stashItem, modifiers: [])
        guard case .rejected = result else {
            Issue.record("expected rejected")
            return
        }
        #expect(h.context.fakeDropZones.performed.isEmpty)
    }
}

extension ShelfHarness {
    @discardableResult
    func stash(_ urls: URL...) async -> DropResult {
        await module.stashZone.handler(DropPayload(urls: urls, modifiers: [], source: .dropDisplay))
    }
}
