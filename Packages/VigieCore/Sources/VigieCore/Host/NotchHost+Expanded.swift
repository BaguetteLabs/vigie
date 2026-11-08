import AppKit
import ModuleKit
import SwiftUI
import VigieUI

/// The expanded view (Story 2.10, SPEC §10, EXPERIENCE "Expanded view").
///
/// It opens only from three places, and never by itself (UX-DR41):
/// - a click on the island (``islandClicked()``), with a click `UserIntent`: takes keyboard focus;
/// - the expand hotkey (``toggleExpanded(focus:)``), with the hotkey's intent: takes keyboard focus;
/// - with `open_on_hover`, a hover longer than `hover_delay` (``islandHoverChanged(_:)``): no focus.
/// App assembly also routes a second launch (`app.expand`) to ``expand(focus:)`` without focus, and modules
/// reach it through `context.host` only with an intent (``CoreHostControl``).
///
/// It collapses on Esc while key (``handleEscape()``, through ``FocusPolicy``), a click outside, the hotkey
/// again and, with `close_on_leave`, when the pointer leaves the panel and island.
extension NotchHost {
    /// `[general] hover_delay` default (SPEC §11).
    public static let defaultHoverDelay: Duration = .milliseconds(150)

    /// True while the expanded view holds keyboard focus.
    public var isExpandedKey: Bool { focusPolicy.isKey(expandedSurface) }

    /// The tabs: Home first, always (FR89, Story 11.1), then running modules with an `expandedView()` in
    /// `[general] tab_order` (A12, A74). A module in `alert` carries the attention marker.
    public var expandedTabs: [ExpandedTab] {
        _ = registry.statuses  // module starts and stops
        let tabs = registry.runningModules.compactMap(ExpandedTabOrder.tab(for:))
            .filter { $0.id != ExpandedTab.homeID }
        return [.home] + ExpandedTabOrder.ordered(tabs, by: tabOrder())
    }

    /// The body of a tab: Home's grid, or its module's `expandedView()`.
    public func expandedContent(for tabID: String) -> AnyView? {
        if tabID == ExpandedTab.homeID { return homeContent() }
        return registry.runningModules.first { $0.manifest.id.rawValue == tabID }?.expandedView()
    }

    // MARK: Open and close

    /// Opens the expanded view on the display under the pointer (or the main Vigie display), on Home every time
    /// (FR87), whichever tab it was left on. With `focus` it becomes the key surface; without, it shows without focus. When it is
    /// already open, `focus` makes it key.
    public func expand(focus: UserIntent?) {
        if isExpanded {
            if focus != nil, !isExpandedKey { focusPolicy.present(expandedSurface, focus: focus) }
            return
        }
        guard let anchor = anchor(forDisplayUnder: pointerLocation()) else {
            logger.info("expand: no island on screen")
            return
        }
        hoverTask?.cancel()
        hoverTask = nil
        hideTask?.cancel()
        hideTask = nil
        expansionGeneration += 1
        let frame = anchor.panelFrame(size: themeController.theme.expandedPanelSize)
        expansionOrigin = anchor.islandFrame.size
        selectedTabID = ExpandedTab.homeID
        let panel = expandedPanel ?? makeExpandedPanel(self)
        expandedPanel = panel
        isExpanded = true
        panel.show(panelFrame: frame)
        focusPolicy.present(expandedSurface, focus: focus)
        pointerWasInside = expandedRegionContains(pointerLocation())
        installExpandedMonitors()
    }

    /// Opens the expanded view on a module's tab.
    public func openTab(_ tabID: String, focus: UserIntent?) {
        expand(focus: focus)
        if isExpanded, expandedTabs.contains(where: { $0.id == tabID }) { selectedTabID = tabID }
    }

