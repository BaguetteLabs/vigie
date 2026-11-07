import Foundation
import ModuleKit
import Synchronization

/// The resolved config and its observers, readable from any isolation domain. `ConfigStore` (main actor) is
/// the only writer; `ConfigModuleSettings` and `ConfigModuleEnablement` read it synchronously, as the
/// `ModuleSettings` and `ModuleEnablement` protocols require.
final class ConfigSharedState: Sendable {
    struct Snapshot: Sendable {
        var schema: ConfigSchema
        var values: [ConfigKeyPath: ConfigResolvedValue] = [:]
        var enabled: [ModuleID: Bool] = [:]
    }

    private struct Observers {
        var keys: [ConfigKeyPath: [UUID: AsyncStream<Void>.Continuation]] = [:]
        var changes: [UUID: AsyncStream<Set<ConfigKeyPath>>.Continuation] = [:]
        var enablement: [UUID: AsyncStream<ModuleID>.Continuation] = [:]
    }

    private let snapshot: Mutex<Snapshot>
    private let observers = Mutex(Observers())

    init(schema: ConfigSchema) {
        snapshot = Mutex(Snapshot(schema: schema))
    }

    func read<R: Sendable>(_ body: (Snapshot) -> R) -> R {
        snapshot.withLock { body($0) }
    }

    func update<R: Sendable>(_ body: (inout Snapshot) -> R) -> R {
        snapshot.withLock { body(&$0) }
    }

    func value(at path: ConfigKeyPath) -> ConfigResolvedValue? {
        snapshot.withLock { $0.values[path] }
    }

    /// A stream that yields when `path`'s resolved value changes, and a closure that ends it.
    func observe(_ path: ConfigKeyPath) -> (stream: AsyncStream<Void>, cancel: @Sendable () -> Void) {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        observers.withLock { $0.keys[path, default: [:]][id] = continuation }
        continuation.onTermination = { [weak self] _ in self?.removeKeyObserver(path, id) }
        return (stream, { continuation.finish() })
    }

    func subscribeChanges() -> AsyncStream<Set<ConfigKeyPath>> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: Set<ConfigKeyPath>.self)
        observers.withLock { $0.changes[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            _ = self?.observers.withLock { $0.changes.removeValue(forKey: id) }
        }
        return stream
    }

    func subscribeEnablement() -> AsyncStream<ModuleID> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: ModuleID.self)
        observers.withLock { $0.enablement[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            _ = self?.observers.withLock { $0.enablement.removeValue(forKey: id) }
        }
        return stream
    }

    func notify(changed: Set<ConfigKeyPath>, enablement: [ModuleID]) {
        guard !changed.isEmpty || !enablement.isEmpty else { return }
        let (keyContinuations, changeContinuations, enablementContinuations) = observers.withLock { observers in
            (
                changed.flatMap { observers.keys[$0]?.values.map { $0 } ?? [] },
                Array(observers.changes.values),
                Array(observers.enablement.values)
            )
        }
        for continuation in keyContinuations { continuation.yield() }
        if !changed.isEmpty {
            for continuation in changeContinuations { continuation.yield(changed) }
        }
        for id in enablement {
            for continuation in enablementContinuations { continuation.yield(id) }
        }
    }

    /// Ends every stream (`ConfigStore.stop()`).
    func finishAll() {
        let (keys, changes, enablement) = observers.withLock { observers in
            defer { observers = Observers() }
            return (
                observers.keys.values.flatMap { Array($0.values) }, Array(observers.changes.values),
                Array(observers.enablement.values)
            )
        }
        for continuation in keys { continuation.finish() }
        for continuation in changes { continuation.finish() }
        for continuation in enablement { continuation.finish() }
    }

    var keyObserverCount: Int { observers.withLock { $0.keys.values.reduce(0) { $0 + $1.count } } }

    private func removeKeyObserver(_ path: ConfigKeyPath, _ id: UUID) {
        observers.withLock { observers in
            observers.keys[path]?.removeValue(forKey: id)
            if observers.keys[path]?.isEmpty == true { observers.keys.removeValue(forKey: path) }
        }
    }
}
