import AppKit
import Foundation
import SwiftUI
import Testing

@testable import VigieUI

/// Story 7.7: the Usage tab provider cards (FR54, UX-DR29, UX-DR31, UX-DR44, UX-DR58, UX-DR78, UX-DR100).
@MainActor @Suite struct UsageTabTests {
    typealias Window = QuotaDialModel.Window

    static func bar(
        _ kind: QuotaWindowKind, used: Double, elapsed: Double?, paced: Bool = true, warning: Bool = false,
        threshold: Int = 80, reset: UsageReset? = UsageReset(time: "16:40", remaining: "1H52")
    ) -> UsageBarModel {
        UsageBarModel(
            window: Window(
                kind: kind, fraction: used, elapsedFraction: paced ? elapsed : nil, isWarning: warning),
            warnThreshold: threshold, elapsed: elapsed, reset: reset)
    }

    static func card(_ id: String, _ name: String, meta: UsageCardMeta, bars: [UsageBarModel])
        -> UsageProviderCardModel
    {
        let byKind = Dictionary(bars.map { ($0.window.kind, $0.window) }, uniquingKeysWith: { a, _ in a })
        let primary = byKind[.fiveHour] ?? byKind[.weekly] ?? byKind[.daily]
        let secondary = byKind[.fiveHour] == nil ? nil : byKind[.weekly]
        let dial = QuotaDialModel(providerName: name, primary: primary, secondary: secondary)
        return UsageProviderCardModel(id: id, name: name, meta: meta, content: .windows(dial: dial, bars: bars))
    }

    /// The mockup's main state: Claude Code (5h within, weekly ahead +9) and Codex (weekly within +3).
    static let claude = card(
        "claude", "Claude Code", meta: UsageCardMeta(planName: "Max", kind: .warn(threshold: 80)),
        bars: [
            bar(.fiveHour, used: 0.62, elapsed: 0.627),
            bar(.weekly, used: 0.41, elapsed: 0.32, reset: UsageReset(time: "MON 09:00", remaining: "4D18")),
        ])
    static let codex = card(
        "codex", "Codex", meta: UsageCardMeta(planName: "Plus", kind: .warn(threshold: 80)),
        bars: [
            bar(.fiveHour, used: 0.84, elapsed: 0.893, warning: true),
            bar(.weekly, used: 0.31, elapsed: 0.527, reset: UsageReset(time: "SAT 22:10", remaining: "3D07")),
        ])
    static let ultra = card(
        "claude", "Claude Code", meta: UsageCardMeta(planName: "Ultra", kind: .weeklyOnly),
        bars: [bar(.weekly, used: 0.47, elapsed: 0.32)])
    static let gemini = card(
        "gemini", "Gemini CLI", meta: UsageCardMeta(kind: .dailyOnly), bars: [bar(.daily, used: 0.18, elapsed: 0.242)])

    // MARK: Model

    @Test func paceLabels() {
        #expect(Self.bar(.fiveHour, used: 0.62, elapsed: 0.627).paceLabel?.text == "WITHIN PACE")
        #expect(Self.bar(.weekly, used: 0.12, elapsed: 0.09).paceLabel?.text == "WITHIN PACE · +3")
        #expect(Self.bar(.weekly, used: 0.41, elapsed: 0.32).paceLabel?.text == "AHEAD OF PACE · +9")
        // Under half a point reads as no lead.
        #expect(Self.bar(.weekly, used: 0.304, elapsed: 0.30).paceLabel == .within(lead: 0))
    }

