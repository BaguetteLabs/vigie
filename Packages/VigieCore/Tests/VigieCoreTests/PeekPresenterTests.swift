import AppKit
import Foundation
import ModuleKit
import SwiftUI
import Testing
import VigieUI

@testable import VigieCore

// MARK: - Fakes

@MainActor
final class FakePeekAnchors: PeekAnchorProvider {
    var anchor: PeekAnchor? = PeekAnchor(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        notchRect: CGRect(x: 656, y: 950, width: 200, height: 32), bandHeight: 34)
    private(set) var pointers: [NSPoint?] = []

    func anchor(forDisplayUnder pointer: NSPoint?) -> PeekAnchor? {
        pointers.append(pointer)
        return anchor
    }
}

@MainActor
final class RecordingPeekDriver: PeekPanelDriver {
    struct Presentation {
        let content: PeekContent
        let dwell: PeekDwellState
        let anchor: PeekAnchor
        let handlers: PeekHandlers
    }

    private(set) var presented: [Presentation] = []
    private(set) var dwellUpdates: [PeekDwellState] = []
    private(set) var retractCount = 0

    func present(_ content: PeekContent, dwell: PeekDwellState, anchor: PeekAnchor, handlers: PeekHandlers) {
        presented.append(Presentation(content: content, dwell: dwell, anchor: anchor, handlers: handlers))
    }

    func update(dwell: PeekDwellState) { dwellUpdates.append(dwell) }
    func retract() { retractCount += 1 }
}

@MainActor
final class PeekHarness {
    let clock = TestClock()
    let anchors = FakePeekAnchors()
    let driver = RecordingPeekDriver()
    let themeController = ThemeController(library: try! ThemeLoader.loadBundled())
    var enabled = true
    private(set) var announcements: [String] = []
    private(set) var presenter: PeekPresenter!

    init() {
        presenter = PeekPresenter(
            anchors: anchors, theme: themeController, driver: driver, clock: clock,
            dwell: { .seconds(5) }, enabled: { [unowned self] _ in self.enabled },
            pointer: { NSPoint(x: 700, y: 980) }, announce: { [unowned self] in self.announcements.append($0) },
            logger: testLogger)
    }

    static func alert(
        _ kind: String = "session.blocked", module: ModuleID = "agents.sessions", severity: AlertSeverity = .critical,
        title: String = "api-refactor", action: AlertAction? = .openSettings(pane: "agents"), id: UUID = UUID(),
        reminder: Bool = false
    ) -> ActiveAlert {
        ActiveAlert(
            id: id, module: module,
            event: NotifierEvent(kind: kind, severity: severity, title: title, action: action),
            outputs: [.peek], postedAt: Date(timeIntervalSince1970: 0), isReminder: reminder)
    }

    var visibleTitle: String? { presenter.visible?.event.title }

    /// Waits until the presenter's sleeping tasks (dwell, rate-limit hold) are registered with the clock.
    func settle(sleepers: Int) async {
        let clock = clock
        _ = await eventually { clock.sleeperCount == sleepers }
    }

    func advance(_ duration: Duration) async {
        clock.advance(by: duration)
        // Let resumed tasks hop back to the main actor.
        for _ in 0..<20 { await Task.yield() }
    }
}

// MARK: - Presenter

@MainActor @Suite struct PeekPresenterTests {
    @Test func disabledPeeksShowNothingAndReturnAnInertToken() async {
        let h = PeekHarness()
        h.enabled = false
        let token = h.presenter.show(PeekHarness.alert())
        #expect(h.driver.presented.isEmpty)
        #expect(h.presenter.visible == nil)
        #expect(h.presenter.queuedAlerts.isEmpty)
        #expect(h.announcements.isEmpty)
        h.presenter.retract(token)
        #expect(h.driver.retractCount == 0)
    }

