import AppKit
import Foundation
import ModuleKit
import Observation
import Synchronization
import Testing

@testable import VigieCore

/// Records posted events with the id of each handle and counts resolutions.
final class NotchFakeNotifier: Notifier {
    private struct State {
        var posted: [(event: NotifierEvent, id: UUID)] = []
        var resolved: [UUID] = []
    }
    private let state = Mutex(State())

    func post(_ event: NotifierEvent) -> AlertHandle {
        let id = UUID()
        state.withLock { $0.posted.append((event, id)) }
        return AlertHandle(id: id) { [weak self] in self?.state.withLock { $0.resolved.append(id) } }
    }

    var events: [NotifierEvent] { state.withLock { $0.posted.map(\.event) } }
    var ids: [UUID] { state.withLock { $0.posted.map(\.id) } }
    var resolveCount: Int { state.withLock { $0.resolved.count } }
}

@MainActor
final class NotchFakeRunningApps: RunningApplicationsObserving {
    var ids: Set<String> = []
    func runningBundleIDs() -> Set<String> { ids }
    var changes: AsyncStream<Void> { AsyncStream { _ in } }
}

@MainActor @Observable
final class NotchFakeDrawn {
    var physical = true
}

@MainActor @Observable
final class NotchFakeDismissals {
    var ids: Set<UUID> = []
}

/// A KVO-compliant stand-in for `NSWorkspace`.
@MainActor
final class NotchFakeWorkspace: NSObject {
    @objc dynamic var runningApplications: [String] = []
    var running: Set<String> {
        get { Set(runningApplications) }
        set { runningApplications = newValue.sorted() }
    }

    var live: WorkspaceRunningApplications {
        WorkspaceRunningApplications(
            observing: self, keyPath: \.runningApplications, bundleIDs: { [unowned self] in self.running })
    }
}

@MainActor
struct OtherNotchAppMonitorTests {
    let apps = NotchFakeRunningApps()
    let notch = NotchFakeDrawn()
    let dismissals = NotchFakeDismissals()
    let notifier = NotchFakeNotifier()

    private func makeMonitor() -> OtherNotchAppMonitor {
        let notch = notch
        let dismissals = dismissals
        return OtherNotchAppMonitor(
            apps: apps, drawsOnPhysicalNotch: { notch.physical }, notifier: notifier,
            wasDismissed: { dismissals.ids.contains($0) }, log: testLogger)
    }

    @Test func listedAppOnPhysicalNotchPostsOnceWithTheExactEvent() throws {
        apps.ids = ["lo.cafe.NotchNook"]
        let monitor = makeMonitor()
        monitor.start()
        monitor.refresh()
        #expect(notifier.events.count == 1)
        let event = try #require(notifier.events.first)
        #expect(event.kind == "setup.problem")
        #expect(event.severity == .warn)
        #expect(event.title == "Another notch app is running: NotchNook")
        #expect(event.body == "Two apps can't share the notch. Quit NotchNook, or choose another display for Vigie.")
        #expect(event.action == .openSettings(pane: "display"))
        #expect(event.dedupeKey == "notch-app.lo.cafe.notchnook")
        #expect(event.category == "DISPLAY")
        monitor.stop()
    }

    @Test func theDisplayPaneIsARealSettingsPane() {
        #expect(SettingsPaneCatalog.corePaneIDs.contains(OtherNotchAppMonitor.settingsPane))
    }

    @Test func unlistedAppPostsNothing() {
        apps.ids = ["com.apple.finder"]
        let monitor = makeMonitor()
        monitor.start()
        #expect(notifier.events.isEmpty)
        monitor.stop()
    }

    @Test func noPhysicalNotchPostsNothingUntilOneIsDrawn() async {
        apps.ids = ["lo.cafe.NotchNook"]
        notch.physical = false
        let monitor = makeMonitor()
        monitor.start()
        #expect(notifier.events.isEmpty)
        notch.physical = true
        #expect(await eventually { notifier.events.count == 1 })
        monitor.stop()
    }

