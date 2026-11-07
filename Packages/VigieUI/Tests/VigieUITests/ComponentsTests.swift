import Foundation
import SwiftUI
import Testing

@testable import VigieUI

private func minutes(_ count: Int) -> Duration { .seconds(count * 60) }

@Suite struct StatusLabelTests {
    let formatter = StatusLabelFormatter(timeZone: TimeZone(identifier: "Europe/Paris")!)

    @Test(
        arguments: [
            (SessionStatus.idle, nil, "IDLE"),
            (.idle, minutes(5), "IDLE"),
            (.working, nil, "WORKING"),
            (.working, minutes(14), "WORKING · 14M"),
            (.done, nil, "DONE"),
            (.done, minutes(1), "DONE · 1M"),
            (.blocked, nil, "BLOCKED"),
            (.blocked, minutes(12), "BLOCKED · 12M"),
            (.failed, nil, "FAILED"),
            (.failed, minutes(41), "FAILED · 41M"),
            (.stale, nil, "STALE"),
            (.stale, minutes(18), "STALE · 18M"),
        ] as [(SessionStatus, Duration?, String)])
    func sessionLabels(status: SessionStatus, elapsed: Duration?, expected: String) {
        #expect(formatter.label(for: status, elapsed: elapsed) == expected)
    }

    @Test(arguments: [
        (Duration.seconds(30), "0M"),
        (.seconds(119), "1M"),
        (minutes(59), "59M"),
        (minutes(60), "1H"),
        (minutes(112), "1H52"),
        (minutes(125), "2H05"),
        (minutes(24 * 60), "1D"),
        (minutes(42 * 60 + 10), "1D 18H"),
        (.seconds(-5), "0M"),
    ])
    func elapsedFormat(duration: Duration, expected: String) {
        #expect(formatter.elapsed(duration) == expected)
    }

    @Test func runLabels() {
        // 2026-11-04 13:44 UTC = 14:44 in Paris.
        let downAt = Date(timeIntervalSince1970: 1_793_799_840)
        #expect(formatter.label(for: RunStatus.running) == "RUNNING")
        #expect(formatter.label(for: RunStatus.failedExit(3)) == "FAILED · EXIT 3")
        #expect(formatter.label(for: RunStatus.failedExit(2)) == "FAILED · EXIT 2")
        #expect(formatter.label(for: RunStatus.ok) == "OK")
        #expect(formatter.label(for: RunStatus.warn) == "WARN")
        #expect(formatter.label(for: RunStatus.down) == "DOWN")
        #expect(formatter.label(for: RunStatus.ok, qualifier: .checkedAgo(minutes(2))) == "OK · CHECKED 2 MIN AGO")
        #expect(formatter.label(for: RunStatus.ok, qualifier: .checkedAgo(.seconds(20))) == "OK · CHECKED <1 MIN AGO")
        #expect(formatter.label(for: RunStatus.warn, qualifier: .checkedAgo(minutes(112))) == "WARN · CHECKED 1H52 AGO")
        #expect(formatter.label(for: RunStatus.down, qualifier: .since(downAt)) == "DOWN SINCE 14:44")
        #expect(formatter.label(for: RunStatus.ok, qualifier: .since(downAt)) == "OK · SINCE 14:44")
        #expect(formatter.label(for: RunStatus.ok, qualifier: .detail("UP")) == "OK · UP")
        #expect(
            formatter.label(for: StatusLevel.down, qualifier: .checkedAgo(minutes(2))) == "DOWN · CHECKED 2 MIN AGO")
    }

    @Test func clockUsesTheFormatterTimeZone() {
        let date = Date(timeIntervalSince1970: 1_793_799_840)
        let utc = StatusLabelFormatter(timeZone: TimeZone(identifier: "UTC")!)
        #expect(utc.label(for: RunStatus.down, qualifier: .since(date)) == "DOWN SINCE 13:44")
    }

    @Test func colorRoles() {
        #expect(SessionStatus.idle.colorRole == .statusIdle)
        #expect(SessionStatus.working.colorRole == .statusWorking)
        #expect(SessionStatus.done.colorRole == .statusDone)
        #expect(SessionStatus.blocked.colorRole == .statusBlocked)
        #expect(SessionStatus.failed.colorRole == .statusFailed)
        #expect(SessionStatus.stale.colorRole == .ink3)
        #expect(RunStatus.running.colorRole == .ink3)
        #expect(RunStatus.failedExit(1).colorRole == .statusFailed)
        #expect(RunStatus.ok.colorRole == .statusIdle)
        #expect(RunStatus.warn.colorRole == .quotaWarningText)
        #expect(RunStatus.down.colorRole == .statusFailed)
    }
}

