import Foundation
import ModuleKit
import Synchronization

/// Collects every `RegistrationToken` a module obtains through its context, so the Registry can remove them all
/// when the module stops (FR3). One tracker per module run; after `cancelAll()` any new token is cancelled at once.
public final class RegistrationTracker: Sendable {
    private struct State {
        var tokens: [UUID: RegistrationToken] = [:]
        var closed = false
    }

    private let state = Mutex(State())

    public init() {}

    /// Tracks `token` and returns a token that, when cancelled, also stops tracking it.
    @discardableResult
    public func track(_ token: RegistrationToken) -> RegistrationToken {
        let accepted = state.withLock { state -> Bool in
            guard !state.closed else { return false }
            state.tokens[token.id] = token
            return true
        }
        guard accepted else {
            token.cancel()
            return token
        }
        return RegistrationToken(id: token.id) { [weak self] in
            self?.untrack(token.id)
            token.cancel()
        }
    }

    /// Cancels every outstanding token and closes the tracker.
    public func cancelAll() {
        let tokens = state.withLock { state -> [RegistrationToken] in
            state.closed = true
            defer { state.tokens.removeAll() }
            return Array(state.tokens.values)
        }
        for token in tokens { token.cancel() }
    }

    /// Number of registrations still outstanding.
    public var activeCount: Int { state.withLock { $0.tokens.count } }

    public var isClosed: Bool { state.withLock { $0.closed } }

    private func untrack(_ id: UUID) {
        _ = state.withLock { $0.tokens.removeValue(forKey: id) }
    }
}
