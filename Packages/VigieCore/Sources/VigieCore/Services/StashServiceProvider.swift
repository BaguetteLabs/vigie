import AppKit
import ModuleKit
import os

/// The macOS Services entry `Stash in Vigie` (Story 9.10, AD-19, AD-20): `NSApp.servicesProvider`, declared in
/// the app's Info.plist under `NSServices` (`NSMessage = stashInVigie`). The service pasteboard becomes a
/// ``DropPayload`` with `source = .service` (``PasteboardReader``) and goes to the enabled primary zone (Stash)
/// through the drop zone directory, so the readout is the same as a drop. Vigie is not activated and the
/// expanded view does not open.
///
/// With the Shelf off (no enabled primary zone) nothing is stashed and a `setup.problem` alert `Shelf is off`
/// offers Open settings › Shelf.
@MainActor
public final class StashServiceProvider: NSObject {
    /// What one service request did.
    public enum Outcome: Equatable, Sendable {
        /// Handed to the Stash zone.
        case stashed(zoneID: String)
        /// The Shelf is off: the setup problem was posted.
        case shelfOff
        /// The pasteboard held nothing the Stash takes.
        case empty
    }

    /// The `NSMessage` of the Info.plist entry.
    public nonisolated static let message = "stashInVigie"
    /// Settings pane of the Shelf module.
    public nonisolated static let shelfPane = "shelf"
    public nonisolated static let shelfOffDedupeKey = "service.shelf-off"

    private let directory: any DropZoneDirectory
    private let notifier: any Notifier
    private let logger: Logger
    /// The last request's handler run (tests).
    public private(set) var pending: Task<DropResult, Never>?

    /// - Parameters:
    ///   - directory: the running modules' zones (``CoreDropZoneDirectory`` in the app).
    ///   - notifier: the core notifier (setup problems).
    public init(directory: any DropZoneDirectory, notifier: any Notifier, logger: Logger) {
        self.directory = directory
        self.notifier = notifier
        self.logger = logger
    }

    /// `stashInVigie:userData:error:`, called by AppKit on the main thread.
    @objc public func stashInVigie(
        _ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        switch handle(pasteboard) {
        case .stashed, .shelfOff: break
        case .empty: error.pointee = Self.text("vigiecore.service.stash.empty") as NSString
        }
    }

    /// Reads `pasteboard` now (it is valid only during the call) and routes it.
    @discardableResult
    public func handle(_ pasteboard: NSPasteboard) -> Outcome {
        guard let zoneID = directory.zones().first(where: { $0.isEnabled && $0.role == .primary })?.id else {
            logger.notice("Stash in Vigie: the Shelf is off; nothing stashed")
            notifier.post(Self.shelfOffEvent())
            return .shelfOff
        }
        guard let payload = PasteboardReader.payload(from: pasteboard, source: .service) else {
            logger.info("Stash in Vigie: nothing usable on the service pasteboard")
            return .empty
        }
        let directory = directory
        pending = Task { @MainActor in await directory.perform(zoneID: zoneID, payload: payload) }
        logger.info("Stash in Vigie: routed to \(zoneID, privacy: .public)")
        return .stashed(zoneID: zoneID)
    }

    /// `SETUP · SHELF`: "Shelf is off", Open settings › Shelf.
    public nonisolated static func shelfOffEvent() -> NotifierEvent {
        NotifierEvent(
            kind: SetupProblemReporter.alertKind, severity: .warn,
            title: text("vigiecore.service.shelfOff.title"),
            body: text("vigiecore.service.shelfOff.body"),
            action: .openSettings(pane: shelfPane), dedupeKey: shelfOffDedupeKey,
            category: text("vigiecore.setup.category.shelf"))
    }

    nonisolated static func text(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }
}
