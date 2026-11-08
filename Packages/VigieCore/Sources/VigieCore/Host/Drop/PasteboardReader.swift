import AppKit
import ModuleKit
import SwiftUI

/// Turns a pasteboard into a ``DropPayload`` for the non-drag paths (Story 9.10): `⌘V` on the Shelf tab
/// (`NSPasteboard.general`, source `.paste`) and the Services entry `Stash in Vigie` (the service pasteboard,
/// source `.service`). Same precedence as a drag (``DropDragItems/read(_:)``): file URLs; else a web link,
/// image data (PNG, else TIFF), then plain text. Only VigieCore reads the clipboard; modules never do (AD-19).
@MainActor
public enum PasteboardReader {
    /// The payload, or nil when the pasteboard holds nothing usable (empty, or only unsupported types).
    public static func payload(
        from pasteboard: NSPasteboard, source: DropSource, modifiers: EventModifiers = []
    ) -> DropPayload? {
        let files =
            (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])
            ?? []
        if !files.isEmpty { return DropPayload(urls: files, modifiers: modifiers, source: source) }
        let links = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        if let link = links.first(where: { !$0.isFileURL && $0.scheme != nil }) {
            return DropPayload(urls: [], modifiers: modifiers, source: source, url: link)
        }
        if let image = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            return DropPayload(urls: [], modifiers: modifiers, source: source, imageData: image)
        }
        if let text = pasteboard.string(forType: .string),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return DropPayload(urls: [], modifiers: modifiers, source: source, text: text)
        }
        return nil
    }
}
