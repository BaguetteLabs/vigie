import Foundation
import ModuleKit
import SwiftUI
import VigieUI

/// Story 12.3: per-Mac confirmation of script files (AD-18, SPEC §9.2). A file runs only once the user confirmed
/// its exact bytes on this Mac; records live in `local.toml` through `context.scriptFolder.confirmations`, never
/// in the synced config.
///
/// Entry points: ``openConfirmation(for:)`` sets ``reviewing``; the module's Settings pane (Settings › Scripts,
/// ``settingsView()``, Story 12.6) lists the scripts with their state and presents the Script Confirmation as
/// a sheet while ``reviewing`` is set. The island surfaces of Stories 12.5 and 12.11 show `NOT CONFIRMED`
/// (`VigieUI.ScriptStateLabel`) and call ``openConfirmation(for:)`` then open Settings on this pane.
extension IntegrationsModule {
    func startConfirmations(_ context: any ModuleContext) {
        confirmations = context.scriptFolder.confirmations
        let changes = confirmations.changes()
        confirmationTask = Task { [weak self] in
            for await _ in changes {
                guard !Task.isCancelled else { return }
                self?.refreshLocalStates()
            }
        }
        refreshLocalStates()
    }

    func stopConfirmations() {
        confirmationTask?.cancel()
        confirmationTask = nil
        reviewing = nil
        confirmations = NoScriptConfirmations()
    }

    /// Recomputes ``localStates`` from the records and the scripts' current hashes.
    func refreshLocalStates() {
        var next: [String: ScriptLocalState] = [:]
        for script in scripts { next[script.id] = computedState(script) }
        if next != localStates {
            localStates = next
            updateRunner()
        }
    }

    private func computedState(_ definition: ScriptModuleDefinition) -> ScriptLocalState {
        ScriptLocalState(
            record: confirmations.record(for: definition.relativePath), contentHash: definition.contentHash)
    }

    /// The state of `definition` (as given: its own hash) on this Mac.
    public func localState(for definition: ScriptModuleDefinition) -> ScriptLocalState {
        _ = localStates[definition.id]  // observation: views re-render when a record or a scan changes it
        return computedState(definition)
    }

    /// Whether the runner may run `definition` on this Mac (Story 12.4): parsed without error, enabled on this Mac
    /// (`[scripts.enabled]` in `local.toml`, Story 12.6), and its current bytes confirmed here.
    public func isEligible(_ definition: ScriptModuleDefinition) -> Bool {
        definition.status == .ok && definition.enabled && localState(for: definition) == .confirmed
    }

    /// Opens the Script Confirmation on `definition` (shown by the Settings pane, see the type's documentation).
    public func openConfirmation(for definition: ScriptModuleDefinition) {
        reviewing = definition
    }

    /// Closes the Script Confirmation without recording anything (Cancel, Escape).
    public func cancelConfirmation() {
        reviewing = nil
    }

    /// What the Script Confirmation shows for `definition`.
    public func confirmationContent(for definition: ScriptModuleDefinition) -> ScriptConfirmationContent {
        ScriptConfirmationContent(definition)
    }

    /// Confirm, from a user action only: records the reviewed bytes' hash for this Mac. If the file changed
    /// since it was read, the record does not match the new bytes and the script stays awaiting confirmation.
    public func confirm(_ definition: ScriptModuleDefinition) async throws {
        try await confirmations.confirm(definition.relativePath, sha256: definition.contentHash)
        finishReview(of: definition)
    }

    /// Decline, from a user action only: the reviewed bytes are disabled on this Mac only.
    public func decline(_ definition: ScriptModuleDefinition) async throws {
        try await confirmations.decline(definition.relativePath, sha256: definition.contentHash)
        finishReview(of: definition)
    }

    private func finishReview(of definition: ScriptModuleDefinition) {
        refreshLocalStates()
        if reviewing?.id == definition.id { reviewing = nil }
    }

    public func settingsView() -> AnyView? {
        AnyView(ScriptsSettingsView(module: self))
    }
}
