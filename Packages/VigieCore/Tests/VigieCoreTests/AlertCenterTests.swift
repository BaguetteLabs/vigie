import Foundation
import ModuleKit
import Synchronization
import Testing

@testable import VigieCore

final class MutableNow: Sendable {
    private let value: Mutex<Date>
    init(_ date: Date) { value = Mutex(date) }
    var date: Date { value.withLock { $0 } }
    func set(_ date: Date) { value.withLock { $0 = date } }
    func advance(seconds: Double) { value.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

@MainActor
struct AlertHarness {
    static let module: ModuleID = "agents.sessions"
    let rules: StaticNotifyRules
    let clock = TestClock()
    let now: MutableNow
    let peek = RecordingPeekSink()
    let system = RecordingSystemSink()
    let sound = RecordingSoundSink()
    let router = RecordingActionRouter()
    let center: AlertCenter
    let notifier: any Notifier

    init(
        global: GlobalNotifyRules = GlobalNotifyRules(), kinds: [String: NotifyRule] = [:],
        now: Date = parisDate(12, 0)
    ) {
        rules = StaticNotifyRules(global: global, kinds: [Self.module: kinds])
        self.now = MutableNow(now)
        let nowBox = self.now
        center = AlertCenter(
            rules: rules, clock: clock, now: { nowBox.date }, calendar: { parisCalendar },
            sinks: AlertSinks(peek: peek, system: system, sound: sound, actionRouter: router), log: testLogger)
        notifier = center.makeNotifier(
            for: ModuleManifest(
                id: Self.module, name: "Sessions", icon: "circle",
                alertKinds: ["session.blocked", "session.done", "session.failed"]))
    }

    @discardableResult
    func post(
        _ kind: String = "session.blocked", severity: AlertSeverity = .critical, dedupeKey: String? = nil,
        metrics: [String: Double] = [:], action: AlertAction? = nil
    ) -> AlertHandle {
        center.post(
            module: Self.module,
            event: NotifierEvent(
                kind: kind, severity: severity, title: "api-refactor", action: action, dedupeKey: dedupeKey,
                metrics: metrics))
    }

    var deliveredCount: Int { center.history.filter { if case .delivered = $0.outcome { true } else { false } }.count }
}

@MainActor @Suite struct AlertCenterTests {
    @Test func undeclaredKindIsDroppedWithInertHandle() {
        let h = AlertHarness()
        let handle = h.notifier.post(NotifierEvent(kind: "subagent.stopped", severity: .critical, title: "x"))
        #expect(h.center.dropCounts[.undeclaredKind] == 1)
        #expect(h.center.active.isEmpty)
        #expect(h.peek.shown.isEmpty && h.sound.played.isEmpty && h.system.delivered.isEmpty)
        handle.resolve()
        #expect(h.peek.retracted.isEmpty)
        #expect(h.center.history.last?.outcome == .dropped(.undeclaredKind))
    }

    @Test func undeclaredForAnUnknownModule() {
        let h = AlertHarness()
        h.center.post(module: "shelf", event: NotifierEvent(kind: "session.blocked", severity: .critical, title: "x"))
        #expect(h.center.dropCounts[.undeclaredKind] == 1)
    }

    @Test func moduleNotifierDeliversWithItsModuleID() {
        let h = AlertHarness()
        let handle = h.notifier.post(NotifierEvent(kind: "session.blocked", severity: .critical, title: "x"))
        #expect(h.center.active.map(\.id) == [handle.id])
        #expect(h.center.active.first?.module == AlertHarness.module)
        #expect(h.peek.shown.count == 1)
    }

    @Test func postFromAnotherThreadIsDeliveredInOrderWithResolve() async {
        let h = AlertHarness()
        let notifier = h.notifier
        await Task.detached {
            let handle = notifier.post(NotifierEvent(kind: "session.blocked", severity: .critical, title: "x"))
            handle.resolve()
        }.value
        #expect(await eventually { h.center.history.count == 2 })
        #expect(h.peek.shown.count == 1)
        #expect(h.peek.retracted.count == 1)
        #expect(h.center.active.isEmpty)
    }

    @Test func mutedKindIsDropped() {
        let h = AlertHarness(kinds: ["session.done": NotifyRule(muted: true)])
        h.post("session.done")
        #expect(h.center.dropCounts[.muted] == 1)
        h.post("session.blocked")
        #expect(h.deliveredCount == 1)
    }

    @Test func emptyOutputsSilenceTheKind() {
        let h = AlertHarness(kinds: ["session.done": NotifyRule(outputs: [])])
        h.post("session.done")
        #expect(h.center.dropCounts[.noOutputs] == 1)
        #expect(h.peek.shown.isEmpty)
    }

    @Test func minSeverityDropsLowerSeverities() {
        let h = AlertHarness(global: GlobalNotifyRules(defaults: NotifyRule(minSeverity: .warn)))
        h.post(severity: .info)
        #expect(h.center.dropCounts[.belowMinSeverity] == 1)
        h.post(severity: .warn)
        h.post(severity: .critical)
        #expect(h.deliveredCount == 2)
    }

    @Test func quietHoursDropAcrossMidnight() throws {
        let quiet = try #require(QuietHours("22:00-08:00"))
        let h = AlertHarness(
            global: GlobalNotifyRules(defaults: NotifyRule(quietHours: quiet)), now: parisDate(23, 30))
        h.post()
        h.now.set(parisDate(7, 59, day: 8))
        h.post()
        #expect(h.center.dropCounts[.quietHours] == 2)
        h.now.set(parisDate(8, 0, day: 8))
        h.post()
        h.now.set(parisDate(21, 59, day: 8))
        h.post()
        #expect(h.deliveredCount == 2)
        #expect(h.peek.shown.count == 2)
    }

    @Test func cooldownIsPerDedupeKey() {
        let h = AlertHarness(global: GlobalNotifyRules(defaults: NotifyRule(cooldown: .seconds(60))))
        h.post(dedupeKey: "s1")
        h.now.advance(seconds: 30)
        h.post(dedupeKey: "s1")
        #expect(h.center.dropCounts[.cooldown] == 1)
        h.post(dedupeKey: "s2")
        #expect(h.deliveredCount == 2)
        h.now.advance(seconds: 30)
        h.post(dedupeKey: "s1")
        #expect(h.deliveredCount == 3)
        #expect(h.center.dropCounts[.cooldown] == 1)
    }

    @Test func zeroCooldownNeverDrops() {
        let h = AlertHarness()
        h.post(dedupeKey: "s1")
        h.post(dedupeKey: "s1")
        #expect(h.deliveredCount == 2)
    }

    @Test func minWorkingTimeConditionUsesEventMetrics() {
        let h = AlertHarness(kinds: [
            "session.done": NotifyRule(conditions: [.minWorkingTime(.seconds(30))])
        ])
        h.post("session.done", severity: .info, metrics: ["working_duration": 29.9])
        h.post("session.done", severity: .info)
        #expect(h.center.dropCounts[.conditionNotMet] == 2)
        h.post("session.done", severity: .info, metrics: ["working_duration": 30])
        h.post("session.done", severity: .info, metrics: ["working_duration": 120])
        #expect(h.deliveredCount == 2)
    }

    @Test func configuredOutputsReachOnlyThoseSinks() {
        let h = AlertHarness(kinds: ["session.blocked": NotifyRule(outputs: [.peek, .sound])])
        h.post()
        #expect(h.peek.shown.count == 1)
        #expect(h.sound.played.count == 1)
        #expect(h.system.delivered.isEmpty)
    }

    @Test func systemOutputWhenConfigured() {
        let h = AlertHarness(kinds: ["session.failed": NotifyRule(outputs: [.system])])
        h.post("session.failed")
        #expect(h.system.delivered.map(\.kind) == ["session.failed"])
        #expect(h.peek.shown.isEmpty && h.sound.played.isEmpty)
    }

    @Test func defaultOutputsForEverySeverity() {
        let h = AlertHarness()
        h.post(severity: .info)
        h.post(severity: .warn)
        h.post(severity: .critical)
        #expect(h.peek.shown.count == 3)
        #expect(h.sound.played.count == 3)
        #expect(h.system.delivered.isEmpty)
        #expect(h.center.active.allSatisfy { $0.outputs == [.peek, .sound] })
    }

    @Test func reminderReplaysPeekAndSoundOnce() async {
        let h = AlertHarness(kinds: [
            "session.blocked": NotifyRule(reminder: .seconds(600), outputs: [.peek, .sound, .system])
        ])
        h.post()
        #expect(await eventually { h.clock.sleeperCount == 1 })
        h.clock.advance(by: .seconds(599))
        await Task.yield()
        #expect(h.peek.shown.count == 1)
        h.clock.advance(by: .seconds(1))
        #expect(await eventually { h.peek.shown.count == 2 })
        #expect(h.sound.played.count == 2)
        #expect(h.system.delivered.count == 1)
        #expect(h.peek.shown.last?.isReminder == true)
        // The first peek is retracted when the reminder peek replaces it.
        #expect(h.peek.retracted == [h.peek.tokens[0]])

        h.clock.advance(by: .seconds(3600))
        for _ in 0..<10 { await Task.yield() }
        #expect(h.clock.sleeperCount == 0)
        #expect(h.peek.shown.count == 2)
        #expect(h.sound.played.count == 2)
        #expect(h.center.active.count == 1)
    }

    @Test func resolveCancelsReminderAndRetractsPeek() async {
        let h = AlertHarness(kinds: ["session.blocked": NotifyRule(reminder: .seconds(600))])
        let handle = h.post()
        #expect(await eventually { h.clock.sleeperCount == 1 })
        handle.resolve()
        #expect(h.peek.retracted == [h.peek.tokens[0]])
        #expect(h.center.active.isEmpty)
        #expect(await eventually { h.clock.sleeperCount == 0 })
        h.clock.advance(by: .seconds(600))
        for _ in 0..<10 { await Task.yield() }
        #expect(h.peek.shown.count == 1)
        #expect(h.sound.played.count == 1)
        handle.resolve()
        #expect(h.peek.retracted.count == 1)
    }

    @Test func reminderInsideQuietHoursIsSuppressed() async throws {
        let quiet = try #require(QuietHours("22:00-08:00"))
        let h = AlertHarness(
            global: GlobalNotifyRules(defaults: NotifyRule(quietHours: quiet)),
            kinds: ["session.blocked": NotifyRule(reminder: .seconds(600))], now: parisDate(21, 55))
        h.post()
        #expect(await eventually { h.clock.sleeperCount == 1 })
        h.now.set(parisDate(22, 5))
        h.clock.advance(by: .seconds(600))
        #expect(await eventually { h.center.history.last?.outcome == .reminderSuppressed })
        #expect(h.peek.shown.count == 1)
    }

    @Test func actionsAreRouted() throws {
        let h = AlertHarness()
        let payload = Data([1, 2, 3])
        h.post(action: .module(id: "agents.sessions", actionID: "focus", payload: payload))
        let alert = try #require(h.center.active.first)
        h.center.activate(alert)
        h.center.perform(.module(id: "shelf", actionID: "other", payload: Data()), for: alert)
        h.center.perform(.openSettings(pane: "alerts"), for: alert)
        let url = try #require(URL(string: "https://example.com/usage"))
        h.center.perform(.openURL(url), for: alert)
        #expect(
            h.router.calls == [
                .module("agents.sessions", actionID: "focus", payload: payload),
                .module("agents.sessions", actionID: "other", payload: Data()),
                .settings(pane: "alerts"),
                .url(url),
            ])
    }

    @Test func rulesChangeRefreshesTheCache() async {
        let h = AlertHarness()
        h.post("session.done")
        #expect(h.deliveredCount == 1)
        h.rules.update(kinds: [AlertHarness.module: ["session.done": NotifyRule(muted: true)]])
        #expect(await eventually { h.center.rulesRevision == 1 })
        h.post("session.done")
        #expect(h.center.dropCounts[.muted] == 1)
        #expect(h.deliveredCount == 1)
    }

    @Test func historyIsCapped() {
        let rules = StaticNotifyRules()
        let center = AlertCenter(rules: rules, historyLimit: 3, log: testLogger)
        let notifier = center.makeNotifier(
            for: ModuleManifest(id: "shelf", name: "Shelf", icon: "tray", alertKinds: ["shelf.expiring"]))
        for index in 0..<5 {
            notifier.post(NotifierEvent(kind: "shelf.expiring", severity: .info, title: "\(index)"))
        }
        #expect(center.history.count == 3)
        #expect(center.active.count == 5)
    }

    @Test func contextFactoryUsesTheAlertCenter() {
        let center = AlertCenter(rules: StaticNotifyRules(), log: testLogger)
        let factory = CoreModuleContextFactory(
            environment: makeEnvironment(makeTempDirectory()), eventBus: InProcessEventBus(), alertCenter: center)
        let manifest = ModuleManifest(id: "dev.sample", name: "Sample", icon: "circle", alertKinds: ["sample.ping"])
        let context = factory.makeContext(for: manifest, tracker: RegistrationTracker())
        context.notifier.post(NotifierEvent(kind: "sample.ping", severity: .info, title: "x"))
        context.notifier.post(NotifierEvent(kind: "sample.other", severity: .info, title: "x"))
        #expect(center.active.map(\.module) == ["dev.sample"])
        #expect(center.dropCounts[.undeclaredKind] == 1)
    }
}
