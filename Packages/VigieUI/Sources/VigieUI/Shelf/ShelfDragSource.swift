import AppKit
import SwiftUI

/// The row's drag-out handle (FR59, UX-DR50): an AppKit dragging source over the grip, because SwiftUI's
/// `onDrag` does not report how a drag ended. The drag offers move and copy; Finder moves on the same volume
/// and copies with ⌥ held (or onto another volume), and ``ShelfDragOperation`` carries its answer back.
struct ShelfDragHandle: NSViewRepresentable {
    let beginDrag: @MainActor () -> URL?
    let endDrag: @MainActor (ShelfDragOperation) -> Void
    var badgeColor: NSColor = .controlAccentColor

    func makeNSView(context: Context) -> ShelfDragSourceView {
        let view = ShelfDragSourceView()
        view.beginDrag = beginDrag
        view.endDrag = endDrag
        view.badgeColor = badgeColor
        return view
    }

    func updateNSView(_ view: ShelfDragSourceView, context: Context) {
        view.beginDrag = beginDrag
        view.endDrag = endDrag
        view.badgeColor = badgeColor
    }
}

final class ShelfDragSourceView: NSView, NSDraggingSource {
    /// Pointer travel before a press becomes a drag (points).
    static let dragThreshold: CGFloat = 3
    /// The file icon under the pointer while dragging.
    static let iconSide: CGFloat = 32

    var beginDrag: (@MainActor () -> URL?)?
    var endDrag: (@MainActor (ShelfDragOperation) -> Void)?
    /// Draws the ⌥ badge (accent from the theme), set by the row.
    var badgeColor: NSColor = .controlAccentColor
    private var pressed: NSEvent?
    private var icon: NSImage?
    private var showsOptionBadge = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pressed = event
    }

    override func mouseUp(with event: NSEvent) {
        pressed = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pressed else { return }
        let start = pressed.locationInWindow
        let now = event.locationInWindow
        guard hypot(now.x - start.x, now.y - start.y) >= Self.dragThreshold else { return }
        self.pressed = nil
        guard let url = beginDrag?() else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let point = convert(pressed.locationInWindow, from: nil)
        let side = Self.iconSide
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        self.icon = icon
        showsOptionBadge = false
        item.setDraggingFrame(
            NSRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side), contents: icon)
        let session = beginDraggingSession(with: [item], event: pressed, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        Self.operationMask
    }

    /// ⌥ held while the drag is still over the panel (its only targets there are the `SEND TO` zones, where ⌥
    /// means the alternate folder): the ghost carries an ⌥ badge (UX-DR32). Outside the panel Finder shows its
    /// own copy badge.
    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        let inside = window?.frame.contains(screenPoint) ?? false
        let wanted = inside && NSEvent.modifierFlags.contains(.option)
        guard wanted != showsOptionBadge, let icon else { return }
        showsOptionBadge = wanted
        let contents = wanted ? Self.badged(icon, color: badgeColor) : icon
        session.enumerateDraggingItems(
            options: [], for: self, classes: [NSPasteboardItem.self, NSURL.self], searchOptions: [:]
        ) { item, _, _ in
            item.setDraggingFrame(item.draggingFrame, contents: contents)
        }
    }

    /// The file icon with a small ⌥ badge in its top-right corner.
    static func badged(_ icon: NSImage, color: NSColor) -> NSImage {
        let side = iconSide
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            icon.draw(in: rect)
            let badge = NSRect(x: side - badgeSide, y: side - badgeSide, width: badgeSide, height: badgeSide)
            color.setFill()
            NSBezierPath(roundedRect: badge, xRadius: badgeRadius, yRadius: badgeRadius).fill()
            let text = NSAttributedString(
                string: optionGlyph,
                attributes: [
                    .font: NSFont.systemFont(ofSize: badgeFont, weight: .semibold), .foregroundColor: NSColor.black,
                ])
            let size = text.size()
            text.draw(at: NSPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2))
            return true
        }
    }

    static let badgeSide: CGFloat = 14
    static let badgeRadius: CGFloat = 4
    static let badgeFont: CGFloat = 9
    static let optionGlyph = "⌥"

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        icon = nil
        showsOptionBadge = false
        endDrag?(Self.operation(operation))
    }

    /// Move and copy (Finder picks with ⌥); generic for targets that only take that.
    static let operationMask: NSDragOperation = [.move, .copy, .generic]

    /// Move (or the Trash's delete, or a generic drop) → ``ShelfDragOperation/move``: the module removes the
    /// item only once its file has left; copy or link → copy; nothing → none.
    static func operation(_ operation: NSDragOperation) -> ShelfDragOperation {
        if operation.isEmpty { return .none }
        if !operation.intersection([.move, .delete, .generic]).isEmpty { return .move }
        return .copy
    }
}
