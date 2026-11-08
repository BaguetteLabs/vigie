import AppKit
import ModuleKit
import Synchronization
import Testing
import UniformTypeIdentifiers

@testable import VigieCore

/// Story 9.10 host side: the clipboard read for `⌘V` (only VigieCore reads it) and the Services entry
/// `Stash in Vigie`.
@MainActor @Suite struct PasteAndServiceTests {
    static func pasteboard(_ fill: (NSPasteboard) -> Void = { _ in }) -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("vigie-test-\(UUID().uuidString)"))
        board.clearContents()
        fill(board)
        return board
    }

    @Test func filesWinThenLinkImageAndText() throws {
        let file = URL(fileURLWithPath: "/tmp/a.pdf")
        let files = try #require(
            PasteboardReader.payload(from: Self.pasteboard { $0.writeObjects([file as NSURL]) }, source: .paste))
        #expect(files.urls == [file] && files.source == .paste)

        let link = URL(string: "https://example.com/x")!
        let web = try #require(
            PasteboardReader.payload(from: Self.pasteboard { $0.writeObjects([link as NSURL]) }, source: .service))
        #expect(web.urls.isEmpty && web.url == link && web.source == .service)

        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let image = try #require(
            PasteboardReader.payload(
                from: Self.pasteboard {
                    $0.setData(png, forType: .png)
                    $0.setString("caption", forType: .string)
                }, source: .paste))
        #expect(image.imageData == png && image.text == nil)

        let text = try #require(
            PasteboardReader.payload(from: Self.pasteboard { $0.setString("hello", forType: .string) }, source: .paste))
        #expect(text.text == "hello" && text.urls.isEmpty)
    }

    @Test func emptyOrUnsupportedIsNil() {
        #expect(PasteboardReader.payload(from: Self.pasteboard(), source: .paste) == nil)
        #expect(
            PasteboardReader.payload(from: Self.pasteboard { $0.setString("   \n", forType: .string) }, source: .paste)
                == nil)
        #expect(
            PasteboardReader.payload(
                from: Self.pasteboard { $0.setData(Data([1]), forType: NSPasteboard.PasteboardType("com.x.y")) },
                source: .paste) == nil)
    }

    @Test func pasteRunsTheZoneWithPasteSourceAndEmptyRunsNothing() async {
        let f = DropFixture()
        f.shelf.dropZones = [DropReadoutTests.zone("stash", accepts: []) { _ in .readout("NOT STASHED") }]
        await f.start()
        let board = Self.pasteboard()
        let directory = CoreDropZoneDirectory(link: NotchHostLink(host: f.host), pasteboard: { board })
        #expect(await directory.performPaste(into: "stash") == nil)
        #expect(f.display.lastDrop == nil)
        #expect(f.host.transient == nil, "no readout for an empty clipboard")
        board.setString("note", forType: .string)
        guard case .readout = await directory.performPaste(into: "stash") else {
            Issue.record("expected the handler's result")
            return
        }
        #expect(f.display.lastDrop?.payload.source == .paste)
        #expect(f.display.lastDrop?.payload.text == "note")
        #expect(f.host.transient == .message("NOT STASHED"))
    }

    @Test func serviceStashesWithServiceSourceWithoutOpeningAnything() async throws {
        let f = DropFixture()
        await f.start()
        let notifier = RecordingCoreNotifier()
        let provider = StashServiceProvider(
            directory: CoreDropZoneDirectory(link: NotchHostLink(host: f.host)), notifier: notifier, logger: testLogger)
        let file = URL(fileURLWithPath: "/tmp/report.pdf")
        #expect(provider.handle(Self.pasteboard { $0.writeObjects([file as NSURL]) }) == .stashed(zoneID: "stash"))
        _ = await provider.pending?.value
        let call = try #require(f.log.all.first)
        #expect(call.id == "stash" && call.payload.source == .service && call.payload.urls == [file])
        #expect(!f.host.isExpanded && !f.display.isOpen)
        #expect(notifier.events.isEmpty)
        #expect(provider.handle(Self.pasteboard()) == .empty)
    }

    @Test func serviceWithTheShelfOffRaisesShelfIsOffAndStashesNothing() async {
        let f = DropFixture()
        f.enablement.set("shelf", false)
        await f.start()
        let notifier = RecordingCoreNotifier()
        let provider = StashServiceProvider(
            directory: CoreDropZoneDirectory(link: NotchHostLink(host: f.host)), notifier: notifier, logger: testLogger)
        let board = Self.pasteboard { $0.setString("hello", forType: .string) }
        #expect(provider.handle(board) == .shelfOff)
        #expect(f.log.all.isEmpty)
        let event = notifier.events.first
        #expect(event?.kind == "setup.problem")
        #expect(event?.title == "Shelf is off")
        #expect(event?.action == .openSettings(pane: "shelf"))
        #expect(event?.dedupeKey == "service.shelf-off")
        // The ObjC entry point answers the same way.
        var error: NSString?
        provider.stashInVigie(board, userData: nil, error: &error)
        #expect(error == nil)
        provider.stashInVigie(Self.pasteboard(), userData: nil, error: &error)
        #expect(notifier.events.count == 3, "posted each time; the Notifier dedupes by key")
    }

    @Test func theServiceSelectorMatchesTheInfoPlistMessage() {
        #expect(StashServiceProvider.message == "stashInVigie")
        #expect(StashServiceProvider.instancesRespond(to: NSSelectorFromString("stashInVigie:userData:error:")))
    }
}

/// Records posted events.
final class RecordingCoreNotifier: Notifier, Sendable {
    private let posted = Mutex<[NotifierEvent]>([])
    var events: [NotifierEvent] { posted.withLock { $0 } }

    func post(_ event: NotifierEvent) -> AlertHandle {
        posted.withLock { $0.append(event) }
        return AlertHandle {}
    }
}
