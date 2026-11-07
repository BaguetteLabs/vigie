import Foundation
import ModuleKit
import Observation
import Wire
import os

/// The only reader (and, from Story 2.13, writer) of `config.toml` and `local.toml` (AD-8).
///
/// Resolution per known key: `.local` keys come from `local.toml`, `.synced` keys from `config.toml`, else the
/// declared default. Both containing folders are watched (AD-12); edits apply live and observers hear only
/// about keys whose resolved value changed. A file with a TOML parse error keeps its last valid content.
@MainActor @Observable
public final class ConfigStore {
    /// Current problems in both files, sorted by file then key. Recomputed on every load.
    public private(set) var problems: [ConfigProblem] = []
    /// Bumped whenever a resolved value changes; `value(_:as:)` reads it so SwiftUI views re-render.
    public private(set) var revision = 0

    public nonisolated let environment: AppEnvironment
    /// `<config folder>/config.toml` (synced).
    public nonisolated let configURL: URL
    /// `AppEnvironment.localConfigURL` (never synced).
    public nonisolated let localURL: URL

    nonisolated let shared: ConfigSharedState

    private struct FileState {
        var data: Data?
        var document = ConfigDocument.empty
        var problem: ConfigProblem?
    }

    @ObservationIgnored private let watcher: any DirectoryWatching
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let logger: Logger
    @ObservationIgnored private var configFile = FileState()
    @ObservationIgnored private var localFile = FileState()
    @ObservationIgnored private var loggedUnknownKeys: Set<String> = []
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false

    public static let configFileName = "config.toml"

    /// - Parameters:
    ///   - environment: paths (AD-17); injected by the App.
    ///   - manifests: modules whose settings are known from the start (more via `register(manifest:)`).
    ///   - watcher: directory watcher; tests pass a `ManualDirectoryWatcher`.
    ///   - debounce: events within this window are coalesced into one reload.
    public init(
        environment: AppEnvironment,
        manifests: [ModuleManifest] = [],
        watcher: any DirectoryWatching = DispatchDirectoryWatcher(),
        debounce: Duration = .milliseconds(100)
    ) {
        self.environment = environment
        configURL = environment.configFolderURL.appendingPathComponent(Self.configFileName)
        localURL = environment.localConfigURL
        var schema = ConfigSchema()
        for manifest in manifests { schema.register(manifest) }
        shared = ConfigSharedState(schema: schema)
        self.watcher = watcher
        self.debounce = debounce
        logger = Logger(subsystem: environment.bundleID, category: "config")
        recompute()
    }

    // MARK: - Schema

    public var schema: ConfigSchema { shared.read { $0.schema } }

    /// Makes a module's `enabled` key and settings known. Idempotent; re-resolves the loaded files.
    public func register(manifest: ModuleManifest) {
        let added = shared.update { $0.schema.register(manifest) }
        if added { recompute() }
    }

    // MARK: - Lifecycle

    /// Creates missing files (`config.toml` with the commented SPEC §11 defaults, an empty `local.toml`),
    /// loads both and starts watching their folders.
    public func start() async {
        guard !isStarted else { return }
        isStarted = true
        let configURL = configURL
        let localURL = localURL
        let defaultText = Self.defaultConfigText
        let created = await Task.detached {
            Self.createMissingFiles(configURL: configURL, localURL: localURL, defaultText: defaultText)
        }.value
        for message in created { logger.info("\(message, privacy: .public)") }
        await reload()

        let configFolder = configURL.deletingLastPathComponent().standardizedFileURL
        let localFolder = localURL.deletingLastPathComponent().standardizedFileURL
        let onChange: @MainActor () -> Void = { [weak self] in self?.scheduleReload() }
        if configFolder.path == localFolder.path {
            watcher.watch(
                configFolder, files: [configURL.lastPathComponent, localURL.lastPathComponent], handler: onChange)
        } else {
            watcher.watch(configFolder, files: [configURL.lastPathComponent], handler: onChange)
            watcher.watch(localFolder, files: [localURL.lastPathComponent], handler: onChange)
        }
    }

