import AppKit
import CoreGraphics
import Foundation

// Story 20.1 (spike, docs/decisions/spike-away-detection.md): the raw signals the Away service (Story 20.3,
// AD-25) is built on. Nothing here decides Away; 20.3 combines input idle time with these screen signals.

// MARK: - Input idle time

/// Seconds since the last keyboard, mouse or trackpad input in the user's session.
public protocol IdleTimeReading: Sendable {
    func secondsSinceLastInput() -> TimeInterval
}

/// `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: <any input>)`.
///
/// Needs no permission: it is a query on the window server's session counters, not an event tap, so Input
/// Monitoring and Accessibility are not involved (measured in the spike: no TCC prompt, no `tccd` request).
/// Keep-awake power assertions do not reset it; synthetic events posted by other apps may.
public struct CGEventSourceIdleReader: IdleTimeReading {
    /// `kCGAnyInputEventType` (`~0`): the most recent of every input type.
    public static let anyInput = CGEventType(rawValue: ~0)!

    public let eventType: CGEventType
    public let state: CGEventSourceStateID

    public init(
        eventType: CGEventType = CGEventSourceIdleReader.anyInput, state: CGEventSourceStateID = .combinedSessionState
    ) {
        self.eventType = eventType
        self.state = state
    }

    public func secondsSinceLastInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(state, eventType: eventType)
    }
}

// MARK: - Screen and session signals

/// A change the Away service treats as "the user cannot be looking at the screen" (or its end).
public enum ScreenSignal: String, Hashable, Sendable, CaseIterable {
    /// `com.apple.screenIsLocked` (distributed).
    case screenLocked
    /// `com.apple.screenIsUnlocked` (distributed).
    case screenUnlocked
    /// `com.apple.screensaver.didstart` (distributed).
    case screensaverStarted
    /// `com.apple.screensaver.didstop` (distributed).
    case screensaverStopped
    /// `NSWorkspace.screensDidSleepNotification`.
    case displaysSlept
    /// `NSWorkspace.screensDidWakeNotification`.
    case displaysWoke
    /// `NSWorkspace.sessionDidResignActiveNotification` (fast user switching away).
    case sessionResigned
    /// `NSWorkspace.sessionDidBecomeActiveNotification`.
    case sessionActivated
    /// `NSWorkspace.willSleepNotification` (also on `PowerService.sleepWake`, Story 4.12).
    case systemWillSleep
    /// `NSWorkspace.didWakeNotification`.
    case systemDidWake
}

/// A signal with the moment it was received.
public struct ScreenSignalEvent: Hashable, Sendable {
    public let signal: ScreenSignal
    public let at: Date

    public init(_ signal: ScreenSignal, at: Date = Date()) {
        self.signal = signal
        self.at = at
    }
}

/// Lock, screensaver, display sleep, session switch and system sleep notifications.
public protocol LockStateObserving: Sendable {
    /// Yields each signal as it arrives. Each access returns a new stream with its own observers, removed when
    /// the stream ends.
    var signals: AsyncStream<ScreenSignalEvent> { get }
    /// Whether the screen is locked right now (for the state at launch, before any notification).
    func isScreenLockedNow() -> Bool
}

/// The real observers: `DistributedNotificationCenter` for lock and screensaver, `NSWorkspace`'s center for
/// displays, session and system sleep.
public final class SystemLockStateObserver: LockStateObserving {
    static let distributed: [(String, ScreenSignal)] = [
        ("com.apple.screenIsLocked", .screenLocked),
        ("com.apple.screenIsUnlocked", .screenUnlocked),
        ("com.apple.screensaver.didstart", .screensaverStarted),
        ("com.apple.screensaver.didstop", .screensaverStopped),
    ]

    static let workspace: [(Notification.Name, ScreenSignal)] = [
        (NSWorkspace.screensDidSleepNotification, .displaysSlept),
        (NSWorkspace.screensDidWakeNotification, .displaysWoke),
        (NSWorkspace.sessionDidResignActiveNotification, .sessionResigned),
        (NSWorkspace.sessionDidBecomeActiveNotification, .sessionActivated),
        (NSWorkspace.willSleepNotification, .systemWillSleep),
        (NSWorkspace.didWakeNotification, .systemDidWake),
    ]

