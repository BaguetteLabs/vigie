import AppKit
import Foundation
import ModuleKit
import PDFKit
import Synchronization
import Testing
import UniformTypeIdentifiers

@testable import Shelf

/// Fails the test run's URL loading: counts every request any URLSession in the process starts.
final class NoNetworkProtocol: URLProtocol, @unchecked Sendable {
    static let requests = Mutex<[URL]>([])
    override class func canInit(with request: URLRequest) -> Bool {
        requests.withLock { $0.append(request.url ?? URL(fileURLWithPath: "/")) }
        return false
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
}

struct FailingRecognizer: TextRecognizing {
    func lines(in source: TextSource) throws -> [String] { throw TextRecognitionError.unreadable }
}

extension DropResult {
    var confirmation: DropReadout? { if case .confirmation(let readout) = self { readout } else { nil } }
    var confirmationText: String? { confirmation.map { String(localized: $0.text) } }
    var announcement: String? { confirmation?.announcement.map { String(localized: $0) } }
    var isRejected: Bool { if case .rejected = self { true } else { false } }
}

@MainActor @Suite(.serialized) struct ImageToTextTests {
    static func harness(on: Bool = true, recognizer: any TextRecognizing = VisionTextRecognizer()) -> ShelfHarness {
        ShelfHarness(settings: ["image_to_text": on], recognizer: recognizer)
    }

    static func lower(_ lines: [String]) -> [String] { lines.map { $0.lowercased() } }

    // MARK: Recognition

    @Test func visionReadsAGeneratedImageInReadingOrder() throws {
        let lines = try VisionTextRecognizer().lines(in: .file(TextFixtures.png()))
        #expect(Self.lower(lines) == Self.lower(TextFixtures.lines))
    }

    @Test func pdfWithEmbeddedTextUsesIt() throws {
        let url = TextFixtures.textPDF()
        let embedded = PDFDocument(url: url)?.page(at: 0)?.string ?? ""
        #expect(embedded.contains("Hello world"))
        let lines = try VisionTextRecognizer().lines(in: .file(url))
        #expect(lines == TextFixtures.lines)
    }

    @Test func pdfWithoutTextIsRenderedAndRecognized() throws {
        let url = TextFixtures.scannedPDF()
        #expect((PDFDocument(url: url)?.page(at: 0)?.string ?? "").isEmpty)
        let lines = try VisionTextRecognizer().lines(in: .file(url))
        #expect(Self.lower(lines) == Self.lower(TextFixtures.lines))
    }

    @Test func readingOrderIsTopToBottomThenLeftToRight() {
        typealias P = VisionTextRecognizer.Piece
        let pieces = [
            P(text: "bottom", box: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1)),
            P(text: "right", box: CGRect(x: 0.6, y: 0.71, width: 0.2, height: 0.1)),
            P(text: "left", box: CGRect(x: 0.1, y: 0.7, width: 0.2, height: 0.1)),
            P(text: "middle", box: CGRect(x: 0.1, y: 0.4, width: 0.3, height: 0.1)),
        ]
        #expect(VisionTextRecognizer.readingOrder(pieces) == ["left right", "middle", "bottom"])
    }

    // MARK: Handler

    @Test func anImageDropCopiesTheTextAndReadsOutTheLineCount() async throws {
        let h = Self.harness()
        try await h.start()
        let result = await h.module.imageToTextZone.handler(ShelfHarness.files(TextFixtures.png()))
        #expect(result.confirmationText == "COPIED · 3 LINES")
        #expect(result.announcement == "Copied 3 lines")
        #expect(result.confirmation?.drains == true)
        let copied = try #require(h.context.fakeClipboard.copied.first)
        #expect(Self.lower(copied.components(separatedBy: "\n")) == Self.lower(TextFixtures.lines))
        #expect(h.module.lastImageToText == ImageToTextRun(lines: 3, at: h.clock.now))
        #expect(h.module.items.isEmpty, "nothing is stashed")
    }

