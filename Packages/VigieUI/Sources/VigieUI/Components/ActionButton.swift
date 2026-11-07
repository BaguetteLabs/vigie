import SwiftUI

/// The shared action button (DESIGN "Action button", UX-DR25): 30px, label left (action type, uppercase),
/// shortcut right. Chrome Hologram: pill, 1px platinum border at 22% and a faint glass gradient; secondary
/// has no fill and a dimmer border; light looks fill white → panel with a 1px shadow. Twin Metal Tactical:
/// square, 1px struct inner border at 30%; primary adds a gold frame, gold text and a gold gradient.
/// Keyboard focus draws a 1px ring in `iris-1` (2px under Increase contrast); borders turn solid `ink-3` and
/// glass gradients flat `surface-card` under Increase contrast / Reduce transparency (`theme.a11y`). Its accessibility label includes the shortcut.
public struct ActionButton: View {
    public enum Role: Sendable, Equatable {
        case primary
        case secondary
    }

    private let label: Text
    private let accessibilityText: String
    private let shortcut: String?
    private let role: Role
    private let action: @MainActor () -> Void

    /// - Parameters:
    ///   - label: catalog string from the caller's package (`Open settings`).
    ///   - shortcut: key glyphs shown on the right (`⌥⌘↵`, `⌘,`), or nil.
    public init(
        label: LocalizedStringResource,
        shortcut: String? = nil,
        role: Role = .secondary,
        action: @escaping @MainActor () -> Void
    ) {
        self.label = Text(label)
        self.accessibilityText = AccessibilityLabel.control(String(localized: label), shortcut: shortcut)
        self.shortcut = shortcut
        self.role = role
        self.action = action
    }

    public var body: some View {
        Button(action: action) { label }
            .buttonStyle(ActionButtonStyle(shortcut: shortcut, role: role))
            .focusEffectDisabled()
            .accessibilityLabel(Text(verbatim: accessibilityText))
    }
}

struct ActionButtonStyle: ButtonStyle {
    let shortcut: String?
    let role: ActionButton.Role

    func makeBody(configuration: Configuration) -> some View {
        ActionButtonBody(label: configuration.label, shortcut: shortcut, role: role, isPressed: configuration.isPressed)
    }
}

private struct ActionButtonBody: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    let label: ButtonStyleConfiguration.Label
    let shortcut: String?
    let role: ActionButton.Role
    let isPressed: Bool

    var body: some View {
        let height = theme.actionHeight
        let shape = RoundedRectangle(cornerRadius: theme.actionRadius(height: height), style: .continuous)
        HStack(spacing: theme.spacing(.actionGap)) {
            label
                .font(theme.font(.action))
                .tracking(theme.tracking(.action))
                .textCase(.uppercase)
                .foregroundStyle(theme.color(labelRole))
                .lineLimit(1)
            if let shortcut {
                Spacer(minLength: theme.spacing(.actionGap))
                Text(verbatim: shortcut)
                    .font(theme.font(.body))
                    .foregroundStyle(theme.color(.ink2))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, theme.spacing(.tabPaddingX))
        .frame(height: height)
        .background(fill, in: shape)
        .overlay {
            shape.strokeBorder(borderColor, lineWidth: theme.a11y.hairlineWidth)
        }
        .overlay {
            if theme.usesCornerMarks && role == .primary {
                CornerMarks()
                    .stroke(theme.color(.gold), lineWidth: theme.a11y.hairlineWidth)
            }
        }
        .overlay {
            if isFocused {
                shape.strokeBorder(theme.color(.iris1), lineWidth: theme.a11y.focusRingWidth)
            }
        }
        .shadow(
            color: theme.isLight && !theme.usesCornerMarks && role == .primary && !theme.a11y.flatSurfaces
                ? theme.color(.shadow).opacity(ComponentMetrics.actionBorderSecondary) : .clear,
            radius: 0, y: ComponentMetrics.hairline
        )
        .contentShape(shape)
        .opacity(isPressed ? ComponentMetrics.pressedOpacity : (isEnabled ? 1 : ComponentMetrics.disabledOpacity))
    }

    private var labelRole: ColorRole {
        theme.usesCornerMarks && role == .primary ? .goldText : .ink1
    }

    private var borderColor: Color {
        if theme.usesCornerMarks {
            return theme.borderColor(.structure, opacity: ComponentMetrics.structBorder)
        }
        let opacity = role == .primary ? ComponentMetrics.actionBorderPrimary : ComponentMetrics.actionBorderSecondary
        return theme.borderColor(.ink1, opacity: opacity)
    }

    private var fill: AnyShapeStyle {
        if role == .secondary { return AnyShapeStyle(Color.clear) }
        // Reduce transparency / Increase contrast: every glass gradient becomes flat `surface-card`.
        if theme.usesCornerMarks {
            return theme.glassFill(
                LinearGradient(
                    colors: [
                        theme.color(.gold).opacity(ComponentMetrics.goldTop),
                        theme.color(.gold).opacity(ComponentMetrics.goldBottom),
                    ], startPoint: .top, endPoint: .bottom), flat: .surfaceCard)
        }
        if theme.isLight {
            return theme.glassFill(
                LinearGradient(
                    colors: [theme.color(.surfaceCard), theme.color(.surfacePanel)],
                    startPoint: .top, endPoint: .bottom), flat: .surfaceCard)
        }
        return theme.glassFill(
            LinearGradient(
                colors: [
                    theme.color(.ink1).opacity(ComponentMetrics.glassTop),
                    theme.color(.ink1).opacity(ComponentMetrics.glassBottom),
                ], startPoint: .top, endPoint: .bottom), flat: .surfaceCard)
    }
}

