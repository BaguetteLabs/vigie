import AppKit
import Foundation
import ModuleKit
import Synchronization

/// Begins and ends the system activity that keeps the Mac from idle-sleeping. The test seam of
/// ``CorePowerService``; production uses ``ProcessInfoIdleSleepActivities``.
public protocol IdleSleepActivities: Sendable {
    func begin(reason: String) -> IdleSleepActivity
    func end(_ activity: IdleSleepActivity)
}

/// An activity returned by `ProcessInfo.beginActivity`, carried across isolation domains. The object is only
/// handed back to `endActivity(_:)`.
public struct IdleSleepActivity: @unchecked Sendable {
    public let object: any NSObjectProtocol

    public init(_ object: any NSObjectProtocol) {
        self.object = object
    }
}

/// `ProcessInfo.beginActivity(options: [.idleSystemSleepDisabled], reason:)`. Prevents idle sleep only: closing
/// the lid or choosing Sleep still sleeps the Mac (PRD FR-19).
public struct ProcessInfoIdleSleepActivities: IdleSleepActivities {
    public init() {}

    public func begin(reason: String) -> IdleSleepActivity {
        IdleSleepActivity(ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled], reason: reason))
    }

    public func end(_ activity: IdleSleepActivity) {
        ProcessInfo.processInfo.endActivity(activity.object)
    }
}

/// `context.power` (Story 4.12, AD-19, AD-5).
///
/// Keep-awake: every `preventIdleSleep(reason:)` call is a request; while at least one request is open **and**
/// `[general] prevent_idle_sleep` is on, the service holds exactly one system activity
/// (`.idleSystemSleepDisabled`). With the setting off a request is accepted but inert: the returned token is
/// valid and cancelling it is harmless, and no activity is begun. The setting is re-read on every request and
/// release, and on ``settingChanged()`` (App assembly calls it when the key changes), so turning the setting on
/// while a request is open begins the activity, and turning it off ends it. Cancelling a token twice is a no-op.
/// The activity also ends when the service is deallocated.
///
/// Sleep/wake: `sleepWake` yields `.willSleep` and `.didWake` from `NSWorkspace.shared.notificationCenter`
/// (`willSleepNotification`, `didWakeNotification`). Each access returns a new stream with its own observers,
/// removed when the stream ends. The wake time is when the event is received; `SleepWakeEvent.didWake` carries
/// no date.
///
/// One instance per launch; module contexts wrap it with their `RegistrationTracker` (``TrackedPowerService``)
/// so a module's requests end when it stops.
public final class CorePowerService: PowerService {
    private struct State {
        var requests: [UUID: String] = [:]
        var activity: IdleSleepActivity?
    }

    private let state = Mutex(State())
    private let isEnabled: @Sendable () -> Bool
    private let activities: any IdleSleepActivities
    private let notificationCenter: NotificationCenter

    /// - Parameters:
    ///   - isEnabled: reads `[general] prevent_idle_sleep`.
    ///   - activities: the system activity seam.
    ///   - notificationCenter: where sleep and wake are observed; defaults to `NSWorkspace.shared.notificationCenter`.
    public init(
        isEnabled: @escaping @Sendable () -> Bool,
        activities: any IdleSleepActivities = ProcessInfoIdleSleepActivities(),
        notificationCenter: NotificationCenter? = nil
    ) {
        self.isEnabled = isEnabled
        self.activities = activities
        self.notificationCenter = notificationCenter ?? NSWorkspace.shared.notificationCenter
    }

    deinit {
        if let activity = state.withLock({ $0.activity }) { activities.end(activity) }
    }

    public func preventIdleSleep(reason: String) -> RegistrationToken {
        let id = UUID()
        state.withLock { $0.requests[id] = reason }
        reconcile()
        return RegistrationToken(id: id) { [weak self] in
            guard let self else { return }
            let removed = self.state.withLock { $0.requests.removeValue(forKey: id) != nil }
            if removed { self.reconcile() }
        }
    }

    /// Re-reads the setting and begins or ends the activity to match.
    public func settingChanged() {
        reconcile()
    }

    /// True while the system activity is held.
    public var isPreventingIdleSleep: Bool { state.withLock { $0.activity != nil } }

    /// Open requests, whether or not the setting lets them hold the activity.
    public var openRequests: Int { state.withLock { $0.requests.count } }

    public var sleepWake: AsyncStream<SleepWakeEvent> {
        let center = notificationCenter
        let (stream, continuation) = AsyncStream<SleepWakeEvent>.makeStream()
        let sleep = center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: nil
        ) { _ in continuation.yield(.willSleep) }
        let wake = center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: nil
        ) { _ in continuation.yield(.didWake) }
        let pair = ObserverPair(sleep: sleep, wake: wake)
        continuation.onTermination = { _ in
            center.removeObserver(pair.sleep)
            center.removeObserver(pair.wake)
        }
        return stream
    }

    private func reconcile() {
        let wanted = isEnabled()
        // Decide and swap under the lock; call the system outside it.
        enum Step {
            case none
            case begin(String)
            case end(IdleSleepActivity)
        }
        let step: Step = state.withLock { state in
            let hold = wanted && !state.requests.isEmpty
            if hold, state.activity == nil {
                let reason = state.requests.values.sorted().first ?? ""
                return .begin(reason)
            }
            if !hold, let activity = state.activity {
                state.activity = nil
                return .end(activity)
            }
            return .none
        }
        switch step {
        case .none:
            break
        case .end(let activity):
            activities.end(activity)
        case .begin(let reason):
            let activity = activities.begin(reason: reason)
            let extra: IdleSleepActivity? = state.withLock { state in
                // A concurrent call may have begun one, or the last request may have gone meanwhile.
                guard state.activity == nil, !state.requests.isEmpty else { return activity }
                state.activity = activity
                return nil
            }
            if let extra { activities.end(extra) }
        }
    }
}

/// The two observer tokens of one `sleepWake` stream; only passed to `removeObserver(_:)`.
private final class ObserverPair: @unchecked Sendable {
    let sleep: any NSObjectProtocol
    let wake: any NSObjectProtocol

    init(sleep: any NSObjectProtocol, wake: any NSObjectProtocol) {
        self.sleep = sleep
        self.wake = wake
    }
}

/// A module's view of the launch's ``CorePowerService``: its requests are tracked, so they end when it stops.
struct TrackedPowerService: PowerService {
    let base: any PowerService
    let tracker: RegistrationTracker

    func preventIdleSleep(reason: String) -> RegistrationToken {
        tracker.track(base.preventIdleSleep(reason: reason))
    }

    var sleepWake: AsyncStream<SleepWakeEvent> { base.sleepWake }
}
