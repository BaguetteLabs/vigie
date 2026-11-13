import Foundation
import Synchronization
import Wire

/// The config folder in effect, readable from any isolation domain (Story 16.1). ConfigStore owns it and is the
/// only one that moves it (AD-12); services derived from the folder (the script folder of `context.scriptFolder`)
/// read it on demand and follow ``changes()``.
public final class ConfigFolderLocation: Sendable {
    private struct State {
        var folder: URL
        var observers: [UUID: AsyncStream<URL>.Continuation] = [:]
    }

    private let state: Mutex<State>

    public init(folder: URL) {
        state = Mutex(State(folder: folder))
    }

    /// The config folder now.
    public var folder: URL { state.withLock { $0.folder } }

    /// `<config folder>/modules/` now (AD-18).
    public var scriptModulesFolderURL: URL { AppEnvironment.scriptModulesFolderURL(in: folder) }

    /// `<config folder>/config.toml` now.
    public var configFileURL: URL { folder.appendingPathComponent(AppEnvironment.configFileName) }

    /// Yields the new folder after each relocation. One stream per call; it ends when the caller stops iterating.
    public func changes() -> AsyncStream<URL> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: URL.self, bufferingPolicy: .bufferingNewest(1))
        state.withLock { $0.observers[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            _ = self?.state.withLock { $0.observers.removeValue(forKey: id) }
        }
        return stream
    }

    /// Moves the location (ConfigStore only) and tells every observer.
    func set(_ folder: URL) {
        let observers = state.withLock { state -> [AsyncStream<URL>.Continuation] in
            state.folder = folder
            return Array(state.observers.values)
        }
        for observer in observers { observer.yield(folder) }
    }
}
