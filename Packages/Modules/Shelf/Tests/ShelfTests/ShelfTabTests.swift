import Foundation
import ModuleKit
import Testing
import VigieUI

@testable import Shelf

private let day: TimeInterval = 86_400
private let hour: TimeInterval = 3600

/// Records Quick Look requests; `available` false plays "no key window".
@MainActor final class FakeQuickLook: QuickLookPresenting {
    var available = true
    var shown: [URL] = []
    var closers: [@MainActor () -> Void] = []

    func present(_ url: URL, onClose: @escaping @MainActor () -> Void) -> Bool {
        guard available else { return false }
        shown.append(url)
        closers.append(onClose)
        return true
    }
}

final class RecordingRevealer: FileRevealer, @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    var revealed: [URL] { lock.withLock { urls } }
    @MainActor func reveal(_ url: URL) { lock.withLock { urls.append(url) } }
}

@MainActor struct TabHarness {
    let base: ShelfHarness
    let quickLook = FakeQuickLook()
    let revealer = RecordingRevealer()
    let module: ShelfModule

    init(settings: [String: any SettingValue] = [:]) {
        let base = ShelfHarness(settings: settings)
        self.base = base
        let clock = base.clock
        module = ShelfModule(
            scope: base.scope, recycler: base.recycler, revealer: revealer, quickLook: quickLook,
            now: { clock.now })
        module.moveSettle = (1, .zero)
    }

    func start() async throws { try await module.start(context: base.context) }

    @discardableResult
    func stash(_ urls: URL...) async -> DropResult {
        await module.stashZone.handler(DropPayload(urls: urls, modifiers: [], source: .dropDisplay))
    }
}

