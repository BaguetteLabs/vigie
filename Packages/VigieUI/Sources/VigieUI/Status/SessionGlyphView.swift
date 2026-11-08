import ModuleKit
import SwiftUI

/// How a session glyph moves (DESIGN "Status glyph", "Presence mode"; UX-DR56, UX-DR96). Pure, so the motion
/// rules are testable without rendering.
public enum SessionGlyphMotion: Sendable, Equatable {
    /// Static.
    case none
    /// Working: the A open arc spins, the C tick ring turns, over `motion.working-cycle`.
    case spin
    /// A blocked: the outline ripples out over `motion.blocked-cycle`.
    case ripple
    /// C blocked: the corner brackets breathe over `motion.blocked-cycle`.
    case breathe
    /// Failed: a double stutter (two quick blinks) over `motion.failed-cycle`.
    case stutter
    /// Calm presence: blocked and failed show one slow halo every `motion.calm-pulse`; nothing else moves.
    case calmPulse

    /// The motion for a status in a theme. Idle, done and stale never move; stale is static in every
    /// Presence mode (Story 1.7b). Reduce motion stops everything; Calm keeps only the blocked / failed pulse.
    public static func resolve(_ status: SessionStatus, theme: Theme) -> SessionGlyphMotion {
        guard theme.a11y.motionEnabled else { return .none }
        switch status {
        case .idle, .done, .stale:
            return .none
        case .working:
            return theme.loopsEnabled ? .spin : .none
        case .blocked:
            guard theme.loopsEnabled else { return .calmPulse }
            return theme.usesTacticalGlyphs ? .breathe : .ripple
        case .failed:
            return theme.loopsEnabled ? .stutter : .calmPulse
        }
    }
}

extension Theme {
    /// Twin Metal Tactical shapes when the variant draws structure marks (``SessionStatus/glyph(in:)``).
    var usesTacticalGlyphs: Bool { defines(.structure) }
}

/// One agent session's status glyph (DESIGN "Status glyph"; FR37, UX-DR17–19, UX-DR56): a 16 px shape-coded
/// mark in the status hue, animated per status and Presence. Chrome Hologram draws hollow ring, spinning ¼ arc,
/// ring + check, rippling diamond and stuttering ×; Twin Metal Tactical draws its instrument set. Stale is a
/// dashed `ink-3` ring with an `ink-2` `?`, never animated. Color is never the only cue: the shape differs per
/// state and the caller passes the spoken label ("vigie, blocked, 2 minutes", UX-DR63).
public struct SessionGlyphView: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.privacyActive) private var privacyActive
    private let status: SessionStatus
    private let label: String?
    private let sensitive: [String?]
    private let size: StatusMarkSize

    /// - Parameters:
    ///   - status: the display status (stale included).
    ///   - accessibilityLabel: "<project>, <status>, <time>"; nil reads the status word alone.
    ///   - sensitive: the user text inside `accessibilityLabel` (the project), masked while Privacy mode is on.
    ///   - size: 16 px slot (`medium`) by default; 26 px (`large`) in legends and the peek beacon.
    public init(
        _ status: SessionStatus, accessibilityLabel: String? = nil, sensitive: [String?] = [],
        size: StatusMarkSize = .medium
    ) {
        self.status = status
        self.label = accessibilityLabel
        self.sensitive = sensitive
        self.size = size
    }

    /// The spoken label, with the sensitive parts masked while Privacy mode is on (AD-24).
    static func spokenLabel(_ label: String?, sensitive: [String?], status: SessionStatus, privacyActive: Bool)
        -> String
    {
        guard let label else { return L10n.string(status.accessibilityKey) }
        return privacyActive ? PrivacyMask.scrub(label, removing: sensitive) : label
    }

    public var body: some View {
        let length = size.length(in: theme)
        let motion = SessionGlyphMotion.resolve(status, theme: theme)
        SessionGlyphShape(
            glyph: status.glyph(in: theme), status: status, unit: length / StatusMarkSize.medium.fallback,
            motion: motion
        )
        .frame(width: length, height: length)
        .id(motion)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(
                verbatim: Self.spokenLabel(label, sensitive: sensitive, status: status, privacyActive: privacyActive)))
    }
}

