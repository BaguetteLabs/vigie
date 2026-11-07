import AppKit
import Foundation
import ModuleKit
import Observation
import Testing
import VigieUI

@testable import VigieCore

// MARK: - Fakes

/// Records the temporary shortcut bindings instead of registering Carbon hotkeys.
@MainActor
final class FakeTemporaryBackend: TemporaryShortcutBackend {
    private(set) var bound: [String: HotkeySpec] = [:]
    private var handlers: [String: @MainActor () -> Void] = [:]
    private(set) var suspended: Set<String> = []
    private(set) var bindCount = 0

    func bind(name: String, shortcut: HotkeySpec, onKeyUp: @escaping @MainActor () -> Void) {
        bound[name] = shortcut
        handlers[name] = onKeyUp
        bindCount += 1
    }

    func unbind(name: String) {
        bound[name] = nil
        handlers[name] = nil
    }

    func suspend(names: Set<String>) { suspended.formUnion(names) }
    func resume(names: Set<String>) { suspended.subtract(names) }

    /// Simulates pressing the combination: fires whatever is bound to it. Returns false if nothing is.
    @discardableResult
    func press(_ spec: HotkeySpec) -> Bool {
        guard let name = bound.first(where: { $0.value == spec })?.key, let handler = handlers[name] else {
            return false
        }
        handler()
        return true
    }
}

@MainActor
final class RecordingPeekEvents: PeekSinkEvents {
    private(set) var primaries: [ActiveAlert] = []
    private(set) var intents: [UserIntent] = []
    private(set) var dismissals: [ActiveAlert] = []
    private(set) var preemptions: [ActiveAlert] = []

    func peekPrimary(_ alert: ActiveAlert, intent: UserIntent) {
        primaries.append(alert)
        intents.append(intent)
    }

    func peekDismissed(_ alert: ActiveAlert) { dismissals.append(alert) }
    func peekPreempted(_ alert: ActiveAlert) { preemptions.append(alert) }
}

/// A module that takes alert actions.
@MainActor @Observable
final class ActionModule: NotchModule, AlertActionHandler {
    let manifest = ModuleManifest(id: "agents.sessions", name: "Sessions", icon: "circle")
    var state: ModuleState = .hidden
    private(set) var actions: [(id: String, payload: Data, intent: UserIntent?)] = []

    func handleAlertAction(_ actionID: String, payload: Data, intent: UserIntent?) {
        actions.append((actionID, payload, intent))
    }

    func start(context: any ModuleContext) async throws {}
    func stop() async {}
}

/// An `AlertCenter` whose peek sink is a real `PeekPresenter` with fake shortcuts.
@MainActor
final class PeekActionHarness {
    static let module: ModuleID = "agents.sessions"
    let clock = TestClock()
    let anchors = FakePeekAnchors()
    let driver = RecordingPeekDriver()
    let backend = FakeTemporaryBackend()
    let router = RecordingActionRouter()
    let activity = RecordingActivityLog()
    var others: [String: HotkeySpec] = [:]
    private(set) var shortcuts: TemporaryShortcuts!
    private(set) var presenter: PeekPresenter!
    private(set) var center: AlertCenter!

    init(kinds: [String: NotifyRule] = [:]) {
        shortcuts = TemporaryShortcuts(backend: backend, others: { [unowned self] in self.others })
        presenter = PeekPresenter(
            anchors: anchors, theme: ThemeController(library: try! ThemeLoader.loadBundled()), driver: driver,
            clock: clock, dwell: { .seconds(5) }, pointer: { NSPoint(x: 700, y: 980) }, announce: { _ in },
            shortcuts: shortcuts, logger: testLogger)
        center = AlertCenter(
            rules: StaticNotifyRules(global: GlobalNotifyRules(), kinds: [Self.module: kinds]), clock: clock,
            sinks: AlertSinks(peek: presenter, actionRouter: router), activity: activity, log: testLogger)
        _ = center.makeNotifier(
            for: ModuleManifest(
                id: Self.module, name: "Sessions", icon: "circle",
                alertKinds: ["session.blocked", "session.done", "session.failed"]))
    }

