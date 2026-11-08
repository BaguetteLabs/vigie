import AppKit
import ModuleKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
import VigieUI
import os

/// The window side of the drop display: ``DropDisplayPanelController`` in the app, a recorder in tests.
@MainActor
public protocol DropDisplayPanelDriver: AnyObject {
    /// Shows `model` grown out of the notch of `anchor`, as a drag destination. Never becomes key.
    func present(_ model: DropDisplayModel, anchor: IslandAnchor)
    /// Retracts over `motion.exit` (instant under Reduce motion) and stops taking drags.
    func retract()
}

/// Esc while the drop display is open. A non-activating panel gets no key events, so the system monitor
/// listens globally (it needs the Accessibility permission Vigie already asks for; without it Esc reaches only
/// the drag itself, which AppKit cancels, and the display retracts on the drag exit).
@MainActor
public protocol DropEscapeMonitoring: AnyObject {
    func start(_ onEscape: @escaping @MainActor () -> Void)
    func stop()
}

/// The Notch Host's drag-only drop display (Story 9.1, AD-19, UX-DR83).
///
/// - Nothing happens until a file drag is over the island; then the display grows out of that display's notch
///   with the zones of the running modules (`NotchModule.dropZones`, no other registration path), minus the
///   zones whose `isEnabled` is off, laid out by ``DropGridLayoutEngine``. No zone → no display.
/// - It never takes focus: both panels are non-activating and never key (UX-DR45).
/// - Hovering a zone lights it when it accepts the dragged types (`DropZone.accepts(contentTypes:)`); ⌥ is read
///   from the modifier flags during the drag.
/// - Leaving both the island and the display, ending the drag without a drop, Esc or a release outside every
///   zone retracts it with no action.
/// - A release on an accepting zone materializes file promises into `<drops>/<UUID>/` first, then calls that
///   zone's handler exactly once, off the main actor, with `source = .dropDisplay` and the modifiers.
/// - Peeks wait while it is open (``isOpen``; `PeekPresenter` reads it) and resume through ``onClose``.
@MainActor @Observable
public final class DropDisplayController {
    /// True from the moment the display opens until it retracts.
    public private(set) var isOpen = false
    /// What the display shows while open.
    public private(set) var model: DropDisplayModel?
    /// The display it opened on (nil: the main Vigie display).
    public private(set) var displayID: CGDirectDisplayID?

    /// Called after every close (peeks queued meanwhile show then).
    @ObservationIgnored public var onClose: (@MainActor () -> Void)?
    /// The anchor of an island; set by the Notch Host.
    @ObservationIgnored var anchorProvider: @MainActor (CGDirectDisplayID?) -> IslandAnchor? = { _ in nil }
    /// The last handler run (zone, payload, result), for tests and the log.
    @ObservationIgnored public private(set) var lastDrop: (zoneID: String, payload: DropPayload, result: DropResult)?
    /// The drop in flight: materialization then the handler. Nil result: nothing was delivered.
    @ObservationIgnored public private(set) var pendingDrop: Task<DropResult?, Never>?

    @ObservationIgnored private let zones: @MainActor () -> [DropZone]
    @ObservationIgnored private let theme: @MainActor () -> Theme
    @ObservationIgnored private let dropsDirectory: URL?
    @ObservationIgnored private let escape: any DropEscapeMonitoring
    @ObservationIgnored private let modifierFlags: @MainActor () -> NSEvent.ModifierFlags
    @ObservationIgnored private let exitGrace: Duration
    @ObservationIgnored private let logger: Logger
    @ObservationIgnored private let makeDriver: @MainActor (DropDisplayController) -> any DropDisplayPanelDriver
    @ObservationIgnored private var driverStorage: (any DropDisplayPanelDriver)?

    @ObservationIgnored private var openZones: [String: DropZone] = [:]
    @ObservationIgnored private var contentTypes: [UTType] = []
    @ObservationIgnored private var sourceOperations: NSDragOperation = []
    @ObservationIgnored private var sequence: Int?
    @ObservationIgnored private var cancelledSequence: Int?
    @ObservationIgnored private var insideIsland = false
    @ObservationIgnored private var insideDisplay = false
    @ObservationIgnored private var exitTask: Task<Void, Never>?
    @ObservationIgnored private var simulationTask: Task<Void, Never>?

    /// How long after leaving one panel the drag may enter the other before the display retracts (the island
    /// reports an exit when the display opens over it).
    public static let defaultExitGrace: Duration = .milliseconds(150)