/// Draws a glyph in a 16-unit box (DESIGN and the `key-closed-notch-states.html` geometry) and runs its motion.
private struct SessionGlyphShape: View {
    @Environment(\.vigieTheme) private var theme
    let glyph: StatusGlyph
    let status: SessionStatus
    /// Points per DESIGN pixel (1 at 16 px).
    let unit: CGFloat
    let motion: SessionGlyphMotion

    @State private var phase = false

    private var color: Color { theme.color(status.colorRole) }
    /// Dark looks glow (A); light looks and Increase contrast drop halos (DESIGN "Status glyph").
    private var haloEnabled: Bool { theme.look == .dark && theme.a11y.haloEnabled && !theme.usesTacticalGlyphs }

    var body: some View {
        // The loop is scoped to `phase` on this glyph only, so its repeat-forever transaction never reaches
        // sibling views in the lane.
        shape
            .animation(animation, value: phase)
            .modifier(StutterModifier(enabled: motion == .stutter, period: theme.motionSeconds(.failedCycle)))
            .onAppear {
                if animation != nil { phase = true }
            }
    }

    /// The loop driving `phase`, or nil when the glyph is static.
    private var animation: Animation? {
        switch motion {
        case .none, .stutter: nil
        case .spin: theme.loopAnimation(.workingCycle)
        case .ripple: theme.loopAnimation(.blockedCycle)
        case .breathe: halfCycle(.blockedCycle)
        case .calmPulse: halfCycle(.calmPulse)
        }
    }

    private func halfCycle(_ role: MotionRole) -> Animation {
        .easeInOut(duration: theme.motionSeconds(role) / 2).repeatForever(autoreverses: true)
    }

    @ViewBuilder private var shape: some View {
        switch glyph {
        case .ring: ring
        case .openArc: openArc
        case .ringCheck: ringCheck
        case .diamond: diamond
        case .cross: cross
        case .dotInCircle: dotInCircle
        case .triangleInTickRing: triangleInTickRing
        case .checkInCircle: checkInCircle
        case .squareInBrackets: squareInBrackets
        case .crossInSquare: crossInSquare
        case .dashedRingQuestion: staleRing
        default: EmptyView()
        }
    }

    // MARK: Chrome Hologram (A)

    private var ring: some View {
        Circle().inset(by: 2 * unit).strokeBorder(color, lineWidth: 1.5 * unit)
            .halo(color, opacity: 0.35, radius: 3 * unit, enabled: haloEnabled)
    }