    /// Stops watching and ends every observer stream.
    public func stop() {
        guard isStarted else { return }
        isStarted = false
        watcher.stopAll()
        debounceTask?.cancel()
        debounceTask = nil
        shared.finishAll()
    }

    /// Re-reads both files now (also `vigie reload`). Unchanged files are not re-parsed.
    public func reload() async {
        let previous = reloadTask
        let task = Task {
            await previous?.value
            await self.performReload()
        }
        reloadTask = task
        await task.value
    }

    /// Waits for a reload scheduled by a watcher event (tests).
    func waitForScheduledReload() async {
        await debounceTask?.value
    }

    private func scheduleReload() {
        guard debounceTask == nil else { return }
        let debounce = debounce
        debounceTask = Task {
            try? await Task.sleep(for: debounce)
            self.debounceTask = nil
            guard self.isStarted else { return }
            await self.reload()
        }
    }

    // MARK: - Reading

    /// The resolved value of a known key as `T`, or nil when the key is unknown, has no value, or is of
    /// another type. Durations read as `Duration`, lists as `[String]`, paths as `String` or `URL`.
    public func value<T: SettingValue>(_ key: ConfigKeyPath, as type: T.Type) -> T? {
        _ = revision
        return shared.value(at: key)?.typed(as: type)
    }

    /// The resolved value of a known key, untyped.
    public func resolvedValue(_ key: ConfigKeyPath) -> ConfigResolvedValue? {
        _ = revision
        return shared.value(at: key)
    }

    /// `modules."<id>".enabled` from `config.toml`, or nil when absent (or invalid).
    public func isModuleEnabled(_ id: ModuleID) -> Bool? {
        shared.read { $0.enabled[id] }
    }

    /// Yields each time `key`'s resolved value changes.
    public func observe(_ key: ConfigKeyPath) -> AsyncStream<Void> {
        shared.observe(key).stream
    }

    /// Each element is the set of keys whose resolved value changed in one load. One stream per access.
    public var changes: AsyncStream<Set<ConfigKeyPath>> {
        shared.subscribeChanges()
    }

    // MARK: - Default file

    /// The commented SPEC §11 default written to a fresh config folder.
    public nonisolated static var defaultConfigText: String? {
        let url =
            Bundle.module.url(forResource: "default-config", withExtension: "toml", subdirectory: "Config")
            ?? Bundle.module.url(forResource: "default-config", withExtension: "toml")
        return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    nonisolated static let localHeader = """
        # Vigie machine-specific settings (never synced). Same tables as config.toml, for the keys it marks "local".

        """

    private nonisolated static func createMissingFiles(configURL: URL, localURL: URL, defaultText: String?)
        -> [String]
    {
        var messages: [String] = []
        let fm = FileManager.default
        func create(_ url: URL, _ text: String) {
            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(text.utf8).write(to: url, options: .atomic)
                messages.append("Created \(url.lastPathComponent)")
            } catch {
                messages.append("Could not create \(url.lastPathComponent): \(error)")
            }
        }
        if !fm.fileExists(atPath: configURL.path) {
            if let defaultText {
                create(configURL, defaultText)
            } else {
                messages.append("Default config resource missing; \(configURL.lastPathComponent) not created")
            }
        }
        if !fm.fileExists(atPath: localURL.path) {
            create(localURL, localHeader)
        }
        return messages
    }

    // MARK: - Loading

    private func performReload() async {
        async let configRead = ConfigFileReader.read(configURL)
        async let localRead = ConfigFileReader.read(localURL)
        let (configResult, localResult) = await (configRead, localRead)
        let configChanged = ingest(configResult, into: &configFile, url: configURL)
        let localChanged = ingest(localResult, into: &localFile, url: localURL)
        if configChanged || localChanged { recompute() }
    }