    @Test func queueOrdersBySeverityThenArrival() {
        let h = PeekHarness()
        _ = h.presenter.show(PeekHarness.alert("x.event", module: "m0", severity: .info, title: "first"))
        _ = h.presenter.show(PeekHarness.alert("x.event", module: "m1", severity: .info, title: "info"))
        _ = h.presenter.show(PeekHarness.alert("x.event", module: "m2", severity: .warn, title: "warn"))
        _ = h.presenter.show(PeekHarness.alert("x.event", module: "m3", severity: .critical, title: "critical"))
        _ = h.presenter.show(PeekHarness.alert("x.event", module: "m4", severity: .warn, title: "warn2"))
        #expect(h.visibleTitle == "first")
        #expect(h.presenter.queuedAlerts.map(\.event.title) == ["critical", "warn", "warn2", "info"])
    }

    @Test func queueOrdersByKindUrgency() {
        let h = PeekHarness()
        _ = h.presenter.show(PeekHarness.alert("session.failed", module: "m0", title: "visible"))
        _ = h.presenter.show(PeekHarness.alert("setup.problem", module: "m1", severity: .critical, title: "setup"))
        _ = h.presenter.show(PeekHarness.alert("session.done", module: "m2", severity: .info, title: "done"))
        _ = h.presenter.show(PeekHarness.alert("usage.quota_warning", module: "m3", severity: .warn, title: "quota"))
        _ = h.presenter.show(PeekHarness.alert("time.timer_end", module: "m4", severity: .info, title: "timer"))
        _ = h.presenter.show(PeekHarness.alert("session.blocked", module: "m5", title: "blocked"))
        #expect(
            h.presenter.queuedAlerts.map(\.event.title) == ["blocked", "timer", "quota", "done", "setup"])
    }

    @Test func oneVisibleAtATimeAndTheNextShowsAfterRetract() {
        let h = PeekHarness()
        let first = h.presenter.show(PeekHarness.alert(module: "m1", title: "one"))
        _ = h.presenter.show(PeekHarness.alert(module: "m2", title: "two"))
        #expect(h.driver.presented.count == 1)
        #expect(h.visibleTitle == "one")
        h.presenter.retract(first)
        #expect(h.driver.retractCount == 1)
        #expect(h.driver.presented.count == 2)
        #expect(h.visibleTitle == "two")
        #expect(h.presenter.queuedAlerts.isEmpty)
    }

    @Test func moduleRateLimitHoldsItsNextPeekForThreeSeconds() async {
        let h = PeekHarness()
        let first = h.presenter.show(PeekHarness.alert(module: "m1", title: "one"))
        _ = h.presenter.show(PeekHarness.alert(module: "m1", title: "two"))
        h.presenter.retract(first)
        #expect(h.presenter.visible == nil)
        #expect(h.presenter.queuedAlerts.map(\.event.title) == ["two"])
        // The hold waits for the rate limit.
        await h.settle(sleepers: 1)
        await h.advance(.milliseconds(2900))
        #expect(h.presenter.visible == nil)
        await h.advance(.milliseconds(100))
        #expect(await eventually { h.visibleTitle == "two" })
        #expect(h.driver.presented.count == 2)
    }

    @Test func rateLimitDoesNotHoldOtherModules() {
        let h = PeekHarness()
        let first = h.presenter.show(PeekHarness.alert(module: "m1", title: "one"))
        _ = h.presenter.show(PeekHarness.alert(module: "m1", severity: .critical, title: "same module"))
        _ = h.presenter.show(PeekHarness.alert("session.done", module: "m2", severity: .info, title: "other"))
        h.presenter.retract(first)
        #expect(h.visibleTitle == "other")
        #expect(h.presenter.queuedAlerts.map(\.event.title) == ["same module"])
    }

    @Test func anAlertPeeksOnceExceptThroughItsReminder() async {
        let h = PeekHarness()
        let id = UUID()
        let first = h.presenter.show(PeekHarness.alert(id: id))
        h.presenter.retract(first)
        await h.settle(sleepers: 0)
        await h.advance(.seconds(10))
        _ = h.presenter.show(PeekHarness.alert(id: id))
        #expect(h.driver.presented.count == 1)
        #expect(h.presenter.visible == nil)

        let reminder = h.presenter.show(PeekHarness.alert(id: id, reminder: true))
        #expect(h.driver.presented.count == 2)
        h.presenter.retract(reminder)
        await h.advance(.seconds(10))
        _ = h.presenter.show(PeekHarness.alert(id: id, reminder: true))
        #expect(h.driver.presented.count == 2)
    }

    @Test func dwellExpiryRetracts() async {
        let h = PeekHarness()
        _ = h.presenter.show(PeekHarness.alert())
        #expect(
            h.driver.presented.first?.dwell
                == PeekDwellState(total: .seconds(5), remaining: .seconds(5), isRunning: true))
        await h.settle(sleepers: 1)
        await h.advance(.milliseconds(4900))
        #expect(h.presenter.visible != nil)
        await h.advance(.milliseconds(100))
        #expect(await eventually { h.presenter.visible == nil })
        #expect(h.driver.retractCount == 1)
    }

    @Test func hoverPausesAndLeavingResumesTheDwell() async {
        let h = PeekHarness()
        _ = h.presenter.show(PeekHarness.alert())
        await h.settle(sleepers: 1)
        await h.advance(.seconds(2))
        h.presenter.hoverChanged(true)
        #expect(h.presenter.dwellState == PeekDwellState(total: .seconds(5), remaining: .seconds(3), isRunning: false))
        #expect(h.driver.dwellUpdates.last?.isRunning == false)
        await h.settle(sleepers: 0)
        await h.advance(.seconds(30))
        #expect(h.presenter.visible != nil)

        h.presenter.hoverChanged(false)
        #expect(h.presenter.dwellState?.isRunning == true)
        #expect(h.presenter.dwellState?.remaining == .seconds(3))
        await h.settle(sleepers: 1)
        await h.advance(.milliseconds(2900))
        #expect(h.presenter.visible != nil)
        await h.advance(.milliseconds(100))
        #expect(await eventually { h.presenter.visible == nil })
    }

    @Test func retractingAQueuedTokenDropsIt() {
        let h = PeekHarness()
        let first = h.presenter.show(PeekHarness.alert(module: "m1", title: "one"))
        let queued = h.presenter.show(PeekHarness.alert(module: "m2", title: "two"))
        h.presenter.retract(queued)
        #expect(h.presenter.queuedAlerts.isEmpty)
        #expect(h.visibleTitle == "one")
        h.presenter.retract(first)
        #expect(h.presenter.visible == nil)
        #expect(h.driver.presented.count == 1)
    }

    @Test func announcesKickerTitleAndPrimaryShortcut() {
        let h = PeekHarness()
        _ = h.presenter.show(PeekHarness.alert("session.blocked", title: "api-refactor"))
        #expect(h.announcements == ["Blocked, api-refactor, Option Command Return, Focus terminal"])
    }

    @Test func announcementWithoutAPrimaryActionHasNoShortcut() {
        let h = PeekHarness()
        _ = h.presenter.show(PeekHarness.alert("session.done", title: "docs-site", action: nil))
        #expect(h.announcements == ["Done, docs-site"])
        #expect(h.driver.presented.first?.content.primary == nil)
    }

    @Test func asksTheAnchorProviderWithThePointer() {
        let h = PeekHarness()
        _ = h.presenter.show(PeekHarness.alert())
        #expect(h.anchors.pointers == [NSPoint(x: 700, y: 980)])
        #expect(h.driver.presented.first?.anchor == h.anchors.anchor)
    }

    @Test func noIslandSkipsThePeek() {
        let h = PeekHarness()
        h.anchors.anchor = nil
        _ = h.presenter.show(PeekHarness.alert())
        #expect(h.driver.presented.isEmpty)
        #expect(h.presenter.visible == nil)
        #expect(h.presenter.queuedAlerts.isEmpty)
    }

    @Test func primaryAndDismissReachTheirHandlersAndRetract() {
        let h = PeekHarness()
        let events = RecordingPeekEvents()
        h.presenter.events = events
        _ = h.presenter.show(PeekHarness.alert(module: "m1", title: "one"))
        _ = h.presenter.show(PeekHarness.alert(module: "m2", title: "two"))
        h.driver.presented[0].handlers.primary()
        #expect(events.primaries.map(\.event.title) == ["one"])
        #expect(h.visibleTitle == "two")
        h.driver.presented[1].handlers.secondary()
        #expect(events.dismissals.map(\.event.title) == ["two"])
        #expect(h.presenter.visible == nil)
        #expect(h.driver.retractCount == 2)
    }

    @Test func turningPeeksOffDropsTheQueue() {
        let h = PeekHarness()
        let first = h.presenter.show(PeekHarness.alert(module: "m1", title: "one"))
        _ = h.presenter.show(PeekHarness.alert(module: "m2", title: "two"))
        h.enabled = false
        h.presenter.retract(first)
        #expect(h.presenter.visible == nil)
        #expect(h.presenter.queuedAlerts.isEmpty)
    }

    @Test func worksAsTheAlertCenterPeekSink() async {
        let h = PeekHarness()
        let center = AlertCenter(
            rules: StaticNotifyRules(global: GlobalNotifyRules(), kinds: [:]), clock: h.clock,
            sinks: AlertSinks(peek: h.presenter), log: testLogger)
        let notifier = center.makeNotifier(
            for: ModuleManifest(
                id: "agents.sessions", name: "Sessions", icon: "circle", alertKinds: ["session.blocked"]))
        let handle = center.post(
            module: "agents.sessions",
            event: NotifierEvent(kind: "session.blocked", severity: .critical, title: "api-refactor"))
        _ = notifier
        #expect(h.visibleTitle == "api-refactor")
        center.resolve(handle.id)
        #expect(h.presenter.visible == nil)
    }
}