/// Small inline chip for row actions and tags (`FOCUS ↵`, `JOIN CALL ↵`, `COPY`, `REVEAL`), in the action
/// type, uppercase. Neutral: `ink-2` on a faint fill; accent: iris (A) / gold text (C).
public struct InlineChip: View {
    public enum Tone: Sendable, Equatable {
        case neutral
        case accent
    }

    @Environment(\.vigieTheme) private var theme
    private let text: Text
    private let tone: Tone

    public init(text: LocalizedStringResource, tone: Tone = .neutral) {
        self.text = Text(text)
        self.tone = tone
    }

    /// A chip showing data as given (a shortcut, a count).
    public init(verbatim: String, tone: Tone = .neutral) {
        self.text = Text(verbatim: verbatim)
        self.tone = tone
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius(.code), style: .continuous)
        let role: ColorRole = tone == .accent ? theme.accentRole : .ink2
        text
            .font(theme.font(.action))
            .tracking(theme.tracking(.action))
            .textCase(.uppercase)
            .foregroundStyle(theme.color(role))
            .lineLimit(1)
            .padding(.horizontal, theme.spacing(.glyphGap))
            .padding(.vertical, theme.spacing(.glyphGap) / 2)
            .background(theme.color(role).opacity(ComponentMetrics.chipFill), in: shape)
            .overlay {
                shape.strokeBorder(
                    theme.borderColor(role, opacity: ComponentMetrics.chipBorder),
                    lineWidth: theme.a11y.hairlineWidth)
            }
    }
}

#Preview("Actions · dark") {
    ActionPreview(look: .dark)
}

#Preview("Actions · light") {
    ActionPreview(look: .light)
}

#Preview("Actions · Twin Metal") {
    ActionPreview(look: .dark, variant: "twin-metal-tactical")
}

private struct ActionPreview: View {
    let look: Look
    var variant = ThemeLibrary.defaultVariantID

    var body: some View {
        let theme = PreviewThemes.theme(look, variant: variant)
        VStack(alignment: .leading, spacing: theme.spacing(.actionGap)) {
            ActionButton(label: VigieCopy.openSettings, shortcut: "⌥⌘↵", role: .primary) {}
            ActionButton(label: VigieCopy.openSystemSettings, shortcut: "⌥⌘⌫") {}
            HStack(spacing: theme.spacing(.glyphGap)) {
                InlineChip(verbatim: "Focus ↵", tone: .accent)
                InlineChip(verbatim: "Copy")
            }
        }
        .frame(width: theme.componentLength("send-to-card", "width"))
        .padding(theme.spacing(.gridPaddingX))
        .background(theme.color(.surfacePanel))
        .vigieTheme(theme)
    }
}
