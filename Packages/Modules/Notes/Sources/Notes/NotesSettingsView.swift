import ModuleKit
import SwiftUI
import VigieUI

/// The Notes pane's own part, below the generated `hotkey`, `folder` and `clipboard_clear` rows (Story 15.1):
/// the key status line, the dev build's own folder, `Set up notes` or the recovery key entry, the recovery key
/// shown once, and the iCloud Keychain statement. Native controls (DESIGN "Settings window").
struct NotesSettingsView: View {
    let module: NotesModule
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text(NotesText.resource("notes.settings.key")).font(.headline)
            Text(verbatim: NotesSettingsView.statusLine(module.keyState, sessionOnly: module.keyIsSessionOnly))
                .font(.callout)
            if module.store != nil {
                Text(NotesText.folderCount(module.noteCount)).font(.caption).foregroundStyle(.secondary)
            }
            if module.usesOwnFolder, let folder = module.folder {
                Text(verbatim: NotesText.format("notes.folder.ownBuild", folder.path))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let recoveryKey = module.pendingRecoveryKey {
                recoveryKeyBlock(recoveryKey)
            } else {
                actions
            }
            if module.showsRecoveryOnlyStatement {
                Text(NotesText.resource("notes.icloud.statement")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { await module.refresh() }
    }

    @ViewBuilder private var actions: some View {
        if module.keyState == .noKey {
            Button {
                Task { await module.setUpNotes() }
            } label: {
                Text(NotesText.resource("notes.action.setUp"))
            }
            if module.setupFailed {
                Text(NotesText.resource("notes.setup.failed")).font(.caption).foregroundStyle(.secondary)
            }
        }
        switch module.keyState {
        case .noKey, .waiting, .mismatch, .unavailable:
            HStack {
                SecureField(text: $draft) { Text(NotesText.resource("notes.recovery.field")) }
                    .onSubmit { submit() }
                    .onChange(of: draft) { module.clearRecoveryError() }
                Button {
                    submit()
                } label: {
                    Text(NotesText.resource("notes.action.enterRecoveryKey"))
                }
                .disabled(draft.isEmpty)
            }
            if let error = module.recoveryError {
                Text(error.message).font(.caption).foregroundStyle(.secondary)
            }
        case .checking, .ready:
            EmptyView()
        }
    }

    private func recoveryKeyBlock(_ recoveryKey: String) -> some View {
        VStack(alignment: .leading) {
            Text(NotesText.resource("notes.recovery.title")).font(.subheadline)
            Text(verbatim: recoveryKey).font(.body.monospaced()).textSelection(.enabled)
            Text(NotesText.resource("notes.recovery.sentence")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button {
                    module.copyRecoveryKey()
                } label: {
                    Text(NotesText.resource("notes.action.copy"))
                }
                Button {
                    module.confirmRecoveryKeySaved()
                } label: {
                    Text(NotesText.resource("notes.action.saved"))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func submit() {
        let text = draft
        Task { @MainActor in
            if await module.enterRecoveryKey(text) { draft = "" }
        }
    }

    /// The key status line for a state.
    nonisolated static func statusLine(_ state: NotesKeyState, sessionOnly: Bool) -> String {
        switch state {
        case .checking: NotesText.string("notes.status.checking")
        case .unavailable: NotesText.string("notes.status.unavailable")
        case .noKey: NotesText.string("notes.status.noKey")
        case .waiting: NotesText.string("notes.status.waiting")
        case .mismatch: NotesText.string("notes.status.mismatch")
        case .ready(let keyID):
            NotesText.format(sessionOnly ? "notes.status.readySession" : "notes.status.ready", keyID)
        }
    }
}
