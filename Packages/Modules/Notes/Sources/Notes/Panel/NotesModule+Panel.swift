import Foundation
import ModuleKit
import SwiftUI

/// The floating notes panel (Story 15.3, SPEC §7.6): `notes.open` (`[modules.notes] hotkey`, default `opt+cmd+n`)
/// opens it through `context.host` with the hotkey's `UserIntent`; pressing it again closes it.
///
/// The hotkey is registered as `open` (full name `notes.open`) with the `hotkey` setting's value as its shortcut,
/// and registered again whenever the setting changes (`""` or `none` = off).
extension NotesModule {
    /// The panel request id.
    nonisolated static let panelID = "notes.panel"
    /// The hotkey name under the module id (`notes.open`).
    nonisolated static let panelHotkeyName = "open"

    func startPanelHotkey(_ context: any ModuleContext) {
        registerPanelHotkey(context)
        let changes = context.settings.observe("hotkey")
        tasks.append(
            Task { @MainActor [weak self] in
                for await _ in changes {
                    guard !Task.isCancelled, let self, self.isRunning, let context = self.context else { return }
                    self.registerPanelHotkey(context)
                }
            })
    }

    /// The `hotkey` setting as a shortcut (the declared default when it cannot be read): nil when it is empty
    /// or `none` (off).
    static func panelShortcut(_ settings: any ModuleSettings) -> String? {
        let value = (settings.value("hotkey", as: String.self) ?? defaultHotkey).trimmingCharacters(in: .whitespaces)
        return value.isEmpty || value.lowercased() == "none" ? nil : value
    }

    private func registerPanelHotkey(_ context: any ModuleContext) {
        panelHotkey?.cancel()
        panelHotkey = nil
        do {
            panelHotkey = try context.hotkeys.register(
                name: Self.panelHotkeyName, default: Self.panelShortcut(context.settings)
            ) { [weak self] intent in
                self?.togglePanel(focus: intent)
            }
        } catch {
            context.log.error("Notes hotkey not registered: \(String(describing: error), privacy: .public)")
        }
    }

    /// The hotkey: opens the panel, or closes it when it is open.
    public func togglePanel(focus: UserIntent) {
        guard isRunning, let context else { return }
        if isPanelOpen {
            context.host.dismissFloatingPanel()
            return
        }
        openPanel(focus: focus, context: context)
    }

    private func openPanel(focus: UserIntent, context: any ModuleContext) {
        panelSession = nil
        preparePanelSession()
        let request = FloatingPanelRequest(
            id: Self.panelID,
            content: { [weak self] in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(NotesPanelView(module: self))
            },
            onEscape: { [weak self] in self?.panelEscape() },
            onClose: { [weak self] in self?.panelClosed() })
        isPanelOpen = context.host.presentFloatingPanel(request, focus: focus)
        if !isPanelOpen {
            panelSession = nil
            context.log.info("Notes panel refused by the host")
        }
    }

    /// Starts the panel's note once the key is ready (at open, or when setup or a recovery key unlocks notes
    /// while the panel is open).
    func preparePanelSession() {
        guard panelSession == nil, case .ready = keyState, let store else { return }
        panelSession = NotesPanelSession(
            store: store, now: now(), isSynced: folder.map(isUbiquitous) ?? false, sleep: panelSleep)
    }

    /// Esc: save now; the host closes the panel next.
    private func panelEscape() {
        guard let session = panelSession else { return }
        let previous = panelClose
        panelClose = Task { @MainActor in
            await previous?.value
            await session.save()
        }
    }

    /// The panel went away: final save, and a blank note is deleted.
    private func panelClosed() {
        isPanelOpen = false
        guard let session = panelSession else { return }
        panelSession = nil
        let previous = panelClose
        panelClose = Task { @MainActor in
            await previous?.value
            await session.close()
        }
    }

    /// Module stop: closes the panel (its note saved) before the store goes away.
    func stopPanel() async {
        panelHotkey?.cancel()
        panelHotkey = nil
        if isPanelOpen { context?.host.dismissFloatingPanel() }
        // A host that did not call back still gets the note saved.
        if isPanelOpen { panelClosed() }
        await panelClose?.value
        panelClose = nil
    }
}
