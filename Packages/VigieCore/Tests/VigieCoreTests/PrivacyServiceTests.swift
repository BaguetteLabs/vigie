import AppKit
import Foundation
import ModuleKit
import SwiftUI
import Testing
import VigieUI

@testable import VigieCore

/// Story 21.2: the core Privacy mode state and the Notifier outputs while it is active (AD-13, AD-24, UX-DR98).
@MainActor @Suite struct PrivacyServiceTests {
    static let seedPrefix = "SEEDED-SECRET"

    // MARK: State

    @Test func forcedOnIsActiveAndContextFollows() async {
        let privacy = CorePrivacyService()
        #expect(!privacy.isActive && !privacy.context.isActive)
        var changes = privacy.context.changes.makeAsyncIterator()
        privacy.setForced(true)
        #expect(privacy.isActive && privacy.isForced)
        #expect(privacy.context.isActive)
        #expect(await changes.next() == true)
        privacy.setForced(false)
        #expect(!privacy.isActive)
        #expect(await changes.next() == false)
    }

    @Test func activeIsForcedOrDetected() {
        let privacy = CorePrivacyService()
        privacy.setDetected(true)
        #expect(privacy.isActive)
        privacy.setForced(true)
        privacy.setDetected(false)
        #expect(privacy.isActive)
        privacy.setForced(false)
        #expect(!privacy.isActive)
        #expect(CorePrivacyService(forced: true).isActive)
    }

    @Test func defaultDetectorNeverTurnsItOn() async {
        let privacy = CorePrivacyService()
        await privacy.refreshDetection()
        #expect(!privacy.isActive)
        #expect(privacy.detector.requiredPermission == nil)
    }

    @Test func pluggedDetectorDrivesTheState() async {
        let privacy = CorePrivacyService(
            detector: PrivacyDetectionProbe(
                mode: .titleHeuristic,
                windows: { [WindowSnapshot(owner: "zoom.us", name: "zoom share toolbar window")] },
                hasScreenRecording: { true }))
        await privacy.refreshDetection()
        #expect(privacy.isDetected && privacy.isActive)
    }

    @Test func modulesReadTheSameState() {
        let privacy = CorePrivacyService()
        let factory = CoreModuleContextFactory(
            environment: makeEnvironment(makeTempDirectory()), eventBus: InProcessEventBus(), privacy: privacy)
        let manifest = ModuleManifest(id: "dev.sample", name: "Sample", icon: "circle")
        let context = factory.makeContext(for: manifest, tracker: RegistrationTracker())
        #expect(!context.privacy.isActive)
        privacy.setForced(true)
        #expect(context.privacy.isActive)
    }

    // MARK: Outputs

    @Test func togglingPostsNoAlertPeekOrSound() {
        let peek = RecordingPeekSink()
        let sound = RecordingSoundSink()
        let system = RecordingSystemSink()
        let center = AlertCenter(
            rules: StaticNotifyRules(), sinks: AlertSinks(peek: peek, system: system, sound: sound), log: testLogger)
        let privacy = CorePrivacyService()
        let factory = CoreModuleContextFactory(
            environment: makeEnvironment(makeTempDirectory()), eventBus: InProcessEventBus(), alertCenter: center,
            privacy: privacy)
        _ = factory.makeContext(for: SetupProblemReporter.manifest, tracker: RegistrationTracker())
        privacy.setForced(true)
        privacy.setForced(false)
        privacy.setDetected(true)
        #expect(peek.shown.isEmpty && sound.played.isEmpty && system.delivered.isEmpty)
        #expect(center.active.isEmpty && center.history.isEmpty)
    }

    static func alert(_ kind: String = "session.blocked") -> ActiveAlert {
        ActiveAlert(
            id: UUID(), module: "agents.sessions",
            event: NotifierEvent(
                kind: kind, severity: .critical, title: "\(seedPrefix)-1 / api",
                body: "Claude Code wants to run \(seedPrefix)-2", category: "PERMISSION"),
            outputs: [.system], postedAt: Date())
    }

    @Test func systemNotificationCarriesOnlyTheKindLabelWhilePrivate() async {
        let client = FakeNotificationCenterClient(status: .authorized)
        let privacy = CorePrivacyService(forced: true)
        let sink = SystemNotificationSink(client: client, router: RecordingActionRouter(), privacy: privacy)
        await sink.show(alert: Self.alert())
        await sink.show(alert: Self.alert("setup.problem"))
        await sink.show(alert: Self.alert("usage.quota_warning"))
        #expect(client.added.map(\.content.title) == ["BLOCKED", "SETUP", "QUOTA · WARN"])
        #expect(client.added.allSatisfy { $0.content.body.isEmpty && $0.content.subtitle.isEmpty })
        privacy.setForced(false)
        await sink.show(alert: Self.alert())
        #expect(client.added.last?.content.title.hasPrefix(Self.seedPrefix) == true)
    }

