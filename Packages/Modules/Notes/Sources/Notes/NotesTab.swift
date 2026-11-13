import ModuleKit
import SwiftUI
import VigieUI

/// What the Notes tab shows in Story 15.1 (the list and preview arrive with Story 15.5).
public enum NotesTabContent: Hashable, Sendable {
    case checking
    /// The recovery key just created, shown once (`Copy`, `I saved it`).
    case recoveryKey
    /// `KEYCHAIN UNAVAILABLE IN THIS BUILD` and the recovery entry.
    case unavailable
    /// The setup card: `Set up notes`.
    case setup
    /// `NOTES LOCKED` · "Waiting for iCloud Keychain, or enter your recovery key." and the recovery entry.
    case locked
    /// Ready: `NO NOTES`, or `N NOTES` until Story 15.5's list.
    case ready
}

extension NotesModule {
    public func expandedView() -> AnyView? {
        AnyView(NotesTabView(module: self))
    }

    public func settingsView() -> AnyView? {
        AnyView(NotesSettingsView(module: self))
    }

    public var tabContent: NotesTabContent {
        if pendingRecoveryKey != nil { return .recoveryKey }
        switch keyState {
        case .checking: return .checking
        case .unavailable: return .unavailable
        case .noKey: return .setup
        case .waiting, .mismatch: return .locked
        case .ready: return .ready
        }
    }
}

struct NotesTabView: View {
    @Environment(\.vigieTheme) private var theme
    let module: NotesModule
    @State private var showsEntry = false

    var body: some View {
        Group {
            switch module.tabContent {
            case .checking:
                Color.clear
            case .recoveryKey:
                NotesRecoveryKeyCard(module: module)
            case .unavailable:
                VStack(spacing: theme.spacing(.rowGap)) {
                    EmptyStateBlock(
                        label: NotesText.resource("notes.unavailable.label"),
                        sentence: NotesText.resource("notes.unavailable.sentence"))
                    NotesRecoveryEntry(module: module)
                }
            case .setup:
                if showsEntry {
                    NotesRecoveryEntry(module: module)
                } else {
                    SetupCard(
                        topic: NotesText.resource("notes.setup.topic"),
                        title: NotesText.resource("notes.setup.title"),
                        sentence: NotesText.resource("notes.setup.sentence"),
                        primary: ActionButton(
                            label: NotesText.resource("notes.action.setUp"), role: .primary,
                            action: { Task { await module.setUpNotes() } }),
                        secondary: ActionButton(
                            label: NotesText.resource("notes.action.enterRecoveryKey"),
                            action: { showsEntry = true }))
                }
            case .locked:
                VStack(spacing: theme.spacing(.rowGap)) {
                    EmptyStateBlock(VigieCopy.notesLocked)
                    countLine(NotesText.lockedCount(module.lockedNoteCount), when: module.lockedNoteCount > 0)
                    NotesRecoveryEntry(module: module)
                }
            case .ready:
                VStack(spacing: theme.spacing(.rowGap)) {
                    if module.noteCount > 0 {
                        EmptyStateBlock(label: NotesText.noteCount(module.noteCount))
                    } else {
                        EmptyStateBlock(VigieCopy.noNotes)
                    }
                    countLine(NotesText.lockedCount(module.lockedNoteCount), when: module.lockedNoteCount > 0)
                    let downloading = module.store?.downloadingFiles.count ?? 0
                    countLine(NotesText.downloadingCount(downloading), when: downloading > 0)
                }
            }
        }
        .padding(theme.spacing(.gridPaddingX))
        .task { await module.refresh() }
    }

    @ViewBuilder private func countLine(_ text: LocalizedStringResource, when shown: Bool) -> some View {
        if shown {
            Text(text)
                .font(theme.font(.kicker))
                .tracking(theme.tracking(.kicker))
                .foregroundStyle(theme.color(.ink3))
        }
    }
}

/// The recovery key field and `Enter recovery key` button; the refusal message under it.
struct NotesRecoveryEntry: View {
    @Environment(\.vigieTheme) private var theme
    let module: NotesModule
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.actionGap)) {
            HStack(spacing: theme.spacing(.actionGap)) {
                SecureField(text: $draft) { Text(NotesText.resource("notes.recovery.field")) }
                    .textFieldStyle(.plain)
                    .font(theme.font(.code))
                    .foregroundStyle(theme.color(.ink1))
                    .onSubmit { submit() }
                    .onChange(of: draft) { module.clearRecoveryError() }
                ActionButton(
                    label: NotesText.resource("notes.action.enterRecoveryKey"), role: .primary, action: submit
                )
                .fixedSize()
                .disabled(draft.isEmpty)
            }
            if let error = module.recoveryError {
                Text(error.message)
                    .font(theme.font(.prose))
                    .foregroundStyle(theme.color(.statusBlocked))
            }
        }
        .frame(maxWidth: theme.componentLength("setup-card", "max-width"))
    }

    private func submit() {
        let text = draft
        Task { @MainActor in
            if await module.enterRecoveryKey(text) { draft = "" }
        }
    }
}

/// The recovery key, shown once after setup, with `Copy` and `I saved it`.
struct NotesRecoveryKeyCard: View {
    @Environment(\.vigieTheme) private var theme
    let module: NotesModule

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.actionGap)) {
            Text(NotesText.resource("notes.recovery.title"))
                .font(theme.font(.kicker))
                .tracking(theme.tracking(.kicker))
                .foregroundStyle(theme.color(.ink2))
            Text(verbatim: module.pendingRecoveryKey ?? "")
                .font(theme.font(.code))
                .foregroundStyle(theme.color(.ink1))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text(NotesText.resource("notes.recovery.sentence"))
                .font(theme.font(.prose))
                .foregroundStyle(theme.color(.ink2))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: theme.spacing(.actionGap)) {
                ActionButton(label: NotesText.resource("notes.action.copy"), action: module.copyRecoveryKey)
                ActionButton(
                    label: NotesText.resource("notes.action.saved"), role: .primary,
                    action: module.confirmRecoveryKeySaved)
            }
            .fixedSize()
        }
        .frame(maxWidth: theme.componentLength("setup-card", "max-width"), alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
