import AppKit
import Foundation
import ModuleKit
import SwiftUI
import Testing

@testable import VigieUI

/// Story 21.2: the Privacy display filter in VigieUI (AD-24, UX-DR98). Seeded user text must not appear in a
/// redacted model or in the rendered accessibility tree while Privacy mode is active; dots render instead.
@MainActor @Suite struct PrivacyTests {
    static func seed(_ n: Int) -> String { "SEEDED-SECRET-\(n)" }
    static let seedPrefix = "SEEDED-SECRET"
    static let theme = Fixtures.library.resolve(themeID: ThemeLibrary.defaultVariantID, look: .dark).theme

    /// Everything a value prints through `dump` (stored properties, wrappers included).
    static func dumped(_ value: Any) -> String {
        var out = ""
        dump(value, to: &out)
        return out
    }

    /// Labels, values, titles, help and identifiers of every accessibility element under `view`.
    static func accessibilityStrings(_ view: some View, size: CGSize) -> [String] {
        announceAccessibilityClient()
        let (window, hosting) = hostOffscreen(view.vigieTheme(theme), size: size)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        var strings: [String] = []
        func visit(_ element: Any, depth: Int) {
            guard depth < 40, let object = element as? NSObject else { return }
            for key in [
                "accessibilityLabel", "accessibilityValue", "accessibilityTitle", "accessibilityHelp",
                "accessibilityIdentifier",
            ]
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

    static func expectNoSeed(_ strings: [String], _ comment: Comment? = nil) {
        let leaks = strings.filter { $0.contains(seedPrefix) }
        #expect(leaks.isEmpty, comment)
    }

    // MARK: Marking

    @Test func maskIsFixedWidthWhateverTheLength() {
        #expect(PrivacyMask.text == "••••••")
        #expect(Sensitive(wrappedValue: "a").masked == PrivacyMask.text)
        #expect(Sensitive(wrappedValue: String(repeating: "x", count: 300)).masked == PrivacyMask.text)
        #expect(Sensitive(wrappedValue: "").masked == PrivacyMask.text)
        #expect(Sensitive<String?>(wrappedValue: nil).masked == nil)
        #expect(Sensitive<String?>(wrappedValue: "x").masked == PrivacyMask.text)
        #expect(Sensitive(wrappedValue: "raw").value(privacyActive: false) == "raw")
    }

    @Test func scrubReplacesSensitivePartsOfComposedText() {
        let label = PrivacyMask.scrub("vigie-api, blocked, 12 minutes", removing: ["vigie", "vigie-api", nil, ""])
        #expect(label == "••••••, blocked, 12 minutes")
    }

    @Test func revealIsUnavailableWhilePrivate() {
        #expect(PrivacyReveal.isAvailable(privacyActive: false))
        #expect(!PrivacyReveal.isAvailable(privacyActive: true))
    }

    @Test func copyResolves() {
        #expect(L10n.string("privacy.indicator") == "Privacy mode on")
        #expect(L10n.string("privacy.hidden") == "Hidden")
    }

    // MARK: Sessions (4.9 rows, 11.2 Home card)

    static let sessionRows: [SessionRowModel] = (0..<3).map { n in
        SessionRowModel(
            id: "claude:\(n)", glyphStatus: n == 0 ? .blocked : .working, agentName: "Claude Code",
            project: seed(n), lastAction: "Bash · \(seed(10 + n))", terminalName: "Warp",
            statusLabel: n == 0 ? "BLOCKED · 12M" : "WORKING · 3M",
            accessibilityLabel: "\(seed(n)), \(n == 0 ? "blocked" : "working"), 3 minutes")
    }

    @Test func sessionRowsRedactProjectActionAndLabel() {
        let snapshot = SessionsSnapshot(rows: Self.sessionRows).privacy(true)
        #expect(!Self.dumped(snapshot).contains(Self.seedPrefix))
        #expect(snapshot.rows.allSatisfy { $0.project == PrivacyMask.text && $0.lastAction == PrivacyMask.text })
        #expect(snapshot.rows[0].accessibilityLabel == "••••••, blocked, 3 minutes")
        // Glyph status, agent, status label and ids stay.
        #expect(snapshot.rows.map(\.statusLabel) == Self.sessionRows.map(\.statusLabel))
        #expect(snapshot.rows.map(\.id) == Self.sessionRows.map(\.id))
        #expect(snapshot.rows[0].agentName == "Claude Code")
        #expect(SessionsSnapshot(rows: Self.sessionRows).privacy(false) == SessionsSnapshot(rows: Self.sessionRows))
    }

    @Test(arguments: [true, false])
    func sessionsTabRendersDotsWhilePrivate(active: Bool) {
        let tab = SessionsTabView(
            now: Date(timeIntervalSince1970: 0), snapshot: { _ in SessionsSnapshot(rows: Self.sessionRows) },
            onFocus: { _ in }
        )
        .privacyActive(active)
        let strings = Self.accessibilityStrings(tab, size: CGSize(width: 900, height: 400))
        if active {
            Self.expectNoSeed(strings)
            #expect(strings.contains { $0.contains(PrivacyMask.text) })
            #expect(strings.contains { $0.contains("BLOCKED · 12M") || $0.contains("blocked") })
        } else {
            #expect(strings.contains { $0.contains(Self.seed(0)) })
        }
    }

    @Test func sessionsHomeCardHidesProjects() {
        let card = SessionsHomeCardView(rows: Self.sessionRows, onFocus: { _ in }).privacyActive(true)
        let strings = Self.accessibilityStrings(card, size: CGSize(width: 222, height: 138))
        Self.expectNoSeed(strings)
        #expect(strings.contains { $0.contains(PrivacyMask.text) })
    }

    /// The host sets `privacyActive` on the expanded panel root; Home cards inside the grid inherit it.
    @Test func privacyReachesHomeCards() {
        let seen = PrivacySeen()
        let grid = HomeGridView(cards: [
            HomeCardModel(id: "probe", title: "Probe", content: AnyView(PrivacyProbe(seen: seen)))
        ]) { _ in }
        .privacyActive(true)
        _ = Self.accessibilityStrings(grid, size: CGSize(width: 760, height: 400))
        #expect(seen.values.contains(true))
        #expect(!seen.values.contains(false))
    }

    @Test func sessionGlyphMasksItsSpokenProject() {
        let label = "\(Self.seed(1)), blocked, 2 minutes"
        #expect(
            SessionGlyphView.spokenLabel(label, sensitive: [Self.seed(1)], status: .blocked, privacyActive: true)
                == "••••••, blocked, 2 minutes")
        #expect(
            SessionGlyphView.spokenLabel(label, sensitive: [Self.seed(1)], status: .blocked, privacyActive: false)
                == label)
        let strings = Self.accessibilityStrings(
            SessionGlyphView(.blocked, accessibilityLabel: label, sensitive: [Self.seed(1)]).privacyActive(true),
            size: CGSize(width: 40, height: 40))
        Self.expectNoSeed(strings)
    }

