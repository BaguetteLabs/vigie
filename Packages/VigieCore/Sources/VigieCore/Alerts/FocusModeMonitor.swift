import Foundation
import os

/// Whether macOS Do Not Disturb or any Focus mode is on (FR17, Story 3.5). Lives with the Notifier (Architecture
/// "Deferred": DND detection is inside Notifier behind a testable abstraction). The App uses
/// `FocusFilterMonitor` (Story 3.10).
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
