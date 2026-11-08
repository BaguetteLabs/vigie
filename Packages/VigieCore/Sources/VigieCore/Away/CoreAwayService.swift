import Foundation
import ModuleKit
import Observation
import Synchronization
import os

/// The one Present / Away signal (AD-25, Story 20.3, spike `docs/decisions/spike-away-detection.md`).
///
/// - **Away** when input idle time (``IdleTimeReading``) reaches the threshold (`[modules.time.breaks]
///   away_after`, default 90 s), or at once when the screen becomes unavailable (``ScreenAvailability``:
///   lock, screensaver, display sleep, session switch, system sleep). `since` is the last input for an idle
///   Away, or the receipt time of the screen signal.
/// - **Present** again when the screen is available and input happened within the threshold, so unlocking
///   alone is not enough: the unlock (or any) input makes it Present on the next check.
/// - **Only while subscribed** (PRD FR-4): the 5 s idle poll and the screen observers run only while at least
///   one ``AwayServiceBroadcast/changes`` stream is open; the first subscriber starts them, the last one leaving
///   stops them. Without subscribers nothing is read and ``presence`` is `.present`.
/// - Keep-awake power assertions do not reset input idle time (measured in the spike), so Away is detected
///   while one is held. No camera, no permission request.
/// - Each transition is recorded in the activity log (A80): `away.away` / `away.present`, category `presence`.
///
/// Modules get ``context`` (wrapped per module by ``TrackedAwayService``), readable from any isolation.
@MainActor @Observable
public final class CoreAwayService {
    /// The current presence (as published to ``context``).
    public private(set) var presence: Presence = .present
    /// True while the poll and the screen observers run.
    public private(set) var isMonitoring = false

    /// `context.away` for every module.
    public nonisolated let context: AwayServiceBroadcast

    /// `away_after` default (SPEC §11).
    public nonisolated static let defaultThreshold: Duration = .seconds(90)
    /// The idle poll while subscribed (spike: 5 s keeps a 90 s threshold within 5 %).
    public nonisolated static let defaultPollInterval: Duration = .seconds(5)

    @ObservationIgnored private let idle: any IdleTimeReading
    @ObservationIgnored private let observer: any LockStateObserving
    @ObservationIgnored private let threshold: @Sendable () -> Duration
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let activity: (any ActivityLog)?
    @ObservationIgnored private let logger: Logger

    @ObservationIgnored private var screen = ScreenAvailability()
    /// When the screen became unavailable, while it is.
    @ObservationIgnored private var screenSince: Date?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var signalTask: Task<Void, Never>?

    /// - Parameters:
    ///   - idle: input idle time; ``CGEventSourceIdleReader`` by default.
    ///   - observer: lock, screensaver, display, session and system sleep signals; ``SystemLockStateObserver``
    ///     by default.
    ///   - threshold: `away_after`, re-read on every check.
    ///   - pollInterval: the idle poll while subscribed.
    ///   - now: wall time.
    ///   - sleep: waits between polls (tests drive it by hand).
    ///   - activity: where transitions are recorded; nil for none.
    public init(
        idle: any IdleTimeReading = CGEventSourceIdleReader(),
        observer: (any LockStateObserving)? = nil,
        threshold: @escaping @Sendable () -> Duration = { CoreAwayService.defaultThreshold },
        pollInterval: Duration = CoreAwayService.defaultPollInterval,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        activity: (any ActivityLog)? = nil,
        logger: Logger = Logger(subsystem: "fr.baguettelabs.vigie", category: "away")
    ) {
        self.idle = idle
        self.observer = observer ?? SystemLockStateObserver(now: now)
        self.threshold = threshold
        self.pollInterval = pollInterval
        self.now = now
        self.sleep = sleep
        self.activity = activity
        self.logger = logger
        self.context = AwayServiceBroadcast()
        context.setDemandHandler { [weak self] in
            Task { @MainActor in self?.reconcile() }
        }
    }

    isolated deinit {
        pollTask?.cancel()
        signalTask?.cancel()
    }

    // MARK: Start / stop