    // MARK: Usage (7.7/7.8 cost by project, 7.10 Accounts, 11.2 card, closed-notch readout)

    static func usageSnapshot() -> UsageTabSnapshot {
        let window = QuotaDialModel.Window(kind: .fiveHour, fraction: 0.62, elapsedFraction: 0.5, isWarning: false)
        let dial = QuotaDialModel(providerName: "Claude", primary: window, accountLabel: seed(20))
        let bar = UsageBarModel(window: window, warnThreshold: 80, elapsed: 0.5, reset: nil)
        let card = UsageProviderCardModel(
            id: "claude.work", name: "Claude Code", meta: UsageCardMeta(kind: .warn(threshold: 80)),
            content: .windows(dial: dial, bars: [bar]), providerID: "claude", account: seed(20))
        let cost = UsageCostList(
            rows: [
                UsageCostList.Row(name: seed(21), path: "/Users/me/\(seed(21))", cost: 3.2, fraction: 1),
                UsageCostList.Row(name: seed(22), path: "/Users/me/\(seed(22))", cost: 1.1, fraction: 0.3),
            ], total: 4.3, isApproximate: false,
            accountRows: [UsageCostList.Row(name: seed(23), path: nil, cost: 4.3, fraction: 1)])
        return UsageTabSnapshot(providers: [card], history: .empty, cost: .list(cost))
    }

    @Test func usageSnapshotRedactsAccountsAndProjects() {
        let original = Self.usageSnapshot()
        let snapshot = original.privacy(true)
        #expect(!Self.dumped(snapshot).contains(Self.seedPrefix))
        #expect(snapshot.providers[0].title == "Claude Code · ••••••")
        guard case .windows(let dial, _) = snapshot.providers[0].content, case .list(let list) = snapshot.cost else {
            Issue.record("content changed shape")
            return
        }
        #expect(dial.nameLabel == "CLAUDE · ••••••")
        #expect(dial.readoutValue == "62 %" || dial.readoutValue?.contains("62") == true)
        #expect(list.totalText == UsageFormat.cost(4.3))
        #expect(list.rows.map(\.costText) == [UsageFormat.cost(3.2), UsageFormat.cost(1.1)])
        // Row identity survives redaction (ForEach).
        guard case .list(let raw) = original.cost else { return }
        #expect(list.rows.map(\.id) == raw.rows.map(\.id))
        #expect(Set(list.rows.map(\.id)).count == 2)
    }

    @Test func usageTabRendersNoSeedWhilePrivate() {
        let tab = UsageTabView(snapshot: { Self.usageSnapshot() }).privacyActive(true)
        let strings = Self.accessibilityStrings(tab, size: CGSize(width: 900, height: 420))
        Self.expectNoSeed(strings)
        #expect(strings.contains { $0.contains(PrivacyMask.text) })
    }

    @Test func usageHomeCardRendersNoSeedWhilePrivate() {
        let card = UsageHomeCardView(snapshot: { Self.usageSnapshot() }).privacyActive(true)
        let strings = Self.accessibilityStrings(card, size: CGSize(width: 222, height: 138))
        Self.expectNoSeed(strings)
    }

