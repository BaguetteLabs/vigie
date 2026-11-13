import AppKit
import Observation
import SwiftUI

/// Settings › Sync (Story 16.2, FR102): the iCloud toggle with its status (`OFF`, `ON · <root>`,
/// `UNAVAILABLE · iCloud Drive is off`), an inline confirmation before turning on or off, errors inline,
/// `Reveal in Finder` while on, and the note that per-Mac settings and secrets never sync. Every change goes
/// through ``SyncController`` (AD-12).
@MainActor @Observable
public final class SyncPaneModel {
    public enum Status: Equatable, Sendable {
        case off
        case on(String)
        case unavailable
    }

    @ObservationIgnored public let controller: SyncController
    /// Shows a folder in Finder. Tests replace it.
    @ObservationIgnored var reveal: @MainActor (URL) -> Void
    /// The checked change waiting for confirmation.
    public private(set) var pending: SyncPlan?
    public private(set) var error: String?
    public private(set) var isWorking = false
    /// iCloud Drive availability, re-checked by ``refresh()`` and before each change.
    public private(set) var isAvailable: Bool

    public init(controller: SyncController) {
        self.controller = controller
        reveal = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
        isAvailable = controller.isAvailable
    }

    public func refresh() {
        let available = controller.isAvailable
        if available != isAvailable { isAvailable = available }
    }

    public var status: Status {
        if controller.isOn { return .on(controller.environment.abbreviatingHome(controller.rootURL)) }
        return isAvailable ? .off : .unavailable
    }

    /// The status line.
    public var statusText: String {
        switch status {
        case .off: SettingsText.string("settings.sync.status.off")
        case .on(let path): SettingsText.format("settings.sync.status.on", path)
        case .unavailable: SettingsText.string("settings.sync.status.unavailable")
        }
    }

    /// The toggle can be turned on only with iCloud Drive; it can always be turned off.
    public var canToggle: Bool { !isWorking && (controller.isOn || isAvailable) }

    /// The toggle: asks for confirmation of the change (the toggle keeps showing the real state until then).
    public func request(_ on: Bool) {
        guard !isWorking, on != controller.isOn else { return }
        refresh()
        do throws(SyncError) {
            pending = try on ? controller.planTurnOn() : controller.planTurnOff()
            error = nil
        } catch {
            pending = nil
            self.error = error.errorDescription
        }
    }

    /// The confirmation sentence of ``pending``.
    public var confirmationText: String? {
        guard let pending else { return nil }
        guard pending.turnsOn else { return SettingsText.string("settings.sync.confirm.off") }
        let text = SettingsText.string("settings.sync.confirm.on")
        guard pending.adoptsConfig || pending.adoptsNotes else { return text }
        return text + " " + SettingsText.string("settings.sync.confirm.adopt")
    }

    public func confirm() async {
        guard let plan = pending, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do throws(SyncError) {
            try await controller.apply(plan)
            error = nil
        } catch {
            self.error = error.errorDescription
        }
        pending = nil
        refresh()
    }

    public func cancel() {
        pending = nil
    }

    public func revealInFinder() {
        reveal(controller.rootURL)
    }
}

/// The Sync pane's content.
struct SyncSection: View {
    let model: SyncPaneModel

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(
                    isOn: Binding(get: { model.controller.isOn }, set: { model.request($0) })
                ) {
                    Text(CoreSettings.label("config.sync.icloud"))
                    Text(verbatim: model.statusText)
                        .textSelection(.enabled)
                }
                .disabled(!model.canToggle)
            }
            if case .on = model.status {
                Button {
                    model.revealInFinder()
                } label: {
                    Text(SettingsText.resource("settings.sync.reveal"))
                }
            }
            if let text = model.confirmationText {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button {
                            model.cancel()
                        } label: {
                            Text(SettingsText.resource("settings.sync.cancel"))
                        }
                        Button {
                            Task { await model.confirm() }
                        } label: {
                            Text(
                                SettingsText.resource(
                                    model.pending?.turnsOn == true
                                        ? "settings.sync.confirm.onButton" : "settings.sync.confirm.offButton"))
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                    .disabled(model.isWorking)
                }
            }
            if let error = model.error {
                Text(verbatim: error).foregroundStyle(.red)
            }
        } footer: {
            Text(SettingsText.resource("settings.sync.note"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
