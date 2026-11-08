import ModuleKit
import SwiftUI

// Privacy mode rendering (AD-24, UX-DR98, Story 21.2). The host sets `privacyActive` at each surface root
// (closed notch, peek, expanded panel and its Home cards, Settings); views mark user text with `.sensitive()`
// and build composed strings (VoiceOver labels, tooltips) from `model.privacy(active)`. Status glyphs, rings,
// `T+`, numbers, status labels, kickers, provider and module names are never marked.

extension EnvironmentValues {
    /// True while Privacy mode is on. Set by the host at each surface root; false by default.
    @Entry public var privacyActive: Bool = false
}

extension View {
    /// Sets Privacy mode for this view tree (host surface roots).
    public func privacyActive(_ isActive: Bool) -> some View {
        environment(\.privacyActive, isActive)
    }

    /// Hides this view while Privacy mode is active (AD-24): text becomes the fixed-width dots mask in
    /// `ink-3` (DESIGN "Secret mask", UX-DR98), a thumbnail a neutral placeholder of the same size. The hidden
    /// content leaves the accessibility tree; the mask reads "Hidden".
    public func sensitive(_ style: SensitiveStyle = .text) -> some View {
        modifier(SensitiveModifier(style: style))
    }
}

/// How a hidden field is drawn.
public enum SensitiveStyle: Sendable, Hashable {
    /// Fixed-width dots in the secret-mask style, whatever the text's length.
    case text
    /// A neutral placeholder in the content's own frame (image thumbnails).
    case thumbnail
}

struct SensitiveModifier: ViewModifier {
    @Environment(\.privacyActive) private var privacyActive
    let style: SensitiveStyle

    @ViewBuilder func body(content: Content) -> some View {
        if !privacyActive {
            content
        } else {
            switch style {
            case .text:
                PrivacyMaskView()
            case .thumbnail:
                content.hidden()
                    .accessibilityHidden(true)
                    .overlay { PrivacyThumbnailPlaceholder() }
            }
        }
    }
}

/// The dots that stand for a hidden field (UX-DR98): ``PrivacyMask/text`` in the code face, `ink-3`,
/// one line, never truncated, so every hidden field has the same width.
public struct PrivacyMaskView: View {
    @Environment(\.vigieTheme) private var theme

    public init() {}

    public var body: some View {
        Text(verbatim: PrivacyMask.text)
            .font(theme.font(.code))
            .foregroundStyle(theme.color(.ink3))
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel(Text(L10n.resource("privacy.hidden")))
    }
}

/// A hidden thumbnail: a flat `ink-3` tint in the thumbnail's frame.
struct PrivacyThumbnailPlaceholder: View {
    @Environment(\.vigieTheme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: theme.radius(.row), style: .continuous)
            .fill(theme.color(.ink3).opacity(PrivacyMetrics.thumbnailTint))
            .accessibilityLabel(Text(L10n.resource("privacy.hidden")))
    }
}

/// The Privacy mode indicator (UX-DR98): an eye-slash in `ink-3`, left of the settings gear in the expanded
/// tab row and in the peek band. Never on the closed notch. VoiceOver: "Privacy mode on".
public struct PrivacyIndicator: View {
    @Environment(\.vigieTheme) private var theme

    public init() {}

    public var body: some View {
        Image(systemName: "eye.slash")
            .font(.system(size: ExpandedMetrics.gearIcon, weight: .light))
            .foregroundStyle(theme.color(.ink3))
            .frame(width: theme.gearSize, height: theme.gearSize)
            .help(Text(L10n.resource("privacy.indicator")))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(L10n.resource("privacy.indicator")))
            .accessibilityIdentifier(PrivacyIndicator.accessibilityID)
    }

    /// Lets tests find the indicator in a rendered tree.
    public static let accessibilityID = "privacy.indicator"
}

/// Reveal controls (secret fields in Settings, later Notes secrets, Story 15.4) are unavailable while Privacy
/// mode is active (UX-DR98). Focus, Dismiss, Join call and drop zones are unaffected.
public enum PrivacyReveal {
    public static func isAvailable(privacyActive: Bool) -> Bool { !privacyActive }
}

/// A view model whose user text Privacy mode hides. `redacted()` replaces every ``Sensitive`` field with its
/// mask and scrubs the strings composed from them (VoiceOver labels, tooltips).
public protocol PrivacyRedactable {
    func redacted() -> Self
}

extension PrivacyRedactable {
    /// `redacted()` while `privacyActive`, else `self`.
    public func privacy(_ privacyActive: Bool) -> Self { privacyActive ? redacted() : self }
}

enum PrivacyMetrics {
    /// The thumbnail placeholder's `ink-3` tint.
    static let thumbnailTint = 0.18
}