@Suite struct StatusMarkTests {
    @Test func stylePerLevelAndLook() {
        for look in Look.allCases {
            let ok = StatusMarkStyle(level: .ok, look: look)
            #expect(ok.shape == .ring)
            #expect(ok.shapeRole == .statusIdle)
            #expect(ok.labelRole == .statusIdle)
            let down = StatusMarkStyle(level: .down, look: look)
            #expect(down.shape == .cross)
            #expect(down.shapeRole == .statusFailed)
            #expect(down.labelRole == .statusFailed)
            let warn = StatusMarkStyle(level: .warn, look: look)
            #expect(warn.shape == .triangle)
            #expect(warn.shapeRole == .quotaWarning)
        }
        #expect(StatusMarkStyle(level: .warn, look: .dark).labelRole == .quotaWarning)
        #expect(StatusMarkStyle(level: .warn, look: .light).labelRole == .quotaWarningText)
    }

    @Test func sizesComeFromTheTheme() {
        let theme = ComponentFixtures.theme(.dark)
        #expect(StatusMarkSize.large.length(in: theme) == 26)
        #expect(StatusMarkSize.medium.length(in: theme) == 16)
        #expect(StatusMarkSize.small.length(in: theme) == 10)
        #expect(StatusMarkSize.large.length(in: .empty) == 26)
    }

    @Test func userStatusColorsFollow() {
        let library = ComponentFixtures.library
        let theme = library.resolve(
            themeID: ThemeLibrary.defaultVariantID, look: .dark, overrides: [.statusIdle: "#112233"]
        ).theme
        let style = StatusMarkStyle(level: .ok, look: theme.look)
        #expect(theme.themeColor(style.shapeRole).hex == "#112233")
    }
}

@Suite struct AccessibilityLabelTests {
    @Test func sessionFormat() {
        #expect(
            AccessibilityLabel.session(
                project: "vigie", session: "api-refactor", status: .blocked, elapsed: .seconds(120))
                == "vigie / api-refactor, blocked, 2 minutes")
        #expect(AccessibilityLabel.session(project: "vigie", status: .idle) == "vigie, idle")
        #expect(
            AccessibilityLabel.session(project: "blog", status: .done, elapsed: .seconds(60)) == "blog, done, 1 minute")
        #expect(
            AccessibilityLabel.session(project: "infra", session: "backup", status: .failed, elapsed: minutes(65))
                == "infra / backup, failed, 1 hour, 5 minutes")
    }

    @Test func itemFormat() {
        #expect(AccessibilityLabel.item(name: "vigie.app", level: .ok) == "vigie.app, OK")
        #expect(AccessibilityLabel.item(name: "Agents", status: "needs attention") == "Agents, needs attention")
        #expect(AccessibilityLabel.item(name: "vigie.app", level: .down, detail: "503") == "vigie.app, DOWN, 503")
        #expect(AccessibilityLabel.control("Open settings", shortcut: "⌘,") == "Open settings, ⌘,")
        #expect(AccessibilityLabel.control("Copy", shortcut: nil) == "Copy")
    }
}

@Suite struct CopyTests {
    /// Every catalog key the components use.
    static let keys: [String] = {
        var keys = [
            "status.running", "status.ok", "status.warn", "status.down", "status.failedExit", "status.withDetail",
            "status.down.since", "status.qualifier.since", "status.qualifier.checkedMinutesAgo",
            "status.qualifier.checkedUnderMinute", "status.qualifier.checkedAgo", "status.elapsed.minutes",
            "status.elapsed.hours", "status.elapsed.hoursMinutes", "status.elapsed.days", "status.elapsed.daysHours",
            "a11y.path", "a11y.join", "a11y.grip", "action.openSettings", "action.openSystemSettings", "scroll.hint",
            "setup.kicker", "setup.calendar.topic", "setup.calendar.title", "setup.calendar.sentence",
            "setup.calendar.secondary", "empty.shelf.sentence",
        ]
        keys += SessionStatus.allCases.flatMap { [$0.labelKey, $0.accessibilityKey] }
        keys += labelKeys + sentenceKeys
        return keys
    }()

