import Foundation
import ModuleKit
import Synchronization
import Testing

@testable import VigieCore

final class RecordingActivityLog: ActivityLog {
    private let storage = Mutex<[ActivityEntry]>([])
    var entries: [ActivityEntry] { storage.withLock { $0 } }
    func record(_ entry: ActivityEntry) { storage.withLock { $0.append(entry) } }
}

extension AlertHarness {
    static let otherModule: ModuleID = "shelf"

    /// A notifier for a second module.
    func otherNotifier() -> any Notifier {
        center.makeNotifier(
            for: ModuleManifest(id: Self.otherModule, name: "Shelf", icon: "tray", alertKinds: ["shelf.sample"]))
    }

    func postOther() -> AlertHandle {
        center.post(
            module: Self.otherModule, event: NotifierEvent(kind: "shelf.sample", severity: .warn, title: "file"))
    }

    func setFocus(_ active: Bool) async {
        focus.set(active)
        _ = await eventually { center.isFocusActive == active }
    }

    func outcomes(_ id: UUID) -> [AlertHistoryEntry.Outcome] {
        center.history.filter { $0.alertID == id }.map(\.outcome)
    }
}

@MainActor @Suite struct FocusModeAlertTests {
    @Test func focusSuppressesPeekAndSoundButActivatesTheAlert() {
        let h = AlertHarness(
            kinds: ["session.blocked": NotifyRule(outputs: [.peek, .sound, .system])], focusActive: true)
        let handle = h.post()
        #expect(h.peek.shown.isEmpty)
        #expect(h.sound.played.isEmpty)
        // macOS applies the Focus to notifications itself.
        #expect(h.system.delivered.map(\.id) == [handle.id])
        // Still active: the module's closed-notch state and tab read `active`.
        #expect(h.center.active.map(\.id) == [handle.id])
        #expect(h.center.active.first?.module == AlertHarness.module)
        #expect(h.outcomes(handle.id) == [.suppressedByFocus(delivered: [.system])])
        #expect(
            h.activity.entries.map(\.outcome) == [.suppressed(reason: "dnd")])
        #expect(h.activity.entries.first?.module == AlertHarness.module)
        #expect(h.activity.entries.first?.kind == "session.blocked")
    }

    @Test func resolveDuringFocusWorks() {
        let h = AlertHarness(focusActive: true)
        let handle = h.post()
        h.center.resolve(handle.id)
        #expect(h.center.active.isEmpty)
        #expect(h.peek.retracted.isEmpty)
        #expect(h.outcomes(handle.id) == [.suppressedByFocus(delivered: []), .resolved])
        #expect(h.activity.entries.map(\.outcome) == [.suppressed(reason: "dnd"), .resolved])
    }

    @Test func rulesStillDropBeforeFocus() {
        let h = AlertHarness(kinds: ["session.done": NotifyRule(muted: true)], focusActive: true)
        h.post("session.done")
        #expect(h.center.dropCounts[.muted] == 1)
        #expect(h.center.active.isEmpty)
        #expect(h.activity.entries.map(\.outcome) == [.suppressed(reason: "mute")])
    }

    @Test func monitorFlipsMidTest() async {
        let h = AlertHarness()
        h.post()
        #expect(h.peek.shown.count == 1)
        await h.setFocus(true)
        h.post()
        #expect(h.peek.shown.count == 1)
        #expect(h.sound.played.count == 1)
        await h.setFocus(false)
        h.post()
        #expect(h.peek.shown.count == 2)
        #expect(h.sound.played.count == 2)
        #expect(h.center.active.count == 3)
    }

    @Test func reminderInsideFocusIsSuppressed() async {
        let h = AlertHarness(kinds: ["session.blocked": NotifyRule(reminder: .seconds(600))])
        let handle = h.post()
        #expect(await eventually { h.clock.sleeperCount == 1 })
        await h.setFocus(true)
        h.clock.advance(by: .seconds(600))
        #expect(await eventually { h.center.history.last?.outcome == .reminderSuppressedByFocus })
        #expect(h.peek.shown.count == 1)
        #expect(h.sound.played.count == 1)
        // Suppressed, not deferred: nothing shows when the Focus ends.
        await h.setFocus(false)
        for _ in 0..<10 { await Task.yield() }
        #expect(h.peek.shown.count == 1)
        #expect(h.center.active.map(\.id) == [handle.id])
        #expect(h.activity.entries.last?.outcome == .suppressed(reason: "dnd"))
    }

    @Test func dropAfterFocusShowsNothing() async {
        let h = AlertHarness(focusActive: true)
        _ = h.otherNotifier()
        h.post()
        _ = h.postOther()
        await h.setFocus(false)
        for _ in 0..<10 { await Task.yield() }
        #expect(h.peek.shown.isEmpty)
        #expect(h.sound.played.isEmpty)
        // Still visible in the module tabs.
        #expect(h.center.active.count == 2)
    }

    @Test func replayShowsTheLatestUnresolvedPerModuleOnce() async {
        let h = AlertHarness(global: GlobalNotifyRules(afterFocus: .replay), focusActive: true)
        _ = h.otherNotifier()
        let first = h.post()
        h.now.advance(seconds: 10)
        let second = h.post()
        h.now.advance(seconds: 10)
        let resolvedDuringFocus = h.postOther()
        h.center.resolve(resolvedDuringFocus.id)
        #expect(h.peek.shown.isEmpty)

        await h.setFocus(false)
        #expect(await eventually { h.peek.shown.count == 1 })
        #expect(h.peek.shown.map(\.id) == [second.id])
        // No sound burst: one sound for the one replayed peek, per its rule.
        #expect(h.sound.played.map(\.id) == [second.id])
        #expect(h.outcomes(second.id).last == .replayedAfterFocus([.peek, .sound]))
        #expect(!h.outcomes(first.id).contains(.replayedAfterFocus([.peek, .sound])))
        #expect(h.outcomes(resolvedDuringFocus.id) == [.suppressedByFocus(delivered: []), .resolved])

        // Once only: another Focus cycle with nothing new replays nothing.
        await h.setFocus(true)
        await h.setFocus(false)
        for _ in 0..<10 { await Task.yield() }
        #expect(h.peek.shown.count == 1)
        #expect(h.sound.played.count == 1)
    }

    @Test func replayCoversEveryModuleAndFollowsEachRule() async {
        let h = AlertHarness(
            global: GlobalNotifyRules(afterFocus: .replay),
            kinds: ["session.blocked": NotifyRule(outputs: [.peek])], focusActive: true)
        _ = h.otherNotifier()
        let sessions = h.post()
        h.now.advance(seconds: 5)
        let shelf = h.postOther()
        await h.setFocus(false)
        #expect(await eventually { h.peek.shown.count == 2 })
        #expect(h.peek.shown.map(\.id) == [sessions.id, shelf.id])
        // `session.blocked` routes to peek only; the shelf kind uses the default peek and sound.
        #expect(h.sound.played.map(\.id) == [shelf.id])
        // A replayed peek is retracted on resolve like any other.
        h.center.resolve(sessions.id)
        #expect(h.peek.retracted == [h.peek.tokens[0]])
    }

    @Test func replayFollowsTheSettingAtFocusEnd() async {
        let h = AlertHarness(focusActive: true)
        h.post()
        h.rules.update(global: GlobalNotifyRules(afterFocus: .replay))
        await h.setFocus(false)
        #expect(await eventually { h.peek.shown.count == 1 })
    }

    @Test func systemOnlyAlertIsNotMarkedSuppressed() {
        let h = AlertHarness(kinds: ["session.failed": NotifyRule(outputs: [.system])], focusActive: true)
        h.post("session.failed")
        #expect(h.system.delivered.count == 1)
        #expect(h.center.history.last?.outcome == .delivered([.system]))
        #expect(h.activity.entries.map(\.outcome) == [.posted])
    }
}
