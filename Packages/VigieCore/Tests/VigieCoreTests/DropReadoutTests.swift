import AppKit
import ModuleKit
import SwiftUI
import Synchronization
import Testing
import UniformTypeIdentifiers
import VigieUI

@testable import VigieCore

/// Story 9.9 host side: loose content vs files-only zones, the `READING…` progress readout, confirmation
/// readouts (drain, VoiceOver, hold while hovered) and the materialized files handed to the handler.
@MainActor @Suite struct DropReadoutTests {
    static func zone(
        _ id: String, accepts: [UTType], loose: Set<DropLooseContent> = [], progress: LocalizedStringResource? = nil,
        handler: @escaping @Sendable (DropPayload) async -> DropResult = { _ in .accepted }
    ) -> DropZone {
        DropZone(
            id: id, label: LocalizedStringResource(stringLiteral: id), glyph: "drop.stash", accentToken: "iris-2",
            role: id == "stash" ? .primary : .secondary,
            cell: id == "stash"
                ? DropCell(preferredColumn: 1, preferredRow: 1, span: .init(columns: 2, rows: 2))
                : DropCell(preferredColumn: 4, preferredRow: 1, span: .init(columns: 1, rows: 1)),
            order: id == "stash" ? 0 : 20, accepts: accepts, handler: handler, looseContent: loose,
            progressReadout: progress)
    }

    @Test func looseContentKindFollowsTheDraggedPayload() {
        #expect(DropDragItems(text: "hi").looseContent == .text)
        #expect(DropDragItems(webURL: URL(string: "https://example.com")!).looseContent == .link)
        #expect(DropDragItems(imageData: Data([1])).looseContent == .image)
        #expect(DropDragItems(fileURLs: [URL(fileURLWithPath: "/tmp/a.txt")], text: "hi").looseContent == nil)
        #expect(DropDragItems().looseContent == nil)
    }