    static let labelKeys = [
        "empty.agents.noAgent.label", "empty.agents.noSessions.label", "empty.home.label", "empty.usage.label",
        "empty.usage.readingLogs.label", "empty.usage.noHistory.label", "empty.usage.noCost.label",
        "empty.shelf.label", "empty.calendar.label", "empty.time.label", "empty.notes.label",
        "empty.notes.noMatch.label", "empty.notes.locked.label", "setup.calendar.topic", "scroll.hint",
    ]

    static let sentenceKeys = [
        "empty.agents.noAgent.sentence", "empty.agents.noSessions.sentence", "empty.home.sentence",
        "empty.usage.sentence", "empty.notes.sentence", "empty.notes.locked.sentence", "setup.calendar.title",
        "setup.calendar.sentence",
    ]

    static let allCopy: [VigieCopy.EmptyState] = [
        VigieCopy.noAgentConnected, VigieCopy.noActiveSessions, VigieCopy.noWidgets, VigieCopy.noUsageProvider,
        VigieCopy.readingLogs, VigieCopy.noHistoryYet, VigieCopy.noCostData, VigieCopy.stashEmpty(days: 7),
        VigieCopy.noEventsToday, VigieCopy.nothingRunning, VigieCopy.noNotes, VigieCopy.noMatch,
        VigieCopy.notesLocked,
    ]

    @Test(arguments: keys)
    func keyResolves(key: String) {
        let value = Bundle.module.localizedString(forKey: key, value: "\u{1}missing", table: nil)
        #expect(value != key && value != "\u{1}missing", "\(key) is not in the VigieUI catalog")
    }

    @Test func copyResolvesThroughResources() {
        for copy in Self.allCopy {
            let label = String(localized: copy.label)
            #expect(!label.contains("."), "unresolved \(label)")
            if let sentence = copy.sentence {
                #expect(String(localized: sentence).hasSuffix("."))
            }
        }
        #expect(String(localized: VigieCopy.noAgentConnected.label) == "NO AGENT CONNECTED")
        #expect(
            String(localized: VigieCopy.noAgentConnected.sentence!)
                == "Connect Claude Code, Codex or Gemini in Settings.")
        #expect(String(localized: VigieCopy.openSettings) == "Open settings")
        #expect(String(localized: VigieCopy.scrollHint) == "SCROLL ↓")
        #expect(
            VigieCopy.setupKicker(topic: String(localized: VigieCopy.calendarAccess.topic)) == "SETUP · CALENDAR ACCESS"
        )
        #expect(String(localized: VigieCopy.calendarAccess.title) == "Vigie can't read your calendars")
        #expect(String(localized: VigieCopy.calendarAccess.primaryAction) == "Open System Settings")
        #expect(String(localized: VigieCopy.calendarAccess.secondaryAction) == "Calendar settings")
    }

    @Test func stashSentenceCarriesTheDays() {
        #expect(
            String(localized: VigieCopy.stashEmpty(days: 7).sentence!)
                == "Drag a file, text or image onto the notch, or press ⌘V, to keep it here for 7 days.")
        #expect(String(localized: VigieCopy.stashEmpty(days: 1).sentence!).hasSuffix("for 1 day."))
    }

    @Test func voiceAndTone() {
        for key in Self.keys {
            let value = Bundle.module.localizedString(forKey: key, value: nil, table: nil)
            #expect(!value.contains("!"), "\(key) has an exclamation mark")
        }
        for key in Self.labelKeys {
            let value = Bundle.module.localizedString(forKey: key, value: nil, table: nil)
            #expect(value == value.uppercased(), "\(key) is not uppercase")
        }
        for status in SessionStatus.allCases {
            let value = StatusLabelFormatter().label(for: status)
            #expect(value == value.uppercased())
        }
    }
}

@Suite struct ScrollMetricsTests {
    @Test func edges() {
        let fits = ScrollMetrics(offset: 0, contentHeight: 80, visibleHeight: 100)
        #expect(!fits.overflows && !fits.hasMoreAbove && !fits.hasMoreBelow)
        #expect(fits.thumb(minimumLength: 14) == nil)

        let top = ScrollMetrics(offset: 0, contentHeight: 400, visibleHeight: 100)
        #expect(top.hasMoreBelow && !top.hasMoreAbove)
        #expect(top.thumb(minimumLength: 14)?.length == 25)
        #expect(top.thumb(minimumLength: 14)?.top == 0)

        let middle = ScrollMetrics(offset: 150, contentHeight: 400, visibleHeight: 100)
        #expect(middle.hasMoreBelow && middle.hasMoreAbove)
        #expect(middle.thumb(minimumLength: 14)?.top == 37.5)

        let end = ScrollMetrics(offset: 300, contentHeight: 400, visibleHeight: 100)
        #expect(!end.hasMoreBelow && end.hasMoreAbove)
        #expect(end.thumb(minimumLength: 14)?.top == 75)

        let long = ScrollMetrics(offset: 0, contentHeight: 10_000, visibleHeight: 100)
        #expect(long.thumb(minimumLength: 14)?.length == 14)
    }
}