@MainActor @Suite struct ShelfTabTests {
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Wed 04 Nov 2026 14:48 UTC (the mockup's time).
    static let now = ISO8601DateFormatter().date(from: "2026-11-04T14:48:00Z")!

    static func item(
        _ name: String = "a.txt", size: Int64 = 184_000, mode: ShelfItemMode = .reference, added: Date = now,
        expiresIn: TimeInterval? = 6 * day, pinned: Bool = false
    ) -> ShelfItem {
        ShelfItem(
            name: name, size: size, addedAt: added, mode: mode, pinned: pinned,
            expiresAt: pinned ? nil : expiresIn.map { now.addingTimeInterval($0) })
    }

    static func row(_ item: ShelfItem, ttl: Duration = .seconds(7 * 86_400)) -> ShelfRowModel {
        ShelfTabFormat.row(item, ttl: ttl, now: now, calendar: utc)
    }

    // MARK: Labels

    @Test func sizeAndModeTag() {
        #expect(Self.row(Self.item(size: 184_000)).sizeMode == "184 KB · REF")
        #expect(Self.row(Self.item(size: 1_200_000, mode: .saved)).sizeMode == "1.2 MB · SAVED")
        #expect(Self.row(Self.item(size: 92_000, mode: .copy)).sizeMode == "92 KB · COPY")
        #expect(Self.row(Self.item("invoice.pdf")).kind == "PDF")
        #expect(Self.row(Self.item("README")).kind == "")
        #expect(Self.row(Self.item()).sourceApp == nil)
    }

    @Test func addedTimeAndDay() throws {
        let today = Self.row(Self.item(added: Self.now.addingTimeInterval(-17 * 60)))
        #expect(today.addedTime == "14:31")
        #expect(today.addedDay == "TODAY")
        let tuesday = try #require(ISO8601DateFormatter().date(from: "2026-11-03T11:40:00Z"))
        #expect(Self.row(Self.item(added: tuesday)).addedDay == "TUE 03")
        #expect(Self.row(Self.item(added: tuesday)).addedTime == "11:40")
        let october = try #require(ISO8601DateFormatter().date(from: "2026-10-30T09:12:00Z"))
        #expect(Self.row(Self.item(added: october)).addedDay == "FRI 30 OCT")
    }

    @Test func expiryColumn() {
        #expect(Self.row(Self.item(expiresIn: 7 * day)).expiry == .timeLeft("7D LEFT", fraction: 1))
        #expect(
            Self.row(Self.item(expiresIn: day + 18 * hour)).expiry
                == .timeLeft("1D 18H LEFT", fraction: (day + 18 * hour) / (7 * day)))
        #expect(Self.row(Self.item(expiresIn: 5 * hour)).expiry == .expiring("EXPIRES IN 5H", fraction: 5 / 168))
        #expect(Self.row(Self.item(pinned: true)).expiry == .pinned)
        #expect(Self.row(Self.item(pinned: true)).isPinned)
        #expect(
            Self.row(Self.item("a.txt", expiresIn: 5 * hour)).accessibilityLabel == "a.txt, 184 KB · REF, EXPIRES IN 5H"
        )
        #expect(Self.row(Self.item("a.txt", pinned: true)).accessibilityLabel == "a.txt, 184 KB · REF, pinned")
    }

    @Test func emptySentenceNamesTheTTL() {
        #expect(
            String(localized: ShelfTabFormat.emptySentence(.seconds(7 * 86_400)))
                == "Drag a file, text or image onto the notch, or press ⌘V, to keep it here for 7 days.")
        #expect(
            String(localized: ShelfTabFormat.emptySentence(.seconds(86_400)))
                == "Drag a file, text or image onto the notch, or press ⌘V, to keep it here for 1 day.")
        #expect(
            String(localized: ShelfTabFormat.emptySentence(.seconds(12 * 3600)))
                == "Drag a file, text or image onto the notch, or press ⌘V, to keep it here for 12 hours.")
        #expect(ShelfTabFormat.ttlMeta(.seconds(7 * 86_400)) == "TTL 7D")
        #expect(ShelfTabFormat.ttlMeta(.seconds(12 * 3600)) == "TTL 12H")
    }

    // MARK: Module snapshot

    @Test func snapshotTitleMetaAndRows() async throws {
        let h = TabHarness()
        try await h.start()
        let empty = h.module.tabSnapshot()
        #expect(empty.title == "STASH · 0")
        #expect(empty.rows.isEmpty)
        #expect(empty.ttlMeta == "TTL 7D")
        await h.stash(makeFile("a.txt"))
        h.base.clock.advance(3 * day)
        await h.stash(makeFile("b.txt"))
        let snapshot = h.module.tabSnapshot()
        #expect(snapshot.title == "STASH · 2")
        #expect(snapshot.rows.map(\.name) == ["b.txt", "a.txt"])
        #expect(snapshot.expiringMeta == nil)
        h.base.clock.advance(3.5 * day)
        #expect(h.module.tabSnapshot(now: h.base.clock.now).expiringMeta == "1 EXPIRING")
        #expect(h.module.expandedView() != nil)
        #expect(h.module.homeCard() != nil)
    }

    @Test func selectionFollowsTheRows() async throws {
        let h = TabHarness()
        try await h.start()
        await h.stash(makeFile("a.txt"), makeFile("b.txt"))
        let ids = h.module.tabSnapshot().rows.map(\.id)
        h.module.tabActions.select(ids[1])
        #expect(h.module.tabSnapshot().selectedID == ids[1])
        h.module.tabActions.select(ShelfSelection.move(ids[1], by: -1, in: ids))
        #expect(h.module.tabSnapshot().selectedID == ids[0])
        await h.module.remove(ids[0])
        #expect(h.module.tabSnapshot().selectedID == nil)
    }

    // MARK: Actions

    @Test func quickLookShowsTheFileAndHoldsItsScopeUntilClosed() async throws {
        let h = TabHarness()
        try await h.start()
        let file = makeFile("a.txt")
        await h.stash(file)
        let id = try #require(h.module.items.first?.id)
        let starts = h.base.scope.starts
        h.module.tabActions.quickLook(id)
        #expect(h.quickLook.shown.map(\.lastPathComponent) == ["a.txt"])
        #expect(h.module.selectedID == id)
        #expect(h.base.scope.starts == starts + 1)
        #expect(h.base.scope.stops == h.base.scope.starts - 1)
        h.quickLook.closers.first?()
        #expect(h.base.scope.stops == h.base.scope.starts)
    }

    @Test func quickLookWithoutAKeyWindowLeavesAHint() async throws {
        let h = TabHarness()
        try await h.start()
        await h.stash(makeFile("a.txt"))
        let id = try #require(h.module.items.first?.id)
        h.quickLook.available = false
        h.module.showQuickLook(id)
        #expect(h.quickLook.shown.isEmpty)
        #expect(h.module.tabSnapshot().notice == "CLICK THE PANEL, THEN ␣")
        #expect(h.base.scope.stops == h.base.scope.starts)
        h.module.select(id)
        #expect(h.module.tabSnapshot().notice == nil)
    }

    @Test func quickLookOnAMissingFileSaysSo() async throws {
        let h = TabHarness(settings: ["mode": "copy"])
        try await h.start()
        await h.stash(makeFile("a.txt"))
        let item = try #require(h.module.items.first)
        try FileManager.default.removeItem(at: try #require(h.module.store?.fileURL(for: item)))
        h.module.showQuickLook(item.id)
        #expect(h.quickLook.shown.isEmpty)
        #expect(h.module.notice == "FILE NOT FOUND")
    }

    @Test func revealOpensFinderAtTheFile() async throws {
        let h = TabHarness()
        try await h.start()
        let file = makeFile("a.txt")
        await h.stash(file)
        let id = try #require(h.module.items.first?.id)
        await h.module.reveal(id)
        #expect(h.revealer.revealed.map(\.lastPathComponent) == ["a.txt"])
        #expect(h.base.scope.stops == h.base.scope.starts)
    }

    @Test func togglePinPinsAndUnpins() async throws {
        let h = TabHarness()
        try await h.start()
        await h.stash(makeFile("a.txt"))
        let id = try #require(h.module.items.first?.id)
        await h.module.togglePin(id)
        #expect(h.module.items.first?.pinned == true)
        #expect(h.module.tabSnapshot().rows.first?.expiry == .pinned)
        await h.module.togglePin(id)
        #expect(h.module.items.first?.pinned == false)
        #expect(h.module.items.first?.expiresAt != nil)
    }

    // MARK: Drag out

    @Test func dragMoveOfAReferenceRemovesTheItem() async throws {
        let h = TabHarness()
        try await h.start()
        let file = makeFile("a.txt")
        await h.stash(file)
        let id = try #require(h.module.items.first?.id)
        let url = try #require(h.module.beginDrag(id))
        #expect(h.base.scope.starts > h.base.scope.stops)
        // Finder moves the original.
        try FileManager.default.moveItem(at: url, to: makeTempDirectory().appendingPathComponent("a.txt"))
        await h.module.endDrag(id, .move)
        #expect(h.module.items.isEmpty)
        #expect(h.base.scope.stops == h.base.scope.starts)
    }

    @Test func dragMoveOfACopyRemovesTheItemAndItsFolder() async throws {
        let h = TabHarness(settings: ["mode": "copy"])
        try await h.start()
        await h.stash(makeFile("a.txt"))
        let id = try #require(h.module.items.first?.id)
        let url = try #require(h.module.beginDrag(id))
        try FileManager.default.moveItem(at: url, to: makeTempDirectory().appendingPathComponent("a.txt"))
        await h.module.endDrag(id, .move)
        #expect(h.module.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    }

    @Test func optionDragCopyKeepsTheItem() async throws {
        let h = TabHarness()
        try await h.start()
        await h.stash(makeFile("a.txt"))
        let id = try #require(h.module.items.first?.id)
        _ = try #require(h.module.beginDrag(id))
        await h.module.endDrag(id, .copy)
        #expect(h.module.items.map(\.id) == [id])
        #expect(h.base.scope.stops == h.base.scope.starts)
    }

    @Test func aMoveThatLeftTheFileOrACancelKeepsTheItem() async throws {
        let h = TabHarness(settings: ["mode": "copy"])
        try await h.start()
        await h.stash(makeFile("a.txt"))
        let id = try #require(h.module.items.first?.id)
        _ = try #require(h.module.beginDrag(id))
        await h.module.endDrag(id, .move)
        #expect(h.module.items.map(\.id) == [id])
        _ = try #require(h.module.beginDrag(id))
        await h.module.endDrag(id, .none)
        #expect(h.module.items.map(\.id) == [id])
    }

    @Test func dragOfAMissingFileIsRefused() async throws {
        let h = TabHarness(settings: ["mode": "copy"])
        try await h.start()
        await h.stash(makeFile("a.txt"))
        let item = try #require(h.module.items.first)
        try FileManager.default.removeItem(at: try #require(h.module.store?.fileURL(for: item)))
        #expect(h.module.beginDrag(item.id) == nil)
        #expect(h.module.notice == "FILE NOT FOUND")
    }
}
