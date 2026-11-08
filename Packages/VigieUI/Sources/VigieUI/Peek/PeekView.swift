import SwiftUI

/// The peek alert panel (DESIGN "Peek alert panel", UX-DR21): `components.peek-panel` (700 × 150), flush top
/// with `rounded.peek` bottom corners, the 34px black band, then the body in `surface-panel` with the
/// three-column grid `44 | 1fr | 176` (beacon, kicker / title / detail, action pair) and the dwell line
/// along the bottom.
///
/// The view only draws: the Notch Host owns the dwell clock, the queue and the shortcuts. `isRevealed`
/// grows the panel out of the band over `motion.peek-grow` and retracts it over `motion.exit`; under Reduce
/// motion both are instant. Hovering reports through `onHover` (the host pauses the dwell).
public struct PeekView: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.privacyActive) private var privacyActive

    private let content: PeekContent
    private let dwell: PeekDwellState
    private let isRevealed: Bool
    private let onPrimary: @MainActor () -> Void
    private let onSecondary: @MainActor () -> Void
    private let onHover: @MainActor (Bool) -> Void

    /// - Parameters:
    ///   - onPrimary: the `⌥⌘↵` action (clicking the primary button; the global shortcut is Story 3.3).
    ///   - onSecondary: the `⌥⌘⌫` action (Dismiss).
    public init(
        content: PeekContent,
        dwell: PeekDwellState,
        isRevealed: Bool = true,
        onPrimary: @escaping @MainActor () -> Void = {},
        onSecondary: @escaping @MainActor () -> Void = {},
        onHover: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.content = content
        self.dwell = dwell
        self.isRevealed = isRevealed
        self.onPrimary = onPrimary
        self.onSecondary = onSecondary
        self.onHover = onHover
    }

    public var body: some View {
        let size = theme.peekSize
        let band = theme.spacing(.bandHeight)
        let inset = theme.spacing(.peekInsetX)
        let shape = IslandShape(radius: theme.radius(.peek))
        let shadow = theme.peekShadow
        ZStack(alignment: .top) {
            PeekBackground(content: content)
            PeekEdge(content: content)
            VStack(spacing: 0) {
                Color.clear.frame(height: band)
                    .overlay(alignment: .trailing) {
                        // Privacy mode (UX-DR98): the eye-slash in the band; title and detail are dots.
                        if privacyActive {
                            PrivacyIndicator().padding(.trailing, inset)
                        }
                    }
                grid
                    .padding(.horizontal, inset)
                    .padding(.bottom, theme.spacing(.peekTimerBottom))
                    .frame(maxHeight: .infinity)
                PeekDwellLine(dwell: dwell, foreground: lineRole)
                    .padding(.horizontal, inset)
                    .padding(.bottom, theme.spacing(.peekTimerBottom))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .mask(alignment: .top) {
            Rectangle().frame(height: !theme.a11y.motionEnabled || isRevealed ? size.height : band)
        }
        .opacity(!theme.a11y.motionEnabled && !isRevealed ? 0 : 1)
        .animation(revealAnimation, value: isRevealed)
        .shadow(color: theme.color(.shadow).opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
        .contentShape(shape)
        .onHover { onHover($0) }
        .accessibilityElement(children: .contain)
    }

    /// Grow over `motion.peek-grow`, retract over `motion.exit`; a short cross-fade under Reduce motion.
    private var revealAnimation: Animation? {
        isRevealed
            ? theme.animation(.peekGrow, curve: .easeOut, reducedMotion: .crossFade)
            : theme.animation(.exit, curve: .easeIn, reducedMotion: .crossFade)
    }

    private var grid: some View {
        let columns = theme.peekColumns
        return HStack(spacing: theme.spacing(.peekColumnGap)) {
            if content.kind.showsBeacon {
                PeekBeacon(kind: content.kind, accent: content.accentRole)
                    .frame(width: columns.leading, height: columns.leading)
            }
            textBlock
                .frame(maxWidth: .infinity, alignment: .leading)
            actions
                .frame(width: columns.trailing)
        }
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: content.kicker)
                .font(theme.font(.kicker))
                .tracking(theme.tracking(.kicker))
                .textCase(.uppercase)
                .foregroundStyle(theme.color(content.kickerRole(look: theme.look)))
                .lineLimit(1)
                .padding(.bottom, theme.spacing(.actionGap))
            Text(verbatim: content.title)
                .font(theme.font(.peekTitle))
                .tracking(theme.tracking(.peekTitle))
                .foregroundStyle(theme.color(.ink1))
                .lineLimit(1)
                .truncationMode(.middle)
                .sensitive()
            if let body = content.body {
                Text(verbatim: body)
                    .font(theme.font(.body))
                    .tracking(theme.tracking(.body))
                    .foregroundStyle(theme.color(.ink2))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .sensitive()
                    .padding(.top, theme.spacing(.glyphGap))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: theme.spacing(.actionGap)) {
            if let primary = content.primary {
                ActionButton(label: primary.label, shortcut: primary.shortcut, role: .primary, action: onPrimary)
            }
            if let secondary = content.secondary {
                ActionButton(
                    label: secondary.label, shortcut: secondary.shortcut, role: .secondary, action: onSecondary)
            }
        }
    }

    /// The dwell line color: the alert hue; neutral `ink-3` for setup.
    private var lineRole: ColorRole {
        content.kind.isNeutral ? .ink3 : content.accentRole
    }
}

// MARK: - Parts

/// The black band over the panel body (`surface-panel`), plus, in A dark looks, a faint tint of the alert hue
/// rising from below. Light looks drop glows (DESIGN "Elevation & Depth").
struct PeekBackground: View {
    @Environment(\.vigieTheme) private var theme
    let content: PeekContent

    var body: some View {
        VStack(spacing: 0) {
            theme.color(.band).frame(height: theme.spacing(.bandHeight))
            ZStack {
                theme.color(.surfacePanel)
                if !theme.isLight && !theme.usesCornerMarks && !content.kind.isNeutral {
                    GeometryReader { proxy in
                        EllipticalGradient(
                            colors: [
                                theme.color(content.accentRole).opacity(PeekMetrics.bodyTint),
                                theme.color(content.accentRole).opacity(0),
                            ]
                        )
                        .frame(width: proxy.size.width * 1.2, height: proxy.size.height * 1.8)
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 1.3)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The panel edge: A, a 1px rim in the alert hue along the sides and bottom (neutral platinum for setup);
/// C, a hairline and corner marks in the alert hue.
struct PeekEdge: View {
    @Environment(\.vigieTheme) private var theme
    let content: PeekContent

    var body: some View {
        let radius = theme.radius(.peek)
        Group {
            if theme.usesCornerMarks {
                let role: ColorRole = content.kind.isNeutral ? .structure : content.accentRole
                ZStack {
                    IslandRimShape(radius: radius, lineWidth: ComponentMetrics.hairline)
                        .fill(theme.color(role).opacity(PeekMetrics.structHairline), style: FillStyle(eoFill: true))
                    CornerMarks()
                        .stroke(theme.color(role), lineWidth: ComponentMetrics.hairline)
                        .padding(.top, theme.spacing(.bandHeight))
                }
            } else if content.kind.isNeutral {
                IslandRimShape(radius: radius, lineWidth: ComponentMetrics.hairline)
                    .fill(theme.color(.ink1).opacity(PeekMetrics.neutralRim), style: FillStyle(eoFill: true))
            } else {
                LinearGradient(
                    colors: [
                        theme.color(content.accentRole), theme.color(.iris3), theme.color(content.accentRole),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .mask(
                    IslandRimShape(radius: radius, lineWidth: ComponentMetrics.hairline)
                        .fill(style: FillStyle(eoFill: true)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// The 44px beacon: A, a round radial tint in the alert hue with a 1px inner ring; C, a faint square with
/// corner marks. Holds the 26px kind glyph.
struct PeekBeacon: View {
    @Environment(\.vigieTheme) private var theme
    let kind: PeekKind
    let accent: ColorRole

    var body: some View {
        let hue = theme.color(accent)
        let glyph = StatusMarkSize.large.length(in: theme)
        ZStack {
            if theme.usesCornerMarks {
                Rectangle().fill(hue.opacity(PeekMetrics.beaconTint / 2))
                CornerMarks().stroke(hue, lineWidth: ComponentMetrics.hairline)
            } else {
                if !theme.isLight {
                    Circle().fill(
                        RadialGradient(
                            colors: [hue.opacity(PeekMetrics.beaconTint), hue.opacity(0)], center: .center,
                            startRadius: 0, endRadius: glyph))
                }
                Circle().strokeBorder(hue.opacity(PeekMetrics.beaconRing), lineWidth: ComponentMetrics.hairline)
            }
            PeekGlyph(kind: kind)
                .foregroundStyle(hue)
                .frame(width: glyph, height: glyph)
        }
        .accessibilityHidden(true)
    }
}

/// The large kind glyph: blocked diamond, done ring + check, failed ×, quota triangle, Time ring (dashed for a
/// due break), and a plain ring otherwise. Static: the peek is short and Reduce motion needs no change.
struct PeekGlyph: View {
    let kind: PeekKind

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            let stroke = max(1, side / 13)
            switch kind {
            case .blocked:
                ZStack {
                    Diamond().inset(by: side * 0.27).fill()
                    Diamond().inset(by: side * 0.12).stroke(lineWidth: ComponentMetrics.hairline)
                }
            case .done:
                ZStack {
                    Circle().inset(by: side * 0.12).fill().opacity(0.22)
                    Circle().inset(by: side * 0.12).stroke(lineWidth: stroke)
                    CheckMark().stroke(style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
                }
            case .failed, .sleepSummary:
                CrossShape().stroke(style: StrokeStyle(lineWidth: stroke * 1.5, lineCap: .round))
            case .quotaWarning:
                WarningTriangle().fill()
            case .breakDue:
                Circle().inset(by: side * 0.12)
                    .stroke(style: StrokeStyle(lineWidth: stroke, dash: [stroke * 1.1, stroke]))
            case .timerEnd, .calendarReminder, .generic, .setupProblem:
                Circle().inset(by: side * 0.12).stroke(lineWidth: stroke)
            }
        }
    }
}

/// A square standing on a corner.
struct Diamond: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var path = Path()
        path.move(to: CGPoint(x: r.midX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        path.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.midY))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> Diamond {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// The check inside the done ring.
struct CheckMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.minY + rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.45, y: rect.minY + rect.height * 0.63))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.67, y: rect.minY + rect.height * 0.38))
        return path
    }
}

/// The dwell line: the shared ``DrainLine`` in the alert hue, emptying over what is left of the dwell. The
/// presenter owns the timer (and the pause on hover); this view only slides the line from the remaining share
/// to zero while the dwell runs. Under Reduce motion (`theme.a11y.drainStyle`) it is a static full line that
/// disappears at the end (UX-DR96).
struct PeekDwellLine: View {
    @Environment(\.vigieTheme) private var theme
    let dwell: PeekDwellState
    let foreground: ColorRole
    @State private var fraction: Double = 1

    var body: some View {
        DrainLine(remaining: shownFraction, foreground: foreground, foregroundOpacity: 1)
            .onAppear(perform: sync)
            .onChange(of: dwell) { sync() }
    }

    /// The share handed to the line: the sliding fraction, or the presenter's share for a static line.
    var shownFraction: Double {
        switch theme.a11y.drainStyle {
        case .animated: fraction
        case .staticFullLine: dwell.remainingFraction
        }
    }

    private func sync() {
        guard theme.a11y.drainStyle == .animated else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { fraction = dwell.remainingFraction }
        guard dwell.isRunning, dwell.remaining > .zero else { return }
        withAnimation(.linear(duration: dwell.remainingSeconds)) { fraction = 0 }
    }
}

#Preview("Peeks · dark") {
    PeekPreview(look: .dark)
}

#Preview("Peeks · light") {
    PeekPreview(look: .light)
}

#Preview("Peeks · Twin Metal") {
    PeekPreview(look: .dark, variant: "twin-metal-tactical")
}

private struct PeekPreview: View {
    let look: Look
    var variant = ThemeLibrary.defaultVariantID

    var body: some View {
        let theme = PreviewThemes.theme(look, variant: variant)
        let dwell = PeekDwellState(
            total: theme.motion(.peekDwell), remaining: theme.motion(.peekDwell), isRunning: false)
        VStack(spacing: theme.spacing(.gridGap)) {
            PeekView(
                content: PeekContent(
                    kind: .blocked, kicker: "Blocked", title: "vigie / api-refactor",
                    body: "Claude Code wants to run Bash · npm run db:migrate",
                    primary: PeekAction(label: VigieCopy.openSettings, shortcut: PeekAction.primaryShortcut),
                    secondary: PeekAction(label: VigieCopy.openSystemSettings, shortcut: PeekAction.secondaryShortcut),
                    accentRole: .statusBlocked),
                dwell: dwell)
        }
        .padding(theme.spacing(.gridPaddingX))
        .vigieTheme(theme)
    }
}
