import Foundation
import ModuleKit
import Testing
import VigieUI

@testable import Shelf

private let day: TimeInterval = 86_400
private let hour: TimeInterval = 3600

/// Story 11.3: the Home shelf widget.
@MainActor @Suite struct HomeWidgetTests {
    static func harness(airdrop: Bool = true, imageToText: Bool = true) async throws -> ShelfHarness {
        let h = ShelfHarness(settings: ["airdrop": airdrop, "image_to_text": imageToText])
        try await h.start()
        return h
    }

    /// AC 1: the stash list with Stash and Ask AI zones, and only those two (FR57), even with AirDrop and Image
    /// to Text on.
    @Test func showsTheStashListWithStashAndAskAIOnly() async throws {
        let h = try await Self.harness()
        await h.drop(ShelfHarness.files(makeFile("a.txt")))
        h.clock.advance(60)
        await h.drop(ShelfHarness.files(makeFile("b.pdf")))
        let zones = [SendToTests.askSummary()] + h.module.dropZones.map { DropZoneSummary($0, moduleID: "shelf") }
        h.context.fakeDropZones.summaries = zones
        #expect(h.module.homeCard() != nil)
        let model = h.module.homeCardModel()
        #expect(model.title == "Shelf")
        #expect(model.meta == "2 items")
        #expect(model.items.map(\.row.name) == ["b.pdf", "a.txt"], "newest first")
        #expect(model.items.allSatisfy { $0.tag == nil })
        #expect(model.warning == nil)
        #expect(model.targets.map(\.id) == ["shelf.stash", "agents.sessions.ask"])
        #expect(model.stashZone?.zone.isPrimary == true)
        #expect(model.stashZone.map { String(localized: $0.zone.label) } == "Stash")
        // agents.sessions off: only the Stash.
        #expect(h.module.homeCardModel(zones: []).targets.map(\.id) == ["shelf.stash"])
    }

    @Test func emptyShelfKeepsBothZonesAndSaysZeroItems() async throws {
        let h = try await Self.harness()
        let model = h.module.homeCardModel(zones: [SendToTests.askSummary()])
        #expect(model.items.isEmpty && model.meta == "0 items")
        #expect(model.targets.count == 2)
        #expect(model.stashZone?.zone.meta.map { String(localized: $0) } == "KEEP 7 DAYS · 0 ITEMS")
    }

    /// AC 2: an item in its last 24 h comes first with `5H`, and the warning line reads `1 EXPIRES IN 5H`.
    @Test func lastDayItemComesFirstWithTagAndWarning() async throws {
        let h = try await Self.harness()
        await h.drop(ShelfHarness.files(makeFile("old.txt")))
        h.clock.advance(day)
        await h.drop(ShelfHarness.files(makeFile("mid.txt")))
        h.clock.advance(hour)
        await h.drop(ShelfHarness.files(makeFile("new.txt")))
        // old.txt expires 7 days after it was stashed: 5 h left (4 h 30 rounds up).
        let now = h.clock.now.addingTimeInterval(7 * day - day - hour - 4.5 * hour)
        let model = h.module.homeCardModel(zones: [], now: now)
        #expect(model.items.map(\.row.name) == ["old.txt", "new.txt", "mid.txt"])
        #expect(model.items.map(\.tag) == ["5H", nil, nil])
        #expect(model.items.first?.isExpiring == true)
        #expect(model.warning == "1 EXPIRES IN 5H")
        // The tag and the row use the same rule as the Shelf tab.
        guard case .expiring(let text, _) = model.items[0].row.expiry else {
            Issue.record("the first row is not in its warning form")
            return
        }
        #expect(text == "EXPIRES IN 5H")
    }

    @Test func twoInTheirLastDaySoonestFirstPluralWarning() async throws {
        let h = try await Self.harness()
        await h.drop(ShelfHarness.files(makeFile("old.txt")))
        let start = h.clock.now
        h.clock.advance(12 * hour)
        await h.drop(ShelfHarness.files(makeFile("mid.txt")))
        let model = h.module.homeCardModel(zones: [], now: start.addingTimeInterval(7 * day - hour))
        #expect(model.items.map(\.row.name) == ["old.txt", "mid.txt"])
        #expect(model.items.map(\.tag) == ["1H", "13H"])
        #expect(model.warning == "2 EXPIRE IN 1H")
    }