    @Test func oneLineReadsSingular() {
        #expect(String(localized: ShelfModule.copiedResult(lines: 1).confirmation!.text) == "COPIED · 1 LINE")
        #expect(ShelfModule.copiedResult(lines: 1).announcement == "Copied 1 line")
    }

    @Test func looseImageDataIsRecognized() async throws {
        let h = Self.harness()
        try await h.start()
        let payload = DropPayload(
            urls: [], modifiers: [], source: .dropDisplay, imageData: TextFixtures.pngData(["Loose image text"]))
        let result = await h.module.imageToText(payload)
        #expect(result.confirmationText == "COPIED · 1 LINE")
        #expect(h.context.fakeClipboard.copied.map { $0.lowercased() } == ["loose image text"])
    }

    @Test func anImageWithoutTextLeavesTheClipboardAlone() async throws {
        let h = Self.harness()
        try await h.start()
        let result = await h.module.imageToText(ShelfHarness.files(TextFixtures.png([])))
        #expect(result.confirmationText == "NO TEXT FOUND")
        #expect(result.announcement == "No text found")
        #expect(h.context.fakeClipboard.copied.isEmpty)
        #expect(h.module.lastImageToText == nil)
        #expect(h.context.fakeActivity.entries.isEmpty)
    }

    @Test func aFailureReadsNoTextFoundAndWritesAnActivityEntry() async throws {
        let h = Self.harness(recognizer: FailingRecognizer())
        try await h.start()
        let result = await h.module.imageToText(ShelfHarness.files(TextFixtures.png()))
        #expect(result.confirmationText == "NO TEXT FOUND")
        #expect(h.context.fakeClipboard.copied.isEmpty)
        let entry = try #require(h.context.fakeActivity.entries.first)
        #expect(entry.kind == "shelf.image_to_text")
        #expect(entry.outcome == .custom("failed"))
    }

    @Test func anUnreadableImageFileFailsWithTheRealRecognizer() async throws {
        let h = Self.harness()
        try await h.start()
        let result = await h.module.imageToText(ShelfHarness.files(makeFile("broken.png", contents: "not a png")))
        #expect(result.confirmationText == "NO TEXT FOUND")
        #expect(h.context.fakeActivity.entries.count == 1)
    }

    @Test func noNetworkRequestIsMade() async throws {
        NoNetworkProtocol.requests.withLock { $0 = [] }
        URLProtocol.registerClass(NoNetworkProtocol.self)
        defer { URLProtocol.unregisterClass(NoNetworkProtocol.self) }
        let h = Self.harness()
        try await h.start()
        _ = await h.module.imageToText(ShelfHarness.files(TextFixtures.png()))
        _ = await h.module.imageToText(ShelfHarness.files(TextFixtures.scannedPDF()))
        #expect(NoNetworkProtocol.requests.withLock { $0 }.isEmpty)
    }