    /// Applies one read to a file's state; returns whether anything changed.
    private func ingest(_ read: ConfigFileRead, into state: inout FileState, url: URL) -> Bool {
        let name = url.lastPathComponent
        switch read {
        case .data(let data):
            guard data != state.data else { return false }
            state.data = data
            guard let text = String(data: data, encoding: .utf8) else {
                state.problem = ConfigProblem(
                    kind: .invalidFile(line: nil), path: url, key: nil, message: "\(name) is not valid UTF-8")
                logger.error("\(name, privacy: .public) is not valid UTF-8; keeping the last valid config")
                return true
            }
            do {
                state.document = try ConfigDocument.parse(text)
                state.problem = nil
            } catch {
                let line = error.line.map { " at line \($0)" } ?? ""
                state.problem = ConfigProblem(
                    kind: .invalidFile(line: error.line), path: url, key: nil,
                    message: "\(name): TOML parse error\(line): \(error.message)")
                logger.error(
                    "\(name, privacy: .public) has a TOML error\(line, privacy: .public): \(error.message, privacy: .public); keeping the last valid config"
                )
            }
            return true
        case .missing:
            if state.data != nil {
                logger.notice("\(name, privacy: .public) is missing; keeping the last values")
            }
            return false
        case .pending:
            logger.info("\(name, privacy: .public) is downloading from iCloud; keeping the last values")
            return false
        case .failed(let reason):
            state.data = nil
            state.problem = ConfigProblem(
                kind: .invalidFile(line: nil), path: url, key: nil, message: "\(name) is unreadable: \(reason)")
            logger.error("\(name, privacy: .public) is unreadable: \(reason, privacy: .public)")
            return true
        }
    }

    /// Re-resolves every key from the current documents, publishes problems and notifies observers of
    /// changed values. Keys that were not known before (just registered) are not reported as changed.
    private func recompute() {
        let schema = shared.read { $0.schema }
        let resolution = ConfigResolver.resolve(
            schema: schema, config: configFile.document, local: localFile.document,
            configURL: configURL, localURL: localURL)
        let (oldValues, oldEnabled) = shared.update { snapshot in
            defer {
                snapshot.values = resolution.values
                snapshot.enabled = resolution.enabled
            }
            return (snapshot.values, snapshot.enabled)
        }
        var changed = Set<ConfigKeyPath>()
        for (path, value) in resolution.values {
            if let old = oldValues[path], old != value { changed.insert(path) }
        }
        let enablement = Set(oldEnabled.keys).union(resolution.enabled.keys)
            .filter { oldEnabled[$0] != resolution.enabled[$0] }
            .sorted()

        let newProblems = [configFile.problem, localFile.problem].compactMap { $0 } + resolution.problems
        let previousIDs = Set(problems.map(\.id))
        for problem in newProblems where !previousIDs.contains(problem.id) {
            switch problem.kind {
            case .unknownKey:
                if loggedUnknownKeys.insert(problem.id).inserted {
                    logger.info(
                        "\(problem.message, privacy: .public) (\(problem.path.lastPathComponent, privacy: .public))")
                }
            case .invalidValue, .wrongFile:
                logger.error(
                    "\(problem.message, privacy: .public) (\(problem.path.lastPathComponent, privacy: .public))")
            case .invalidFile:
                break  // logged when read
            }
        }
        if newProblems != problems { problems = newProblems }
        if !changed.isEmpty || !enablement.isEmpty { revision += 1 }
        shared.notify(changed: changed, enablement: enablement)
    }
}

/// The outcome of reading one config file off the main actor.
enum ConfigFileRead: Sendable {
    case data(Data)
    case missing
    /// An iCloud item that is not downloaded yet; a download was requested (AD-12).
    case pending
    case failed(String)
}

enum ConfigFileReader {
    /// Reads `url` off the main actor through `NSFileCoordinator`, after checking its iCloud status (AD-12).
    static func read(_ url: URL) async -> ConfigFileRead {
        await Task.detached { readNow(url) }.value
    }

    static func readNow(_ url: URL) -> ConfigFileRead {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return .missing }
        if let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
            values.isUbiquitousItem == true,
            let status = values.ubiquitousItemDownloadingStatus, status != .current
        {
            try? fm.startDownloadingUbiquitousItem(at: url)
            return .pending
        }
        var coordinationError: NSError?
        var result = ConfigFileRead.failed("coordination failed")
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            do {
                result = .data(try Data(contentsOf: readURL))
            } catch {
                result = fm.fileExists(atPath: readURL.path) ? .failed(error.localizedDescription) : .missing
            }
        }
        if let coordinationError { return .failed(coordinationError.localizedDescription) }
        return result
    }
}
