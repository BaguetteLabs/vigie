import AppKit
import SwiftUI

/// One entry of a Shelf row's `Send to` menu (Story 9.10, UX-DR102): the enabled zones that take the item
/// (Ask AI, Ask AI in alternate folder, AirDrop, Image to Text), then Quick Look, Reveal and Pin / Unpin. The
/// same entries are the row's VoiceOver custom actions.
public struct ShelfMenuEntry: Identifiable, Sendable {
    public enum Action: Sendable {
        /// Runs a zone with the item and `source = .stashItem`, these modifiers held (⌥: alternate folder).
        case send(zoneID: String, modifiers: EventModifiers)
        case quickLook
        case reveal
        case togglePin
    }

    public let id: String
    /// Menu title, sentence case ("Ask AI in alternate folder").
    public let title: String
    public let action: Action

    public init(id: String, title: String, action: Action) {
        self.id = id
        self.title = title
        self.action = action
    }

    /// The zone entries, then Quick Look, Reveal and Pin (Unpin for a pinned item).
    public static func entries(sendTo: [ShelfMenuEntry], isPinned: Bool) -> [ShelfMenuEntry] {
        sendTo + [
            ShelfMenuEntry(id: "quick_look", title: L10n.string("shelf.menu.quickLook"), action: .quickLook),
            ShelfMenuEntry(id: "reveal", title: L10n.string("shelf.menu.reveal"), action: .reveal),
            ShelfMenuEntry(
                id: "pin", title: L10n.string(isPinned ? "shelf.menu.unpin" : "shelf.menu.pin"), action: .togglePin),
        ]
    }

    /// Runs the entry for `item` through the tab's actions.
    @MainActor public func perform(on item: UUID, _ actions: ShelfTabActions) {
        switch action {
        case .send(let zoneID, let modifiers): actions.send(item, zoneID, modifiers)
        case .quickLook: actions.quickLook(item)
        case .reveal: actions.reveal(item)
        case .togglePin: actions.togglePin(item)
        }
    }
}

/// Pops the row's `Send to` menu as an `NSMenu` when ↵ asks for it (a SwiftUI context menu cannot be opened
/// from the keyboard). `token` changes once per request.
struct ShelfMenuAnchor: NSViewRepresentable {
    let token: Int?
    let entries: @MainActor () -> [ShelfMenuEntry]
    let run: @MainActor (ShelfMenuEntry) -> Void

    func makeNSView(context: Context) -> ShelfMenuAnchorView {
        let view = ShelfMenuAnchorView()
        view.shownToken = token
        return view
    }

    func updateNSView(_ view: ShelfMenuAnchorView, context: Context) {
        guard let token, token != view.shownToken else { return }
        view.shownToken = token
        let entries = entries()
        let run = run
        DispatchQueue.main.async { MainActor.assumeIsolated { view.popUp(entries, run: run) } }
    }
}

final class ShelfMenuAnchorView: NSView {
    var shownToken: Int?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func popUp(_ entries: [ShelfMenuEntry], run: @escaping @MainActor (ShelfMenuEntry) -> Void) {
        guard window != nil else { return }
        let menu = Self.menu(entries, run: run)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.minY), in: self)
    }

    /// The `NSMenu` of the entries; each item runs its entry.
    static func menu(_ entries: [ShelfMenuEntry], run: @escaping @MainActor (ShelfMenuEntry) -> Void) -> NSMenu {
        let menu = NSMenu(title: L10n.string("shelf.menu.title"))
        menu.autoenablesItems = false
        var sawZone = false
        for entry in entries {
            if case .send = entry.action {
                sawZone = true
            } else if sawZone {
                menu.addItem(.separator())
                sawZone = false
            }
            let target = ShelfMenuTarget { run(entry) }
            let item = NSMenuItem(title: entry.title, action: #selector(ShelfMenuTarget.run), keyEquivalent: "")
            item.target = target
            item.representedObject = target
            menu.addItem(item)
        }
        return menu
    }
}

/// An `NSMenuItem` target running a closure (kept alive by the item's `representedObject`).
final class ShelfMenuTarget: NSObject {
    private let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @MainActor @objc func run() { action() }
}
