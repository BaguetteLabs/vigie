import AppKit
import Foundation

/// The running apps, as the other-notch-app monitor sees them (Story 17.5). Only bundle ids are read: no paths,
/// no process launch, no polling. The test seam of ``OtherNotchAppMonitor``.
@MainActor
public protocol RunningApplicationsObserving {
    /// Bundle ids of the apps running now.
    func runningBundleIDs() -> Set<String>
    /// Yields when the set of running apps changed. Each access returns a new stream with its own observation,
    /// removed when the stream ends.
    var changes: AsyncStream<Void> { get }
}

/// `NSWorkspace.shared.runningApplications`, observed with key-value observing.
///
/// `NSWorkspace.didLaunchApplicationNotification` and `didTerminateApplicationNotification` are not used: they
/// are documented as not posted for background apps and `LSUIElement` apps, which is how notch apps usually
/// run. Observing `runningApplications` is the documented way to see every app come and go.
@MainActor
public struct WorkspaceRunningApplications: RunningApplicationsObserving {
    /// Ends one observation. Safe to call from any thread, more than once.
    private final class Observation: @unchecked Sendable {
        // `NSKeyValueObservation` is not annotated `Sendable`; `invalidate()` is thread-safe and this box
        // only ever calls it.
        private let token: NSKeyValueObservation
        init(_ token: NSKeyValueObservation) { self.token = token }
        func end() { token.invalidate() }
    }

    private let observe: @MainActor (@escaping @Sendable () -> Void) -> Observation
    private let readBundleIDs: @MainActor () -> Set<String>

    /// Observes `NSWorkspace.shared.runningApplications` and reads its bundle ids.
    public init() {
        self.init(
            observing: NSWorkspace.shared, keyPath: \.runningApplications,
            bundleIDs: { Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)) })
    }

    /// - Parameters:
    ///   - root: the object whose key path is observed (a test double for the tests).
    ///   - keyPath: the KVO-compliant property that changes when an app launches or quits.
    ///   - bundleIDs: reads the running bundle ids.
    init<Root: NSObject, Value>(
        observing root: Root, keyPath: KeyPath<Root, Value>, bundleIDs: @escaping @MainActor () -> Set<String>
    ) {
        self.observe = { onChange in
            Observation(root.observe(keyPath, options: []) { _, _ in onChange() })
        }
        self.readBundleIDs = bundleIDs
    }

    public func runningBundleIDs() -> Set<String> { readBundleIDs() }

    public var changes: AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let observation = observe { continuation.yield() }
        continuation.onTermination = { _ in observation.end() }
        return stream
    }
}
