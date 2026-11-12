import AppKit
import Foundation
import ModuleKit
import Testing
import VigieUI

@testable import VigieCore

/// Story 13.4: the `calendar.reminder` peek (now accent, event-track beacon, Join call / Open calendar, Dismiss
/// routed to the module), its rank, `after_focus`, its sound and the Sounds pane row.
@MainActor @Suite struct CalendarPeekTests {
    static let calendar: ModuleID = "calendar"
    static let theme = ThemeController(library: try! ThemeLoader.loadBundled()).theme
    static let manifest = ModuleManifest(
        id: calendar, name: "Calendar", icon: "calendar", alertKinds: ["calendar.reminder"])

    static func action(_ id: String) -> AlertAction {
        .module(id: calendar, actionID: id, payload: Data("standup@1".utf8))
    }

    /// As the Calendar module posts it (CalendarReminders).
    static func reminder(join: Bool = false) -> NotifierEvent {
        NotifierEvent(
            kind: "calendar.reminder", severity: .info, title: "Standup", body: "16:00–16:30 · Work",
            action: action(join ? "reminder.join" : "reminder.open"), dedupeKey: "calendar:standup@1:1",
            category: "in 10 min", secondaryAction: action("reminder.dismiss"),
            primaryLabel: join ? "Join call" : nil)
    }

    static func alert(_ event: NotifierEvent) -> ActiveAlert {
        ActiveAlert(id: UUID(), module: calendar, event: event, outputs: [.peek], postedAt: Date())
    }

    // MARK: Style

    @Test func reminderPeekUsesTheNowAccentAndTheEventTrackBeacon() throws {
        let content = PeekContentMapper.content(for: Self.alert(Self.reminder()), theme: Self.theme)
        #expect(content.kind == .calendarReminder)
        #expect(content.kind.showsBeacon)
        #expect(content.accentRole == .iris1, "A: iris-1, never a status hue or the calendar color")
        #expect(content.kicker == "Calendar · in 10 min")
        #expect(content.title == "Standup")
        #expect(content.body == "16:00–16:30 · Work")
        #expect(content.primary.map { String(localized: $0.label) } == "Open calendar")
        #expect(content.primary?.shortcut == "⌥⌘↵")
        #expect(content.secondary.map { String(localized: $0.label) } == "Dismiss")
        #expect(content.secondary?.shortcut == "⌥⌘⌫")
        #expect(content.tertiary == nil)
        #expect(
            PeekContentMapper.announcement(for: content)
                == "Calendar · in 10 min, Standup, Option Command Return, Open calendar")