    @Test func warningWinsOverPaceAhead() {
        let bar = Self.bar(.fiveHour, used: 0.95, elapsed: 0.2, warning: true)
        #expect(bar.window.pace == .ahead)
        #expect(bar.paceLabel == .warning(threshold: 80))
        #expect(bar.paceLabel?.text == "WARN · ≥ 80%")
        #expect(bar.fill == .warning)
        #expect(
            Self.bar(.fiveHour, used: 0.95, elapsed: 0.2, warning: true, threshold: 90).paceLabel?.text
                == "WARN · ≥ 90%")
    }

    @Test func fills() {
        #expect(Self.bar(.fiveHour, used: 0.5, elapsed: 0.5).fill == .metal(secondary: false))
        #expect(Self.bar(.weekly, used: 0.1, elapsed: 0.5).fill == .metal(secondary: true))
        #expect(Self.bar(.daily, used: 0.1, elapsed: 0.5).fill == .metal(secondary: true))
        #expect(Self.bar(.weekly, used: 0.41, elapsed: 0.32).fill == .ahead)
    }

    @Test func paceOffKeepsElapsedButNoMarkerOrLabel() {
        let bar = Self.bar(.fiveHour, used: 0.9, elapsed: 0.3, paced: false)
        #expect(bar.elapsedText == "ELAPSED 30%")
        #expect(bar.markerFraction == nil)
        #expect(bar.paceLabel == nil)
        #expect(bar.fill == .metal(secondary: false))
        // The warning still shows with pace off.
        #expect(Self.bar(.fiveHour, used: 0.9, elapsed: 0.3, paced: false, warning: true).paceLabel != nil)
    }

    @Test func barGeometryAndText() {
        let bar = Self.bar(.fiveHour, used: 0.62, elapsed: 0.627, threshold: 75)
        #expect(bar.label == "5H")
        #expect(bar.thresholdFraction == 0.75)
        #expect(bar.markerFraction == 0.627)
        #expect(bar.elapsedText == "ELAPSED 63%")
        #expect(L10n.format("usage.bar.value", bar.window.percent) == "62%")
        #expect(L10n.format("usage.bar.in", "1H52") == "IN 1H52")
        #expect(L10n.string("usage.bar.reset") == "RESET")
        #expect(
            bar.accessibilityLabel == "5 hour window 62 percent, reset 16:40 in 1H52, elapsed 63 percent, within pace")
        #expect(Self.bar(.weekly, used: 0.3, elapsed: nil, reset: nil).elapsedText == nil)
    }

    @Test func metaVariants() {
        #expect(UsageCardMeta(planName: "Max", kind: .warn(threshold: 80)).text == "MAX · WARN 80%")
        #expect(UsageCardMeta(kind: .warn(threshold: 80)).text == "WARN 80%")
        #expect(UsageCardMeta(planName: "Ultra", kind: .weeklyOnly).text == "ULTRA · WEEKLY ONLY")
        #expect(UsageCardMeta(kind: .weeklyOnly).text == "WEEKLY ONLY")
        #expect(UsageCardMeta(kind: .dailyOnly).text == "DAILY QUOTA ONLY")
        #expect(UsageCardMeta(kind: .localOnly).text == "LOCAL LOGS ONLY")
        #expect(UsageCardMeta(kind: .warn(threshold: 80), stale: "STALE · 14:02").text == "WARN 80% · STALE · 14:02")
    }

    @Test func emptyAndOverflow() {
        #expect(UsageTabSnapshot(providers: []).isEmpty)
        #expect(!UsageTabSnapshot(providers: [Self.claude, Self.codex]).overflows)
        #expect(UsageTabSnapshot(providers: [Self.codex, Self.ultra, Self.gemini]).overflows)
    }

    @Test func catalogHasEveryTabString() {
        let expected: [String: String] = [
            "usage.history.title": "HISTORY · 7D", "usage.cost.title": "COST · TODAY",
            "usage.card.noPlanWindows": "NO PLAN WINDOWS", "usage.footer.reorder": "DRAG TO REORDER · ALSO IN",
            "usage.footer.settings": "SETTINGS", "usage.tab.settingsShortcut": "⌘,",
        ]
        for (key, value) in expected {
            #expect(L10n.string(key) == value, "\(key)")
        }
        #expect(String(localized: VigieCopy.readingLogs.label) == "READING LOGS…")
        #expect(String(localized: VigieCopy.noUsageProvider.label) == "NO USAGE PROVIDER")
    }

    // MARK: Render

    /// The four states of the AC in A dark, A light and C dark: one provider (Max plan), three providers
    /// overflowing with the footer, no provider, and reading logs. Set `VIGIE_RENDER_DIR` to keep the PNGs.
    @Test(arguments: [
        (Look.dark, ThemeLibrary.defaultVariantID), (.light, ThemeLibrary.defaultVariantID),
        (.dark, "twin-metal-tactical"),
    ])
    func rendersTheTab(look: Look, variant: String) throws {
        let theme = SessionsTabTests.theme(look, variant: variant)
        let suffix = "\(variant)-\(look.rawValue)"
        let states: [(String, UsageTabSnapshot, Int)] = [
            ("one", UsageTabSnapshot(providers: [Self.claude]), 3000),
            ("main", UsageTabSnapshot(providers: [Self.claude, Self.codex]), 5000),
            ("overflow", UsageTabSnapshot(providers: [Self.codex, Self.ultra, Self.gemini]), 5000),
            ("empty", UsageTabSnapshot(providers: []), 500),
            (
                "reading",
                UsageTabSnapshot(providers: [
                    UsageProviderCardModel(
                        id: "claude", name: "Claude Code", meta: UsageCardMeta(kind: .warn(threshold: 80)),
                        content: .readingLogs)
                ]), 300
            ),
            (
                "local",
                UsageTabSnapshot(providers: [
                    UsageProviderCardModel(
                        id: "claude", name: "Claude Code", meta: UsageCardMeta(kind: .localOnly),
                        content: .noPlanWindows)
                ]), 300
            ),
        ]
        for (name, snapshot, minimum) in states {
            var tab = UsageTabView(snapshot: { snapshot }, onOpenSettings: {})
            tab.scrolls = false
            let image = try SessionsTabTests.render(tab, theme: theme, name: "usage-\(name)-\(suffix)")
            #expect(SessionGlyphTests.inkedPixels(image) > minimum, "\(name) \(suffix)")
        }
    }
}