// MARK: - Anchor and layout

@MainActor @Suite struct PeekAnchorTests {
    static let builtIn = PeekAnchor(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        notchRect: CGRect(x: 656, y: 950, width: 200, height: 32), bandHeight: 34)
    static let external = PeekAnchor(
        screenFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
        notchRect: CGRect(x: 2692, y: 1408, width: 200, height: 32), bandHeight: 34)

    @Test func picksTheIslandUnderThePointer() {
        let anchor = PeekAnchor.select(
            pointer: NSPoint(x: 2000, y: 700), islands: [Self.builtIn, Self.external], main: Self.builtIn)
        #expect(anchor == Self.external)
    }

    @Test func pointerOnTheTopEdgeCounts() {
        let anchor = PeekAnchor.select(
            pointer: NSPoint(x: 2000, y: 1440), islands: [Self.builtIn, Self.external], main: Self.builtIn)
        #expect(anchor == Self.external)
    }

    @Test func fallsBackToTheMainVigieDisplayWhenThePointerDisplayHasNoIsland() {
        // The pointer is on the external display, which shows no island.
        let anchor = PeekAnchor.select(pointer: NSPoint(x: 2000, y: 700), islands: [Self.builtIn], main: Self.builtIn)
        #expect(anchor == Self.builtIn)
        #expect(
            PeekAnchor.select(pointer: nil, islands: [Self.builtIn, Self.external], main: Self.external)
                == Self.external)
        #expect(PeekAnchor.select(pointer: nil, islands: [Self.external], main: nil) == Self.external)
        #expect(PeekAnchor.select(pointer: nil, islands: [], main: nil) == nil)
    }

    @Test func panelIsCenteredUnderTheNotchAtTheTopOfTheScreen() {
        let frame = PeekLayout.panelFrame(anchor: Self.builtIn, size: CGSize(width: 700, height: 150))
        #expect(frame == CGRect(x: 406, y: 832, width: 700, height: 150))
        #expect(frame.midX == Self.builtIn.notchRect.midX)
    }

    @Test func panelStaysOnScreen() {
        var anchor = Self.builtIn
        anchor.notchRect.origin.x = 20
        let frame = PeekLayout.panelFrame(anchor: anchor, size: CGSize(width: 700, height: 150))
        #expect(frame.minX == 0)
    }

    @Test func windowAddsTheShadowMarginOnTheSidesAndBelow() {
        let panel = CGRect(x: 406, y: 832, width: 700, height: 150)
        let window = PeekLayout.windowFrame(panel: panel, shadowMargin: 58)
        #expect(window == CGRect(x: 348, y: 774, width: 816, height: 208))
        #expect(window.maxY == panel.maxY)
    }

    @Test func peekPanelIsNeverKeyAndFloatsAboveTheIsland() {
        let panel = PeekPanel(contentRect: CGRect(x: 0, y: 0, width: 700, height: 150), rootView: EmptyView())
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.level.rawValue > NSWindow.Level.statusBar.rawValue + 1)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.ignoresCycle))
    }
}

