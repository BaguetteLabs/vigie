import Foundation
import ModuleKit
import UniformTypeIdentifiers
import VigieUI

/// One Image to Text copy: how many lines, and when (the `SEND TO` card meta `LAST · 3 LINES · 14:48`).
public struct ImageToTextRun: Hashable, Sendable {
    public let lines: Int
    public let at: Date
}

/// The Image to Text zone (Story 9.9, PRD FR-34, DESIGN "Copied readout").
extension ShelfModule {
    /// The Image to Text zone id.
    public nonisolated static let imageToTextZoneID = "shelf.image_to_text"
    /// `[modules.shelf] image_to_text` (default off).
    nonisolated static let imageToTextSetting = "image_to_text"
    /// Activity entry kind of a failed recognition.
    nonisolated static let imageToTextActivityKind = "shelf.image_to_text"
    /// The types the zone takes: images and PDFs (and loose image data).
    public nonisolated static let imageToTextTypes: [UTType] = [.image, .pdf]

    /// True when `image_to_text` is on.
    var isImageToTextOn: Bool { settings?.value(Self.imageToTextSetting, as: Bool.self) ?? false }

    /// Column 4 row 2, order 30; lit only for an image or PDF; hidden while `image_to_text` is off or the
    /// module is stopped (AirDrop then spans column 4).
    public var imageToTextZone: DropZone {
        DropZone(
            id: Self.imageToTextZoneID,
            label: ShelfText.resource("shelf.imageToText.label"),
            glyph: "drop.image-to-text",
            accentToken: "iris-2",
            role: .secondary,
            cell: DropCell(preferredColumn: 4, preferredRow: 2, span: .init(columns: 1, rows: 1)),
            order: 30,
            accepts: Self.imageToTextTypes,
            handler: { [weak self] payload in await self?.imageToText(payload) ?? .rejected },
            meta: ShelfText.resource("shelf.imageToText.meta"),
            releaseLine: ShelfText.resource("shelf.imageToText.release"),
            accessibilityLabel: ShelfText.resource("shelf.imageToText.a11y"),
            isEnabled: isRunning && isImageToTextOn,
            looseContent: [.image],
            progressReadout: ShelfText.resource("shelf.imageToText.reading"))
    }

    /// The zone as the `SEND TO` card's 38px mini zone (meta `COPY`, Story 9.7); nil while hidden.
    public var imageToTextMiniZone: DropDisplayZone? {
        guard isRunning, isImageToTextOn else { return nil }
        return DropDisplayZone(
            id: Self.imageToTextZoneID, label: ShelfText.resource("shelf.imageToText.label"),
            glyph: "drop.image-to-text", accent: .iris2, style: .standard, isPrimary: false,
            meta: ShelfText.resource("shelf.imageToText.miniMeta"),
            releaseLine: ShelfText.resource("shelf.imageToText.release"),
            accessibilityLabel: ShelfText.resource("shelf.imageToText.a11y"))
    }

    /// The zone handler: recognizes off the main actor, copies the text, answers with the readout. Promise
    /// files the host materialized for this drop are deleted afterwards (never the user's own files).
    public func imageToText(_ payload: DropPayload) async -> DropResult {
        guard isRunning, isImageToTextOn else { return .rejected }
        let sources = Self.textSources(payload)
        guard !sources.isEmpty else { return .rejected }
        let recognizer = recognizer
        let outcome = await Task.detached(priority: .userInitiated) { () -> Result<[String], any Error> in
            Result { try sources.flatMap { try recognizer.lines(in: $0) } }
        }.value
        Self.deleteMaterialized(payload)
        switch outcome {
        case .success(let lines) where !lines.isEmpty:
            clipboard?.copy(lines.joined(separator: "\n"), clearAfter: nil)
            lastImageToText = ImageToTextRun(lines: lines.count, at: now())
            log?.info("Image to Text copied \(lines.count, privacy: .public) line(s)")
            return Self.copiedResult(lines: lines.count)
        case .success:
            log?.info("Image to Text found no text")
            return Self.noTextResult
        case .failure(let error):
            log?.error("Image to Text failed: \(String(describing: error), privacy: .public)")
            activity?.record(
                ActivityEntry(
                    at: now(), category: .module, kind: Self.imageToTextActivityKind, outcome: .custom("failed"),
                    detail: ["reason": String(describing: error)]))
            return Self.noTextResult
        }
    }

    /// `COPIED · 3 LINES`, announced "Copied 3 lines", with the drain line.
    nonisolated static func copiedResult(lines: Int) -> DropResult {
        .confirmation(
            DropReadout(
                text: LocalizedStringResource(
                    "shelf.imageToText.copied", defaultValue: "COPIED · \(lines) LINES", bundle: bundle),
                announcement: LocalizedStringResource(
                    "shelf.imageToText.copied.a11y", defaultValue: "Copied \(lines) lines", bundle: bundle)))
    }

    /// `NO TEXT FOUND`, announced "No text found".
    nonisolated static var noTextResult: DropResult {
        .confirmation(
            DropReadout(
                text: ShelfText.resource("shelf.imageToText.noText"),
                announcement: ShelfText.resource("shelf.imageToText.noText.a11y")))
    }

    /// The images and PDFs of the payload (by type), or its loose image data.
    nonisolated static func textSources(_ payload: DropPayload) -> [TextSource] {
        if payload.urls.isEmpty, let data = payload.imageData { return [.imageData(data)] }
        return payload.urls.filter(isImageOrPDF).map(TextSource.file)
    }

    nonisolated static func isImageOrPDF(_ url: URL) -> Bool {
        let type =
            (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
        guard let type else { return false }
        return imageToTextTypes.contains { type.conforms(to: $0) }
    }

    /// Deletes the payload's materialized promise files (and their drop folder once empty).
    nonisolated static func deleteMaterialized(_ payload: DropPayload, fileManager: FileManager = .default) {
        let dropped = Set(payload.urls.map(\.standardizedFileURL))
        for url in payload.materializedURLs where dropped.contains(url.standardizedFileURL) {
            try? fileManager.removeItem(at: url)
            let folder = url.deletingLastPathComponent()
            if let rest = try? fileManager.contentsOfDirectory(atPath: folder.path), rest.isEmpty {
                try? fileManager.removeItem(at: folder)
            }
        }
    }
}