    @Test func bundleIDMatchIgnoresCase() {
        apps.ids = ["LO.CAFE.NOTCHNOOK"]
        let monitor = makeMonitor()
        monitor.start()
        #expect(notifier.events.count == 1)
        monitor.stop()
    }

    @Test func twoListedAppsGiveTwoAlerts() {
        apps.ids = ["lo.cafe.NotchNook", "wiki.qaq.NotchDrop"]
        let monitor = makeMonitor()
        monitor.start()
        monitor.refresh()
        #expect(Set(notifier.events.compactMap(\.dedupeKey)).count == 2)
        #expect(notifier.events.count == 2)
        monitor.stop()
    }

    @Test func quittingResolvesTheAlert() {
        apps.ids = ["lo.cafe.NotchNook"]
        let monitor = makeMonitor()
        monitor.start()
        apps.ids = []
        monitor.refresh()
        #expect(notifier.resolveCount == 1)
        monitor.stop()
        #expect(notifier.resolveCount == 1)
    }

    @Test func noLongerDrawingOnAPhysicalNotchResolves() async {
        apps.ids = ["lo.cafe.NotchNook"]
        let monitor = makeMonitor()
        monitor.start()
        notch.physical = false
        #expect(await eventually { notifier.resolveCount == 1 })
        monitor.stop()
    }