// MARK: - Content

@MainActor @Suite struct PeekContentMapperTests {
    static let theme = ThemeController(library: try! ThemeLoader.loadBundled()).theme

    @Test(arguments: [
        ("session.blocked", PeekKind.blocked, ColorRole.statusBlocked, "Blocked", "Focus terminal"),
        ("session.failed", .failed, .statusFailed, "Failed", "Focus terminal"),
        ("session.done", .done, .statusDone, "Done", "Focus terminal"),
        ("usage.quota_warning", .quotaWarning, .quotaWarning, "Quota · warn", "Open usage"),
        ("setup.problem", .setupProblem, .ink2, "Setup", "Open settings"),
        ("time.timer_end", .timerEnd, .iris1, "Timer · ended", "Open time"),
        ("calendar.reminder", .calendarReminder, .iris1, "Calendar", "Open calendar"),
        ("shelf.expiring", .generic, .ink1, "Alert", "Open"),
    ])
    func mapsKindToCopyAndHue(kind: String, peek: PeekKind, role: ColorRole, kicker: String, primary: String) {
        let content = PeekContentMapper.content(
            for: PeekHarness.alert(kind, title: "t"), theme: Self.theme)
        #expect(content.kind == peek)
        #expect(content.accentRole == role)
        #expect(content.kicker == kicker)
        #expect(content.primary.map { String(localized: $0.label) } == primary)
        #expect(content.primary?.shortcut == "⌥⌘↵")
        #expect(content.secondary.map { String(localized: $0.label) } == "Dismiss")
        #expect(content.secondary?.shortcut == "⌥⌘⌫")
    }

    @Test func carriesTheModuleTitleAndDetail() {
        let alert = ActiveAlert(
            id: UUID(), module: "agents.sessions",
            event: NotifierEvent(
                kind: "session.blocked", severity: .critical, title: "vigie / api-refactor",
                body: "Claude Code wants to run Bash"),
            outputs: [.peek], postedAt: Date())
        let content = PeekContentMapper.content(for: alert, theme: Self.theme)
        #expect(content.title == "vigie / api-refactor")
        #expect(content.body == "Claude Code wants to run Bash")
        #expect(content.primary == nil)
    }

    @Test func timePeeksUseGoldInTwinMetal() throws {
        let theme = try ThemeLoader.loadBundled().resolve(themeID: "twin-metal-tactical", look: .dark).theme
        let content = PeekContentMapper.content(for: PeekHarness.alert("time.timer_end"), theme: theme)
        #expect(content.accentRole == .gold)
    }

    @Test func breakPeekSecondaryIsSkip() {
        let content = PeekContentMapper.content(for: PeekHarness.alert("time.break_reminder"), theme: Self.theme)
        #expect(content.secondary.map { String(localized: $0.label) } == "Skip")
        #expect(content.primary.map { String(localized: $0.label) } == "Start break")
    }
}
