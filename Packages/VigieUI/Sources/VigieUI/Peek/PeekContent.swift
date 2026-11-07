import Foundation
import SwiftUI

/// The peek variants (DESIGN "Peek alert panel", EXPERIENCE "Peek alert panel"). The kind picks the beacon
/// glyph; the hue comes from ``PeekContent/accentRole``.
public enum PeekKind: String, Sendable, CaseIterable, Codable {
    case blocked
    case failed
    case done
    /// Several sessions interrupted by sleep: failed hue and × beacon.
    case sleepSummary
    case quotaWarning
    /// Neutral: no beacon, no status hue.
    case setupProblem
    case timerEnd
    case breakDue
    case calendarReminder
    /// Any other module alert: a plain ring beacon.
    case generic

    /// The setup-problem peek drops the beacon column (DESIGN "Setup-problem alert").
    public var showsBeacon: Bool { self != .setupProblem }

    /// The setup-problem peek is neutral: static `ink` rim and dwell line, no tint.
    public var isNeutral: Bool { self == .setupProblem }
}

/// One peek action button: its label (catalog string from the caller's package) and the shortcut glyphs
/// shown on it (`⌥⌘↵`, `⌥⌘⌫`).
public struct PeekAction: Sendable, Equatable {
    public let label: LocalizedStringResource
    public let shortcut: String

    public init(label: LocalizedStringResource, shortcut: String) {
        self.label = label
        self.shortcut = shortcut
    }

    /// `⌥⌘↵`, the primary peek shortcut (registered by the host while a peek is visible, Story 3.3).
    public static let primaryShortcut = "⌥⌘↵"
    /// `⌥⌘⌫`, the secondary (Dismiss) peek shortcut.
    public static let secondaryShortcut = "⌥⌘⌫"

    public static func == (lhs: PeekAction, rhs: PeekAction) -> Bool {
        lhs.label.key == rhs.label.key && lhs.shortcut == rhs.shortcut
    }
}

/// What a peek shows: kicker (state line, shown uppercase), title, optional detail and up to two actions.
/// Built by the Notch Host from an alert; the view draws it with the theme.
public struct PeekContent: Sendable, Equatable {
    public var kind: PeekKind
    /// The state line, e.g. `Blocked` (shown uppercase in the kicker type).
    public var kicker: String
    public var title: String
    public var body: String?
    public var primary: PeekAction?
    public var secondary: PeekAction?
    /// The alert hue: rim, beacon, kicker and dwell line (`status-blocked`, `quota-warning`, `iris-1`...).
    public var accentRole: ColorRole

    public init(
        kind: PeekKind, kicker: String, title: String, body: String? = nil, primary: PeekAction? = nil,
        secondary: PeekAction? = nil, accentRole: ColorRole
    ) {
        self.kind = kind
        self.kicker = kicker
        self.title = title
        self.body = body
        self.primary = primary
        self.secondary = secondary
        self.accentRole = accentRole
    }

    /// The text color of the kicker: the accent, except `quota-warning` which reads `quota-warning-text` in
    /// light looks, and the neutral setup peek in `ink-2`.
    public func kickerRole(look: Look) -> ColorRole {
        if kind.isNeutral { return .ink2 }
        if accentRole == .quotaWarning && look == .light { return .quotaWarningText }
        if accentRole == .gold { return .goldText }
        return accentRole
    }
}

/// The dwell timer as the view draws it: how much of the dwell is left and whether it is draining. The
/// presenter owns the clock; the view only animates the line from `remaining` to zero while running.
public struct PeekDwellState: Sendable, Equatable {
    public var total: Duration
    public var remaining: Duration
    /// False while hovered (paused) or once expired.
    public var isRunning: Bool

    public init(total: Duration, remaining: Duration, isRunning: Bool) {
        self.total = total
        self.remaining = remaining
        self.isRunning = isRunning
    }

    /// The share of the dwell left, 0...1.
    public var remainingFraction: Double {
        guard total > .zero else { return 0 }
        return min(max(Self.seconds(remaining) / Self.seconds(total), 0), 1)
    }

    public var remainingSeconds: Double { Self.seconds(remaining) }

    static func seconds(_ d: Duration) -> Double {
        Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }
}

// MARK: - Theme metrics

extension Theme {
    /// `components.peek-panel` width × height (700 × 150).
    public var peekSize: CGSize {
        CGSize(
            width: componentLength("peek-panel", "width") ?? PeekMetrics.width,
            height: componentLength("peek-panel", "height") ?? PeekMetrics.height)
    }

    /// The fixed grid columns of `components.peek-panel.columns` (`44px 1fr 176px`): leading and trailing.
    public var peekColumns: (leading: CGFloat, trailing: CGFloat) {
        let lengths = (component("peek-panel", "columns") ?? "")
            .split(separator: " ")
            .map { ThemeValue.length(String($0)) }
        guard lengths.count == 3, let leading = lengths[0], let trailing = lengths[2] else {
            return (PeekMetrics.beaconColumn, PeekMetrics.actionColumn)
        }
        return (leading, trailing)
    }

    /// The neutral drop shadow of the panel (`components.peek-panel.shadow-dark` / `shadow-light`), first
    /// layer only.
    public var peekShadow: PeekShadow {
        let key = look == .dark ? "shadow-dark" : "shadow-light"
        return component("peek-panel", key).flatMap(PeekShadow.init(css:)) ?? PeekShadow.fallback
    }
}

/// A CSS box shadow (`0 18px 40px rgba(0,0,0,.45)`) in SwiftUI terms.
public struct PeekShadow: Sendable, Equatable {
    public var y: CGFloat
    /// SwiftUI radius: half the CSS blur.
    public var radius: CGFloat
    public var opacity: Double

    public init(y: CGFloat, radius: CGFloat, opacity: Double) {
        self.y = y
        self.radius = radius
        self.opacity = opacity
    }

    /// Parses the first layer of a CSS `box-shadow`.
    init?(css: String) {
        let layer = css.components(separatedBy: "),").first ?? css
        let parts = layer.split(separator: " ", maxSplits: 3).map(String.init)
        guard parts.count == 4, let y = ThemeValue.length(parts[1]), let blur = ThemeValue.length(parts[2]) else {
            return nil
        }
        let alpha = parts[3].split(separator: ",").last.map {
            String($0).trimmingCharacters(in: CharacterSet(charactersIn: " )"))
        }
        self.init(y: y, radius: blur / 2, opacity: alpha.flatMap(Double.init) ?? PeekShadow.fallback.opacity)
    }

    /// DESIGN `shadow-dark`, used only if a theme lacks the component.
    static let fallback = PeekShadow(y: 18, radius: 20, opacity: 0.45)

    /// The room the shadow needs around the panel (sides and bottom), so the host can size its window.
    public var margin: CGFloat { radius * 2 + y }
}

/// DESIGN values for the peek panel, used only if a theme file lacks `components.peek-panel`.
enum PeekMetrics {
    static let width: CGFloat = 700
    static let height: CGFloat = 150
    static let beaconColumn: CGFloat = 44
    static let actionColumn: CGFloat = 176
    /// Beacon glyph (`components.status-glyph.size-large`).
    static let glyph: CGFloat = 26
    /// Beacon tint and inner ring opacities (A), alert-hue tint from below (A dark).
    static let beaconTint = 0.18
    static let beaconRing = 0.25
    static let bodyTint = 0.14
    /// Neutral setup rim (platinum at 28%).
    static let neutralRim = 0.28
    /// C hairline in the alert hue.
    static let structHairline = 0.32
}
