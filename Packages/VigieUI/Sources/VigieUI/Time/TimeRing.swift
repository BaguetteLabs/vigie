import SwiftUI

/// The time ring (DESIGN `components.time-ring`, Story 1.7e): a `line` track and an arc in the Time accent
/// for the share left, clockwise from 12 o'clock. Solid for Timers and work; dashed (2.2 / 2) for breaks.
/// 30px in the Time tab rows, 26px in the peek beacon, 23px on the closed notch (Story 20.6). Decoration:
/// hidden from VoiceOver (the row label says the time left).
public struct TimeRing: View {
    @Environment(\.vigieTheme) private var theme
    private let fractionLeft: Double
    private let dashed: Bool
    private let dimmed: Bool
    private let size: CGFloat?
    private let lineWidth: CGFloat?

    /// - Parameters:
    ///   - fractionLeft: 0...1, the arc drawn.
    ///   - dashed: a break arc.
    ///   - dimmed: `ink-3` instead of the accent (paused, Away).
    ///   - size: the diameter; nil reads `components.time-ring.size-row`.
    ///   - lineWidth: the stroke; nil for the 2px row stroke (the closed ring uses 1.6px).
    public init(
        fractionLeft: Double, dashed: Bool = false, dimmed: Bool = false, size: CGFloat? = nil,
        lineWidth: CGFloat? = nil
    ) {
        self.fractionLeft = min(max(fractionLeft, 0), 1)
        self.dashed = dashed
        self.dimmed = dimmed
        self.size = size
        self.lineWidth = lineWidth
    }

    public var body: some View {
        let side = size ?? TimeMetrics.ringSize(theme)
        let line = lineWidth ?? TimeMetrics.ringStroke
        let inset = line / 2
        ZStack {
            Circle()
                .inset(by: inset)
                .stroke(theme.trackColor(.line), lineWidth: line)
            Circle()
                .inset(by: inset)
                .trim(from: 0, to: fractionLeft)
                .stroke(
                    theme.color(dimmed ? .ink3 : TimeMetrics.accentRole(theme)),
                    style: StrokeStyle(
                        lineWidth: line, lineCap: dashed ? .butt : .round, dash: dashed ? TimeMetrics.breakDash : [])
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// A Countdown's mark in the ring column (mockup `.dtrk`): a 1px track, the now dot at the elapsed share
/// and a tick at the end.
public struct CountdownTrack: View {
    @Environment(\.vigieTheme) private var theme
    private let fractionElapsed: Double

    public init(fractionElapsed: Double) {
        self.fractionElapsed = min(max(fractionElapsed, 0), 1)
    }

    public var body: some View {
        let side = TimeMetrics.ringSize(theme)
        let dot = TimeMetrics.trackDot
        let travel = side - dot - TimeMetrics.trackDotInset
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(theme.trackColor(.line))
                .frame(height: theme.a11y.hairlineWidth)
            Rectangle()
                .fill(theme.color(.ink1))
                .frame(width: theme.a11y.hairlineWidth, height: TimeMetrics.trackTick)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Circle()
                .fill(theme.color(TimeMetrics.accentRole(theme)))
                .frame(width: dot, height: dot)
                .offset(x: TimeMetrics.trackDotInset + travel * fractionElapsed)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// Lengths and roles of the Time surfaces that DESIGN states in prose (mockup `key-design-pass-1-7.html`).
enum TimeMetrics {
    static let ringStroke: CGFloat = 2
    static let breakDash: [CGFloat] = [2.2, 2]
    static let rowRingSize: CGFloat = 30
    static let beaconRingSize: CGFloat = 26
    static let trackDot: CGFloat = 5
    static let trackDotInset: CGFloat = 6
    static let trackTick: CGFloat = 7

    static let quickStartHeight: CGFloat = 84
    static let rowHeight: CGFloat = 62
    static let valueWidth: CGFloat = 92
    static let controlsWidth: CGFloat = 196
    static let columnGap: CGFloat = 14
    static let quickGap: CGFloat = 7
    static let quickButtonHeight: CGFloat = 34
    static let quickPaddingX: CGFloat = 12
    static let quickValueSize: CGFloat = 15
    static let quickUnitSize: CGFloat = 9
    static let fieldWidth: CGFloat = 40
    static let startHeight: CGFloat = 24
    static let chipHeight: CGFloat = 24
    static let chipPaddingX: CGFloat = 8
    static let chipGap: CGFloat = 5
    static let chipSize: CGFloat = 8
    static let kindSize: CGFloat = 8.5
    static let sublineSize: CGFloat = 7.5
    static let labelGap: CGFloat = 7
    static let valueGap: CGFloat = 5
    static let chipBorder = 0.18
    static let chipBorderDim = 0.08
    static let quickBorder = 0.18
    static let pomodoroBorder = 0.38
    /// The primary chip's accent fill (`START BREAK`).
    static let primaryChipFill = 0.10
    /// The closed-notch ring (`components.time-ring` on the left wing, mockup 23px) and its stroke.
    static let wingRingSize: CGFloat = 23
    static let wingRingStroke: CGFloat = 1.6
    /// The ring-only break-due triangle against the ring diameter.
    static let triangleShare: CGFloat = 0.3
    static let quickGlassTop = 0.07
    static let quickGlassBottom = 0.01
    static let fieldFill = 0.035
    static let fieldBorder = 0.08
    static let countdownFormWidth: CGFloat = 240
    static let previewHeight: CGFloat = 350

    /// The Time accent: A `iris-1` (cyan), C `gold` (DESIGN "Time accent"); never a status hue.
    static func accentRole(_ theme: Theme) -> ColorRole { theme.usesCornerMarks ? .gold : .iris1 }
    /// Text in the Time accent: C reads `gold-text`.
    static func accentTextRole(_ theme: Theme) -> ColorRole { theme.usesCornerMarks ? .goldText : .iris1 }

    static func ringSize(_ theme: Theme) -> CGFloat {
        theme.componentLength("time-ring", "size-row") ?? rowRingSize
    }

    /// Row rule (`--hair2`): 4% dark, 7% light.
    static func rowRule(_ look: Look) -> Double { look == .dark ? 0.04 : 0.07 }

    /// A role's family at a mockup size (the role's weight unless given).
    static func font(_ theme: Theme, _ role: TypographyRole, size: CGFloat, weight: Int? = nil) -> Font {
        let spec = theme.fontSpec(role)
        return FontSpec(
            family: spec.family, size: size, weight: weight ?? spec.weight, tabularDigits: spec.tabularDigits
        ).font
    }
}
