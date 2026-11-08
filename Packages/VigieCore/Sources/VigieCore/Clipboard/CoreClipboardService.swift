import AppKit
import ModuleKit

/// The pasteboard calls the clipboard service makes: write only (clear, then set a string), plus the change
/// count to tell whether the clipboard still holds what was copied. ``CoreClipboardService`` never reads the
/// pasteboard's contents.
@MainActor
public protocol PasteboardWriting: AnyObject {
    /// Increments on every change of ownership (any app's copy).
    var changeCount: Int { get }
    /// Empties the pasteboard; returns the new change count.
    @discardableResult func clearContents() -> Int
    /// Writes `string` as plain text; false when the pasteboard refused it.
    @discardableResult func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool
}

extension NSPasteboard: PasteboardWriting {}

/// `context.clipboard` (AD-19, Story 9.9): copy-only. Each copy clears the general pasteboard and writes plain
/// text on the main actor. With `clearAfter`, the pasteboard is cleared after that delay unless something else
/// was copied meanwhile (its change count moved).
public struct CoreClipboardService: ClipboardService {
    private let pasteboard: @MainActor @Sendable () -> any PasteboardWriting

    /// - Parameter pasteboard: the pasteboard to write; `NSPasteboard.general` by default.
    public init(pasteboard: @escaping @MainActor @Sendable () -> any PasteboardWriting = { NSPasteboard.general }) {
        self.pasteboard = pasteboard
    }

    /// Copies `text`. On the main thread the write happens before this returns; elsewhere it is scheduled on
    /// the main actor.
    public func copy(_ text: String, clearAfter: Duration?) {
        let pasteboard = pasteboard
        if Thread.isMainThread {
            MainActor.assumeIsolated { Self.write(text, to: pasteboard(), clearAfter: clearAfter) }
        } else {
            Task { @MainActor in Self.write(text, to: pasteboard(), clearAfter: clearAfter) }
        }
    }

    @MainActor
    private static func write(_ text: String, to pasteboard: any PasteboardWriting, clearAfter: Duration?) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        guard let clearAfter else { return }
        let written = pasteboard.changeCount
        Task { @MainActor [weak pasteboard] in
            try? await Task.sleep(for: clearAfter)
            guard let pasteboard, pasteboard.changeCount == written else { return }
            pasteboard.clearContents()
        }
    }
}
