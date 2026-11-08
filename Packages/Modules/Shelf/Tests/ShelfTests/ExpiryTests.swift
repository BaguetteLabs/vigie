import Foundation
import ModuleKit
import Testing

@testable import Shelf

private let day: TimeInterval = 86_400
private let hour: TimeInterval = 3600

@MainActor @Suite struct ExpiryTests {
    static func item(expiresIn seconds: TimeInterval, now: Date, pinned: Bool = false) -> ShelfItem {
        ShelfItem(
            name: "a.txt", size: 1, addedAt: now, mode: .reference, pinned: pinned,
            expiresAt: pinned ? nil : now.addingTimeInterval(seconds))
    }

    @Test func timeLeftLabelsAtTheBoundaries() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func label(_ seconds: TimeInterval) -> String? {
            Self.item(expiresIn: seconds, now: now).timeLeftLabel(now: now)
        }
        #expect(label(7 * day) == "7D LEFT")
        #expect(label(7 * day - 60) == "6D LEFT")
        #expect(label(2 * day) == "2D LEFT")
        #expect(label(2 * day - 1) == "1D 23H LEFT")
        #expect(label(day + 18 * hour + 30 * 60) == "1D 18H LEFT")
        #expect(label(day + 30 * 60) == "1D LEFT")
        #expect(label(day) == "EXPIRES IN 24H")
        #expect(label(5 * hour) == "EXPIRES IN 5H")
        #expect(label(4 * hour + 1) == "EXPIRES IN 5H")
        #expect(label(10 * 60) == "EXPIRES IN 1H")
        #expect(label(0) == "EXPIRES IN 1H")
        #expect(Self.item(expiresIn: 0, now: now, pinned: true).timeLeftLabel(now: now) == nil)
    }

    @Test func expiringFlagStartsAt24Hours() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(!Self.item(expiresIn: day + 1, now: now).isExpiring(now: now))
        #expect(Self.item(expiresIn: day, now: now).isExpiring(now: now))
        #expect(Self.item(expiresIn: 1, now: now).isExpiring(now: now))
        #expect(!Self.item(expiresIn: 0, now: now).isExpiring(now: now))
        #expect(!Self.item(expiresIn: 1, now: now, pinned: true).isExpiring(now: now))
        #expect(ShelfExpiry.expiringMeta(count: 0) == nil)
        #expect(ShelfExpiry.expiringMeta(count: 1) == "1 EXPIRING")
    }

    @Test func expiresAtIsAddedAtPlusTTL() async throws {
        let h = ShelfHarness(settings: ["ttl": Duration.seconds(3 * 86_400)])
        try await h.start()
        _ = await h.drop(ShelfHarness.files(makeFile()))
        #expect(h.module.items.first?.expiresAt == h.clock.now.addingTimeInterval(3 * day))
    }

    @Test func startSweepsAndSchedulesEveryMinute() async throws {
        let h = ShelfHarness()
        try await h.start()
        #expect(h.context.fakeScheduler.intervals == [.seconds(60)])
        #expect(h.module.lastSweep == h.clock.now)
    }

    @Test func moduleCountsExpiringItems() async throws {
        let h = ShelfHarness()
        try await h.start()
        _ = await h.drop(ShelfHarness.files(makeFile()))
        h.clock.advance(day)
        _ = await h.drop(ShelfHarness.files(makeFile()))
        #expect(h.module.expiringCount == 0)
        h.clock.advance(5 * day + 1)
        await h.context.fakeScheduler.fire()
        #expect(h.module.expiringCount == 1)
        #expect(h.module.expiringMeta == "1 EXPIRING")
    }

    @Test func notificationIsPostedOnceAndOnlyWhenEnabled() async throws {
        let off = ShelfHarness()
        try await off.start()
        _ = await off.drop(ShelfHarness.files(makeFile()))
        off.clock.advance(6 * day + hour)
        await off.module.sweep()
        #expect(off.module.expiringCount == 1)
        #expect(off.context.fakeNotifier.posted.isEmpty)

        let on = ShelfHarness(settings: ["expiry_notification": true])
        try await on.start()
        _ = await on.drop(ShelfHarness.files(makeFile("deck.key")))
        on.clock.advance(5 * day)
        await on.module.sweep()
        #expect(on.context.fakeNotifier.posted.isEmpty)
        on.clock.advance(day + 5 * hour)  // 19 h left
        await on.module.sweep()
        await on.module.sweep()
        on.clock.advance(hour)
        await on.context.fakeScheduler.fire()
        let posted = on.context.fakeNotifier.posted
        #expect(posted.count == 1)
        let event = try #require(posted.first)
        let id = try #require(on.module.items.first?.id)
        #expect(event.kind == "shelf.expiring")
        #expect(event.dedupeKey == "shelf.expiring:\(id.uuidString)")
        #expect(event.title == "deck.key expires soon")
        #expect(event.body == "Leaves the shelf in 19 h. Pin it to keep it.")
        #expect(on.module.items.first?.expiryNotifiedAt != nil)
    }

    @Test func noticeSurvivesARelaunch() async throws {
        let storage = FakeStorage()
        let first = ShelfHarness(settings: ["expiry_notification": true], storage: storage)
        try await first.start()
        _ = await first.drop(ShelfHarness.files(makeFile()))
        first.clock.advance(6 * day + hour)
        await first.module.sweep()
        #expect(first.context.fakeNotifier.posted.count == 1)
        await first.module.stop()

        let second = ShelfHarness(settings: ["expiry_notification": true], storage: storage)
        second.clock.set(first.clock.now)
        try await second.start()
        #expect(second.context.fakeNotifier.posted.isEmpty)
    }

    @Test func referenceExpiryLeavesTheOriginal() async throws {
        let h = ShelfHarness()
        try await h.start()
        let file = makeFile("keep.pdf")
        _ = await h.drop(ShelfHarness.files(file))
        h.clock.advance(7 * day)
        await h.module.sweep()
        #expect(h.module.items.isEmpty)
        #expect(h.module.state == .hidden)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(h.recycler.recycled.isEmpty)
    }

    @Test func copiesAndSavedItemsGoToTheTrash() async throws {
        let h = ShelfHarness(settings: ["mode": "copy"])
        try await h.start()
        let original = makeFile("copy.txt")
        _ = await h.drop(ShelfHarness.files(original))
        _ = await h.drop(DropPayload(urls: [], modifiers: [], source: .dropDisplay, text: "memo"))
        let files = h.module.items.compactMap { h.module.store?.fileURL(for: $0) }
        #expect(files.count == 2)
        h.clock.advance(7 * day)
        await h.module.sweep()
        #expect(h.module.items.isEmpty)
        #expect(Set(h.recycler.recycled) == Set(files))
        // Moved, not deleted: the Trash holds them; the original of the copy is untouched.
        #expect(FileManager.default.fileExists(atPath: h.recycler.trash.appendingPathComponent("copy.txt").path))
        #expect(FileManager.default.fileExists(atPath: h.recycler.trash.appendingPathComponent("memo.txt").path))
        #expect(FileManager.default.fileExists(atPath: original.path))
        // The emptied item folders are gone.
        for file in files {
            #expect(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
        }
    }

    @Test func aFailedTrashKeepsTheItem() async throws {
        let h = ShelfHarness(settings: ["mode": "copy"])
        try await h.start()
        _ = await h.drop(ShelfHarness.files(makeFile()))
        h.recycler.fail = true
        h.clock.advance(8 * day)
        await h.module.sweep()
        #expect(h.module.items.count == 1)
        let file = try #require(h.module.items.first.flatMap { h.module.store?.fileURL(for: $0) })
        #expect(FileManager.default.fileExists(atPath: file.path))
        h.recycler.fail = false
        await h.module.sweep()
        #expect(h.module.items.isEmpty)
    }

    @Test func pinnedItemsNeverExpire() async throws {
        let h = ShelfHarness(settings: ["mode": "copy", "expiry_notification": true])
        try await h.start()
        _ = await h.drop(ShelfHarness.files(makeFile()))
        let id = try #require(h.module.items.first?.id)
        await h.module.setPinned(id, true)
        #expect(h.module.items.first?.expiresAt == nil)
        h.clock.advance(365 * day)
        await h.module.sweep()
        #expect(h.module.items.count == 1)
        #expect(h.recycler.recycled.isEmpty)
        #expect(h.context.fakeNotifier.posted.isEmpty)
        #expect(h.module.items.first?.timeLeftLabel(now: h.clock.now) == nil)
        // Unpinned: expires ttl after it was stashed, so at once here.
        await h.module.setPinned(id, false)
        #expect(h.module.items.isEmpty)
    }

    @Test func ttlChangeRecomputesFromAddedAt() async throws {
        let h = ShelfHarness()
        try await h.start()
        _ = await h.drop(ShelfHarness.files(makeFile()))
        let added = h.clock.now
        _ = await h.drop(ShelfHarness.files(makeFile()))
        let pinned = try #require(h.module.items.first?.id)
        await h.module.setPinned(pinned, true)
        h.clock.advance(day)
        try await h.context.fakeSettings.set(Duration.seconds(3 * 86_400), for: "ttl")
        await h.module.ttlChanged()
        let unpinned = try #require(h.module.items.first { !$0.pinned })
        #expect(unpinned.expiresAt == added.addingTimeInterval(3 * day))
        #expect(h.module.items.first { $0.pinned }?.expiresAt == nil)
        #expect(h.module.stashZone.meta.map { String(localized: $0) } == "KEEP 3 DAYS · 2 ITEMS")
        // A shorter ttl the items already passed expires them at once.
        try await h.context.fakeSettings.set(Duration.seconds(12 * 3600), for: "ttl")
        await h.module.ttlChanged()
        #expect(h.module.items.map(\.id) == [pinned])
    }

    @Test func ttlChangeObservedFromSettings() async throws {
        let h = ShelfHarness()
        try await h.start()
        try await h.context.fakeSettings.set(Duration.seconds(2 * 86_400), for: "ttl")
        for _ in 0..<200 where h.module.ttl != .seconds(2 * 86_400) { try await Task.sleep(for: .milliseconds(5)) }
        #expect(h.module.ttl == .seconds(2 * 86_400))
    }

    @Test func sweepIsIdempotent() async throws {
        let h = ShelfHarness(settings: ["mode": "copy", "expiry_notification": true])
        try await h.start()
        _ = await h.drop(ShelfHarness.files(makeFile()))
        h.clock.advance(day)
        _ = await h.drop(ShelfHarness.files(makeFile()))
        h.clock.advance(6 * day + hour)  // the first expired, the second in its last 24 h
        let store = try #require(h.module.store)
        let sweeper = try #require(h.module.sweeper)
        let first = await sweeper.sweep(store, now: h.clock.now, notify: true)
        #expect(first.expired.count == 1 && first.recycled.count == 1 && first.notified.count == 1)
        let writes = h.context.fakeStorage.writeCount("index")
        let second = await sweeper.sweep(store, now: h.clock.now, notify: true)
        #expect(second == ExpirySweeper.Report())
        #expect(!second.changed)
        #expect(h.context.fakeStorage.writeCount("index") == writes)
        #expect(h.recycler.recycled.count == 1)
        #expect(h.context.fakeNotifier.posted.count == 1)
    }

    @Test func removeTakesTheItemOffWithoutTouchingItsFile() async throws {
        let h = ShelfHarness(settings: ["mode": "copy"])
        try await h.start()
        _ = await h.drop(ShelfHarness.files(makeFile()))
        let item = try #require(h.module.items.first)
        let file = try #require(h.module.store?.fileURL(for: item))
        #expect(await h.module.remove(item.id)?.id == item.id)
        #expect(h.module.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}
