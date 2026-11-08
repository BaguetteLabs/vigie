import Foundation

/// The AD-13 kind-to-sound table: which `[sounds]` key an alert kind plays (Story 10.1, FR98).
///
/// Notifier is the only reader of `[sounds]`. Kinds missing here (`shelf.expiring`, `setup.problem`, pace) never
/// play a sound, whatever their rule's outputs say. The `time.*` and `calendar.reminder` keys default to `"off"`
/// (SPEC §11); Settings › Sounds lists `timer_end` since Story 20.2, the other two join with 20.4 and 13.4.
public enum SoundTable {
    /// Alert kind → `[sounds]` key.
    public static let keys: [String: String] = [
        "session.blocked": "blocked",
        "session.failed": "failed",
        "session.done": "done",
        "usage.quota_warning": "quota_warning",
        "time.timer_end": "timer_end",
        "time.break_reminder": "break_reminder",
        "calendar.reminder": "calendar_reminder",
    ]

    /// Every sound key, in Settings order.
    public static let allSoundKeys = [
        "blocked", "failed", "done", "quota_warning", "timer_end", "break_reminder", "calendar_reminder",
    ]

    /// The keys Settings › Sounds lists today (Story 10.2; `timer_end` Story 20.2); the other two join with their
    /// stories.
    public static let settingsKeys = ["blocked", "failed", "done", "quota_warning", "timer_end"]

    /// The `[sounds]` key `kind` plays, or nil when the kind has no sound.
    public static func key(for kind: String) -> String? { keys[kind] }

    /// The built-in sound a key falls back to when it is switched on without a remembered choice.
    public static func naturalBuiltIn(for key: String) -> String {
        switch key {
        case "blocked": "blocked"
        case "failed": "failed"
        case "done", "timer_end": "done"
        default: "warn"
        }
    }
}
