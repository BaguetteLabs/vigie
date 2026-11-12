import SwiftUI

/// The status widget body (DESIGN "Script widget" › Status): the 26px status-vocabulary glyph, then the level
/// label (`OK · UP`, row-status style in the level hue) over the value line (peek-title style, `ink-1`), on a
/// `26px | 1fr` grid. Script text (qualifier, value) is masked under Privacy mode; the level stays.
public struct ScriptStatusWidget: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.privacyActive) private var privacyActive
    private let level: StatusLevel
    private let qualifier: String?
    private let value: String?

    public init(level: StatusLevel, qualifier: String? = nil, value: String? = nil) {
        self.level = level
        self.qualifier = qualifier
        self.value = value
    }

    public var body: some View {
        let style = StatusMarkStyle(level: level, look: theme.look)
        let shownQualifier = privacyActive ? qualifier.privacyMasked : qualifier
        let label = StatusLabelFormatter().label(for: level, qualifier: shownQualifier.map { .detail($0) })
        HStack(alignment: .center, spacing: theme.spacing(.glyphGap)) {
            StatusMarkGlyph(level: level, size: .large)
            VStack(alignment: .leading, spacing: theme.spacing(.glyphGap) / 2) {
                Text(verbatim: label)
                    .font(theme.font(.rowStatus))
                    .tracking(theme.tracking(.rowStatus))
                    .foregroundStyle(theme.color(style.labelRole))
                if let value {
                    Text(verbatim: value)
                        .font(theme.font(.peekTitle))
                        .tracking(theme.tracking(.peekTitle))
                        .foregroundStyle(theme.color(.ink1))
                        .sensitive()
                }
            }
            .lineLimit(1)
        }
    }
}

/// The number widget body (DESIGN "Script widget" › Number, UX-DR36): the big numeral and its label, the
/// segmented 6px bar with the warn segment outlined in the quota-warning yellow (A43), the detail under it. The
/// number stays under Privacy mode; label and detail are masked.
public struct ScriptNumberWidget: View {
    @Environment(\.vigieTheme) private var theme
    private let value: String
    private let label: String?
    private let detail: String?
    private let bar: ScriptNumberBar

    public init(value: String, label: String? = nil, detail: String? = nil, bar: ScriptNumberBar) {
        self.value = value
        self.label = label
        self.detail = detail
        self.bar = bar
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.glyphGap)) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.glyphGap)) {
                Text(verbatim: value)
                    .font(theme.font(.numeralBig))
                    .tracking(theme.tracking(.numeralBig))
                    .foregroundStyle(theme.color(.ink1))
                    .minimumScaleFactor(ScriptWidgetMetrics.numeralMinimumScale)
                if let label {
                    Text(verbatim: label)
                        .font(theme.font(.body))
                        .foregroundStyle(theme.color(.ink2))
                        .sensitive()
                }
            }
            .lineLimit(1)
            ScriptNumberBarView(bar: bar)
            if let detail {
                Text(verbatim: detail)
                    .font(theme.font(.cardTitle))
                    .tracking(theme.tracking(.cardTitle))
                    .foregroundStyle(theme.color(.ink3))
                    .lineLimit(1)
                    .sensitive()
            }
        }
    }
}

/// The segmented bar: lit segments in the metal fill (A platinum → silver, C silver → white), unlit ones in a
/// faint `line` tint, the warn segment outlined 1px in `quota-warning`.
public struct ScriptNumberBarView: View {
    @Environment(\.vigieTheme) private var theme
    private let bar: ScriptNumberBar

    public init(bar: ScriptNumberBar) {
        self.bar = bar
    }

    public var body: some View {
        let shape = Capsule(style: .continuous)
        HStack(spacing: ScriptWidgetMetrics.segmentGap) {
            ForEach(Array(bar.segments.enumerated()), id: \.offset) { _, segment in
                shape
                    .fill(fill(segment))
                    .overlay {
                        if case .warn = segment {
                            shape.strokeBorder(theme.color(.quotaWarning), lineWidth: theme.a11y.hairlineWidth)
                        }
                    }
            }
        }
        .frame(height: ScriptWidgetMetrics.barHeight)
        .accessibilityHidden(true)
    }

    private func fill(_ segment: ScriptNumberBar.Segment) -> AnyShapeStyle {
        let lit: Bool
        switch segment {
        case .on: lit = true
        case .off: lit = false
        case .warn(let isLit): lit = isLit
        }
        guard lit else { return AnyShapeStyle(theme.color(.line)) }
        let tactical = theme.defines(.structure)
        let colors: [ColorRole] = tactical ? [.lineSilver, .ink1] : [.ink1, .lineSilver]
        return theme.glassFill(
            LinearGradient(colors: colors.map(theme.color), startPoint: .leading, endPoint: .trailing),
            flat: .lineSilver)
    }
}

/// The short-text widget body (DESIGN "Script widget" › Short text): its label (`TEXT` when the output has
/// none) in `ink-3` over the value (peek-title style, `ink-1`). The script's label and value are masked under
/// Privacy mode; the `TEXT` default is core copy.
public struct ScriptTextWidget: View {
    @Environment(\.vigieTheme) private var theme
    private let label: String?
    private let value: String

    public init(label: String? = nil, value: String) {
        self.label = label
        self.value = value
    }

    /// `TEXT`, from the VigieUI catalog.
    public static var defaultLabel: String { L10n.string("script.widget.text") }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.glyphGap) / 2) {
            Group {
                if let label {
                    Text(verbatim: label).sensitive()
                } else {
                    Text(verbatim: Self.defaultLabel)
                }
            }
            .font(theme.font(.cardTitle))
            .tracking(theme.tracking(.cardTitle))
            .textCase(.uppercase)
            .foregroundStyle(theme.color(.ink3))
            .lineLimit(1)
            Text(verbatim: value)
                .font(theme.font(.peekTitle))
                .tracking(theme.tracking(.peekTitle))
                .foregroundStyle(theme.color(.ink1))
                .lineLimit(ScriptWidgetMetrics.textValueLines)
                .sensitive()
        }
    }
}

/// The body of any widget content.
public struct ScriptWidgetBody: View {
    private let content: ScriptWidgetContent

    public init(_ content: ScriptWidgetContent) {
        self.content = content
    }

    public var body: some View {
        switch content {
        case .status(let level, let qualifier, let value):
            ScriptStatusWidget(level: level, qualifier: qualifier, value: value)
        case .number(let value, let label, let detail, let bar, _):
            ScriptNumberWidget(value: value, label: label, detail: detail, bar: bar)
        case .text(let label, let value, _):
            ScriptTextWidget(label: label, value: value)
        }
    }
}

/// Script widget proportions not in the tokens (DESIGN "Script widget", mock 1.7d).
enum ScriptWidgetMetrics {
    /// The number bar's height (`segmented 6px bar`).
    static let barHeight: CGFloat = 6
    /// Gap between bar segments (mock `.seg` `gap: 4px`).
    static let segmentGap: CGFloat = 4
    /// A long number shrinks to this share of the numeral size before truncating.
    static let numeralMinimumScale: CGFloat = 0.5
    /// A short text value wraps to at most this many lines.
    static let textValueLines = 2
}
