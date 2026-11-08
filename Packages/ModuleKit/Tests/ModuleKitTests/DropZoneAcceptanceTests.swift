import Foundation
import Testing
import UniformTypeIdentifiers

@testable import ModuleKit

@Suite struct DropZoneAcceptanceTests {
    private func zone(accepts: [UTType], loose: Set<DropLooseContent> = []) -> DropZone {
        DropZone(
            id: "z", label: "Z", glyph: "drop.stash", accentToken: "iris-2", role: .secondary,
            cell: DropCell(preferredColumn: 4, preferredRow: 1, span: .init(columns: 1, rows: 1)), order: 0,
            accepts: accepts, handler: { _ in .accepted }, looseContent: loose)
    }

    @Test func emptyAcceptsTakesFilesAndAnyLooseContent() {
        let any = zone(accepts: [])
        #expect(any.accepts(contentTypes: [.png], loose: nil))
        for kind in DropLooseContent.allCases {
            #expect(any.accepts(contentTypes: [], loose: kind))
        }
    }

    @Test func filesOnlyZoneRefusesLooseContent() {
        let files = zone(accepts: [.item])
        #expect(files.accepts(contentTypes: [.plainText], loose: nil))
        #expect(!files.accepts(contentTypes: [.plainText], loose: .text))
        #expect(!files.accepts(contentTypes: [.url], loose: .link))
        #expect(!files.accepts(contentTypes: [.image], loose: .image))
    }

    @Test func declaredLooseKindsAreTaken() {
        let images = zone(accepts: [.image, .pdf], loose: [.image])
        #expect(images.accepts(contentTypes: [.png], loose: nil))
        #expect(images.accepts(contentTypes: [.pdf], loose: nil))
        #expect(!images.accepts(contentTypes: [.plainText], loose: nil))
        #expect(images.accepts(contentTypes: [.image], loose: .image))
        #expect(!images.accepts(contentTypes: [.plainText], loose: .text))
    }

    @Test func confirmationCarriesAnnouncementAndDrain() {
        let result = DropResult.confirmation(DropReadout(text: "COPIED · 3 LINES", announcement: "Copied 3 lines"))
        guard case .confirmation(let readout) = result else {
            Issue.record("not a confirmation")
            return
        }
        #expect(String(localized: readout.text) == "COPIED · 3 LINES")
        #expect(readout.announcement.map { String(localized: $0) } == "Copied 3 lines")
        #expect(readout.drains)
    }

    @Test func payloadKeepsMaterializedURLs() {
        let file = URL(fileURLWithPath: "/tmp/drops/A/shot.png")
        let payload = DropPayload(
            urls: [file], modifiers: [], source: .dropDisplay, materializedURLs: [file])
        #expect(payload.materializedURLs == [file])
        #expect(DropPayload(urls: [file], modifiers: [], source: .dropDisplay).materializedURLs.isEmpty)
    }
}
