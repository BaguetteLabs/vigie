import Foundation
import SwiftUI

/// One tab of the expanded view, as the Notch Host passes it: a module with an `expandedView()`, in the
/// user's `[general] tab_order` (SPEC §10, A12).
public struct ExpandedTab: Identifiable, Hashable, Sendable {
    /// The module id (`agents.sessions`).
    public let id: String
    /// Localized module name.
    public let title: String
    /// SF Symbol name from the manifest.
    public let icon: String
    /// The module is in `alert`: the tab carries the 5px attention marker (UX-DR104).
    public let needsAttention: Bool

    public init(id: String, title: String, icon: String, needsAttention: Bool = false) {
        self.id = id
        self.title = title
        self.icon = icon
        self.needsAttention = needsAttention
    }

    /// VoiceOver label: "Agents" or "Agents, needs attention" (the marker is never the only cue).
    public var accessibilityLabel: String {
        needsAttention
            ? AccessibilityLabel.item(name: title, status: L10n.string("expanded.tab.needsAttention")) : title
    }
}

/// `⌘1…9` while the expanded view is key: the nth tab, never the settings gear (UX-DR80).
public enum ExpandedShortcuts {
    /// Tabs that get a `⌘<n>` slot.
    public static let maxSlots = 9

    /// The tab for `⌘<digit>`, or nil when there is no such tab (digit outside 1…9 or beyond the last tab).
    public static func tabID(forDigit digit: Int, in tabs: [ExpandedTab]) -> String? {
        guard (1...maxSlots).contains(digit), digit <= tabs.count else { return nil }
        return tabs[digit - 1].id
    }

    /// The digit shown for a tab (1-based), or nil past the ninth.
    public static func digit(for id: String, in tabs: [ExpandedTab]) -> Int? {
        guard let index = tabs.firstIndex(where: { $0.id == id }), index < maxSlots else { return nil }
        return index + 1
    }
}

/// Keyboard focus in the tab row: the tabs in order, then the settings gear (EXPERIENCE "Settings gear").
public enum ExpandedRowFocus: Hashable, Sendable {
    case tab(String)
    case gear

    /// `←` / `→` from `current` (moving focus only; `↵` / Space activates). Stops at both ends.
    public static func moved(from current: ExpandedRowFocus?, forward: Bool, tabs: [ExpandedTab]) -> ExpandedRowFocus? {
        let order = tabs.map { ExpandedRowFocus.tab($0.id) } + [.gear]
        guard let current, let index = order.firstIndex(of: current) else {
            return forward ? order.first : order.last
        }
        let next = forward ? index + 1 : index - 1
        return order.indices.contains(next) ? order[next] : current
    }
}

/// The band status line `● Online · 14:48 · Wed 04 Nov` (DESIGN "Expanded panel").
public enum ExpandedStatusLine {
    /// The text after the dot, with the time and date formatted with `Date.FormatStyle` for `locale`; by
    /// default the user's locale (region, 12/24-hour preference) in the catalog's language, so the day and
    /// month names match the words around them.
    public static func text(at date: Date, locale: Locale? = nil, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let style = Date.FormatStyle(locale: locale ?? displayLocale, timeZone: timeZone)
        let time = date.formatted(style.hour().minute())
        let day = date.formatted(style.weekday(.abbreviated).day(.twoDigits).month(.abbreviated))
        return L10n.format("expanded.status", time, day)
    }

    /// The user's locale with the catalog's language.
    static var displayLocale: Locale {
        var components = Locale.Components(locale: .autoupdatingCurrent)
        let user = components.languageComponents
        var language = Locale.Language.Components(identifier: L10n.catalogLocale.identifier)
        language.region = language.region ?? user.region ?? Locale.autoupdatingCurrent.region
        components.languageComponents = language
        return Locale(components: components)
    }
}
