import AppKit
import Foundation
import SwiftUI
import Testing

@testable import VigieUI

@MainActor @Suite struct PeekViewTests {
    static func theme(_ look: Look, variant: String = ThemeLibrary.defaultVariantID, reduceMotion: Bool = false)
        -> Theme
    {
        Fixtures.library.resolve(
            themeID: variant, look: look,
            accessibility: AccessibilityAdjustments(reduceMotion: reduceMotion)
        ).theme
    }

    static func content(_ kind: PeekKind) -> PeekContent {
        // Labels as VigieCore's catalog spells them (not in this package's catalog, so shown as given).
        let primary = PeekAction(
            label: LocalizedStringResource(stringLiteral: kind == .setupProblem ? "Open settings" : "Focus terminal"),
            shortcut: PeekAction.primaryShortcut)
        let secondary = PeekAction(
            label: LocalizedStringResource(stringLiteral: "Dismiss"), shortcut: PeekAction.secondaryShortcut)
        switch kind {
        case .blocked:
            return PeekContent(
                kind: .blocked, kicker: "Blocked", title: "vigie / api-refactor",
                body: "Claude Code wants to run Bash · npm run db:migrate", primary: primary, secondary: secondary,
                accentRole: .statusBlocked)
        case .done:
            return PeekContent(
                kind: .done, kicker: "Done", title: "vigie / docs-site", body: "Claude Code · Turn ended · 3 files",
                primary: primary, secondary: secondary, accentRole: .statusDone)
        case .failed:
            return PeekContent(
                kind: .failed, kicker: "Failed", title: "infra / backup",
                body: "Claude Code · Run interrupted during Bash · ./scripts/backup.sh", primary: primary,
                secondary: secondary, accentRole: .statusFailed)
        default:
            return PeekContent(
                kind: kind, kicker: "Setup", title: "Codex adapter: CLI version 0.9.2 unsupported",
                body: "Codex sessions are not tracked until the CLI or the adapter is updated.", primary: primary,
                secondary: secondary, accentRole: .ink2)
        }
    }

    static let dwell = PeekDwellState(total: .seconds(5), remaining: .seconds(5), isRunning: false)

    // MARK: Metrics

    @Test func panelMetricsComeFromTheTheme() {
        let theme = Self.theme(.dark)
        #expect(theme.peekSize == CGSize(width: 700, height: 150))
        #expect(theme.peekColumns.leading == 44)
        #expect(theme.peekColumns.trailing == 176)
        #expect(theme.radius(.peek) == 22)
        #expect(theme.spacing(.bandHeight) == 34)
        #expect(theme.motion(.peekGrow) == .milliseconds(280))
        #expect(theme.motion(.exit) == .milliseconds(200))
        #expect(theme.motion(.peekDwell) == .seconds(5))
    }

    @Test func shadowParsesTheComponentSpec() {
        #expect(Self.theme(.dark).peekShadow == PeekShadow(y: 18, radius: 20, opacity: 0.45))
        #expect(Self.theme(.light).peekShadow == PeekShadow(y: 18, radius: 20, opacity: 0.20))
        #expect(PeekShadow(y: 18, radius: 20, opacity: 0.45).margin == 58)
    }

    @Test func colorRolesUsedAreDefined() {
        for look in Look.allCases {
            let theme = Self.theme(look)
            for role in [
                ColorRole.band, .surfacePanel, .statusBlocked, .statusDone, .statusFailed, .ink1, .ink2, .line,
            ] {
                #expect(theme.defines(role), "\(look) misses \(role.rawValue)")
            }
        }
    }

    // MARK: Model

    @Test func dwellFractionTracksWhatIsLeft() {
        let state = PeekDwellState(total: .seconds(5), remaining: .seconds(2), isRunning: true)
        #expect(abs(state.remainingFraction - 0.4) < 0.0001)
        #expect(state.remainingSeconds == 2)
        #expect(PeekDwellState(total: .zero, remaining: .zero, isRunning: false).remainingFraction == 0)
        #expect(PeekDwellState(total: .seconds(5), remaining: .seconds(9), isRunning: true).remainingFraction == 1)
    }

    @Test func kickerRoleFollowsTheKindAndLook() {
        var quota = Self.content(.blocked)
        quota.kind = .quotaWarning
        quota.accentRole = .quotaWarning
        #expect(quota.kickerRole(look: .dark) == .quotaWarning)
        #expect(quota.kickerRole(look: .light) == .quotaWarningText)
        #expect(Self.content(.setupProblem).kickerRole(look: .dark) == .ink2)
        #expect(Self.content(.blocked).kickerRole(look: .dark) == .statusBlocked)
    }