    @discardableResult
    func post(
        _ kind: String = "session.blocked", title: String = "api-refactor",
        action: AlertAction? = .module(id: "agents.sessions", actionID: "focus", payload: Data([1]))
    ) -> AlertHandle {
        center.post(
            module: Self.module,
            event: NotifierEvent(kind: kind, severity: .critical, title: title, action: action))
    }

    func advance(_ duration: Duration) async {
        clock.advance(by: duration)
        for _ in 0..<20 { await Task.yield() }
    }
}

// MARK: - Tests

@MainActor @Suite struct PeekActionsTests {
    @Test func shortcutsAreBoundOnlyWhileAPeekIsVisible() {
        let h = PeekActionHarness()
        #expect(h.backend.bound.isEmpty)
        let handle = h.post()
        #expect(h.presenter.visible != nil)
        #expect(
            h.backend.bound == [
                TemporaryShortcuts.primaryName: TemporaryShortcuts.primarySpec,
                TemporaryShortcuts.secondaryName: TemporaryShortcuts.secondarySpec,
            ])
        #expect(h.shortcuts.isActive)
        handle.resolve()
        #expect(h.presenter.visible == nil)
        #expect(h.backend.bound.isEmpty)
        #expect(!h.shortcuts.isActive)
    }

    @Test func shortcutsAreOptionCommandReturnAndDelete() throws {
        #expect(TemporaryShortcuts.primarySpec == (try spec("opt+cmd+return")))
        #expect(TemporaryShortcuts.secondarySpec == (try spec("opt+cmd+delete")))
    }

    @Test func otherKeysReachTheFrontmostApp() throws {
        let h = PeekActionHarness()
        h.post()
        // Only the two peek combinations are registered: bare Esc and every other key stay with the frontmost app.
        #expect(Set(h.backend.bound.values) == [TemporaryShortcuts.primarySpec, TemporaryShortcuts.secondarySpec])
        #expect(!h.backend.press(try spec("cmd+return")))
        #expect(!h.backend.press(try spec("opt+cmd+escape")))
        #expect(h.presenter.visible != nil)
    }

    @Test func dwellExpiryUnbindsTheShortcuts() async {
        let h = PeekActionHarness()
        h.post()
        _ = await eventually { h.clock.sleeperCount == 1 }
        await h.advance(.seconds(5))
        #expect(await eventually { h.presenter.visible == nil })
        #expect(h.backend.bound.isEmpty)
    }

    @Test func aPeekWithoutPrimaryActionBindsOnlyDismiss() {
        let h = PeekActionHarness()
        h.post(action: nil)
        #expect(h.backend.bound.keys.sorted() == [TemporaryShortcuts.secondaryName])
        #expect(!h.backend.press(TemporaryShortcuts.primarySpec))
        #expect(h.presenter.visible != nil)
    }

    @Test func peekShortcutsTakePrecedenceOverOtherVigieShortcuts() throws {
        let h = PeekActionHarness()
        h.others = ["notes.quick": TemporaryShortcuts.primarySpec, "core.expand": try spec("cmd+shift+space")]
        let handle = h.post()
        #expect(h.backend.suspended == ["notes.quick"])
        handle.resolve()
        #expect(h.backend.suspended.isEmpty)
    }

    @Test func primaryShortcutRoutesTheModuleActionWithAnIntentAndRetracts() {
        let h = PeekActionHarness()
        h.post()
        #expect(h.backend.press(TemporaryShortcuts.primarySpec))
        #expect(h.router.calls == [.module("agents.sessions", actionID: "focus", payload: Data([1]))])
        #expect(h.router.moduleIntents.count == 1)
        #expect(h.router.moduleIntents.first! != nil)
        #expect(h.presenter.visible == nil)
        #expect(h.driver.retractCount == 1)
        #expect(h.backend.bound.isEmpty)
        // The alert stays active until its module resolves it.
        #expect(h.center.active.count == 1)
    }

    @Test func clickingThePrimaryButtonAlsoCarriesAnIntent() {
        let h = PeekActionHarness()
        h.post()
        h.driver.presented[0].handlers.primary()
        #expect(h.router.calls.count == 1)
        #expect(h.router.moduleIntents.first! != nil)
        #expect(h.presenter.visible == nil)
    }

    @Test func primaryRoutesSettingsAndURLActions() async throws {
        let h = PeekActionHarness()
        h.post(title: "one", action: .openSettings(pane: "agents"))
        h.backend.press(TemporaryShortcuts.primarySpec)
        let url = try #require(URL(string: "https://example.com"))
        h.post("session.failed", title: "two", action: .openURL(url))
        _ = await eventually { h.clock.sleeperCount == 1 }
        await h.advance(.seconds(3))
        #expect(await eventually { h.presenter.visible != nil })
        h.backend.press(TemporaryShortcuts.primarySpec)
        #expect(h.router.calls == [.settings(pane: "agents"), .url(url)])
    }

    @Test func dismissShortcutCancelsTheReminderAndLeavesTheAlertActive() async {
        let h = PeekActionHarness(kinds: ["session.blocked": NotifyRule(reminder: .seconds(600))])
        h.post()
        #expect(h.backend.press(TemporaryShortcuts.secondarySpec))
        #expect(h.presenter.visible == nil)
        #expect(h.backend.bound.isEmpty)
        #expect(h.router.calls.isEmpty)
        #expect(h.center.active.count == 1)
        #expect(h.center.history.last?.outcome == .dismissed)
        #expect(h.activity.entries.last?.outcome == .dismissed)
        await h.advance(.seconds(700))
        #expect(!h.center.history.contains { if case .reminded = $0.outcome { true } else { false } })
        #expect(h.driver.presented.count == 1)
    }

    @Test func clickingDismissCancelsTheReminder() async {
        let h = PeekActionHarness(kinds: ["session.blocked": NotifyRule(reminder: .seconds(600))])
        h.post()
        h.driver.presented[0].handlers.secondary()
        await h.advance(.seconds(700))
        #expect(h.center.history.map(\.outcome).contains(.dismissed))
        #expect(h.driver.presented.count == 1)
    }

    @Test func theNextPeekRebindsTheShortcutsToItself() async {
        let h = PeekActionHarness()
        h.post(title: "one", action: .openSettings(pane: "one"))
        h.post("session.failed", title: "two", action: .openSettings(pane: "two"))
        h.backend.press(TemporaryShortcuts.secondarySpec)
        #expect(h.backend.bound.isEmpty)
        // Same module: the next peek waits out the A52 rate limit.
        _ = await eventually { h.clock.sleeperCount == 1 }
        await h.advance(.seconds(3))
        #expect(await eventually { h.presenter.visible?.event.title == "two" })
        #expect(h.backend.bound.count == 2)
        h.backend.press(TemporaryShortcuts.primarySpec)
        #expect(h.router.calls == [.settings(pane: "two")])
        #expect(h.backend.bound.isEmpty)
    }

    @Test func moduleActionsReachModulesThatHandleThem() {
        let module = ActionModule()
        let intent = UserIntentMinter.mint(source: .hotkey(TemporaryShortcuts.primaryName))
        #expect(ModuleAlertActions.deliver("focus", payload: Data([7]), intent: intent, to: module))
        #expect(module.actions.count == 1)
        #expect(module.actions.first?.id == "focus")
        #expect(module.actions.first?.payload == Data([7]))
        #expect(module.actions.first?.intent == intent)
        #expect(!ModuleAlertActions.deliver("focus", payload: Data(), intent: nil, to: LaneModule("x")))
        #expect(!ModuleAlertActions.deliver("focus", payload: Data(), intent: nil, to: nil))
    }

    @Test func dismissingAnUnknownAlertIsIgnored() {
        let h = PeekActionHarness()
        h.center.dismiss(UUID())
        #expect(h.center.history.isEmpty)
    }
}
