import Foundation
import ModuleKit

@testable import Integrations

/// `context.scriptFolder.settings` in memory (Story 12.6): this Mac's enabled flags by relative path (standing for
/// `local.toml`) and the scripts' configured values by id and key (standing for `config.toml`), with every write
/// recorded and `edit` standing for an outside edit. The config files themselves are asserted by VigieCore's
/// `ScriptSettingsConfigTests`.
final class MemoryScriptSettings: ScriptSettingsStore, @unchecked Sendable {
    struct Key: Hashable {
        let id: ModuleID
        let key: String
    }

    private let lock = NSLock()
    private var enabledFlags: [String: Bool]
    private var stored: [Key: any SettingValue] = [:]
    private var known: [ModuleID: [SettingDescriptor]] = [:]
    private var registrations = 0
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    init(enabled: [String: Bool] = [:]) { enabledFlags = enabled }

    var flags: [String: Bool] { lock.withLock { enabledFlags } }
    var registered: [ModuleID: [String]] { lock.withLock { known.mapValues { $0.map(\.key) } } }
    var registeredKinds: [ModuleID: [SettingKind]] { lock.withLock { known.mapValues { $0.map(\.kind) } } }
    var registerCount: Int { lock.withLock { registrations } }
    var values: [Key: any SettingValue] { lock.withLock { stored } }
    var subscribers: Int { lock.withLock { continuations.count } }

    @MainActor func isEnabled(_ relativePath: String) -> Bool { lock.withLock { enabledFlags[relativePath] ?? true } }

    func setEnabled(_ enabled: Bool, for relativePath: String) async throws {
        edit(enabled: enabled ? nil : false, for: relativePath)
    }

    @MainActor func register(_ id: ModuleID, settings: [SettingDescriptor]) {
        lock.withLock {
            known[id] = settings.filter { $0.kind != .secret }
            registrations += 1
        }
    }

    @MainActor func unregister(_ id: ModuleID) { lock.withLock { known[id] = nil } }

    @MainActor func value(_ id: ModuleID, key: String) -> (any SettingValue)? {
        lock.withLock { known[id]?.contains { $0.key == key } == true ? stored[Key(id: id, key: key)] : nil }
    }

    func setValue(_ value: (any SettingValue)?, id: ModuleID, key: String) async throws {
        try lock.withLock {
            guard known[id]?.contains(where: { $0.key == key }) == true else {
                throw ModuleServiceError.notAvailable
            }
            stored[Key(id: id, key: key)] = value
        }
        notify()
    }

    /// An outside edit of `local.toml` (nil removes the flag).
    func edit(enabled: Bool?, for relativePath: String) {
        lock.withLock { enabledFlags[relativePath] = enabled }
        notify()
    }

    /// An outside edit of `config.toml`.
    func edit(_ value: (any SettingValue)?, id: ModuleID, key: String) {
        lock.withLock { stored[Key(id: id, key: key)] = value }
        notify()
    }

    @MainActor func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let id = UUID()
        lock.withLock { continuations[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { _ = self?.continuations.removeValue(forKey: id) }
        }
        return stream
    }

    private func notify() {
        for continuation in lock.withLock({ Array(continuations.values) }) { continuation.yield() }
    }
}

/// Polls `condition` on the main actor until it holds or 5 s pass.
@MainActor
func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}
