import ModuleKit
import VigieCore

/// Fixed module enablement until ConfigStore lands (Story 2.3).
// TODO(Story 2.3 integration): replace with the ConfigStore-backed `ModuleEnablement`.
struct StaticEnablement: ModuleEnablement {
    let values: [ModuleID: Bool]

    func isEnabled(_ id: ModuleID) -> Bool? { values[id] }

    /// Never changes; the stream finishes at once.
    var changes: AsyncStream<ModuleID> { AsyncStream { $0.finish() } }
}