    /// Collapses the expanded view over `motion.exit` (instant under Reduce motion), then orders it out.
    public func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        removeExpandedMonitors()
        hoverTask?.cancel()
        hoverTask = nil
        focusPolicy.dismissed(expandedSurface)
        expandedPanel?.dropKey()
        let generation = expansionGeneration
        let theme = themeController.theme
        let delay = ExpansionStyle(theme: theme).collapseDuration(theme)
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self, !self.isExpanded, self.expansionGeneration == generation else { return }
            self.expandedPanel?.hide()
            self.hideTask = nil
        }
    }

    /// The expand hotkey: opens with focus, or closes. When the view is open without focus (hover), the hotkey
    /// gives it focus instead of closing it.
    public func toggleExpanded(focus: UserIntent?) {
        if isExpanded, isExpandedKey || focus == nil {
            collapse()
        } else {
            expand(focus: focus)
        }
    }

    /// Esc: closes the key surface only (``FocusPolicy/handleEscape()``). Returns true when it closed one.
    @discardableResult
    public func handleEscape() -> Bool {
        focusPolicy.handleEscape()
    }

    // MARK: Pointer

    /// Left click on the closed island.
    func islandClicked() {
        expand(focus: UserIntentMinter.mint(source: .click))
    }

    /// Hover over the closed island. With `open_on_hover`, opens without focus after `hover_delay`; leaving
    /// before then cancels.
    func islandHoverChanged(_ hovering: Bool) {
        transientHoverChanged(hovering)
        hoverTask?.cancel()
        hoverTask = nil
        guard hovering, !isExpanded, openOnHover() else { return }
        let delay = hoverDelay()
        let clock = clock
        hoverTask = Task { @MainActor [weak self] in
            try? await clock.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.hoverTask = nil
            self.expand(focus: nil)
        }
    }

    /// A mouse down in the expanded panel window. On the shadow margin it is a click outside; on the panel
    /// opened without focus it is a deliberate click and takes focus.
    func expandedPanelMouseDown(at point: CGPoint) {
        guard isExpanded else { return }
        if let frame = expandedPanel?.panelFrame, !Self.contains(frame, point) {
            collapse()
        } else if !isExpandedKey {
            focusPolicy.present(expandedSurface, focus: UserIntentMinter.mint(source: .click))
        }
    }

    /// A mouse down anywhere but the expanded panel (another app, the menu bar, another Vigie window).
    func mouseDownOutsideExpanded() {
        collapse()
    }

    /// The pointer moved. With `close_on_leave`, leaving the panel and island collapses the view.
    func pointerMoved(to point: CGPoint) {
        guard isExpanded else { return }
        let inside = expandedRegionContains(point)
        defer { pointerWasInside = inside }
        if pointerWasInside, !inside, closeOnLeave() { collapse() }
    }

    func expandedPanelDidResignKey() {
        focusPolicy.surfaceDidResignKey(expandedSurface)
    }

    private func expandedRegionContains(_ point: CGPoint) -> Bool {
        let island = anchor(forDisplayUnder: point)?.islandFrame
        return [expandedPanel?.panelFrame, island].contains { $0.map { Self.contains($0, point) } ?? false }
    }

    /// Inclusive of the edges (the pointer pinned to the top screen edge is inside the island).
    static func contains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }

    // MARK: Event monitors

    private func installExpandedMonitors() {
        removeExpandedMonitors()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: clicks,
            handler: { _ in
                MainActor.assumeIsolated { [weak self] in self?.mouseDownOutsideExpanded() }
            })
        {
            eventMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: clicks,
            handler: { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let window = event.window, window === self.expandedPanel as AnyObject { return }
                    self.mouseDownOutsideExpanded()
                }
                return event
            })
        {
            eventMonitors.append(local)
        }
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: moves,
            handler: { _ in
                MainActor.assumeIsolated { [weak self] in self?.pointerMoved(to: NSEvent.mouseLocation) }
            })
        {
            eventMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: moves,
            handler: { [weak self] event in
                MainActor.assumeIsolated { self?.pointerMoved(to: NSEvent.mouseLocation) }
                return event
            })
        {
            eventMonitors.append(local)
        }
    }

    func removeExpandedMonitors() {
        for monitor in eventMonitors { NSEvent.removeMonitor(monitor) }
        eventMonitors.removeAll()
    }
}
