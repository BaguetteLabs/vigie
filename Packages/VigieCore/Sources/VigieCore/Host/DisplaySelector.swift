import CoreGraphics

/// `[display] display` (SPEC §5.4, FR19; local): which display(s) show Vigie.
public enum DisplaySelection: Sendable, Equatable {
    /// The default: the notched display if there is one, otherwise the main display (in clamshell mode, the
    /// built-in display is gone, so the main external display).
    case notched
    /// The main display.
    case main
    /// Every display; each shows the same state (FR23).
    case all
    /// The display with this name (`NSScreen.localizedName`, case-insensitive) or display id; the default rule
    /// when it is not connected.
    case named(String)

    /// Parses a config value; empty means the default.
    public init(rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespaces)
        switch value.lowercased() {
        case "", "notched": self = .notched
        case "main": self = .main
        case "all": self = .all
        default: self = .named(value)
        }
    }

    /// The value written to `local.toml`.
    public var rawValue: String {
        switch self {
        case .notched: "notched"
        case .main: "main"
        case .all: "all"
        case .named(let name): name
        }
    }
}

extension DisplaySelection {
    /// Reads `[display] display` from the config store (the App's `displaySelection` closure).
    @MainActor
    public init(configStore: ConfigStore) {
        self.init(rawValue: configStore.value(CoreSettings.path("display", "display"), as: String.self) ?? "")
    }
}

/// Picks the displays that show an island (SPEC §5.4, FR19, FR22). Pure.
public enum DisplaySelector {
    /// The displays that show Vigie for `selection`, main Vigie display first (peeks fall back to it, FR23).
    /// Empty only when no display is connected.
    public static func select(_ displays: [DisplayInfo], selection: DisplaySelection) -> [DisplayInfo] {
        guard let preferred = defaultDisplay(displays) else { return [] }
        switch selection {
        case .notched:
            return [preferred]
        case .main:
            return [displays.first(where: \.isMain) ?? preferred]
        case .all:
            return [preferred] + displays.filter { $0.id != preferred.id }
        case .named(let name):
            let found = displays.filter { Self.matches($0, name) }
            return found.isEmpty ? [preferred] : found
        }
    }

    /// The default rule: the notched display if any (the built-in display with the lid open), otherwise the
    /// main display (in clamshell mode the built-in display is not connected, so this is the main external one).
    public static func defaultDisplay(_ displays: [DisplayInfo]) -> DisplayInfo? {
        displays.first(where: \.hasNotch) ?? displays.first(where: \.isMain) ?? displays.first
    }

    static func matches(_ display: DisplayInfo, _ name: String) -> Bool {
        display.name.caseInsensitiveCompare(name) == .orderedSame || String(display.id) == name
    }
}