    /// A text drag lights Stash (takes anything) but neither a files-only zone (AirDrop, Ask AI) nor Image to
    /// Text; an image drag lights Image to Text; a `.txt` file lights the files-only zone.
    @Test func filesOnlyZonesStayUnlitForLooseContent() async {
        let f = DropFixture()
        f.shelf.dropZones = [
            Self.zone("stash", accepts: []), Self.zone("airdrop", accepts: [.item]),
            DropZone(
                id: "ocr", label: "OCR", glyph: "drop.image-to-text", accentToken: "iris-2", role: .secondary,
                cell: DropCell(preferredColumn: 4, preferredRow: 2, span: .init(columns: 1, rows: 1)), order: 30,
                accepts: [.image, .pdf], handler: { _ in .accepted }, looseContent: [.image]),
        ]
        f.agents.dropZones = []
        await f.start()
        func lit(_ items: DropDragItems) -> Set<String> {
            _ = f.display.islandDragEntered(displayID: nil, items: items)
            var result: Set<String> = []
            for id in ["stash", "airdrop", "ocr"] {
                _ = f.display.displayDragEntered(at: f.center(of: id))
                if f.display.model?.isLit(id) == true { result.insert(id) }
            }
            f.display.dragEnded()
            return result
        }
        #expect(lit(DropDragItems(sequence: 1, text: "hello")) == ["stash"])
        #expect(lit(DropDragItems(sequence: 2, webURL: URL(string: "https://example.com")!)) == ["stash"])
        #expect(lit(DropDragItems(sequence: 3, imageData: Data([1, 2]))) == ["stash", "ocr"])
        #expect(
            lit(DropDragItems(fileURLs: [URL(fileURLWithPath: "/tmp/notes.txt")], sequence: 4)) == ["stash", "airdrop"])
        // A refused drop calls no handler.
        let text = DropDragItems(sequence: 5, text: "hello")
        _ = f.display.islandDragEntered(displayID: nil, items: text)
        #expect(!f.display.performDrop(at: f.center(of: "airdrop"), items: text))
    }

    @Test func progressReadoutShowsWhileTheHandlerRunsThenTheConfirmationReplacesIt() async throws {
        let f = DropFixture()
        let gate = Gate()
        f.shelf.dropZones = [
            Self.zone("stash", accepts: []),
            Self.zone("ocr", accepts: [.image], progress: "READING…") { _ in
                await gate.wait()
                return .confirmation(DropReadout(text: "COPIED · 3 LINES", announcement: "Copied 3 lines"))
            },
        ]
        f.agents.dropZones = []
        await f.start()
        let items = DropFixture.png()
        _ = f.display.islandDragEntered(displayID: nil, items: items)
        #expect(f.display.performDrop(at: f.center(of: "ocr"), items: items))
        #expect(await eventually { f.host.transient == .message("READING…") })
        #expect(f.host.transientDrain == nil)
        #expect(f.announced.isEmpty)
        gate.open()
        _ = await f.display.pendingDrop?.value
        #expect(f.host.transient == .confirmation("COPIED · 3 LINES", announcement: "Copied 3 lines", drains: true))
        #expect(f.host.leadingLayout.shown.map(\.id).contains("transient"))
        guard case .draining(let duration, _) = f.host.transientDrain else {
            Issue.record("no drain line")
            return
        }
        #expect(duration == .seconds(2))
        #expect(f.announced == ["Copied 3 lines"])
    }

    @Test func progressLeavesWhenTheHandlerReturnsWithoutAReadout() async {
        let f = DropFixture()
        f.shelf.dropZones = [Self.zone("stash", accepts: [], progress: "READING…")]
        f.agents.dropZones = []
        await f.start()
        let items = DropFixture.png()
        _ = f.display.islandDragEntered(displayID: nil, items: items)
        #expect(f.display.performDrop(at: f.center(of: "stash"), items: items))
        _ = await f.display.pendingDrop?.value
        #expect(f.host.transient == nil)
    }

    @Test func handlerGetsTheMaterializedPromiseFilesOnly() async throws {
        let f = DropFixture()
        let log = HandlerLog()
        f.shelf.dropZones = [
            Self.zone("stash", accepts: []) { payload in
                log.record("stash", payload)
                return .accepted
            }
        ]
        f.agents.dropZones = []
        await f.start()
        let user = URL(fileURLWithPath: "/tmp/user-file.png")
        let items = DropDragItems(fileURLs: [user], promises: [FakePromise(name: "promised.png")], sequence: 77)
        _ = f.display.islandDragEntered(displayID: nil, items: items)
        #expect(f.display.performDrop(at: f.center(of: "stash"), items: items))
        _ = await f.display.pendingDrop?.value
        let payload = try #require(log.all.first?.payload)
        #expect(payload.urls.count == 2)
        #expect(payload.materializedURLs.map(\.lastPathComponent) == ["promised.png"])
        #expect(!payload.materializedURLs.contains(user))
    }

    // MARK: Hold while hovered (DESIGN "Copied readout")

    @Test func readoutHoldsWhileThePointerIsOverTheNotchThenRunsAgain() async {
        let f = DropFixture()
        await f.start()
        f.host.showTransient(.copied(lines: 2), duration: .milliseconds(60))
        guard case .draining(_, let first) = f.host.transientDrain else {
            Issue.record("no drain")
            return
        }
        f.host.islandHoverChanged(true)
        #expect(f.host.transientDrain == .held)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(f.host.transient == .copied(lines: 2), "held while hovered")
        f.host.islandHoverChanged(false)
        guard case .draining(_, let second) = f.host.transientDrain else {
            Issue.record("no drain after leaving")
            return
        }
        #expect(second != first, "the drain restarts from full")
        #expect(await eventually { f.host.transient == nil })
        #expect(f.host.transientDrain == nil)
    }

    @Test func aReadoutShownWhileHoveredStartsHeld() async {
        let f = DropFixture()
        await f.start()
        f.host.islandHoverChanged(true)
        f.host.showTransient(.noTextFound, duration: .milliseconds(30))
        #expect(f.host.transientDrain == .held)
        #expect(f.announced == ["No text found"])
        try? await Task.sleep(for: .milliseconds(80))
        #expect(f.host.transient == .noTextFound)
        f.host.islandHoverChanged(false)
        #expect(await eventually { f.host.transient == nil })
    }

    @Test func plainReadoutsHaveNoDrainOrAnnouncement() async {
        let f = DropFixture()
        await f.start()
        f.host.showTransient(.message("NOT STASHED"), duration: .milliseconds(30))
        #expect(f.host.transientDrain == nil)
        #expect(f.announced.isEmpty)
        #expect(await eventually { f.host.transient == nil })
    }

    /// 2.8's slot rule with a confirmation readout: after the first item, the last visible one steps into `+X`.
    @Test func confirmationTakesTheSlotAfterTheFirstItem() {
        let snapshots = [
            ArbiterModuleSnapshot(
                moduleID: "scripts", state: .active,
                items: (0..<3).map { i in
                    LeftWingItem(id: "i\(i)", priority: i, order: i) { _ in AnyView(Text(verbatim: "\(i)")) }
                })
        ]
        let readout = TransientReadout.confirmation("COPIED · 3 LINES", announcement: nil, drains: true)
        let layout = ClosedNotchArbiter.leading(snapshots, slots: 3, transient: readout)
        #expect(layout.shown.map(\.id) == ["scripts/i0", "transient", "scripts/i1"])
        #expect(layout.overflowCount == 1)
    }
}

/// Lets a test hold a handler until it opens.
final class Gate: Sendable {
    private let state = Mutex<(open: Bool, waiters: [CheckedContinuation<Void, Never>])>((false, []))
    func wait() async {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { s -> Bool in
                if s.open { return true }
                s.waiters.append(continuation)
                return false
            }
            if ready { continuation.resume() }
        }
    }
    func open() {
        let waiters = state.withLock { s -> [CheckedContinuation<Void, Never>] in
            s.open = true
            defer { s.waiters = [] }
            return s.waiters
        }
        for waiter in waiters { waiter.resume() }
    }
}
