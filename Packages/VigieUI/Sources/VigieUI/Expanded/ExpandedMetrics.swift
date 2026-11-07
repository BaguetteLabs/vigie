import SwiftUI

/// Fixed proportions of the expanded panel that DESIGN.md states in prose or in the mocks rather than as
/// tokens. Sizes come from `components.expanded-panel`, `components.tab-bar` and `components.settings-gear`
/// when the theme sets them; these are the fallbacks and the unnamed values (UX-DR26, UX-DR27, UX-DR80).
public enum ExpandedMetrics {
    /// `components.expanded-panel` width × height (720 × 420).
    public static let defaultSize = CGSize(width: 720, height: 420)
    /// `components.tab-bar.height`.
    static let tabBarHeight: CGFloat = 30
    /// A tab inside the bar (mock: 24px).
    static let tabHeight: CGFloat = 24
    /// Gap between tabs inside the pill (mock: 2px), and the pill's inner padding (mock: 3px).
    static let tabGap: CGFloat = 2
    static let pillInset: CGFloat = 3
    /// Tab row top margin below the band (mock: 6px).
    static let tabRowTop: CGFloat = 6
    /// Attention marker: 5px blocked-hue diamond (A) or square (C).
    public static let attentionMarker: CGFloat = 5
    /// Settings gear: 24px round (A) / 26px square (C), 14px outline gear.
    static let gearSizeA: CGFloat = 24
    static let gearSizeC: CGFloat = 26
    static let gearIcon: CGFloat = 14
    /// A wordmark letter spacing (0.5em; C uses its kicker token).
    static let wordmarkTrackingEm: CGFloat = 0.5
    /// The `status-idle` dot before `Online` (mock: a `●` at 11px).
    static let statusDot: CGFloat = 6
    /// C underline under the active tab (2px gold).
    static let activeUnderline: CGFloat = 2

    // Opacities (DESIGN "Tab bar", "Settings gear", "Elevation & Depth").
    /// A pill container: 3.5% white with a 6% hairline (dark); graphite 4.5% / 7% (light).
    static func pillFill(_ look: Look) -> Double { look == .dark ? 0.035 : 0.045 }
    static func pillHairline(_ look: Look) -> Double { look == .dark ? 0.06 : 0.07 }
    /// A raised pill (active tab, hovered gear): white 12% → 3% with a 16% platinum hairline (dark);
    /// light: white with a 10% graphite hairline.
    static let raisedTop = 0.12
    static let raisedBottom = 0.03
    static func raisedHairline(_ look: Look) -> Double { look == .dark ? 0.16 : 0.10 }
    /// Gear focus: A dark 1px platinum at 55% plus a 3px cyan halo at 14%; C ink-1 at 55%; A light solid.
    static let focusRing = 0.55
    static let focusHalo = 0.14
    static let focusHaloWidth: CGFloat = 3
    /// C hovered gear: 1px struct inner border at 30%.
    static let structBorder = 0.30
    /// Panel drop shadow (`components.expanded-panel.shadow-*`: 0 28px 60px, black 50% dark / 22% light).
    public static let shadowRadius: CGFloat = 30
    public static let shadowOffsetY: CGFloat = 28
    public static func shadowOpacity(_ look: Look) -> Double { look == .dark ? 0.5 : 0.22 }
    /// Room the window keeps around the panel for its shadow (sides and bottom; the top is the screen edge).
    public static let shadowMargin: CGFloat = 60
}

extension Theme {
    /// The expanded panel size (`components.expanded-panel` width × height).
    public var expandedPanelSize: CGSize {
        CGSize(
            width: componentLength("expanded-panel", "width") ?? ExpandedMetrics.defaultSize.width,
            height: componentLength("expanded-panel", "height") ?? ExpandedMetrics.defaultSize.height)
    }

    var tabBarHeight: CGFloat { componentLength("tab-bar", "height") ?? ExpandedMetrics.tabBarHeight }

    var gearSize: CGFloat {
        usesCornerMarks
            ? componentLength("settings-gear", "size-c") ?? ExpandedMetrics.gearSizeC
            : componentLength("settings-gear", "size-a") ?? ExpandedMetrics.gearSizeA
    }
}
