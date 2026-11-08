import AppKit
import SwiftUI

/// The row's drag-out handle (FR59, UX-DR50): an AppKit dragging source over the grip, because SwiftUI's
/// `onDrag` does not report how a drag ended. The drag offers move and copy; Finder moves on the same volume
/// and copies with ⌥ held (or onto another volume), and ``ShelfDragOperation`` carries its answer back.
struct ShelfDragHandle: NSViewRepresentable {
    let beginDrag: @MainActor () -> URL?
    let endDrag: @MainActor (ShelfDragOperation) -> Void

    func makeNSView(context: Context) -> ShelfDragSourceView {
        let view = ShelfDragSourceView()
        view.beginDrag = beginDrag
        view.endDrag = endDrag
        return view
    }

    func updateNSView(_ view: ShelfDragSourceView, context: Context) {
        view.beginDrag = beginDrag
        view.endDrag = endDrag
    }
}

final class ShelfDragSourceView: NSView, NSDraggingSource {
    /// Pointer travel before a press becomes a drag (points).
    static let dragThreshold: CGFloat = 3
    /// The file icon under the pointer while dragging.
    static let iconSide: CGFloat = 32

    var beginDrag: (@MainActor () -> URL?)?
    var endDrag: (@MainActor (ShelfDragOperation) -> Void)?
    private var pressed: NSEvent?

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
        item.setDraggingFrame(
            NSRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side),
            contents: NSWorkspace.shared.icon(forFile: url.path))
        let session = beginDraggingSession(with: [item], event: pressed, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        Self.operationMask
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
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