    private var openArc: some View {
        let width = 1.5 * unit
        return ZStack {
            Circle().inset(by: 2 * unit).strokeBorder(color.opacity(0.18), lineWidth: width)
            Circle().inset(by: 2 * unit + width / 2).trim(from: 0, to: 0.25)
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .rotationEffect(.degrees(phase ? 360 : 0))
    }

    private var ringCheck: some View {
        ZStack {
            Circle().inset(by: unit).fill(color.opacity(0.22))
            Circle().inset(by: unit).strokeBorder(color, lineWidth: 1.5 * unit)
            GlyphPolyline(points: [(4.9, 8.3), (7.0, 10.4), (11.1, 5.8)])
                .stroke(color, style: StrokeStyle(lineWidth: 1.6 * unit, lineCap: .round, lineJoin: .round))
        }
    }

    private var diamond: some View {
        ZStack {
            outline(RoundedRectangle(cornerRadius: 2 * unit).inset(by: 2 * unit), rotated: true)
            RoundedRectangle(cornerRadius: 1.5 * unit).inset(by: 4 * unit).fill(color)
                .rotationEffect(.degrees(45))
                .halo(color, opacity: 0.7, radius: 4 * unit, enabled: haloEnabled)
        }
    }

    private var cross: some View {
        ZStack {
            if motion == .calmPulse { outline(Circle().inset(by: unit), rotated: false) }
            CrossShape()
                .stroke(color, style: StrokeStyle(lineWidth: 2.2 * unit, lineCap: .round))
                .halo(color, opacity: 0.6, radius: 3.5 * unit, enabled: haloEnabled)
        }
    }

    /// The blocked ripple / Calm halo: 1 px outline that grows and fades; at rest a faint static outline
    /// (blocked only).
    @ViewBuilder
    private func outline(_ shape: some InsettableShape, rotated: Bool) -> some View {
        let base = shape.strokeBorder(color, lineWidth: unit).rotationEffect(.degrees(rotated ? 45 : 0))
        switch motion {
        case .ripple:
            base.scaleEffect(phase ? 1.7 : 0.7).opacity(phase ? 0 : 0.9)
        case .calmPulse:
            base.scaleEffect(phase ? 1.45 : 1).opacity(phase ? 0.9 : 0)
        default:
            base.opacity(0.45)
        }
    }

    // MARK: Twin Metal Tactical (C)

    private var dotInCircle: some View {
        ZStack {
            Circle().strokeBorder(color.opacity(0.55), lineWidth: unit)
            Circle().inset(by: 4 * unit).fill(color)
        }
    }

    private var triangleInTickRing: some View {
        let radius = 7 * unit
        let circumference = 2 * Double.pi * radius
        return ZStack {
            Circle().inset(by: unit)
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: 2 * unit, dash: [circumference * 6 / 360, circumference * 24 / 360])
                )
                .rotationEffect(.degrees(phase ? 360 : 0))
            GlyphPolyline(points: [(5, 4.5), (12, 8), (5, 11.5)], closed: true).fill(color)
        }
    }

    private var checkInCircle: some View {
        ZStack {
            Circle().strokeBorder(color.opacity(0.6), lineWidth: unit)
            GlyphPolyline(points: [(4.6, 8.2), (6.9, 10.5), (11.2, 5.5)])
                .stroke(color, style: StrokeStyle(lineWidth: 1.8 * unit, lineCap: .square, lineJoin: .miter))
        }
    }

    private var squareInBrackets: some View {
        let brackets = CornerBrackets(arm: 4 * unit).stroke(color, lineWidth: unit)
        return ZStack {
            switch motion {
            case .breathe:
                brackets.scaleEffect(phase ? 19 / 16 : 1).opacity(phase ? 0.4 : 0.75)
            case .calmPulse:
                brackets.opacity(0.75)
                Rectangle().strokeBorder(color, lineWidth: unit)
                    .scaleEffect(phase ? 1.35 : 1).opacity(phase ? 0.6 : 0)
            default:
                brackets.opacity(0.75)
            }
            Rectangle().inset(by: 5 * unit).fill(color)
        }
    }

    private var crossInSquare: some View {
        ZStack {
            Rectangle().strokeBorder(color, lineWidth: 1.5 * unit)
                .scaleEffect(motion == .calmPulse && phase ? 1.2 : 1)
                .opacity(motion == .calmPulse && phase ? 0.6 : 1)
            CrossShape().stroke(color, lineWidth: 1.6 * unit)
        }
    }

    // MARK: Stale (both variants, Story 1.7b)

    /// A: r 6.6, 1.1 px, dash 2.1 / 1.8, `?` SF Pro 600 9 px. C: r 7, 1 px, dash 1.6 / 1.6, `?` SF Mono 600 9 px.
    private var staleRing: some View {
        let tactical = theme.usesTacticalGlyphs
        let radius = (tactical ? 7 : 6.6) * unit
        let dash = tactical ? [1.6 * unit, 1.6 * unit] : [2.1 * unit, 1.8 * unit]
        let lineWidth = (tactical ? 1 : 1.1) * unit
        let mark = FontSpec(
            family: tactical ? .monospaced : .system, size: 9 * unit, weight: 600, tabularDigits: false)
        return ZStack {
            Circle().inset(by: 8 * unit - radius)
                .stroke(theme.color(.ink3), style: StrokeStyle(lineWidth: lineWidth, dash: dash))
            Text(verbatim: "?")
                .font(mark.font)
                .foregroundStyle(theme.color(.ink2))
        }
    }
}

