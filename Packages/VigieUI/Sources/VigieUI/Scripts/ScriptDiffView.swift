import SwiftUI

/// The line diff of a script update (Story 12.10) in the Script Confirmation: monospaced, `+` lines on a tint of
/// the theme's `status-done`, `−` lines on a tint of `status-failed`, unchanged lines in the secondary text color,
/// long unchanged runs folded into `12 unchanged lines`. Script text: masked in Privacy mode (UX-DR98).
public struct ScriptDiffView: View {
    @Environment(\.vigieTheme) private var theme
    private let rows: [ScriptLineDiff.Row]

    public init(lines: [ScriptLineDiff.Line], context: Int = ScriptLineDiff.defaultContext) {
        rows = ScriptLineDiff.rows(lines, context: context)
    }

    public var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    switch row {
                    case .line(let line): lineView(line)
                    case .skipped(let count):
                        Text(verbatim: ScriptConfirmationCopy.skipped(count))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, ScriptConfirmationMetrics.lineSpacing)
                    }
                }
            }
            .fixedSize()
            .padding(ScriptConfirmationMetrics.codePadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .quaternary.opacity(ScriptConfirmationMetrics.codeBackgroundOpacity),
            in: RoundedRectangle(cornerRadius: ScriptConfirmationMetrics.codeCornerRadius)
        )
        .textSelection(.enabled)
        .sensitive()
    }

    private func lineView(_ line: ScriptLineDiff.Line) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ScriptConfirmationMetrics.paragraphSpacing) {
            Text(verbatim: Self.marker(line.kind))
                .foregroundStyle(markerColor(line.kind))
            Text(verbatim: line.text.isEmpty ? " " : line.text)
                .foregroundStyle(line.kind == .context ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
        .font(.system(.callout, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint(line.kind))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: ScriptConfirmationCopy.spoken(line)))
    }

    static func marker(_ kind: ScriptLineDiff.Line.Kind) -> String {
        switch kind {
        case .added: "+"
        case .removed: "−"
        case .context: " "
        }
    }

    private func markerColor(_ kind: ScriptLineDiff.Line.Kind) -> Color {
        switch kind {
        case .added: theme.color(.statusDone)
        case .removed: theme.color(.statusFailed)
        case .context: .clear
        }
    }

    private func tint(_ kind: ScriptLineDiff.Line.Kind) -> Color {
        switch kind {
        case .added: theme.color(.statusDone).opacity(ScriptConfirmationMetrics.diffTintOpacity)
        case .removed: theme.color(.statusFailed).opacity(ScriptConfirmationMetrics.diffTintOpacity)
        case .context: .clear
        }
    }
}
