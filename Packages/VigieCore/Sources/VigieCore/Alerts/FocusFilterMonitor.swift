import Foundation
import ModuleKit
import os

/// Reads the state of Vigie's Focus filter for the Focus that is on now (`SetFocusFilterIntent.current` in the
/// App). The App implements it next to the intent type; tests pass a fake.
public protocol FocusFilterSource: Sendable {
    /// The filter's `silence` value for the current Focus, or nil when the current Focus has no Vigie filter
    /// (or no Focus is on: `SetFocusFilterIntentError.notFound`).
    func currentSilence() async throws -> Bool?
}

/// A source that never finds a filter (tests, and builds without the intent).
public struct NoFocusFilterSource: FocusFilterSource {
    public init() {}
    public func currentSilence() async throws -> Bool? { nil }
}

/// Whether a Focus mode the user chose should silence Vigie (FR17, Story 3.10; spike
/// `docs/decisions/spike-focus-detection.md`).
///
/// Two inputs, either of which turns it on:
/// - **Focus filter** (primary). The user adds "Silence Vigie" under System Settings › Focus › *mode* › Focus
///   Filters. macOS runs the intent's `perform()` when that Focus turns on (with the user's value) and again
///   with the default (`false`) when it turns off; the App forwards it to ``filterDidRun(silence:)``. At launch
///   ``start()`` reads the current filter, so a Focus that started while Vigie was not running is seen.
/// - **Shortcuts bridge** (fallback). `vigie event app.focus '{"active":true}'` from a "Focus turns on / off"
///   automation, handled by ``receiveShortcut(_:)``. An "on" with no later message for ``shortcutCap`` (12 h)
///   counts as off, so a missed "off" never silences Vigie for good.
///
/// No permission, entitlement or private API: nothing is read from disk.
@MainActor
public final class FocusFilterMonitor: FocusModeMonitor {
    public private(set) var isActive = false
    public let changes: AsyncStream<Bool>
    /// True once the Focus filter has reported in this process (its `perform()` ran, or `current` found it at
    /// launch). Settings' setup row reads the persisted record (`FocusFilterSetup`).
    public private(set) var filterHasRun = false
    /// Called each time the filter reports (after the state is updated).
    public var onFilterRun: (@MainActor () -> Void)?

    public static let defaultShortcutCap: Duration = .seconds(12 * 3600)

    public let shortcutCap: Duration
    private let continuation: AsyncStream<Bool>.Continuation
    private let source: any FocusFilterSource
    private let clock: any Clock<Duration>
    private let now: @Sendable () -> Date
    private let log: Logger
    private var filterSilence = false
    private var shortcutActive = false
    /// `sentAt` of the last applied `app.focus` message: an older one (spool replay) is ignored.
    private var lastShortcutSentAt: Date?
    /// Bumped by every filter report, so a launch-time `current` read that finishes after a `perform()` loses.
    private var filterGeneration = 0
    private let capTimer = TaskLifetime()

    /// - Parameters:
    ///   - source: the filter's `current` value (the App's intent).
    ///   - shortcutCap: how long an `app.focus` "on" holds without a later message.
    ///   - clock: drives the cap timer.
    ///   - now: wall clock, compared with a message's `sentAt` (a spooled "on" may already be old).
    public init(
        source: any FocusFilterSource,
        shortcutCap: Duration = FocusFilterMonitor.defaultShortcutCap,
        clock: any Clock<Duration> = ContinuousClock(),
        now: @escaping @Sendable () -> Date = { Date() },
        log: Logger = Logger(subsystem: "fr.baguettelabs.vigie", category: "notifier")
    ) {
        self.source = source
        self.shortcutCap = shortcutCap
        self.clock = clock
        self.now = now
        self.log = log
        (changes, continuation) = AsyncStream.makeStream(of: Bool.self)
    }

    deinit { capTimer.cancel() }

