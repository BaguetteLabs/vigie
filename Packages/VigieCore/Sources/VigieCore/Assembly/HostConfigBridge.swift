import Foundation

/// Re-places or re-arbitrates the Notch Host when the config keys it reads change (Stories 2.6, 2.7): any
/// `display.*`, `virtual_notch.*`, `closed.max_side_width` or `general.hide_in_fullscreen` change calls
/// `reloadDisplayConfiguration()`; `closed.slots` calls `rearbitrate()`.
@MainActor
public final class HostConfigBridge {
    /// What a set of changed keys asks of the host.
    public struct Actions: Equatable, Sendable {
        public var reloadDisplays = false
        public var rearbitrate = false
    }

    private let changes: AsyncStream<Set<ConfigKeyPath>>
    private let reloadDisplays: @MainActor () -> Void
    private let rearbitrate: @MainActor () -> Void
    private var task: Task<Void, Never>?

    public init(
        changes: AsyncStream<Set<ConfigKeyPath>>,
        reloadDisplays: @escaping @MainActor () -> Void,
        rearbitrate: @escaping @MainActor () -> Void
    ) {
        self.changes = changes
        self.reloadDisplays = reloadDisplays
        self.rearbitrate = rearbitrate
    }

    /// Follows the host's settings in `store`.
    public convenience init(store: ConfigStore, host: NotchHost) {
        self.init(
            changes: store.changes,
            reloadDisplays: { [weak host] in host?.reloadDisplayConfiguration() },
            rearbitrate: { [weak host] in host?.rearbitrate() })
    }

    public func start() {
        task?.cancel()
        let changes = changes
        task = Task { @MainActor [weak self] in
            for await keys in changes {
                self?.apply(Self.actions(for: keys))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    private func apply(_ actions: Actions) {
        if actions.reloadDisplays { reloadDisplays() }
        if actions.rearbitrate { rearbitrate() }
    }

    static let displayKeys: Set<ConfigKeyPath> = [
        CoreSettings.path("closed", "max_side_width"), CoreSettings.path("closed", "notch_overlap"),
        CoreSettings.path("closed", "notch_side_inset"), CoreSettings.path("general", "hide_in_fullscreen"),
    ]

    /// The host work a set of changed keys calls for.
    public static func actions(for keys: Set<ConfigKeyPath>) -> Actions {
        var actions = Actions()
        for key in keys {
            let table = key.segments.first
            if table == "display" || table == "virtual_notch" || displayKeys.contains(key) {
                actions.reloadDisplays = true
            }
            if key == CoreSettings.path("closed", "slots") { actions.rearbitrate = true }
        }
        return actions
    }
}

/// Remembers that the one-time display prompt (Story 2.7, A60) was answered or dismissed. `CoreSettings` has no
/// key for it (the prompt is not a setting), so it lives in the app's `UserDefaults`, which are per machine like
/// `local.toml`.
public struct DisplayPromptRecord: Sendable {
    public static let key = "VigieDisplayPromptDone"
    private let suiteName: String?

    /// - Parameter suiteName: nil for the standard defaults (tests pass their own suite).
    public init(suiteName: String? = nil) { self.suiteName = suiteName }

    private var defaults: UserDefaults { suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    public var isPending: Bool { !defaults.bool(forKey: Self.key) }

    public func markDone() { defaults.set(true, forKey: Self.key) }
}

extension DisplayPromptAnswer {
    /// Writes the answer: `[display] display` in `local.toml` for a choice, and the prompt as done either way.
    @MainActor
    public func apply(store: ConfigStore, record: DisplayPromptRecord) async throws(ConfigError) {
        record.markDone()
        if case .choose(let selection) = self {
            try await store.set(CoreSettings.path("display", "display"), to: .string(selection.rawValue))
        }
    }
}