        let twin = try ThemeLoader.loadBundled().resolve(themeID: "twin-metal-tactical", look: .dark).theme
        #expect(PeekContentMapper.content(for: Self.alert(Self.reminder()), theme: twin).accentRole == .gold)
    }

    @Test func videoLinkMakesThePrimaryJoinCall() {
        let content = PeekContentMapper.content(for: Self.alert(Self.reminder(join: true)), theme: Self.theme)
        #expect(content.primary.map { String(localized: $0.label) } == "Join call")
        #expect(PeekContentMapper.announcement(for: content).hasSuffix("Option Command Return, Join call"))
    }

    @Test func ranksWithBreakDueAndTimerEnd() {
        #expect(AlertUrgency.rank(forKind: "calendar.reminder") == AlertUrgency.rank(forKind: "time.break_reminder"))
        #expect(AlertUrgency.rank(forKind: "calendar.reminder") == AlertUrgency.rank(forKind: "time.timer_end"))
        #expect(AlertUrgency.rank(forKind: "calendar.reminder") > AlertUrgency.rank(forKind: "session.blocked"))
        #expect(AlertUrgency.rank(forKind: "calendar.reminder") < AlertUrgency.rank(forKind: "usage.quota_warning"))
    }

    @Test func privacyKeepsOnlyTheKindLabel() {
        let content = PeekContentMapper.content(for: Self.alert(Self.reminder()), theme: Self.theme).redacted()
        #expect(content.title == PrivacyMask.text)
        #expect(content.body == PrivacyMask.text)
        #expect(content.kicker == "Calendar · in 10 min")
        #expect(SystemNotificationSink.kindLabel(for: Self.alert(Self.reminder())) == "CALENDAR")
    }

    // MARK: Actions

    @MainActor final class Harness {
        let clock = TestClock()
        let backend = FakeTemporaryBackend()
        let router = RecordingActionRouter()
        let driver = RecordingPeekDriver()
        let shortcuts: TemporaryShortcuts
        let presenter: PeekPresenter
        let center: AlertCenter

        init() {
            shortcuts = TemporaryShortcuts(backend: backend)
            presenter = PeekPresenter(
                anchors: FakePeekAnchors(), theme: ThemeController(library: try! ThemeLoader.loadBundled()),
                driver: driver, clock: clock, dwell: { .seconds(5) }, pointer: { NSPoint(x: 700, y: 980) },
                announce: { _ in }, shortcuts: shortcuts, logger: testLogger)
            center = AlertCenter(
                rules: StaticNotifyRules(global: GlobalNotifyRules(), kinds: [:]), clock: clock,
                sinks: AlertSinks(peek: presenter, actionRouter: router), log: testLogger)
            _ = center.makeNotifier(for: CalendarPeekTests.manifest)
        }
    }

    @Test func shortcutsAreBoundOnlyWhileThePeekShowsAndRouteToTheModule() {
        let h = Harness()
        #expect(h.backend.bound.isEmpty)
        h.center.post(module: Self.calendar, event: Self.reminder(join: true))
        #expect(h.backend.bound[TemporaryShortcuts.primaryName] == TemporaryShortcuts.primarySpec)
        #expect(h.backend.bound[TemporaryShortcuts.secondaryName] == TemporaryShortcuts.secondarySpec)
        #expect(h.backend.bound[TemporaryShortcuts.tertiaryName] == nil)
        #expect(h.backend.press(TemporaryShortcuts.primarySpec))
        #expect(h.router.calls == [.module(Self.calendar, actionID: "reminder.join", payload: Data("standup@1".utf8))])
        #expect(h.backend.bound.isEmpty, "unbound when the peek retracts")
    }

    @Test func dismissRoutesToTheModuleSoItResolves() {
        let h = Harness()
        let handle = h.center.post(module: Self.calendar, event: Self.reminder())
        #expect(h.backend.press(TemporaryShortcuts.secondarySpec))
        #expect(
            h.router.calls == [.module(Self.calendar, actionID: "reminder.dismiss", payload: Data("standup@1".utf8))])
        #expect(h.center.active.map(\.id) == [handle.id], "the module resolves it")
        handle.resolve()
        #expect(h.center.active.isEmpty)
    }

    // MARK: Focus

    @Test func replayShowsAnUnresolvedReminderAfterFocus() async {
        let h = AlertHarness(global: GlobalNotifyRules(afterFocus: .replay), focusActive: true)
        _ = h.center.makeNotifier(for: Self.manifest)
        let handle = h.center.post(module: Self.calendar, event: Self.reminder())
        #expect(h.peek.shown.isEmpty)
        #expect(h.sound.played.isEmpty)
        await h.setFocus(false)
        #expect(await eventually { h.peek.shown.map(\.id) == [handle.id] })
    }

    @Test func replayNeverShowsAReminderWhoseEventEnded() async {
        let h = AlertHarness(global: GlobalNotifyRules(afterFocus: .replay), focusActive: true)
        _ = h.center.makeNotifier(for: Self.manifest)
        let handle = h.center.post(module: Self.calendar, event: Self.reminder())
        handle.resolve()  // the module resolves it at the event's end
        await h.setFocus(false)
        for _ in 0..<10 { await Task.yield() }
        #expect(h.peek.shown.isEmpty)
    }

    @Test func dropShowsNothingAfterFocus() async {
        let h = AlertHarness(focusActive: true)
        _ = h.center.makeNotifier(for: Self.manifest)
        h.center.post(module: Self.calendar, event: Self.reminder())
        await h.setFocus(false)
        for _ in 0..<10 { await Task.yield() }
        #expect(h.peek.shown.isEmpty)
        #expect(h.sound.played.isEmpty)
        #expect(h.center.active.count == 1, "still active until its event ends")
    }

    // MARK: Sound

    @Test func soundIsOffByDefaultAndPlaysOnceWhenSet() async {
        #expect(SoundTable.key(for: "calendar.reminder") == "calendar_reminder")
        #expect(defaultSoundSettings.values["calendar_reminder"] == "off")
        let h = SoundSinkHarness()
        await h.play("calendar.reminder")
        #expect(h.player.played.isEmpty)
        h.settings.values["calendar_reminder"] = "builtin:warn"
        await h.play("calendar.reminder")
        #expect(h.player.played.count == 1)
        #expect(SoundTable.naturalBuiltIn(for: "calendar_reminder") == "warn")
    }

    @Test func soundsPaneListsTheCalendarReminderLast() {
        #expect(SoundTable.settingsKeys.last == "calendar_reminder")
        #expect(SoundTable.settingsKeys == SoundTable.allSoundKeys)
        let key = "config.sounds.calendar_reminder"
        #expect(Bundle.module.localizedString(forKey: key, value: nil, table: "Config") != key)
    }
}
