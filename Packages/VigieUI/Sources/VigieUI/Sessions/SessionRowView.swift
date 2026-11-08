import SwiftUI

/// One 30px Agents row on the `components.session-row` grid: glyph, agent, project over the last action (mono),
/// terminal (optional column), `STATUS · T+`, Focus chip. Blocked and failed rows carry the alert tint; hover
/// brightens and shows `FOCUS`; the keyboard selection adds the ring and `↵`, plus `DISMISS` on a dismissable
/// failed row. A click anywhere on the row is Focus.
struct SessionRowView: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.privacyActive) private var privacyActive
    let row: SessionRowModel
    let showsTerminal: Bool
    let isFirst: Bool
    let isSelected: Bool
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onFocus: @MainActor () -> Void
    let onDismiss: @MainActor () -> Void

    var body: some View {
        let columns = SessionColumns(theme: theme)
        let shape = RoundedRectangle(cornerRadius: theme.radius(.row), style: .continuous)
        HStack(spacing: theme.spacing(.rowGap)) {
            SessionGlyphView(row.glyphStatus, accessibilityLabel: spokenLabel)
                .frame(width: columns.glyph)
            Text(verbatim: row.agentName)
                .font(theme.font(.body))
                .foregroundStyle(theme.color(.ink2))
                .lineLimit(1)
                .frame(width: columns.agent, alignment: .leading)
            projectColumn
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsTerminal {
                Text(verbatim: row.terminalName ?? "")
                    .font(theme.font(.body))
                    .foregroundStyle(theme.color(.ink2))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: columns.terminal, alignment: .leading)
            }
            Text(verbatim: row.statusLabel)
                .font(theme.font(.rowStatus))
                .tracking(theme.tracking(.rowStatus))
                .foregroundStyle(theme.color(row.glyphStatus.colorRole))
                .lineLimit(1)
                .fixedSize()
                .frame(width: columns.status, alignment: .trailing)
            actions
                .frame(width: columns.action, alignment: .trailing)
        }
        .padding(.horizontal, theme.spacing(.actionGap))
        .frame(height: columns.height)
        .background { SessionAlertTint(status: row.glyphStatus, isAlert: row.isAlert) }
        .rowHoverBrighten()
        .keyboardSelectionRing(isSelected: isSelected)
        .overlay(alignment: .top) {
            if !isFirst && !row.isAlert {
                Rectangle()
                    .fill(theme.color(.ink1).opacity(ComponentMetrics.cardHairline(theme.look)))
                    .frame(height: theme.a11y.hairlineWidth)
                    .padding(.horizontal, theme.spacing(.actionGap))
                    .allowsHitTesting(false)
            }
        }
        .contentShape(shape)
        .onHover(perform: onHover)
        .onTapGesture { onFocus() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spokenLabel))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onFocus() }
        .accessibilityActions {
            if row.canDismiss {
                Button(L10n.resource("sessions.action.dismiss")) { onDismiss() }
            }
        }
    }

    /// The row's VoiceOver label, the project and last action masked in Privacy mode (AD-24).
    private var spokenLabel: String { row.privacy(privacyActive).accessibilityLabel }

    /// The project over the last action; a selected dismissable row ends it with `DISMISS ⌫`, so the other
    /// columns keep their grid positions.
    private var projectColumn: some View {
        HStack(spacing: theme.spacing(.glyphGap)) {
            projectLines
                .frame(maxWidth: .infinity, alignment: .leading)
            if isSelected && row.canDismiss {
                SessionRowChip(label: L10n.resource("sessions.action.dismiss"), key: "⌫", showsKey: true) {
                    onDismiss()
                }
            }
        }
    }

    private var projectLines: some View {
        VStack(alignment: .leading, spacing: SessionsMetrics.lineGap) {
            Text(verbatim: row.project)
                .font(theme.font(.rowPrimary))
                .foregroundStyle(theme.color(.ink1))
                .lineLimit(1)
                .truncationMode(.tail)
                .sensitive()
            if let lastAction = row.lastAction, !lastAction.isEmpty {
                Text(verbatim: lastAction)
                    .font(theme.font(.code))
                    .foregroundStyle(theme.color(secondaryRole))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .sensitive()
            }
        }
    }

    /// `ink-3`, except on a tinted row in a dark look, where `ink-3` drops under 4.5:1 (UX-DR94).
    private var secondaryRole: ColorRole {
        SessionAlertTint.secondaryRole(isAlert: row.isAlert, look: theme.look)
    }

    @ViewBuilder private var actions: some View {
        if isSelected || isHovered {
            SessionRowChip(label: L10n.resource("sessions.action.focus"), key: "↵", showsKey: isSelected) {
                onFocus()
            }
        }
    }
}