@Suite struct ComponentStyleTests {
    @Test func variantStyles() {
        let chrome = ComponentFixtures.theme(.dark)
        let twin = ComponentFixtures.theme(.dark, variant: "twin-metal-tactical")
        #expect(!chrome.usesCornerMarks)
        #expect(twin.usesCornerMarks)
        #expect(chrome.actionHeight == 30)
        #expect(chrome.actionRadius(height: 30) == 15)
        #expect(twin.actionRadius(height: 30) == 0)
        #expect(chrome.radius(.card) == 16)
        #expect(twin.radius(.card) == 0)
        let insets = chrome.componentInsets("setup-card", "padding")
        #expect(insets?.top == 18 && insets?.leading == 20)
    }

    @Test func loopsStopInCalmOrReduceMotion() {
        var theme = ComponentFixtures.theme(.dark)
        #expect(!theme.stopsLoops)
        theme.presence = .calm
        #expect(theme.stopsLoops && !theme.reducesMotion)
        theme.presence = .full
        theme.accessibility = AccessibilityAdjustments(reduceMotion: true)
        #expect(theme.stopsLoops && theme.reducesMotion && theme.enterAnimation == nil)
    }
}

@MainActor @Suite struct ComponentRenderTests {
    private func render(_ view: some View, look: Look, variant: String = ThemeLibrary.defaultVariantID) {
        let theme = ComponentFixtures.theme(look, variant: variant)
        let renderer = ImageRenderer(
            content: view.frame(width: 360, height: 240).vigieTheme(theme).environment(\.timeZone, .gmt))
        #expect(renderer.nsImage != nil)
    }

    @Test(arguments: [
        (Look.dark, ThemeLibrary.defaultVariantID), (.light, ThemeLibrary.defaultVariantID),
        (.dark, "twin-metal-tactical"), (.light, "twin-metal-tactical"),
    ])
    func componentsRender(look: Look, variant: String) {
        render(
            WidgetCard(title: Text(verbatim: "Sessions"), meta: Text(verbatim: "Sorted by urgency")) {
                VStack {
                    StatusLabel(.blocked, elapsed: minutes(12))
                    StatusLabel(.failedExit(3))
                    StatusMark(level: .ok, size: .large, qualifier: .checkedAgo(minutes(2)))
                    StatusMark(level: .warn, size: .medium)
                    StatusMark(level: .down, size: .small, qualifier: .since(Date()))
                    GripGlyph()
                    InlineChip(verbatim: "Copy")
                    InlineChip(text: VigieCopy.scrollHint, tone: .accent)
                    Text(verbatim: "row").rowHoverBrighten().keyboardSelectionRing(isSelected: true)
                }
            }, look: look, variant: variant)
        render(EmptyStateBlock(VigieCopy.noUsageProvider, settingsShortcut: "⌘,") {}, look: look, variant: variant)
        render(EmptyStateBlock(label: VigieCopy.noMatch.label), look: look, variant: variant)
        render(
            SetupCard(VigieCopy.calendarAccess, primaryAction: {}, secondaryAction: {}), look: look, variant: variant)
        render(
            ActionButton(label: VigieCopy.openSettings, shortcut: "⌥⌘↵", role: .primary) {}, look: look,
            variant: variant)
        render(
            ScrollFadeList(thumbWidth: 3) {
                ForEach(0..<30, id: \.self) { _ in StatusLabel(.idle) }
            }, look: look, variant: variant)
    }
}

enum ComponentFixtures {
    static let library: ThemeLibrary = {
        do { return try ThemeLoader.loadBundled() } catch { fatalError("bundled themes: \(error)") }
    }()

    static func theme(_ look: Look, variant: String = ThemeLibrary.defaultVariantID) -> Theme {
        library.resolve(themeID: variant, look: look).theme
    }
}
