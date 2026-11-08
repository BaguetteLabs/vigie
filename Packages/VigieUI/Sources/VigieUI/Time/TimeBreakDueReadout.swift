import SwiftUI

/// The closed-notch `BREAK DUE` readout (DESIGN "Time readout" › Break due, mockup 1.7e "Quiet readout", Story
/// 20.4): a full dashed 23px ring in the Time accent, then the break length (`5:00`, `15:00`) over `BREAK DUE`.
/// Static, no motion. The ring-only form (``CompactSize/icon``-like slots) adds a small center triangle.
public struct TimeBreakDueReadout: View {
    @Environment(\.vigieTheme) private var theme
    private let value: String
    private let ringOnly: Bool
    private let accessibility: String

    /// - Parameters:
    ///   - value: the break length, already formatted (`5:00`).
    ///   - ringOnly: the ring alone, with the center triangle.
    ///   - accessibilityLabel: what VoiceOver reads ("Break due, 5 minute break").
    public init(value: String, ringOnly: Bool = false, accessibilityLabel: String) {
        self.value = value
        self.ringOnly = ringOnly
        self.accessibility = accessibilityLabel
    }

    public var body: some View {
        let side = theme.componentLength("time-ring", "size-closed") ?? TimeMetrics.wingRingSize
        HStack(spacing: theme.spacing(.glyphGap)) {
            ZStack {
                TimeRing(fractionLeft: 1, dashed: true, size: side, lineWidth: TimeMetrics.wingRingStroke)
                if ringOnly {
                    BreakDueTriangle()
                        .fill(theme.color(TimeMetrics.accentRole(theme)))
                        .frame(width: side * TimeMetrics.triangleShare, height: side * TimeMetrics.triangleShare)
                }
            }
            if !ringOnly {
                WingReadout(value: value, label: L10n.string("time.closed.breakDue"))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibility))
    }
}

/// The ring-only break-due mark: a small play-like triangle pointing right.
struct BreakDueTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview("Break due readout") {
    let theme = PreviewThemes.theme(.dark)
    HStack(spacing: theme.spacing(.gridGap)) {
        TimeBreakDueReadout(value: "15:00", accessibilityLabel: "Break due")
        TimeBreakDueReadout(value: "15:00", ringOnly: true, accessibilityLabel: "Break due")
    }
    .padding(theme.spacing(.gridPaddingX))
    .background(theme.color(.band))
    .vigieTheme(theme)
}