    @Test func dismissedAppIsNotPostedAgainWhileRunning() throws {
        apps.ids = ["lo.cafe.NotchNook"]
        let monitor = makeMonitor()
        monitor.start()
        dismissals.ids.insert(try #require(notifier.ids.first))
        monitor.refresh()
        monitor.refresh()
        #expect(notifier.events.count == 1)
        #expect(notifier.resolveCount == 0)
        monitor.stop()
    }

    @Test func dismissedAppIsNotPostedAgainAfterQuitAndReopen() throws {
        apps.ids = ["lo.cafe.NotchNook"]
        let monitor = makeMonitor()
        monitor.start()
        dismissals.ids.insert(try #require(notifier.ids.first))
        apps.ids = []
        monitor.refresh()
        apps.ids = ["lo.cafe.NotchNook"]
        monitor.refresh()
        #expect(notifier.events.count == 1)
        monitor.stop()
    }

    @Test func dismissedAppIsNotPostedAgainAfterADisplayChange() throws {
        apps.ids = ["lo.cafe.NotchNook"]
        let monitor = makeMonitor()
        monitor.start()
        dismissals.ids.insert(try #require(notifier.ids.first))
        notch.physical = false
        monitor.refresh()
        notch.physical = true
        monitor.refresh()
        #expect(notifier.events.count == 1)
        monitor.stop()
    }

    @Test func aNewMonitorNextLaunchWarnsAgain() throws {
        apps.ids = ["lo.cafe.NotchNook"]
        let first = makeMonitor()
        first.start()
        dismissals.ids.insert(try #require(notifier.ids.first))
        first.refresh()
        first.stop()
        let second = makeMonitor()
        second.start()
        #expect(notifier.events.count == 2)
        second.stop()
    }

    @Test func resolvedWithoutDismissalWarnsAgainOnReopen() {
        apps.ids = ["lo.cafe.NotchNook"]
        let monitor = makeMonitor()
        monitor.start()
        apps.ids = []
        monitor.refresh()
        apps.ids = ["lo.cafe.NotchNook"]
        monitor.refresh()
        #expect(notifier.events.count == 2)
        monitor.stop()
    }

    @Test func stopEndsObservationAndResolves() async {
        apps.ids = ["lo.cafe.NotchNook"]
        let monitor = makeMonitor()
        monitor.start()
        monitor.stop()
        #expect(notifier.resolveCount == 1)
        notch.physical = false
        notch.physical = true
        try? await Task.sleep(for: .milliseconds(100))
        #expect(notifier.events.count == 1)
    }

    @Test func workspaceChangesReachTheMonitorThroughKVO() async {
        let workspace = NotchFakeWorkspace()
        let live = workspace.live
        let notch = notch
        let monitor = OtherNotchAppMonitor(
            apps: live, drawsOnPhysicalNotch: { notch.physical }, notifier: notifier,
            wasDismissed: { _ in false }, log: testLogger)
        monitor.start()
        #expect(notifier.events.isEmpty)
        workspace.running = ["theboringteam.boringnotch"]
        #expect(await eventually { notifier.events.count == 1 })
        workspace.running = []
        #expect(await eventually { notifier.resolveCount == 1 })
        monitor.stop()
    }

    @Test func endingTheStreamRemovesTheObservation() async {
        let workspace = NotchFakeWorkspace()
        let live = workspace.live
        let task = Task { @MainActor in for await _ in live.changes {} }
        #expect(await eventually { workspace.observationInfo != nil })
        task.cancel()
        #expect(await eventually { workspace.observationInfo == nil })
    }

    @Test func theRealWorkspaceKeyPathCanBeObservedAndTornDown() async {
        let live = WorkspaceRunningApplications()
        _ = live.runningBundleIDs()
        let task = Task { @MainActor in for await _ in live.changes {} }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await task.value
    }

    @Test func aDismissalOfAnAlertPostedByTheStreamIsNotedBeforeTheHistoryLosesIt() async throws {
        let workspace = NotchFakeWorkspace()
        let notch = notch
        let dismissals = dismissals
        let monitor = OtherNotchAppMonitor(
            apps: workspace.live, drawsOnPhysicalNotch: { notch.physical }, notifier: notifier,
            wasDismissed: { dismissals.ids.contains($0) }, log: testLogger)
        monitor.start()
        workspace.running = ["lo.cafe.NotchNook"]
        #expect(await eventually { notifier.events.count == 1 })
        dismissals.ids.insert(try #require(notifier.ids.first))
        // The dismissal is noted by the tracked change, without any other refresh.
        try? await Task.sleep(for: .milliseconds(100))
        dismissals.ids.removeAll()
        workspace.running = []
        #expect(await eventually { notifier.resolveCount == 1 })
        workspace.running = ["lo.cafe.NotchNook"]
        try? await Task.sleep(for: .milliseconds(100))
        #expect(notifier.events.count == 1)
        monitor.stop()
    }

    @Test func theListHasNoDuplicatesOrEmptyEntries() {
        let all = KnownNotchApps.all
        #expect(all.count == 7)
        #expect(Set(all.map { $0.bundleID.lowercased() }).count == all.count)
        #expect(all.allSatisfy { !$0.bundleID.isEmpty && !$0.name.isEmpty })
        #expect(KnownNotchApps.app(forBundleID: "WIKI.QAQ.NOTCHDROP")?.name == "NotchDrop")
        #expect(KnownNotchApps.app(forBundleID: "com.apple.finder") == nil)
    }

    @Test func catalogKeysResolve() {
        let keys = [
            "vigiecore.setup.title.notchApp", "vigiecore.setup.body.notchApp", "vigiecore.setup.category.display",
        ]
        for key in keys {
            let value = Bundle.module.localizedString(forKey: key, value: "MISSING", table: nil)
            #expect(value != "MISSING" && value != key)
        }
    }

    @Test func dismissingThroughARealAlertCenterFeedsTheHook() throws {
        let center = AlertCenter(rules: StaticNotifyRules(), log: testLogger)
        let realNotifier = center.makeNotifier(for: SetupProblemReporter.manifest)
        apps.ids = ["lo.cafe.NotchNook"]
        let notch = notch
        let monitor = OtherNotchAppMonitor(
            apps: apps, drawsOnPhysicalNotch: { notch.physical }, notifier: realNotifier,
            wasDismissed: { id in center.history.contains { $0.alertID == id && $0.outcome == .dismissed } },
            log: testLogger)
        monitor.start()
        let alert = try #require(center.active.first)
        #expect(alert.kind == "setup.problem")
        center.dismiss(alert.id)
        apps.ids = []
        monitor.refresh()
        apps.ids = ["lo.cafe.NotchNook"]
        monitor.refresh()
        #expect(center.active.isEmpty)
        monitor.stop()
    }
}
