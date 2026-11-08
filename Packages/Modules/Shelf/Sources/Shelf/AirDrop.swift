import AppKit
import Foundation
import ModuleKit
import UniformTypeIdentifiers
import VigieUI

/// Sends files with AirDrop. ``SystemAirDrop`` wraps `NSSharingService(named: .sendViaAirDrop)`; tests use a
/// fake and never reach the real service.
@MainActor
public protocol AirDropSharing: AnyObject {
    /// False when AirDrop can't start a share for these files.
    func canShare(_ urls: [URL]) -> Bool
    /// Opens the system AirDrop picker for the files. Wi-Fi or Bluetooth off is explained by the system.
    func share(_ urls: [URL])
}

/// The system AirDrop sharing service.
@MainActor
public final class SystemAirDrop: AirDropSharing {
    private lazy var service = NSSharingService(named: .sendViaAirDrop)

    public init() {}

    public func canShare(_ urls: [URL]) -> Bool {
        service?.canPerform(withItems: urls) ?? false
    }

    public func share(_ urls: [URL]) {
        service?.perform(withItems: urls)
    }
}

/// The AirDrop zone (Story 9.8, PRD FR-33).
extension ShelfModule {
    /// The AirDrop zone id.
    public nonisolated static let airDropZoneID = "shelf.airdrop"
    /// `[modules.shelf] airdrop` (default on).
    nonisolated static let airDropSetting = "airdrop"
    /// Activity entry kind of an AirDrop share that could not start.
    nonisolated static let airDropActivityKind = "shelf.airdrop"

    /// True when `airdrop` is on (the default).
    var isAirDropOn: Bool { settings?.value(Self.airDropSetting, as: Bool.self) ?? true }

    /// Column 4 row 1, order 20; takes files (any type, file promises included), never loose text, links or
    /// images; hidden while `airdrop` is off or the module is stopped (Image to Text then spans column 4).
    public var airDropZone: DropZone {
        DropZone(
            id: Self.airDropZoneID,
            label: ShelfText.resource("shelf.airdrop.label"),
            glyph: "drop.airdrop",
            accentToken: "iris-2",
            role: .secondary,
            cell: DropCell(preferredColumn: 4, preferredRow: 1, span: .init(columns: 1, rows: 1)),
            order: 20,
            accepts: [.item],
            handler: { [weak self] payload in await self?.airDrop(payload) ?? .rejected },
            meta: ShelfText.resource("shelf.airdrop.meta"),
            releaseLine: ShelfText.resource("shelf.airdrop.release"),
            accessibilityLabel: ShelfText.resource("shelf.airdrop.a11y"),
            isEnabled: isRunning && isAirDropOn)
    }

    /// The zone as the `SEND TO` card's 38px mini zone (meta `SHARE`, Story 9.7); nil while hidden.
    public var airDropMiniZone: DropDisplayZone? {
        guard isRunning, isAirDropOn else { return nil }
        return DropDisplayZone(
            id: Self.airDropZoneID, label: ShelfText.resource("shelf.airdrop.label"), glyph: "drop.airdrop",
            accent: .iris2, style: .standard, isPrimary: false, meta: ShelfText.resource("shelf.airdrop.miniMeta"),
            releaseLine: ShelfText.resource("shelf.airdrop.release"),
            accessibilityLabel: ShelfText.resource("shelf.airdrop.a11y"))
    }

    /// The `SEND TO` card's mini zones, top to bottom: AirDrop, then Image to Text; hidden ones left out.
    public var sendToMiniZones: [DropDisplayZone] { [airDropMiniZone, imageToTextMiniZone].compactMap { $0 } }

    /// The zone handler: opens the AirDrop picker for the dropped files; nothing is added to the shelf. When
    /// the share can't start (an unreadable file, AirDrop can't take the items) the left wing reads
    /// `AIRDROP UNAVAILABLE` and an activity entry is written; no alert.
    public func airDrop(_ payload: DropPayload) async -> DropResult {
        guard isRunning, isAirDropOn else { return .rejected }
        let urls = payload.urls
        guard !urls.isEmpty else { return .rejected }
        if let unreadable = urls.first(where: { !FileManager.default.isReadableFile(atPath: $0.path) }) {
            return airDropUnavailable(reason: "unreadable", count: urls.count, name: unreadable.lastPathComponent)
        }
        let service = airDropService
        guard service.canShare(urls) else {
            return airDropUnavailable(reason: "cannot_share", count: urls.count, name: nil)
        }
        service.share(urls)
        log?.info("AirDrop picker opened for \(urls.count, privacy: .public) item(s)")
        return .accepted
    }

    private func airDropUnavailable(reason: String, count: Int, name: String?) -> DropResult {
        log?.notice("AirDrop unavailable: \(reason, privacy: .public)")
        var detail = ["reason": reason, "items": String(count)]
        if let name { detail["name"] = name }
        activity?.record(
            ActivityEntry(
                at: now(), category: .module, kind: Self.airDropActivityKind, outcome: .custom("unavailable"),
                detail: detail))
        return .readout(ShelfText.resource("shelf.airdrop.unavailable"))
    }
}
