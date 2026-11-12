import SwiftUI

/// A level on the shared status vocabulary (DESIGN "Status vocabulary", UX-DR82). Modules pass a level,
/// never a color.
public enum StatusLevel: String, Sendable, CaseIterable, Codable {
    case ok
    case warn
    case down
}

/// The shape and color roles for a level in a look. Pure, so it is testable without rendering.
///
/// OK = hollow ring in `status-idle`; WARN = triangle in `quota-warning`, label in `quota-warning-text` in
/// light looks; DOWN = cross in `status-failed`. The roles are the user's status colors, so a recolored
/// `idle` also recolors OK.
public struct StatusMarkStyle: Sendable, Equatable {
    public enum Shape: Sendable, Equatable {
        case ring
        case triangle
        case cross
    }

    public var shape: Shape
    public var shapeRole: ColorRole
    public var labelRole: ColorRole

    public init(level: StatusLevel, look: Look) {
        switch level {
        case .ok:
            shape = .ring
            shapeRole = .statusIdle
            labelRole = .statusIdle
        case .warn:
            shape = .triangle
            shapeRole = .quotaWarning
            labelRole = look == .light ? .quotaWarningText : .quotaWarning
        case .down:
            shape = .cross
            shapeRole = .statusFailed
            labelRole = .statusFailed
        }
    }
}

/// The three status-mark sizes: 26px on cards and the script page, 16px in the closed-notch side slot,
/// 10px inline (`components.status-vocabulary`).
public enum StatusMarkSize: String, Sendable, CaseIterable {
    case large
    case medium
    case small

    /// The size in points from the theme (`size-card`, `size-slot`, `size-inline`), else the DESIGN value.
    public func length(in theme: Theme) -> CGFloat {
        theme.componentLength("status-vocabulary", componentKey) ?? fallback
    }

    var componentKey: String {
        switch self {
        case .large: "size-card"
        case .medium: "size-slot"
        case .small: "size-inline"
        }
    }

    /// DESIGN.md values, used only if a theme file lacks `components.status-vocabulary`.
    var fallback: CGFloat {
        switch self {
        case .large: 26
        case .medium: 16
        case .small: 10
        }
    }
}

/// The status vocabulary primitive: shape, hue and label always together. Static in every Presence mode
/// and never raises an alert; it only draws.
public struct StatusMark: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.timeZone) private var timeZone
    private let level: StatusLevel
    private let size: StatusMarkSize
    private let qualifier: StatusQualifier?

    /// - Parameters:
    ///   - level: OK, WARN or DOWN.
    ///   - size: large (26), medium (16) or small (10).
    ///   - qualifier: optional text after the label (`CHECKED 2 MIN AGO`, `DOWN SINCE 14:44`, `OK · UP`).
    public init(level: StatusLevel, size: StatusMarkSize = .large, qualifier: StatusQualifier? = nil) {
        self.level = level
        self.size = size
        self.qualifier = qualifier
    }

    public var body: some View {
        let style = StatusMarkStyle(level: level, look: theme.look)
        let length = size.length(in: theme)
        let label = StatusLabelFormatter(timeZone: timeZone).label(for: level, qualifier: qualifier)
        HStack(spacing: size == .small ? theme.spacing(.glyphGap) / 2 : theme.spacing(.glyphGap)) {
            StatusMarkShape(shape: style.shape, length: length)
                .foregroundStyle(theme.color(style.shapeRole))
                .frame(width: length, height: length)
            Text(verbatim: label)
                .font(theme.font(.rowStatus))
                .tracking(theme.tracking(.rowStatus))
                .foregroundStyle(theme.color(style.labelRole))
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
    }
}

/// The status vocabulary's shape alone, in its level's hue (UX-DR82): for layouts that place the label
/// themselves (the script status widget's `26px | 1fr` grid, the side-slot item's level over target) and for
/// the WARN badge of an errored script's meta line. Hidden from VoiceOver: the label beside it is read.
public struct StatusMarkGlyph: View {
    @Environment(\.vigieTheme) private var theme
    private let level: StatusLevel
    private let size: StatusMarkSize
    private let length: CGFloat?

    /// - Parameters:
    ///   - size: large (26), medium (16) or small (10), from the theme.
    ///   - length: overrides the size's length (a closed-notch glyph capped to a short band).
    public init(level: StatusLevel, size: StatusMarkSize = .large, length: CGFloat? = nil) {
        self.level = level
        self.size = size
        self.length = length
    }

    public var body: some View {
        let style = StatusMarkStyle(level: level, look: theme.look)
        let side = length ?? size.length(in: theme)
        StatusMarkShape(shape: style.shape, length: side)
            .foregroundStyle(theme.color(style.shapeRole))
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

/// Ring 2px, cross 3px round-capped at 26px, scaled down for smaller sizes (never under 1px).
private struct StatusMarkShape: View {
    let shape: StatusMarkStyle.Shape
    let length: CGFloat

    private var reference: CGFloat { StatusMarkSize.large.fallback }

    var body: some View {
        switch shape {
        case .ring:
            Circle()
                .inset(by: length * 0.12)
                .stroke(lineWidth: max(1, length * 2 / reference))
        case .triangle:
            WarningTriangle()
        case .cross:
            CrossShape()
                .stroke(
                    style: StrokeStyle(lineWidth: max(1, length * 3 / reference), lineCap: .round))
        }
    }
}

/// Filled triangle (mock 1.7d: `M6 1.2 L11.2 10.6 H0.8 Z` in a 12 box).
struct WarningTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let unit = rect.width / 12
        path.move(to: CGPoint(x: rect.minX + 6 * unit, y: rect.minY + 1.2 * unit))
        path.addLine(to: CGPoint(x: rect.minX + 11.2 * unit, y: rect.minY + 10.6 * unit))
        path.addLine(to: CGPoint(x: rect.minX + 0.8 * unit, y: rect.minY + 10.6 * unit))
        path.closeSubpath()
        return path
    }
}

/// An × inset from the square.
struct CrossShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.width * 0.22
        let box = rect.insetBy(dx: inset, dy: inset)
        var path = Path()
        path.move(to: CGPoint(x: box.minX, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
        path.move(to: CGPoint(x: box.maxX, y: box.minY))
        path.addLine(to: CGPoint(x: box.minX, y: box.maxY))
        return path
    }
}

#Preview("Status marks · dark") {
    StatusMarkPreview(look: .dark)
}

#Preview("Status marks · light") {
    StatusMarkPreview(look: .light)
}

private struct StatusMarkPreview: View {
    let look: Look

    var body: some View {
        let theme = PreviewThemes.theme(look)
        VStack(alignment: .leading, spacing: theme.spacing(.rowGap)) {
            ForEach(StatusMarkSize.allCases, id: \.self) { size in
                HStack(spacing: theme.spacing(.gridGap)) {
                    StatusMark(level: .ok, size: size, qualifier: .checkedAgo(PreviewSamples.minutes(2)))
                    StatusMark(level: .warn, size: size)
                    StatusMark(level: .down, size: size, qualifier: .since(.now))
                }
            }
        }
        .padding(theme.spacing(.gridPaddingX))
        .background(theme.color(.surfacePanel))
        .vigieTheme(theme)
    }
}