    @Test func pinnedItemsNeverGetTheTag() async throws {
        let h = try await Self.harness()
        await h.drop(ShelfHarness.files(makeFile("keep.txt")))
        let id = try #require(h.module.items.first?.id)
        await h.module.setPinned(id, true)
        let model = h.module.homeCardModel(zones: [], now: h.clock.now.addingTimeInterval(7 * day - hour))
        #expect(model.items.first?.tag == nil && model.warning == nil)
    }

    /// AC 3: files dropped on either widget zone run that zone with `source = .homeWidget`.
    @Test func fileDropsOnWidgetZonesRunWithHomeWidgetSource() async throws {
        let h = try await Self.harness()
        let file = makeFile("drop.png")
        for zone in [ShelfModule.stashZoneID, "agents.sessions.ask"] {
            let result = await h.module.homeWidgetDrop(zoneID: zone, drop: .files([file]), modifiers: .option)
            #expect(result.isAccepted)
        }
        let calls = h.context.fakeDropZones.performed
        #expect(calls.map(\.zoneID) == [ShelfModule.stashZoneID, "agents.sessions.ask"])
        #expect(calls.allSatisfy { $0.payload.source == .homeWidget && $0.payload.urls == [file] })
        #expect(calls.allSatisfy { $0.payload.modifiers == .option })
    }

    /// AC 3: a stash item dragged from the widget's list onto Ask AI runs it with `source = .homeWidget`,
    /// inside the item's scope; it is never stashed again.
    @Test func stashItemDropRunsWithHomeWidgetSourceAndScopeHeld() async throws {
        let h = try await Self.harness()
        await h.drop(ShelfHarness.files(makeFile("notes.txt")))
        let id = try #require(h.module.items.first?.id)
        _ = h.module.beginDrag(id)
        #expect(h.module.homeCardActions.internalDragTypes() == [.plainText])
        let refused = await h.module.homeWidgetDrop(zoneID: ShelfModule.stashZoneID, drop: .stashItem, modifiers: [])
        #expect(!refused.isAccepted)
        #expect(h.context.fakeDropZones.performed.isEmpty)
        let result = await h.module.homeWidgetDrop(zoneID: "agents.sessions.ask", drop: .stashItem, modifiers: [])
        #expect(result.isAccepted)
        let call = try #require(h.context.fakeDropZones.performed.first)
        #expect(call.zoneID == "agents.sessions.ask" && call.payload.source == .homeWidget)
        #expect(call.payload.urls.map(\.lastPathComponent) == ["notes.txt"])
        #expect(h.scope.starts == h.scope.stops + 1, "only the drag's own access is still open")
        await h.module.endDrag(id, .none)
        #expect(h.scope.starts == h.scope.stops)
        #expect(h.module.homeCardActions.internalDragTypes() == nil)
    }

    /// AC 2 and the card copy: every string from the catalog, plural forms included.
    @Test func copyComesFromTheCatalog() {
        #expect(ShelfText.string("shelf.home.title") == "Shelf")
        #expect(ShelfHomeFormat.meta(count: 1) == "1 item")
        #expect(ShelfHomeFormat.meta(count: 3) == "3 items")
        #expect(ShelfText.format("shelf.home.tag", 5) == "5H")
        #expect(ShelfText.format("shelf.home.warning", 1, 5) == "1 EXPIRES IN 5H")
        #expect(ShelfText.format("shelf.home.warning", 3, 12) == "3 EXPIRE IN 12H")
        for key in ["shelf.home.title", "shelf.home.meta", "shelf.home.tag", "shelf.home.warning"] {
            #expect(ShelfText.string(key) != key, "\(key) is not in the Shelf catalog")
        }
    }

    /// Every locale the Shelf catalog ships has the widget's strings (English only for now, AD-15).
    @Test func everyShippedLocaleHasTheWidgetStrings() throws {
        let url = try #require(ShelfModuleBundle.catalogURL)
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let strings = try #require(catalog?["strings"] as? [String: Any])
        var locales: Set<String> = []
        for case let entry as [String: Any] in strings.values {
            locales.formUnion((entry["localizations"] as? [String: Any])?.keys ?? [:].keys)
        }
        #expect(locales.contains("en"))
        for key in ["shelf.home.title", "shelf.home.meta", "shelf.home.tag", "shelf.home.warning"] {
            let entry = try #require(strings[key] as? [String: Any], "\(key) missing")
            let localized = Set((entry["localizations"] as? [String: Any])?.keys ?? [:].keys)
            #expect(localized == locales, "\(key) is missing a locale")
        }
    }
}

/// The source catalog, next to the tests' package.
enum ShelfModuleBundle {
    static var catalogURL: URL? {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Shelf/Resources/Localizable.xcstrings")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
