import Foundation
import ModuleKit
import Observation
import SwiftUI
import VigieUI

/// Settings › General › Copy diagnostics (Story 17.4, AD-16): builds the redacted report with
/// ``DiagnosticsCollector`` and puts it on the clipboard through the core clipboard service, without the clear
/// timer (the user pastes it into a bug report, possibly minutes later; it holds no secret). The row then reads
/// `COPIED · 12 KB` for the theme's confirm-readout duration. Nothing is sent anywhere.
@MainActor @Observable
public final class DiagnosticsModel {
    @ObservationIgnored public let collector: DiagnosticsCollector
    /// `context.clipboard`'s service (``CoreClipboardService``). Tests pass one on a recording pasteboard.
    @ObservationIgnored var clipboard: any ClipboardService
    /// How long the copied status stays (theme motion `confirm-readout`).
    @ObservationIgnored var readoutDuration: @MainActor () -> Duration = DiagnosticsModel.themeReadout
    /// Size of the last copied text while its status shows.
    public private(set) var copiedBytes: Int?
    /// The inline error of the last copy (the text was copied without its log lines).
    public private(set) var error: String?
    public private(set) var isWorking = false
    @ObservationIgnored private var clearTask: Task<Void, Never>?

    public init(collector: DiagnosticsCollector, clipboard: any ClipboardService) {
        self.collector = collector
        self.clipboard = clipboard
    }

    /// `Copy Diagnostics`.
    public func copy() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let result = await collector.makeText()
        clipboard.copy(result.text, clearAfter: nil)
        copiedBytes = result.byteCount
        error = result.logsUnavailable ? SettingsText.string("settings.diagnostics.logsUnavailable") : nil
        clearTask?.cancel()
        let duration = readoutDuration()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.copiedBytes = nil
        }
    }

    /// `COPIED · 12 KB` while the status shows.
    public var statusText: String? {
        copiedBytes.map { SettingsText.format("settings.diagnostics.copied", Self.sizeText($0)) }
    }

    nonisolated static func sizeText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// The bundled default theme's `confirm-readout` motion.
    static func themeReadout() -> Duration {
        guard let library = try? ThemeLoader.loadBundled() else { return .zero }
        return library.resolve(themeID: ThemeLibrary.defaultVariantID, look: .dark).theme.motion(.confirmReadout)
    }
}

/// The Copy diagnostics section of Settings › General.
struct DiagnosticsSection: View {
    let model: DiagnosticsModel

    var body: some View {
        Section {
            LabeledContent {
                Button {
                    Task { await model.copy() }
                } label: {
                    Text(SettingsText.resource("settings.diagnostics.copy"))
                }
                .disabled(model.isWorking)
            } label: {
                Text(SettingsText.resource("settings.diagnostics.label"))
                Text(SettingsText.resource("settings.diagnostics.help"))
            }
            if let status = model.statusText {
                Text(verbatim: status)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            if let error = model.error {
                Text(verbatim: error).foregroundStyle(.red)
            }
        } header: {
            Text(SettingsText.resource("settings.section.diagnostics"))
        }
    }
}