    /// Starts or stops watching to match the number of open streams. Called (on the main actor) after each
    /// subscription change; idempotent.
    func reconcile() {
        let wanted = context.subscriberCount > 0
        if wanted, !isMonitoring {
            startMonitoring()
        } else if !wanted, isMonitoring {
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        isMonitoring = true
        logger.info("Away: watching presence")
        screen = ScreenAvailability(locked: observer.isScreenLockedNow())
        screenSince = screen.isAvailable ? nil : now()
        let signals = observer.signals
        signalTask = Task { @MainActor [weak self] in
            for await event in signals {
                guard !Task.isCancelled else { return }
                self?.apply(event)
            }
        }
        let sleep = sleep
        let interval = pollInterval
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await sleep(interval)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                self.evaluate()
            }
        }
        evaluate()
    }

    private func stopMonitoring() {
        isMonitoring = false
        pollTask?.cancel()
        pollTask = nil
        signalTask?.cancel()
        signalTask = nil
        screenSince = nil
        logger.info("Away: stopped watching presence")
        // Not watched: no claim either way. Not a transition, so not logged or published.
        presence = .present
        context.reset(.present)
    }

    // MARK: Deciding

    /// A screen signal: folded into ``ScreenAvailability``, then a check.
    func apply(_ event: ScreenSignalEvent) {
        guard isMonitoring else { return }
        let wasAvailable = screen.isAvailable
        screen.apply(event.signal)
        if wasAvailable, !screen.isAvailable {
            screenSince = event.at
        } else if screen.isAvailable {
            screenSince = nil
        }
        lastSignal = event.signal
        evaluate()
    }

    @ObservationIgnored private var lastSignal: ScreenSignal?

    /// Reads idle time and decides. Staying Away keeps the original `since`.
    func evaluate() {
        guard isMonitoring else { return }
        let date = now()
        let idleSeconds = max(0, idle.secondsSinceLastInput())
        let idleAway = idleSeconds >= threshold().awaySeconds
        let screenAway = !screen.isAvailable
        if screenAway || idleAway {
            guard !presence.isAway else { return }
            let since: Date
            let reason: String
            if screenAway, let screenSince {
                since = screenSince
                reason = lastSignal.map(\.rawValue) ?? "screenLocked"
            } else if screenAway {
                since = date
                reason = "screenLocked"
            } else {
                since = date.addingTimeInterval(-idleSeconds)
                reason = "idle"
            }
            publish(.away(since: since), reason: reason, at: date)
        } else if presence != .present {
            publish(.present, reason: "input", at: date)
        }
    }

    private func publish(_ next: Presence, reason: String, at date: Date) {
        presence = next
        context.publish(next)
        switch next {
        case .present:
            logger.info("Away: present")
            activity?.record(
                ActivityEntry(
                    at: date, category: .presence, kind: "away.present", outcome: .custom("present"),
                    detail: ["reason": reason]))
        case .away(let since):
            logger.info("Away: away (\(reason, privacy: .public))")
            activity?.record(
                ActivityEntry(
                    at: date, category: .presence, kind: "away.away", outcome: .custom("away"),
                    detail: ["reason": reason, "since": since.ISO8601Format()]))
        }
    }
}

extension Duration {
    /// Seconds as a `TimeInterval`.
    fileprivate var awaySeconds: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}

/// `context.away` (ModuleKit `AwayService`): the presence readable from any isolation and one stream per
/// subscriber. Opening the first stream and closing the last one wake ``CoreAwayService`` to start or stop
/// watching. Written only by ``CoreAwayService``.
public final class AwayServiceBroadcast: AwayService {
    private struct State {
        var presence: Presence = .present
        var continuations: [UUID: AsyncStream<Presence>.Continuation] = [:]
        var onDemand: (@Sendable () -> Void)?
    }

    private let state = Mutex(State())

    init() {}

    func setDemandHandler(_ handler: @escaping @Sendable () -> Void) {
        state.withLock { $0.onDemand = handler }
    }

    public var presence: Presence { state.withLock { $0.presence } }

    public var changes: AsyncStream<Presence> { subscription().stream }

    /// Open streams.
    public var subscriberCount: Int { state.withLock { $0.continuations.count } }

    /// A new stream and a token that ends it (``TrackedAwayService`` tracks the token).
    func subscription() -> (stream: AsyncStream<Presence>, token: RegistrationToken) {
        let (stream, continuation) = AsyncStream<Presence>.makeStream(bufferingPolicy: .bufferingNewest(8))
        let id = UUID()
        let demand = state.withLock { state -> (@Sendable () -> Void)? in
            state.continuations[id] = continuation
            return state.onDemand
        }
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            let demand = self.state.withLock { state -> (@Sendable () -> Void)? in
                state.continuations.removeValue(forKey: id) == nil ? nil : state.onDemand
            }
            demand?()
        }
        demand?()
        return (stream, RegistrationToken(id: id) { continuation.finish() })
    }

    func publish(_ presence: Presence) {
        let continuations = state.withLock { state -> [AsyncStream<Presence>.Continuation] in
            state.presence = presence
            return Array(state.continuations.values)
        }
        for continuation in continuations { continuation.yield(presence) }
    }

    /// Sets the value without yielding (monitoring stopped).
    func reset(_ presence: Presence) {
        state.withLock { $0.presence = presence }
    }
}

/// A module's view of the launch's ``AwayServiceBroadcast``: its streams are tracked, so they end when it stops.
struct TrackedAwayService: AwayService {
    let base: AwayServiceBroadcast
    let tracker: RegistrationTracker

    var presence: Presence { base.presence }

    var changes: AsyncStream<Presence> {
        let (stream, token) = base.subscription()
        tracker.track(token)
        return stream
    }
}
