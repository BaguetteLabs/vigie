import AppKit

/// Peeks grow from the island on the display under the pointer, else from the main Vigie display (FR23,
/// Story 3.2). The main display is the first island anchor (the notched display, or the one `display` names).
extension NotchHost: PeekAnchorProvider {
    public func anchor(forDisplayUnder pointer: NSPoint?) -> PeekAnchor? {
        let islands = islandAnchors.map(Self.peekAnchor(for:))
        return PeekAnchor.select(pointer: pointer, islands: islands, main: islands.first)
    }

    static func peekAnchor(for island: IslandAnchor) -> PeekAnchor {
        PeekAnchor(screenFrame: island.screenFrame, notchRect: island.notchRect, bandHeight: island.islandFrame.height)
    }
}

/// App assembly builds the `PeekPresenter` (an `AlertCenter` sink) before the host exists; the link forwards
/// to the host once it is set, and supplies no anchor before (the peek is then skipped).
extension NotchHostLink: PeekAnchorProvider {
    public func anchor(forDisplayUnder pointer: NSPoint?) -> PeekAnchor? {
        host?.anchor(forDisplayUnder: pointer)
    }
}