    @Test func wingReadoutKeepsTheProviderAndMasksTheAccount() {
        guard case .windows(let dial, _) = Self.usageSnapshot().providers[0].content else { return }
        let strings = Self.accessibilityStrings(
            QuotaReadoutView(model: dial).privacyActive(true), size: CGSize(width: 160, height: 40))
        Self.expectNoSeed(strings)
        #expect(strings.contains { $0.hasPrefix("Claude") })
        let dialStrings = Self.accessibilityStrings(
            QuotaDialView(model: dial, size: .stacked).privacyActive(true), size: CGSize(width: 80, height: 60))
        Self.expectNoSeed(dialStrings)
    }

    // MARK: Shelf (9.3 rows, 9.7 SEND TO)

    static let shelfRows: [ShelfRowModel] = (0..<2).map { n in
        ShelfRowModel(
            id: UUID(), name: "\(seed(30 + n)).pdf", kind: "PDF", sizeMode: "92 KB · COPY", sourceApp: nil,
            addedTime: "09:12", addedDay: "TODAY", expiry: .timeLeft("6D LEFT", fraction: 1),
            accessibilityLabel: "\(seed(30 + n)).pdf, PDF, 92 KB")
    }

    @Test func shelfSnapshotRedactsNames() {
        let snapshot = ShelfTabTests.snapshot(Self.shelfRows).privacy(true)
        #expect(!Self.dumped(snapshot.rows).contains(Self.seedPrefix))
        #expect(snapshot.rows.allSatisfy { $0.name == PrivacyMask.text && $0.kind == "PDF" })
        #expect(snapshot.rows[0].accessibilityLabel == "••••••, PDF, 92 KB")
    }

    @Test func shelfTabRendersNoSeedWhilePrivate() {
        var tab = ShelfTabView(snapshot: { ShelfTabTests.snapshot(Self.shelfRows) }, actions: ShelfTabActions())
        tab.interactive = false
        let strings = Self.accessibilityStrings(tab.privacyActive(true), size: CGSize(width: 900, height: 420))
        Self.expectNoSeed(strings)
        #expect(strings.contains { $0.contains(PrivacyMask.text) })
    }

    @Test func thumbnailsBecomeAPlaceholder() {
        let image = Text(verbatim: Self.seed(40)).sensitive(.thumbnail).privacyActive(true)
        Self.expectNoSeed(Self.accessibilityStrings(image, size: CGSize(width: 60, height: 40)))
    }

    // MARK: Peek and the indicator

    static let peek = PeekContent(
        kind: .blocked, kicker: "Blocked", title: seed(50), body: "Claude Code wants to run \(seed(51))",
        primary: PeekAction(label: "Focus terminal", shortcut: PeekAction.primaryShortcut),
        secondary: PeekAction(label: "Dismiss", shortcut: PeekAction.secondaryShortcut), accentRole: .statusBlocked)

    static let dwell = PeekDwellState(total: .seconds(5), remaining: .seconds(5), isRunning: false)

    @Test func peekContentRedactsTitleAndBody() {
        let content = Self.peek.redacted()
        #expect(!Self.dumped(content).contains(Self.seedPrefix))
        #expect(content.kicker == "Blocked" && content.kind == .blocked)
        #expect(content.title == PrivacyMask.text && content.body == PrivacyMask.text)
        #expect(Self.peek.privacy(false) == Self.peek)
    }

    @Test(arguments: [true, false])
    func peekShowsDotsAndTheIndicatorOnlyWhilePrivate(active: Bool) {
        let view = PeekView(content: Self.peek, dwell: Self.dwell).privacyActive(active)
        let strings = Self.accessibilityStrings(view, size: CGSize(width: 760, height: 200))
        #expect(strings.contains("Privacy mode on") == active)
        #expect(strings.contains(PrivacyIndicator.accessibilityID) == active)
        if active {
            Self.expectNoSeed(strings)
            #expect(strings.contains { $0.contains("Blocked") })
        } else {
            #expect(strings.contains { $0.contains(Self.seed(50)) })
        }
    }

    @Test(arguments: [true, false])
    func tabRowShowsTheIndicatorOnlyWhilePrivate(active: Bool) {
        let size = Self.theme.expandedPanelSize
        let shell = ExpandedShellView(
            tabs: [ExpandedTab(id: "agents.sessions", title: "Agents", icon: "terminal")], selection: .constant(nil),
            now: Date(timeIntervalSince1970: 0), content: { _ in nil }
        )
        .frame(width: size.width, height: size.height)
        .privacyActive(active)
        let strings = Self.accessibilityStrings(shell, size: size)
        #expect(strings.contains("Privacy mode on") == active)
        #expect(strings.contains { $0 == "Settings" || $0.contains("Settings") })
    }
}

/// Records the `privacyActive` it renders with.
@MainActor final class PrivacySeen {
    var values: [Bool] = []
}

private struct PrivacyProbe: View {
    @Environment(\.privacyActive) private var privacyActive
    let seen: PrivacySeen

    var body: some View {
        seen.values.append(privacyActive)
        return Text(verbatim: "probe")
    }
}