extension View {
    /// The A dark glow under a glyph part.
    fileprivate func halo(_ color: Color, opacity: Double, radius: CGFloat, enabled: Bool) -> some View {
        shadow(color: enabled ? color.opacity(opacity) : .clear, radius: enabled ? radius : 0)
    }
}

/// Repeats the double stutter (opacity 1 → .15 → 1 → .15 → 1, in the first 17 % of the period).
private struct StutterModifier: ViewModifier {
    let enabled: Bool
    let period: TimeInterval

    func body(content: Content) -> some View {
        if enabled, period > 0 {
            content.keyframeAnimator(initialValue: 1.0, repeating: true) { view, opacity in
                view.opacity(opacity)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(0.15, duration: period * 0.05)
                    LinearKeyframe(1.0, duration: period * 0.04)
                    LinearKeyframe(0.15, duration: period * 0.04)
                    LinearKeyframe(1.0, duration: period * 0.04)
                    LinearKeyframe(1.0, duration: period * 0.83)
                }
            }
        } else {
            content
        }
    }
}

/// A polyline (or closed polygon) through points given in the 16-unit glyph box.
private struct GlyphPolyline: Shape {
    let points: [(CGFloat, CGFloat)]
    var closed = false

    func path(in rect: CGRect) -> Path {
        let scale = rect.width / StatusMarkSize.medium.fallback
        var path = Path()
        for (index, point) in points.enumerated() {
            let location = CGPoint(x: rect.minX + point.0 * scale, y: rect.minY + point.1 * scale)
            if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
        }
        if closed { path.closeSubpath() }
        return path
    }
}

/// Four corner brackets with arms of `arm` points, drawn half a stroke inside the edge.
private struct CornerBrackets: Shape {
    let arm: CGFloat

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: 0.5, dy: 0.5)
        var path = Path()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: box.minX, y: box.minY), 1, 1), (CGPoint(x: box.maxX, y: box.minY), -1, 1),
            (CGPoint(x: box.minX, y: box.maxY), 1, -1), (CGPoint(x: box.maxX, y: box.maxY), -1, -1),
        ]
        for (corner, dx, dy) in corners {
            path.move(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
        }
        return path
    }
}

/// The right wing's label-only empty state (DESIGN "Readout"): `NO AGENT CONNECTED` or `NO ACTIVE SESSIONS`
/// in readout-label type, `ink-3`.
public struct WingEmptyReadout: View {
    @Environment(\.vigieTheme) private var theme
    private let label: LocalizedStringResource

    public init(_ state: VigieCopy.EmptyState) {
        label = state.label
    }

    public var body: some View {
        Text(verbatim: String(localized: label))
            .font(theme.font(.readoutLabel))
            .tracking(theme.tracking(.readoutLabel))
            .foregroundStyle(theme.color(.ink3))
            .lineLimit(1)
    }
}

#Preview("Session glyphs") {
    SessionGlyphPreview()
}

private struct SessionGlyphPreview: View {
    var body: some View {
        VStack(alignment: .leading) {
            ForEach(Look.allCases, id: \.self) { look in
                ForEach(ThemeLoader.builtInIDs, id: \.self) { variant in
                    let theme = PreviewThemes.theme(look, variant: variant)
                    HStack(spacing: theme.spacing(.glyphGap)) {
                        ForEach(SessionStatus.allCases, id: \.self) { SessionGlyphView($0) }
                        WingEmptyReadout(VigieCopy.noActiveSessions)
                    }
                    .padding(theme.spacing(.gridPaddingX))
                    .background(theme.color(look == .dark ? .island : .surfacePanel))
                    .vigieTheme(theme)
                }
            }
        }
    }
}