/// Story 11.2 (quota card): the `agents.usage` Home card (UX-DR78, UX-DR97, UX-DR99).
@MainActor @Suite struct UsageHomeCardTests {
    static func stale(_ model: UsageProviderCardModel, _ label: String) -> UsageProviderCardModel {
        var copy = model
        copy.meta.stale = label
        return copy
    }

    static func card(_ providers: [UsageProviderCardModel]) -> UsageHomeCardView {
        UsageHomeCardView(snapshot: { UsageTabSnapshot(providers: providers) })
    }

    @Test func rowsFollowProviderOrder() {
        let rows = Self.card([UsageTabTests.codex, UsageTabTests.gemini, UsageTabTests.claude]).rowsValue()
        #expect(rows.map(\.id) == ["codex", "gemini", "claude"])
        guard case .window(_, let percent, let reset) = rows[0].value else {
            Issue.record("no window")
            return
        }
        #expect(percent == 84)
        #expect(reset == UsageReset(time: "16:40", remaining: "1H52"))
    }

    @Test func warningMetaWinsElseFirstProviderMeta() {
        #expect(Self.card([UsageTabTests.claude, UsageTabTests.codex]).metaValue() == "WARN · ≥ 80%")
        #expect(Self.card([UsageTabTests.claude]).metaValue() == "MAX · WARN 80%")
        #expect(Self.card([]).metaValue() == nil)
    }

    @Test func staleLabelOnTheRightRow() {
        let rows = Self.card([UsageTabTests.claude, Self.stale(UsageTabTests.gemini, "STALE · 14:02")]).rowsValue()
        #expect(rows[0].stale == nil)
        #expect(rows[1].stale == "STALE · 14:02")
    }

    @Test func readingLogsAndNoPlanWindowsRows() {
        let reading = UsageProviderCardModel(
            id: "claude", name: "Claude Code", meta: UsageCardMeta(kind: .warn(threshold: 80)), content: .readingLogs)
        let local = UsageProviderCardModel(
            id: "codex", name: "Codex", meta: UsageCardMeta(kind: .localOnly), content: .noPlanWindows)
        let rows = Self.card([reading, local]).rowsValue()
        #expect(rows[0].value == .readingLogs)
        #expect(rows[1].value == .noPlanWindows)
        #expect(Self.card([]).rowsValue().isEmpty)
        #expect(L10n.string("usage.home.title") == "Usage")
        #expect(VigieCopy.noUsageProvider.sentence != nil)
    }

    @Test(arguments: [0, 1, 3], [Look.dark, .light])
    func rendersInsideTheCell(count: Int, look: Look) throws {
        let theme = SessionsHomeCardTests.theme(look)
        let size = HomeMetrics.cardSize(theme)
        let providers = Array([UsageTabTests.claude, UsageTabTests.codex, UsageTabTests.gemini].prefix(count))
        let stale =
            providers.isEmpty
            ? providers : [providers[0]] + providers.dropFirst().map { Self.stale($0, "STALE · 14:02") }
        var card = Self.card(stale)
        card.scrolls = false
        let view =
            card
            .frame(width: size.width, height: size.height)
            .padding(20)
            .background(look == .dark ? Color(white: 0.22) : Color(white: 0.85))
            .vigieTheme(theme)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: size.width + 40, height: size.height + 40)
        hosting.layoutSubtreeIfNeeded()
        #expect(hosting.fittingSize.height <= size.height + 40 + 0.5)
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let dir = "/private/tmp/claude-501/-Users-me-www-vigie/03a97dc6-097f-4d60-a649-a2f93afa8536/scratchpad/s11.2b"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("usage-card-\(count)-\(look.rawValue).png"))
    }
}