    /// - Parameters:
    ///   - zones: every running module's `dropZones`, read each time a drag arrives.
    ///   - theme: the display theme (metrics for hit-testing).
    ///   - dropsDirectory: `AppEnvironment.dropsDirectory`; nil refuses file promises.
    ///   - escape: Esc while open; ``SystemDropEscapeMonitor`` by default.
    ///   - modifierFlags: the keyboard modifiers now; `NSEvent.modifierFlags` by default.
    ///   - makeDriver: builds the panel; a ``DropDisplayPanelController`` by default.
    public init(
        zones: @escaping @MainActor () -> [DropZone],
        theme: @escaping @MainActor () -> Theme,
        dropsDirectory: URL?,
        escape: (any DropEscapeMonitoring)? = nil,
        modifierFlags: @escaping @MainActor () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags },
        exitGrace: Duration = DropDisplayController.defaultExitGrace,
        makeDriver: @escaping @MainActor (DropDisplayController) -> any DropDisplayPanelDriver,
        logger: Logger
    ) {
        self.zones = zones
        self.theme = theme
        self.dropsDirectory = dropsDirectory
        self.escape = escape ?? SystemDropEscapeMonitor()
        self.modifierFlags = modifierFlags
        self.exitGrace = exitGrace
        self.makeDriver = makeDriver
        self.logger = logger
    }

    private var driver: any DropDisplayPanelDriver {
        if let driverStorage { return driverStorage }
        let made = makeDriver(self)
        driverStorage = made
        return made
    }

    // MARK: Zones

    /// The enabled zones of the running modules, first declaration of an id wins.
    public func enabledZones() -> [DropZone] {
        var seen: Set<String> = []
        return zones().filter { zone in
            guard zone.isEnabled else { return false }
            guard seen.insert(zone.id).inserted else {
                logger.error("Drop zone \(zone.id, privacy: .public) declared twice; the first one is used")
                return false
            }
            return true
        }
    }

    /// A `DropZone` as the display draws it.
    public static func displayZone(_ zone: DropZone) -> DropDisplayZone {
        DropDisplayZone(
            id: zone.id, label: zone.label, glyph: zone.glyph,
            accent: ColorRole(rawValue: zone.accentToken) ?? .iris2,
            style: zone.style == .target ? .target : .standard, isPrimary: zone.role == .primary, meta: zone.meta,
            releaseLine: zone.releaseLine, accessibilityLabel: zone.accessibilityLabel ?? zone.label,
            hint: zone.modifierHint?.idle, hintActive: zone.modifierHint?.active)
    }

    // MARK: Island (drag destination on the closed notch)

    /// A file drag entered the island of `displayID`: opens the display unless no zone is enabled.
    public func islandDragEntered(displayID: CGDirectDisplayID?, items: DropDragItems) -> NSDragOperation {
        guard items.hasFiles, items.sequence != cancelledSequence else { return [] }
        insideIsland = true
        exitTask?.cancel()
        if !isOpen, !open(displayID: displayID, items: items, zones: enabledZones()) { return [] }
        return DropDragItems.operation(for: items.sourceOperations)
    }

    public func islandDragExited() {
        insideIsland = false
        scheduleExitCheck()
    }

    // MARK: Display (drag destination on the drop display)

    /// The drag entered the display at `point` (display coordinates, top-left origin).
    public func displayDragEntered(at point: CGPoint) -> NSDragOperation {
        guard isOpen else { return [] }
        insideDisplay = true
        exitTask?.cancel()
        return displayDragUpdated(at: point)
    }

    /// The drag moved (or a modifier changed): hover, lit state, ⌥.
    public func displayDragUpdated(at point: CGPoint) -> NSDragOperation {
        guard isOpen, let model else { return [] }
        let id = zoneID(at: point)
        let accepts = id.flatMap { openZones[$0] }?.accepts(contentTypes: contentTypes) ?? false
        if model.hoveredZoneID != id { model.hoveredZoneID = id }
        if model.hoveredAccepts != accepts { model.hoveredAccepts = accepts }
        let option = modifierFlags().contains(.option)
        if model.optionHeld != option { model.optionHeld = option }
        return accepts ? DropDragItems.operation(for: sourceOperations) : []
    }

    public func displayDragExited() {
        insideDisplay = false
        if let model {
            model.hoveredZoneID = nil
            model.hoveredAccepts = false
        }
        scheduleExitCheck()
    }

    /// The drag was released over the display at `point`. On an accepting zone: materializes promises, then
    /// runs that zone's handler once (``pendingDrop``). Elsewhere: no action. The display retracts either way.
    @discardableResult
    public func performDrop(at point: CGPoint, items: DropDragItems) -> Bool {
        guard isOpen else { return false }
        defer { close() }
        guard let id = zoneID(at: point), let zone = openZones[id] else {
            logger.debug("Drop released outside every zone; no action")
            return false
        }
        guard zone.accepts(contentTypes: items.contentTypes) else {
            logger.debug("Drop zone \(id, privacy: .public) does not take the dragged items")
            return false
        }
        let modifiers = Self.eventModifiers(modifierFlags())
        let pending: FilePromiseMaterializer.PendingFiles
        do {
            pending = try FilePromiseMaterializer.start(items.promises, in: dropsDirectory)
        } catch {
            logger.error("File promises not materialized: \(String(describing: error), privacy: .public)")
            guard !items.fileURLs.isEmpty else { return false }
            pending = .empty
        }
        let urls = items.fileURLs
        let logger = logger
        pendingDrop = Task { @MainActor [weak self] in
            let promised = await pending.files()
            for error in promised.errors {
                logger.error("File promise failed: \(error, privacy: .public)")
            }
            let all = urls + promised.urls
            guard !all.isEmpty else {
                logger.error("Drop on \(id, privacy: .public) delivered no file; handler not called")
                return nil
            }
            let payload = DropPayload(urls: all, modifiers: modifiers, source: .dropDisplay)
            let handler = zone.handler
            let result = await Task.detached { await handler(payload) }.value
            self?.lastDrop = (id, payload, result)
            switch result {
            case .accepted: logger.info("Drop on \(id, privacy: .public) accepted")
            case .rejected: logger.info("Drop on \(id, privacy: .public) rejected by its module")
            case .failed: logger.error("Drop on \(id, privacy: .public) failed")
            }
            return result
        }
        return true
    }

    /// The drag session ended (dropped anywhere, or cancelled): retracts if still open.
    public func dragEnded() {
        cancelledSequence = nil
        insideIsland = false
        insideDisplay = false
        close()
    }

    /// Esc: retracts with no action; the same drag does not reopen it.
    public func cancel() {
        guard isOpen else { return }
        cancelledSequence = sequence
        logger.debug("Drop display cancelled")
        close()
    }

    // MARK: Debug

    /// `-VigieSimulateDrop YES`: opens the display with `zones` for `duration` on the main Vigie display, as if a
    /// file were dragged over the notch (screenshots).
    public func simulate(zones: [DropZone], hovered: String? = nil, for duration: Duration) {
        let items = DropDragItems(fileURLs: [URL(fileURLWithPath: "/simulated.png")], count: 1, sequence: -1)
        guard open(displayID: nil, items: items, zones: zones) else { return }
        if let hovered, let model {
            model.hoveredZoneID = hovered
            model.hoveredAccepts = true
        }
        simulationTask?.cancel()
        simulationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }

    // MARK: Open / close

    private func open(displayID: CGDirectDisplayID?, items: DropDragItems, zones: [DropZone]) -> Bool {
        guard let layout = DropGridLayoutEngine.layout(zones.map(DropLayoutInput.init)) else {
            logger.debug("No enabled drop zone; no drop display")
            return false
        }
        guard let anchor = anchorProvider(displayID) else {
            logger.info("No island to anchor the drop display")
            return false
        }
        let placed = Set(layout.zoneIDs)
        openZones = Dictionary(
            zones.filter { placed.contains($0.id) }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        contentTypes = items.contentTypes
        sourceOperations = items.sourceOperations
        sequence = items.sequence
        self.displayID = displayID
        let model = DropDisplayModel(
            layout: layout, zones: layout.zoneIDs.compactMap { openZones[$0].map(Self.displayZone) },
            itemCount: max(items.count, 1), optionHeld: modifierFlags().contains(.option), isRevealed: false)
        self.model = model
        isOpen = true
        driver.present(model, anchor: anchor)
        escape.start { [weak self] in self?.cancel() }
        return true
    }

    private func close() {
        guard isOpen else { return }
        isOpen = false
        exitTask?.cancel()
        exitTask = nil
        simulationTask?.cancel()
        simulationTask = nil
        escape.stop()
        driver.retract()
        openZones = [:]
        contentTypes = []
        insideIsland = false
        insideDisplay = false
        model = nil
        displayID = nil
        onClose?()
    }

    private func scheduleExitCheck() {
        guard isOpen else { return }
        exitTask?.cancel()
        let grace = exitGrace
        exitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: grace)
            guard !Task.isCancelled, let self, !self.insideIsland, !self.insideDisplay else { return }
            self.logger.debug("Drag left the notch and the drop display; retracting")
            self.close()
        }
    }

    private func zoneID(at point: CGPoint) -> String? {
        guard let model else { return nil }
        return DropDisplayGeometry.zone(at: point, in: DropDisplayGeometry.zoneFrames(model.layout, theme: theme()))
    }

    /// AppKit modifier flags as SwiftUI `EventModifiers` (the `DropPayload` type).
    public static func eventModifiers(_ flags: NSEvent.ModifierFlags) -> EventModifiers {
        var modifiers: EventModifiers = []
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.capsLock) { modifiers.insert(.capsLock) }
        return modifiers
    }
}

/// Esc through global and local key-down monitors, only while the display is open.
@MainActor
public final class SystemDropEscapeMonitor: DropEscapeMonitoring {
    private var monitors: [Any] = []
    private static let escapeKeyCode: UInt16 = 53

    public init() {}

    public func start(_ onEscape: @escaping @MainActor () -> Void) {
        stop()
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: .keyDown,
            handler: { event in
                guard event.keyCode == Self.escapeKeyCode else { return }
                MainActor.assumeIsolated { onEscape() }
            })
        {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown,
            handler: { event in
                guard event.keyCode == Self.escapeKeyCode else { return event }
                MainActor.assumeIsolated { onEscape() }
                return nil
            })
        {
            monitors.append(local)
        }
    }

    public func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }
}
