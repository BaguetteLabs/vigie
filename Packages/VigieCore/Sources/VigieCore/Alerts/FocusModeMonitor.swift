import Foundation
import os

/// Whether macOS Do Not Disturb or any Focus mode is on (FR17, Story 3.5). Lives with the Notifier (Architecture
/// "Deferred": DND detection is inside Notifier behind a testable abstraction).
@MainActor
public protocol FocusModeMonitor: AnyObject, Sendable {
    /// The current state.
    var isActive: Bool { get }
    /// Yields the new state each time it changes. Consumed by one `AlertCenter`.
    var changes: AsyncStream<Bool> { get }
}

/// A monitor driven by hand: for tests, and for the App's debug override.
@MainActor
public final class ManualFocusModeMonitor: FocusModeMonitor {
    public private(set) var isActive: Bool
    public let changes: AsyncStream<Bool>
    private let continuation: AsyncStream<Bool>.Continuation

    public init(isActive: Bool = false) {
        self.isActive = isActive
        (changes, continuation) = AsyncStream.makeStream(of: Bool.self)
    }

    /// Sets the state; yields on `changes` only when it differs.
    public func set(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        continuation.yield(active)
    }
}

/// Reads the Focus state macOS keeps for the current user, without private API.
///
/// **Detection.** macOS (12+) records Focus assertions in `~/Library/DoNotDisturb/DB/Assertions.json`. A Focus
/// (Do Not Disturb included) is on while `data[0].storeAssertionRecords` is a non-empty array; when it ends the
/// record moves to `storeInvalidationRecords` and `storeAssertionRecords` disappears. The monitor watches the
/// file's folder (`DirectoryWatching`, so atomic replaces are seen) and also re-reads every `pollInterval`
/// (15 s) in case an event is missed.
///
/// **Limits.** The file is undocumented and its format may change between macOS releases; a file that is
/// missing, unreadable (sandbox, privacy protection) or not in the expected shape counts as "no Focus" and is
/// logged once, so Vigie never goes silent because of a parse error. Focus modes turned on by a schedule or
/// an automation may only show up here once macOS writes an assertion for them.
@MainActor
public final class SystemFocusModeMonitor: FocusModeMonitor {
    public private(set) var isActive = false
    public let changes: AsyncStream<Bool>

    private let continuation: AsyncStream<Bool>.Continuation
    private let assertionsURL: URL
    private let watcher: any DirectoryWatching
    private let log: Logger
    private var loggedUnreadable = false
    private let lifetime = TaskLifetime()

    /// - Parameters:
    ///   - assertionsURL: the `Assertions.json` file. The App passes
    ///     `SystemFocusModeMonitor.defaultAssertionsURL()`.
    ///   - watcher: watches the file's folder.
    ///   - pollInterval: fallback re-read period.
    ///   - clock: drives the fallback poll.
    public init(
        assertionsURL: URL,
        watcher: any DirectoryWatching = DispatchDirectoryWatcher(),
        pollInterval: Duration = .seconds(15),
        clock: any Clock<Duration> = ContinuousClock(),
        log: Logger = Logger(subsystem: "fr.baguettelabs.vigie", category: "notifier")
    ) {
        self.assertionsURL = assertionsURL
        self.watcher = watcher
        self.log = log
        (changes, continuation) = AsyncStream.makeStream(of: Bool.self)
        watcher.watch(
            assertionsURL.deletingLastPathComponent(), files: [assertionsURL.lastPathComponent]
        ) { [weak self] in
            guard let self else { return }
            Task { await self.refresh() }
        }
        lifetime.set(
            Task { @MainActor [weak self] in
                await self?.refresh()
                while !Task.isCancelled {
                    do {
                        try await clock.sleep(for: pollInterval)
                    } catch {
                        return
                    }
                    await self?.refresh()
                }
            })
    }

    deinit { lifetime.cancel() }

    /// The Assertions file of the current user. The one place this path is spelled out: it is a macOS system
    /// file, not a Vigie path, so it does not come from `AppEnvironment` (AD-17 covers Vigie's own paths).
    public nonisolated static func defaultAssertionsURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home.appending(path: "Library/DoNotDisturb/DB/Assertions.json")
    }

    /// Re-reads the file (off the main actor) and yields when the state changed. The state starts as "off"
    /// until the first read, which the monitor starts on creation.
    public func refresh() async {
        let url = assertionsURL
        let reading = await Task.detached(priority: .utility) { Self.read(url) }.value
        let active: Bool
        switch reading {
        case .state(let value):
            active = value
        case .unreadable, .unknownFormat:
            if !loggedUnreadable {
                loggedUnreadable = true
                log.error(
                    "Focus assertions \(reading == .unreadable ? "unreadable" : "in an unknown format", privacy: .public); treating Focus as off"
                )
            }
            active = false
        }
        guard active != isActive else { return }
        isActive = active
        log.info("Focus mode \(active ? "on" : "off", privacy: .public)")
        continuation.yield(active)
    }

    /// Stops watching and polling.
    public func stop() {
        watcher.stopAll()
        lifetime.cancel()
        continuation.finish()
    }

    enum Reading: Equatable, Sendable {
        case state(Bool)
        case unreadable
        case unknownFormat
    }

    nonisolated static func read(_ url: URL) -> Reading {
        guard let data = try? Data(contentsOf: url) else { return .unreadable }
        return parse(data).map(Reading.state) ?? .unknownFormat
    }

    /// True when `data[0].storeAssertionRecords` is a non-empty array, false when it is absent or empty, nil
    /// when the data is not an assertions document.
    public nonisolated static func parse(_ data: Data) -> Bool? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let stores = root["data"] as? [Any]
        else { return nil }
        guard let first = stores.first else { return false }
        guard let store = first as? [String: Any] else { return nil }
        guard let records = store["storeAssertionRecords"] else { return false }
        guard let list = records as? [Any] else { return nil }
        return !list.isEmpty
    }
}
