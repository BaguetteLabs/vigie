import AppKit
import Foundation
import Quartz

/// Shows one file in the Quick Look panel (FR59, FR91 Space). Returns false when no Vigie window is key:
/// `QLPreviewPanel` takes key itself and needs a key window to start from, and the expanded panel is
/// non-activating (UX-DR45) — it is key only after the user clicked into it, which is also when the tab gets
/// Space. `onClose` runs once, when the panel closes or shows another file (it ends the file's access).
@MainActor public protocol QuickLookPresenting: AnyObject {
    func present(_ url: URL, onClose: @escaping @MainActor () -> Void) -> Bool
}

/// Opens Finder with the file selected (Reveal).
public protocol FileRevealer: Sendable {
    @MainActor func reveal(_ url: URL)
}

public struct WorkspaceRevealer: FileRevealer {
    public init() {}

    @MainActor public func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// The system Quick Look panel, fed directly (no responder in the expanded panel's chain claims it, since
/// modules cannot reach that window), one level above the key window so it shows over the expanded panel.
/// Space on the same file again closes it.
@MainActor
final class QuickLookPresenter: NSObject, QuickLookPresenting, @preconcurrency QLPreviewPanelDataSource,
    QLPreviewPanelDelegate
{
    private var url: URL?
    private var onClose: (@MainActor () -> Void)?
    private var closeObserver: (any NSObjectProtocol)?

    func present(_ url: URL, onClose: @escaping @MainActor () -> Void) -> Bool {
        if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible,
            self.url == url
        {
            onClose()
            panel.orderOut(nil)
            finish()
            return true
        }
        guard let key = NSApp.keyWindow, let panel = QLPreviewPanel.shared() else { return false }
        finish()
        self.url = url
        self.onClose = onClose
        panel.dataSource = self
        panel.delegate = self
        panel.level = NSWindow.Level(rawValue: key.level.rawValue + 1)
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    private func finish() {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        let close = onClose
        onClose = nil
        url = nil
        close?()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        url as NSURL?
    }
}

/// A shelf item's file held open: a reference's security scope stays started until ``close()``.
@MainActor
final class ShelfFileAccess {
    let url: URL
    private var stop: (() -> Void)?

    init(url: URL, stop: @escaping () -> Void) {
        self.url = url
        self.stop = stop
    }

    /// Ends the access; later calls do nothing.
    func close() {
        stop?()
        stop = nil
    }
}