    private let distributedCenter: NotificationCenter
    private let workspaceCenter: NotificationCenter
    private let now: @Sendable () -> Date

    public init(
        distributedCenter: NotificationCenter? = nil, workspaceCenter: NotificationCenter? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.distributedCenter = distributedCenter ?? DistributedNotificationCenter.default()
        self.workspaceCenter = workspaceCenter ?? NSWorkspace.shared.notificationCenter
        self.now = now
    }

    public var signals: AsyncStream<ScreenSignalEvent> {
        let (stream, continuation) = AsyncStream<ScreenSignalEvent>.makeStream()
        let now = now
        var tokens: [(NotificationCenter, any NSObjectProtocol)] = []
        for (name, signal) in Self.distributed {
            let token = distributedCenter.addObserver(forName: Notification.Name(name), object: nil, queue: nil) { _ in
                continuation.yield(ScreenSignalEvent(signal, at: now()))
            }
            tokens.append((distributedCenter, token))
        }
        for (name, signal) in Self.workspace {
            let token = workspaceCenter.addObserver(forName: name, object: nil, queue: nil) { _ in
                continuation.yield(ScreenSignalEvent(signal, at: now()))
            }
            tokens.append((workspaceCenter, token))
        }
        let box = ObserverTokens(tokens)
        continuation.onTermination = { _ in box.removeAll() }
        return stream
    }

    /// `CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]`, a documented session key.
    public func isScreenLockedNow() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (info["CGSSessionScreenIsLocked"] as? Bool) ?? ((info["CGSSessionScreenIsLocked"] as? Int) == 1)
    }
}

private final class ObserverTokens: @unchecked Sendable {
    private let tokens: [(NotificationCenter, any NSObjectProtocol)]

    init(_ tokens: [(NotificationCenter, any NSObjectProtocol)]) {
        self.tokens = tokens
    }

    func removeAll() {
        for (center, token) in tokens { center.removeObserver(token) }
    }
}

// MARK: - Folding the signals

/// Whether the screen can be seen, folded from ``ScreenSignal``s. Any one of locked, screensaver, displays
/// asleep, session inactive or system asleep makes it unavailable; each is cleared only by its own end signal
/// (a system wake also clears display sleep, since `screensDidWake` may not follow it).
public struct ScreenAvailability: Hashable, Sendable {
    public private(set) var locked = false
    public private(set) var screensaver = false
    public private(set) var displaysAsleep = false
    public private(set) var sessionInactive = false
    public private(set) var systemAsleep = false

    public init(locked: Bool = false) {
        self.locked = locked
    }

    /// True while nothing keeps the user from seeing the screen.
    public var isAvailable: Bool { !(locked || screensaver || displaysAsleep || sessionInactive || systemAsleep) }

    public mutating func apply(_ signal: ScreenSignal) {
        switch signal {
        case .screenLocked: locked = true
        case .screenUnlocked: locked = false
        case .screensaverStarted: screensaver = true
        case .screensaverStopped: screensaver = false
        case .displaysSlept: displaysAsleep = true
        case .displaysWoke: displaysAsleep = false
        case .sessionResigned: sessionInactive = true
        case .sessionActivated: sessionInactive = false
        case .systemWillSleep: systemAsleep = true
        case .systemDidWake:
            systemAsleep = false
            displaysAsleep = false
        }
    }
}

/// The input-idle half of Away: idle once `secondsSinceLastInput() >= threshold`.
public struct IdleThreshold: Sendable {
    public let threshold: TimeInterval

    public init(threshold: TimeInterval) {
        self.threshold = threshold
    }

    public func isIdle(_ reader: any IdleTimeReading) -> Bool {
        reader.secondsSinceLastInput() >= threshold
    }

    /// When the last input happened, as of `now`.
    public func lastInput(_ reader: any IdleTimeReading, now: Date) -> Date {
        now.addingTimeInterval(-reader.secondsSinceLastInput())
    }
}