    /// Reads the filter of the Focus that is on now. `nil` (`notFound`), `silence == false` or an error read
    /// as "off"; a `perform()` that arrives meanwhile wins.
    public func start() async {
        let generation = filterGeneration
        let silence: Bool?
        do {
            silence = try await source.currentSilence()
        } catch {
            log.error("Focus filter unreadable at launch: \(String(describing: error), privacy: .public)")
            return
        }
        guard generation == filterGeneration else { return }
        guard let silence else {
            log.info("No Focus filter for the current Focus at launch")
            return
        }
        log.info("Focus filter at launch: silence \(silence, privacy: .public)")
        // `current` found the filter: it is set up, whatever its value.
        recordFilterRun(silence: silence)
    }

    /// The Focus filter intent ran (`perform()`): `silence` is the user's value for the Focus that turned on,
    /// or the default (`false`) when it turned off.
    public func filterDidRun(silence: Bool) {
        log.info("Focus filter ran: silence \(silence, privacy: .public)")
        recordFilterRun(silence: silence)
    }

    private func recordFilterRun(silence: Bool) {
        filterGeneration += 1
        filterSilence = silence
        filterHasRun = true
        update()
        onFilterRun?()
    }

    /// An `app.focus` message (`{"active": true|false}`). Malformed payloads and messages older than the last
    /// applied one are ignored.
    public func receiveShortcut(_ message: EventMessage) {
        guard let active = Self.parseShortcut(message.payload) else {
            log.error("app.focus ignored: payload is not {\"active\": true|false}")
            return
        }
        if let last = lastShortcutSentAt, message.sentAt < last {
            log.info("app.focus ignored: older than the last message")
            return
        }
        lastShortcutSentAt = message.sentAt
        capTimer.cancel()
        guard active else {
            shortcutActive = false
            update()
            return
        }
        let age = Duration.seconds(max(0, now().timeIntervalSince(message.sentAt)))
        let remaining = shortcutCap - age
        guard remaining > .zero else {
            log.info("app.focus \"on\" is older than the cap; treated as off")
            shortcutActive = false
            update()
            return
        }
        shortcutActive = true
        update()
        let clock = clock
        capTimer.set(
            Task { @MainActor [weak self] in
                do {
                    try await clock.sleep(for: remaining)
                } catch {
                    return
                }
                guard let self, self.shortcutActive else { return }
                self.log.info("app.focus \"on\" expired after the cap; treated as off")
                self.shortcutActive = false
                self.update()
            })
    }

    /// `{"active": Bool}`; nil otherwise.
    nonisolated static func parseShortcut(_ payload: Data) -> Bool? {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
            let value = object["active"] as? NSNumber,
            CFGetTypeID(value) == CFBooleanGetTypeID()
        else { return nil }
        return value.boolValue
    }

    /// Stops the cap timer and finishes `changes`.
    public func stop() {
        capTimer.cancel()
        continuation.finish()
    }

    private func update() {
        let active = filterSilence || shortcutActive
        guard active != isActive else { return }
        isActive = active
        log.info("Focus mode \(active ? "on" : "off", privacy: .public)")
        continuation.yield(active)
    }
}

/// The "filter has run once" record (Story 3.10): `[notify] focus_filter_ran` in `local.toml`, written through
/// ConfigStore. Until it is true, Settings › Alerts shows the Focus row in its needs-setup state.
@MainActor
public final class FocusFilterSetup {
    public static let path = CoreSettings.path("notify", "focus_filter_ran")

    private let store: ConfigStore
    private let monitor: FocusFilterMonitor
    private let log: Logger

    public init(
        store: ConfigStore, monitor: FocusFilterMonitor,
        log: Logger = Logger(subsystem: "fr.baguettelabs.vigie", category: "notifier")
    ) {
        self.store = store
        self.monitor = monitor
        self.log = log
    }

    /// Whether the filter has ever run on this Mac.
    public static func isSetUp(_ store: ConfigStore) -> Bool {
        store.value(path, as: Bool.self) ?? false
    }

    /// Records future filter runs, and one that happened before the store existed.
    public func start() {
        monitor.onFilterRun = { [weak self] in self?.record() }
        if monitor.filterHasRun { record() }
    }

    public func stop() {
        monitor.onFilterRun = nil
    }

    private func record() {
        guard !Self.isSetUp(store) else { return }
        let store = store
        let log = log
        Task { @MainActor in
            do {
                try await store.set(Self.path, to: .bool(true))
            } catch {
                log.error("Could not record the Focus filter setup: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