    @Test func theMaterializedDropFileIsDeletedButNeverTheUsersFile() async throws {
        let h = Self.harness()
        try await h.start()
        let drops = makeTempDirectory().appendingPathComponent("drops/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: drops, withIntermediateDirectories: true)
        let promised = TextFixtures.png(name: "promised.png", in: drops)
        let user = TextFixtures.png(name: "mine.png")
        let payload = DropPayload(
            urls: [user, promised], modifiers: [], source: .dropDisplay, materializedURLs: [promised])
        let result = await h.module.imageToText(payload)
        #expect(result.confirmationText == "COPIED · 6 LINES")
        #expect(!FileManager.default.fileExists(atPath: promised.path))
        #expect(!FileManager.default.fileExists(atPath: drops.path), "the empty drop folder goes too")
        #expect(FileManager.default.fileExists(atPath: user.path))
    }

    @Test func theMaterializedFileIsDeletedEvenWhenNoTextIsFound() async throws {
        let h = Self.harness()
        try await h.start()
        let drops = makeTempDirectory()
        let promised = TextFixtures.png([], name: "blank.png", in: drops)
        let payload = DropPayload(
            urls: [promised], modifiers: [], source: .dropDisplay, materializedURLs: [promised])
        #expect(await h.module.imageToText(payload).confirmationText == "NO TEXT FOUND")
        #expect(!FileManager.default.fileExists(atPath: promised.path))
    }

    @Test func otherTypesAndTheSettingOffAreRejected() async throws {
        let off = Self.harness(on: false)
        try await off.start()
        #expect(await off.module.imageToText(ShelfHarness.files(TextFixtures.png())).isRejected)
        let on = Self.harness()
        try await on.start()
        #expect(await on.module.imageToText(ShelfHarness.files(makeFile("notes.txt"))).isRejected)
        #expect(on.context.fakeClipboard.copied.isEmpty)
    }

    // MARK: Zone

    @Test func zoneDeclaration() async throws {
        let h = Self.harness()
        try await h.start()
        let zone = h.module.imageToTextZone
        #expect(zone.id == "shelf.image_to_text")
        #expect(zone.cell == DropCell(preferredColumn: 4, preferredRow: 2, span: .init(columns: 1, rows: 1)))
        #expect(zone.order == 30)
        #expect(zone.role == .secondary)
        #expect(zone.glyph == "drop.image-to-text")
        #expect(String(localized: zone.label) == "IMAGE TO TEXT")
        #expect(zone.meta.map { String(localized: $0) } == "COPY TEXT")
        #expect(zone.releaseLine.map { String(localized: $0) } == "RELEASE TO COPY TEXT")
        #expect(zone.progressReadout.map { String(localized: $0) } == "READING…")
        #expect(h.module.dropZones.map(\.id).contains("shelf.image_to_text"))
        let mini = try #require(h.module.imageToTextMiniZone)
        #expect(mini.meta.map { String(localized: $0) } == "COPY")
    }

    /// Lights only for an image or PDF (UX-DR85).
    @Test(arguments: [
        ([UTType.png], nil as DropLooseContent?, true), ([.jpeg], nil, true), ([.pdf], nil, true),
        ([.plainText], nil, false), ([.folder], nil, false), ([.png, .plainText], nil, false),
        ([.image], .image, true), ([.plainText], .text, false), ([.url], .link, false),
    ])
    func acceptance(types: [UTType], loose: DropLooseContent?, lit: Bool) async throws {
        let h = Self.harness()
        try await h.start()
        #expect(h.module.imageToTextZone.accepts(contentTypes: types, loose: loose) == lit)
    }

    @Test func hiddenWhenTheSettingIsOffOrTheModuleStopped() async throws {
        let off = Self.harness(on: false)
        try await off.start()
        #expect(!off.module.imageToTextZone.isEnabled)
        #expect(off.module.imageToTextMiniZone == nil)
        let on = Self.harness()
        #expect(!on.module.imageToTextZone.isEnabled, "not started")
        try await on.start()
        #expect(on.module.imageToTextZone.isEnabled)
        try await on.context.fakeSettings.set(false, for: "image_to_text")
        #expect(!on.module.imageToTextZone.isEnabled, "read again on the next drag")
        try await on.context.fakeSettings.set(true, for: "image_to_text")
        await on.module.stop()
        #expect(!on.module.imageToTextZone.isEnabled)
    }

    /// The Shelf's declared set reflows as the host's table expects (UX-DR83): Stash 2 × 2 at (1,1), Image to
    /// Text at (4,2); with the setting off only the Stash zone is enabled.
    @Test func shelfDeclaredSetForTheReflow() async throws {
        let off = Self.harness(on: false)
        try await off.start()
        #expect(off.module.dropZones.filter(\.isEnabled).map(\.id) == ["shelf.stash"])
        let on = Self.harness()
        try await on.start()
        let enabled = on.module.dropZones.filter(\.isEnabled)
        #expect(enabled.map(\.id) == ["shelf.stash", "shelf.image_to_text"])
        #expect(enabled.map(\.cell.preferredColumn) == [1, 4])
        #expect(enabled.map(\.cell.preferredRow) == [1, 2])
    }
}