    @Test func peekAnnouncementLeavesTheTitleOut() {
        let privacy = CorePrivacyService(forced: true)
        let anchors = FakePeekAnchors()
        let driver = RecordingPeekDriver()
        var announcements: [String] = []
        let presenter = PeekPresenter(
            anchors: anchors, theme: ThemeController(library: try! ThemeLoader.loadBundled()), driver: driver,
            clock: TestClock(), pointer: { NSPoint(x: 700, y: 980) }, announce: { announcements.append($0) },
            privacy: privacy, logger: testLogger)
        var alert = Self.alert()
        alert = ActiveAlert(
            id: alert.id, module: alert.module, event: alert.event, outputs: [.peek], postedAt: alert.postedAt)
        _ = presenter.show(alert)
        #expect(announcements.count == 1)
        #expect(!announcements[0].contains(Self.seedPrefix))
        #expect(announcements[0].hasPrefix("Blocked"))
        // The panel gets the content; PeekView masks it from the environment the root sets.
        #expect(driver.presented.count == 1)
    }

    @Test func peekRootSetsPrivacyForThePanel() {
        let privacy = CorePrivacyService(forced: true)
        let model = PeekPanelModel()
        model.content = PeekContentMapper.content(
            for: Self.alert(), theme: ThemeController(library: try! ThemeLoader.loadBundled()).theme)
        model.dwell = PeekDwellState(total: .seconds(5), remaining: .seconds(5), isRunning: false)
        model.isRevealed = true
        let root = PeekRootView(
            model: model, themeController: ThemeController(library: try! ThemeLoader.loadBundled()), privacy: privacy)
        let strings = AXStrings.collect(root, size: CGSize(width: 800, height: 240))
        #expect(!strings.contains { $0.contains(Self.seedPrefix) })
        #expect(strings.contains("Privacy mode on"))
        privacy.setForced(false)
        let open = AXStrings.collect(root, size: CGSize(width: 800, height: 240))
        #expect(open.contains { $0.contains(Self.seedPrefix) })
        #expect(!open.contains("Privacy mode on"))
    }
}

/// The host's roots set `privacyActive`: the eye-slash shows in the expanded tab row only while active.
@MainActor @Suite(.serialized) struct PrivacyHostTests {
    @Test func expandedRootShowsTheIndicatorWhilePrivate() async {
        let f = ExpandedFixture()
        await f.start()
        f.host.expand(focus: f.intent)
        let root = ExpandedRootView(host: f.host, themeController: f.host.themeController)
        let size = CGSize(width: 900, height: 520)
        #expect(!AXStrings.collect(root, size: size).contains("Privacy mode on"))
        f.host.privacy.setForced(true)
        #expect(AXStrings.collect(root, size: size).contains("Privacy mode on"))
    }

    @Test func hostTakesTheLaunchState() async {
        let f = ExpandedFixture()
        await f.start()
        let privacy = CorePrivacyService(forced: true)
        let host = NotchHost(
            themeController: f.host.themeController, registry: f.registry, contextMenu: NotchContextMenu(),
            displays: { [] }, privacy: privacy, logger: testLogger)
        #expect(host.privacy === privacy && host.privacy.isActive)
    }
}

/// Labels and values of every accessibility element of a rendered view.
@MainActor enum AXStrings {
    static func collect(_ view: some View, size: CGSize) -> [String] {
        announceAccessibilityClient()
        let (window, hosting) = hostOffscreen(view, size: size)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        var strings: [String] = []
        func visit(_ element: Any, depth: Int) {
            guard depth < 40, let object = element as? NSObject else { return }
            for key in ["accessibilityLabel", "accessibilityValue", "accessibilityIdentifier"]
            where object.responds(to: NSSelectorFromString(key)) {
                if let text = object.value(forKey: key) as? String, !text.isEmpty { strings.append(text) }
            }
            guard object.responds(to: NSSelectorFromString("accessibilityChildren")) else { return }
            for child in object.value(forKey: "accessibilityChildren") as? [Any] ?? [] {
                visit(child, depth: depth + 1)
            }
        }
        visit(hosting, depth: 0)
        window.close()
        return strings
    }
}
