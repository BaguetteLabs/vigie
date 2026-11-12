import SwiftUI

/// The Pomodoro phase indicator (DESIGN "Phase indicator", `components.phase-pips`, Story 1.7e / 20.5): one pip
/// per work period of the set. Done: a filled 4px dot in `ink-1`. Current: a 7px ring in the Time accent,
/// hatched during a break. Upcoming: a 4px hollow ring in a 1px `ink-3` line (shape, not only lightness, tells
/// it from done). VoiceOver reads the pips as one element ("Work, cycle 2 of 4").
public struct PhasePips: View {
    @Environment(\.vigieTheme) private var theme
    private let pips: TimeRowModel.Pips

    public init(_ pips: TimeRowModel.Pips) {
        self.pips = pips
    }

    public var body: some View {
        HStack(spacing: TimeMetrics.pipGap) {
            ForEach(Array(pips.marks.enumerated()), id: \.offset) { _, mark in
                pip(mark)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: pips.accessibilityLabel))
    }

    @ViewBuilder private func pip(_ mark: TimeRowModel.Pips.Mark) -> some View {
        switch mark {
        case .done:
            Circle()
                .fill(theme.color(.ink1))
                .frame(width: TimeMetrics.pipDot, height: TimeMetrics.pipDot)
        case .upcoming:
            Circle()
                .strokeBorder(theme.color(.ink3), lineWidth: theme.a11y.hairlineWidth)
                .frame(width: TimeMetrics.pipDot, height: TimeMetrics.pipDot)
        case .current(let hatched):
            let accent = theme.color(TimeMetrics.accentRole(theme))
            ZStack {
                if hatched {
                    PipHatch()
                        .stroke(accent, lineWidth: TimeMetrics.pipHatchLine)
                        .clipShape(Circle())
                }
                Circle().strokeBorder(accent, lineWidth: TimeMetrics.pipCurrentStroke)
            }
            .frame(width: TimeMetrics.pipCurrent, height: TimeMetrics.pipCurrent)
        }
    }
}

/// Diagonal lines (135°, `PIP hatch`): the mockup's `repeating-linear-gradient(135deg, accent 0 1px, …)`.
struct PipHatch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let pitch = TimeMetrics.pipHatchPitch
        var offset = -rect.height
        while offset < rect.width {
            path.move(to: CGPoint(x: rect.minX + offset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + offset + rect.height, y: rect.minY))
            offset += pitch
        }
        return path
    }
}

/// The Away pause mark (DESIGN "Time tab" › Away, `components.time-ring.ring-only-away`): two 1px bars, so the
/// paused state is not told by color alone. Decoration: the row label says "paused".
public struct TimePauseMark: View {
    @Environment(\.vigieTheme) private var theme
    private let role: ColorRole

    public init(role: ColorRole = .ink2) {
        self.role = role
    }

    public var body: some View {
        HStack(spacing: TimeMetrics.pauseBarGap) {
            Rectangle().frame(width: TimeMetrics.pauseBarWidth)
            Rectangle().frame(width: TimeMetrics.pauseBarWidth)
        }
        .frame(height: TimeMetrics.pauseBarHeight)
        .foregroundStyle(theme.color(role))
        .accessibilityHidden(true)
    }
}

#Preview("Phase pips") {
    let theme = PreviewThemes.theme(.dark)
    VStack(spacing: theme.spacing(.gridGap)) {
        PhasePips(.init(count: 4, current: 2, onBreak: false, accessibilityLabel: "Work, cycle 2 of 4"))
        PhasePips(.init(count: 4, current: 2, onBreak: true, accessibilityLabel: "Break, cycle 2 of 4"))
        PhasePips(.init(count: 4, current: 4, onBreak: true, accessibilityLabel: "Long break, cycle 4 of 4"))
        TimePauseMark()
    }
    .padding(theme.spacing(.gridPaddingX))
    .background(theme.color(.surfacePanel))
    .vigieTheme(theme)
}
