import Foundation
import Synchronization

/// `local.toml` `[executables]` as name to path, for `ExecutableResolverImpl(overrides:)` (AD-19).
///
/// Read through `ConfigStore.rawTable(at:in: .local)` (the table is local-only and unknown to the schema) and
/// re-read whenever `ConfigStore.changes` reports a path under `[executables]`. `current` is a snapshot the
/// resolver reads from its own actor on each `resolve`.
public final class ExecutableOverrides: Sendable {
    public static let tablePath = ConfigKeyPath([ExecutableResolverImpl.overridesTable])

    private let store: ConfigStore
    private let table = Mutex<[String: String]>([:])
    private let task = Mutex<Task<Void, Never>?>(nil)

    @MainActor
    public init(store: ConfigStore) {
        self.store = store
        refresh()
    }

    deinit { task.withLock { $0?.cancel() } }

    /// The current table; empty when `local.toml` has none.
    public var current: [String: String] { table.withLock { $0 } }

    /// Follows `ConfigStore.changes` until `stop()`.
    @MainActor
    public func start() {
        let changes = store.changes
        refresh()
        let follow = Task { @MainActor [weak self] in
            for await keys in changes where keys.contains(where: { $0.hasPrefix(Self.tablePath) }) {
                self?.refresh()
            }
        }
        task.withLock {
            $0?.cancel()
            $0 = follow
        }
    }

    @MainActor
    public func stop() {
        task.withLock {
            $0?.cancel()
            $0 = nil
        }
    }

    @MainActor
    public func refresh() {
        let parsed = Self.overrides(in: store.rawTable(at: Self.tablePath, in: .local) ?? [:])
        table.withLock { $0 = parsed }
    }

    /// The string values of the table; other value types and empty strings are skipped.
    public static func overrides(in entries: [String: ConfigValue]) -> [String: String] {
        var out: [String: String] = [:]
        for (name, value) in entries {
            if case .string(let path) = value, !path.isEmpty { out[name] = path }
        }
        return out
    }
}