    @Test func setupPeekDropsTheBeacon() {
        #expect(!PeekKind.setupProblem.showsBeacon)
        #expect(PeekKind.allCases.filter { !$0.showsBeacon } == [.setupProblem])
    }

    @Test func reduceMotionShowsAStaticFullLineUntilTheEnd() throws {
        let theme = Self.theme(.dark, reduceMotion: true)
        #expect(!theme.a11y.motionEnabled)
        #expect(theme.a11y.drainStyle == .staticFullLine)
        // The dwell line hands the presenter's share to `DrainLine`, which draws it full until zero.
        let style = theme.a11y.drainStyle
        let running = PeekDwellState(total: .seconds(5), remaining: .seconds(1), isRunning: true)
        let ended = PeekDwellState(total: .seconds(5), remaining: .zero, isRunning: false)
        #expect(style.visibleFraction(remaining: running.remainingFraction) == 1)
        #expect(style.visibleFraction(remaining: ended.remainingFraction) == 0)
        for dwell in [running, ended] {
            let line = PeekDwellLine(dwell: dwell, foreground: .statusBlocked).frame(width: 100)
            #expect(render(line, theme: theme) != nil)
        }
        // Grow and retract become a short cross-fade.
        #expect(theme.animation(.peekGrow, reducedMotion: .crossFade) != nil)
        #expect(theme.animation(.peekGrow) == nil)
    }

    @Test func revealUsesThePeekGrowAndExitTokens() {
        let theme = Self.theme(.dark)
        #expect(theme.a11y.motionEnabled)
        #expect(theme.animation(.peekGrow) == .easeOut(duration: 0.28))
        #expect(theme.animation(.exit, curve: .easeIn) == .easeIn(duration: 0.2))
    }

    @Test func actionStringsComeFromTheCatalog() {
        #expect(String(localized: VigieCopy.openSettings) == "Open settings")
        #expect(PeekAction.primaryShortcut == "⌥⌘↵")
        #expect(PeekAction.secondaryShortcut == "⌥⌘⌫")
    }

    // MARK: Render

    @Test(arguments: [
        (PeekKind.blocked, Look.dark, ThemeLibrary.defaultVariantID),
        (.done, .dark, ThemeLibrary.defaultVariantID),
        (.failed, .dark, ThemeLibrary.defaultVariantID),
        (.blocked, .light, ThemeLibrary.defaultVariantID),
        (.setupProblem, .dark, ThemeLibrary.defaultVariantID),
        (.blocked, .dark, "twin-metal-tactical"),
        (.failed, .light, "twin-metal-tactical"),
        (.calendarReminder, .dark, ThemeLibrary.defaultVariantID),
        (.calendarReminder, .dark, "twin-metal-tactical"),
    ])
    func peekRenders(kind: PeekKind, look: Look, variant: String) throws {
        let theme = Self.theme(look, variant: variant)
        let margin = theme.peekShadow.margin
        let view = PeekView(content: Self.content(kind), dwell: Self.dwell)
            .padding(.horizontal, margin)
            .padding(.bottom, margin)
            .background(look == .dark ? Color(white: 0.22) : Color(white: 0.85))
        let image = try #require(render(view, theme: theme))
        #expect(image.width == Int((theme.peekSize.width + 2 * margin) * 2))
        if let dir = ProcessInfo.processInfo.environment["VIGIE_PEEK_RENDER_DIR"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(
                "peek-\(kind.rawValue)-\(variant)-\(look.rawValue).png")
            let rep = NSBitmapImageRep(cgImage: image)
            try rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }

    @Test func calendarBeaconIsAnEventTrackWithItsEventTick() {
        let rect = CGRect(x: 0, y: 0, width: 26, height: 26)
        let bounds = EventTrackMark().path(in: rect).boundingRect
        #expect(abs(bounds.minX - 26 * EventTrackMark.trackStart) < 0.01)
        #expect(abs(bounds.maxX - 26 * EventTrackMark.trackEnd) < 0.01)
        #expect(bounds.height > 0, "the event tick crosses the track")
        #expect(EventTrackMark.markerOffset(in: 26) < 0, "the now marker sits left of center")
        #expect(PeekKind.calendarReminder.showsBeacon)
    }

    @Test func retractedPeekRendersOnlyTheBand() throws {
        let theme = Self.theme(.dark)
        let image = try #require(
            render(PeekView(content: Self.content(.blocked), dwell: Self.dwell, isRevealed: false), theme: theme))
        #expect(image.height == Int(theme.peekSize.height * 2))
    }

    private func render(_ view: some View, theme: Theme) -> CGImage? {
        let renderer = ImageRenderer(content: view.vigieTheme(theme).environment(\.timeZone, .gmt))
        renderer.scale = 2
        return renderer.cgImage
    }
}
