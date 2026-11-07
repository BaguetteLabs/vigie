import Foundation
import ModuleKit

/// `Scheduler` for one module: each job is a `Task`, cancelled by its token; every token is tracked by the
/// module's `RegistrationTracker`, so the jobs end when the module stops.
public struct CoreScheduler: Scheduler {
    private let tracker: RegistrationTracker

    public init(tracker: RegistrationTracker) {
        self.tracker = tracker
    }

    public func every(_ interval: Duration, _ body: @escaping @Sendable () async -> Void) -> RegistrationToken {
        let task = Task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                guard !Task.isCancelled else { return }
                await body()
            }
        }
        return tracker.track(RegistrationToken { task.cancel() })
    }

    public func at(_ date: Date, _ body: @escaping @Sendable () async -> Void) -> RegistrationToken {
        let task = Task {
            let delay = date.timeIntervalSinceNow
            if delay > 0 {
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            await body()
        }
        return tracker.track(RegistrationToken { task.cancel() })
    }
}
