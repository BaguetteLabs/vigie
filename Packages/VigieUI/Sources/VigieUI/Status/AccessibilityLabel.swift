import Foundation

/// Accessibility labels with state, in one format everywhere (UX-DR63, EXPERIENCE "Accessibility Floor"):
/// "vigie / api-refactor, blocked, 2 minutes", "vigie.app, OK".
public enum AccessibilityLabel {
    /// A session: project, optional session name, lowercase status word, optional elapsed time.
    public static func session(
        project: String,
        session: String? = nil,
        status: SessionStatus,
        elapsed: Duration? = nil
    ) -> String {
        let name = session.map { L10n.format("a11y.path", project, $0) } ?? project
        var label = joined(name, L10n.string(status.accessibilityKey))
        if status != .idle, let elapsed {
            label = joined(label, duration(elapsed))
        }
        return label
    }

    /// An item with its state and an optional detail: "vigie.app, OK", "Agents, needs attention".
    public static func item(name: String, status: String, detail: String? = nil) -> String {
        let label = joined(name, status)
        return detail.map { joined(label, $0) } ?? label
    }

    /// An item on the status vocabulary: "vigie.app, OK".
    public static func item(name: String, level: StatusLevel, detail: String? = nil) -> String {
        item(name: name, status: StatusLabelFormatter().label(for: level), detail: detail)
    }

    /// A control with its keyboard shortcut: "Focus terminal, ⌥⌘↵".
    public static func control(_ label: String, shortcut: String?) -> String {
        shortcut.map { joined(label, $0) } ?? label
    }

    /// A spoken duration in whole minutes ("2 minutes", "1 hour, 5 minutes"); seconds under a minute.
    public static func duration(_ duration: Duration, locale: Locale? = nil) -> String {
        let locale = locale ?? L10n.catalogLocale
        let seconds = max(0, duration.components.seconds)
        if seconds < 60 {
            return Duration.seconds(seconds)
                .formatted(.units(allowed: [.seconds], width: .wide).locale(locale))
        }
        let minutes = Duration.seconds(seconds / 60 * 60)
        return minutes.formatted(
            .units(allowed: [.days, .hours, .minutes], width: .wide, zeroValueUnits: .hide).locale(locale))
    }

    static func joined(_ head: String, _ tail: String) -> String {
        L10n.format("a11y.join", head, tail)
    }
}
