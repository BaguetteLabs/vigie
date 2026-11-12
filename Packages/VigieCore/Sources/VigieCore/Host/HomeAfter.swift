import Foundation

/// `[general] home_after` (Story 11.4, SPEC §11): how long after a close a re-open keeps the last tab.
///
/// A duration such as `"2m"` (re-opening sooner keeps the tab, later lands on Home), `"0s"` (always Home, the
/// Story 11.1 behavior) or `"never"` (always keep the last tab).
public enum HomeAfter: Sendable, Equatable {
    /// Always keep the last tab.
    case never
    /// Land on Home when the view was closed at least this long ago.
    case after(Duration)

    /// The config default, `"2m"`.
    public static let `default` = HomeAfter.after(.seconds(120))

    /// The raw value that means "never return to Home".
    public static let neverValue = "never"

    /// The Settings › General choices, in order: Immediately, 30 s, 2 min, 10 min, Never.
    public static let choices = ["0s", "30s", "2m", "10m", neverValue]

    /// Parses a config value: `"never"` or a duration (``ConfigDuration``); nil for anything else.
    public init?(configValue: String) {
        if configValue == Self.neverValue {
            self = .never
        } else if let duration = ConfigDuration.parse(configValue) {
            self = .after(duration)
        } else {
            return nil
        }
    }

    /// The current `[general] home_after` of `store`, or the default.
    @MainActor
    public init(configStore: ConfigStore) {
        let value = configStore.value(CoreSettings.path("general", "home_after"), as: String.self)
        self = value.flatMap(HomeAfter.init(configValue:)) ?? .default
    }

    /// Whether a re-open `elapsed` after the close lands on Home.
    public func returnsHome(after elapsed: Duration) -> Bool {
        switch self {
        case .never: false
        case .after(let limit): elapsed >= limit
        }
    }
}