/// The row's `FOCUS ↵` / `DISMISS ⌫` chip (DESIGN "Session row"): a 22px pill (C: square) like a small action button,
/// label left and key right on the selection, label centred on hover.
struct SessionRowChip: View {
    @Environment(\.vigieTheme) private var theme
    let label: LocalizedStringResource
    let key: String
    let showsKey: Bool
    let action: @MainActor () -> Void

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: theme.actionRadius(height: SessionsMetrics.chipHeight), style: .continuous)
        Button(action: action) {
            HStack(spacing: theme.spacing(.glyphGap) / 2) {
                Text(label)
                    .font(theme.font(.action))
                    .tracking(theme.tracking(.action))
                    .textCase(.uppercase)
                    .foregroundStyle(theme.color(.ink1))
                if showsKey {
                    Text(verbatim: key)
                        .font(theme.font(.body))
                        .foregroundStyle(theme.color(.ink2))
                }
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, theme.spacing(.actionGap))
            .frame(height: SessionsMetrics.chipHeight)
            .background(fill, in: shape)
            .overlay {
                shape.strokeBorder(
                    theme.usesCornerMarks
                        ? theme.borderColor(.structure, opacity: ComponentMetrics.structBorder)
                        : theme.borderColor(.ink1, opacity: borderOpacity),
                    lineWidth: theme.a11y.hairlineWidth)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityHidden(true)
    }

    private var borderOpacity: Double {
        theme.isLight ? SessionsMetrics.chipBorderLight : ComponentMetrics.actionBorderPrimary
    }

    private var fill: AnyShapeStyle {
        let colors =
            theme.isLight
            ? [theme.color(.surfaceCard), theme.color(.surfacePanel)]
            : [
                theme.color(.ink1).opacity(SessionsMetrics.chipGlassTop),
                theme.color(.ink1).opacity(SessionsMetrics.chipGlassBottom),
            ]
        return theme.glassFill(
            LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom), flat: .surfaceCard)
    }
}

/// The alert tint of a blocked or failed row (DESIGN "Session row"): A, a horizontal fade in the state hue
/// (10% → 0) with a 1px inner outline; C, the same fade plus a 2px left bar in the state hue.
struct SessionAlertTint: View {
    @Environment(\.vigieTheme) private var theme
    let status: SessionStatus
    let isAlert: Bool

    var body: some View {
        if isAlert {
            let color = theme.color(status.colorRole)
            let shape = RoundedRectangle(cornerRadius: theme.radius(.row), style: .continuous)
            shape
                .fill(
                    LinearGradient(
                        colors: [color.opacity(SessionsMetrics.alertFade(theme.look)), color.opacity(0)],
                        startPoint: .leading, endPoint: .trailing)
                )
                .overlay {
                    shape.strokeBorder(
                        theme.borderColor(status.colorRole, opacity: SessionsMetrics.alertOutline(theme.look)),
                        lineWidth: theme.a11y.hairlineWidth)
                }
                .overlay(alignment: .leading) {
                    if theme.usesCornerMarks {
                        Rectangle().fill(color).frame(width: SessionsMetrics.alertBar)
                    }
                }
                .allowsHitTesting(false)
        }
    }

    /// The secondary line's color on a row: `ink-2` on a tinted row in a dark look, else `ink-3`.
    static func secondaryRole(isAlert: Bool, look: Look) -> ColorRole {
        isAlert && look == .dark ? .ink2 : .ink3
    }
}

/// The `components.session-row` grid in points: `18px 84px minmax(0,1fr) 62px 104px 76px`, 30px high.
struct SessionColumns: Equatable {
    var glyph: CGFloat = 18
    var agent: CGFloat = 84
    var terminal: CGFloat = 62
    var status: CGFloat = 104
    var action: CGFloat = 76
    var height: CGFloat = 30

    init(theme: Theme) {
        height = theme.componentLength("session-row", "height") ?? height
        guard let raw = theme.component("session-row", "columns") else { return }
        let fixed = raw.split(separator: " ").filter { !$0.hasPrefix("minmax") }.compactMap {
            ThemeValue.length(String($0))
        }
        guard fixed.count == 5 else { return }
        (glyph, agent, terminal, status, action) = (fixed[0], fixed[1], fixed[2], fixed[3], fixed[4])
    }
}

/// Proportions DESIGN and the Agents mockup state in prose (opacities, the chip size).
enum SessionsMetrics {
    /// Column header row height (mock: 16px).
    static let columnHeaderHeight: CGFloat = 16
    /// Gap between the project and the last-action line.
    static let lineGap: CGFloat = 0
    /// Focus / Dismiss chip height (mock: 22px).
    static let chipHeight: CGFloat = 22
    /// Chip glass gradient (A dark): white 8% → 1%; light border graphite 20%.
    static let chipGlassTop = 0.08
    static let chipGlassBottom = 0.01
    static let chipBorderLight = 0.20
    /// Alert tint: a 10% fade (8% light) with a 1px outline at 18% (20% light); C adds a 2px bar.
    static func alertFade(_ look: Look) -> Double { look == .dark ? 0.10 : 0.08 }
    static func alertOutline(_ look: Look) -> Double { look == .dark ? 0.18 : 0.20 }
    static let alertBar: CGFloat = 2
    /// Between the keyboard hints and `SORTED BY URGENCY` in the card meta (mock: 14px).
    static let metaSeparator = "    "
}
