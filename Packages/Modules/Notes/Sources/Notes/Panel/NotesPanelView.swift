import ModuleKit
import SwiftUI
import VigieUI

/// The floating notes panel body (Story 15.3, DESIGN "Floating notes panel", mockup `key-notes.html`). The host
/// draws the frame (no band, iris filament, `rounded.notes-panel`); this is the header, the editor and the
/// footer.
///
/// - Header: `NOTES · <title>` (title live from the first line, `UNTITLED` when empty) with
///   `SYNCED · ENCRYPTED · ESC` (or `ENCRYPTED · ESC` when the folder is not in iCloud Drive) on the right.
/// - Body: a plain text editor (Markdown source, prose face). While the key is not ready it shows the Notes tab's
///   own state (setup, locked, unavailable, recovery key) so the user learns why; while the store cannot write,
///   the editor is read-only under the `NOTES LOCKED` banner.
/// - Footer: `EDITED HH:MM` on the right; the left slot is kept for Story 15.4's `COPIED · CLEARS IN 30S`.
/// - Privacy mode (AD-24): the header title and the body render as fixed-width dots in `ink-3`; typing still
///   edits. The meta and the footer stay.
struct NotesPanelView: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.locale) private var locale
    let module: NotesModule

    var body: some View {
        let session = module.tabContent == .ready ? module.panelSession : nil
        VStack(spacing: 0) {
            header(session)
            Group {
                if let session {
                    NotesPanelEditor(session: session)
                } else {
                    NotesTabView(module: module)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer(session)
        }
        .onChange(of: module.tabContent) { module.preparePanelSession() }
    }

    private func header(_ session: NotesPanelSession?) -> some View {
        HStack(spacing: theme.spacing(.glyphGap)) {
            HStack(spacing: 0) {
                Text(NotesText.resource("notes.panel.kicker"))
                if let session {
                    Text(NotesText.resource("notes.panel.separator"))
                    NotesPanelTitle(title: session.title)
                }
            }
            .font(theme.font(.cardTitle))
            .tracking(theme.tracking(.cardTitle))
            .textCase(.uppercase)
            .foregroundStyle(theme.color(.ink2))
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: theme.spacing(.glyphGap))
            Text(NotesPanelText.meta(synced: session?.isSynced ?? false))
                .font(theme.font(.kicker))
                .tracking(theme.tracking(.kicker))
                .textCase(.uppercase)
                .foregroundStyle(theme.color(.ink3))
                .lineLimit(1)
                .layoutPriority(1)
        }
        .padding(.horizontal, theme.spacing(.expandedBarPaddingX))
        .frame(height: theme.spacing(.bandHeight))
    }

    private func footer(_ session: NotesPanelSession?) -> some View {
        HStack(spacing: theme.spacing(.glyphGap)) {
            // Story 15.4: `COPIED · CLEARS IN 30S` and its drain line go here.
            Spacer(minLength: 0)
            if let edited = session?.lastEdited {
                Text(verbatim: NotesPanelText.edited(edited, locale: locale))
                    .font(theme.font(.kicker))
                    .tracking(theme.tracking(.kicker))
                    .foregroundStyle(theme.color(.ink3))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, theme.spacing(.expandedBarPaddingX))
        .frame(height: theme.spacing(.bandHeight))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.borderColor(.ink1, opacity: NotesPanelMetrics.footerRule(theme.look)))
                .frame(height: theme.a11y.hairlineWidth)
        }
    }
}

/// The header title: masked while Privacy mode is active.
struct NotesPanelTitle: View {
    let title: String

    var body: some View {
        Group {
            if title.isEmpty {
                Text(NotesText.resource("notes.untitled"))
            } else {
                Text(verbatim: title).truncationMode(.tail)
            }
        }
        .sensitive()
    }
}

/// The editor with its read-only banner.
struct NotesPanelEditor: View {
    @Environment(\.vigieTheme) private var theme
    @Bindable var session: NotesPanelSession
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.actionGap)) {
            if !session.canWrite {
                Text(VigieCopy.notesLocked.label)
                    .font(theme.font(.kicker))
                    .tracking(theme.tracking(.kicker))
                    .foregroundStyle(theme.color(.statusBlocked))
            }
            SensitiveTextEditor(text: $session.draft, font: .prose)
                .disabled(!session.canWrite)
                .focused($focused)
                .accessibilityLabel(Text(NotesText.resource("notes.panel.editor")))
        }
        .padding(.horizontal, theme.spacing(.expandedBarPaddingX))
        .onAppear { focused = true }
    }
}

/// Fixed proportions DESIGN states in the mockup rather than as tokens.
enum NotesPanelMetrics {
    /// The footer's top rule (mockup `--hair2`): ink-1 at 6% dark, 8% light, like a card hairline.
    static func footerRule(_ look: Look) -> Double { look == .dark ? 0.06 : 0.08 }
}
