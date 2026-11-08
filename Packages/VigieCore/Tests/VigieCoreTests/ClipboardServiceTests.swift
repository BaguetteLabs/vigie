import AppKit
import ModuleKit
import Testing

@testable import VigieCore

/// Records writes; never offers contents back (the service must not need them).
@MainActor
final class RecordingPasteboard: PasteboardWriting {
    private(set) var changeCount = 0
    private(set) var strings: [String] = []
    private(set) var clears = 0
    var current: String?

    func clearContents() -> Int {
        clears += 1
        changeCount += 1
        current = nil
        return changeCount
    }

    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        #expect(dataType == .string)
        strings.append(string)
        current = string
        return true
    }

    /// Another app copied something.
    func foreignCopy() {
        changeCount += 1
        current = "other"
    }
}

@MainActor @Suite struct ClipboardServiceTests {
    @Test func copyClearsThenWritesPlainTextOnTheMainActor() {
        let board = RecordingPasteboard()
        let service = CoreClipboardService { board }
        service.copy("line 1\nline 2", clearAfter: nil)
        #expect(board.clears == 1)
        #expect(board.strings == ["line 1\nline 2"])
        #expect(board.current == "line 1\nline 2")
    }

    @Test func copyFromAnotherThreadLandsOnTheMainActor() async {
        let board = RecordingPasteboard()
        let service = CoreClipboardService { board }
        await Task.detached { service.copy("from a handler", clearAfter: nil) }.value
        #expect(await eventually { board.strings == ["from a handler"] })
    }

    @Test func clearAfterEmptiesThePasteboardIfItStillHoldsTheCopy() async {
        let board = RecordingPasteboard()
        let service = CoreClipboardService { board }
        service.copy("secret", clearAfter: .milliseconds(20))
        #expect(await eventually { board.current == nil })
        #expect(board.clears == 2)
    }

    @Test func clearAfterLeavesALaterCopyAlone() async throws {
        let board = RecordingPasteboard()
        let service = CoreClipboardService { board }
        service.copy("secret", clearAfter: .milliseconds(20))
        board.foreignCopy()
        try await Task.sleep(for: .milliseconds(80))
        #expect(board.current == "other")
        #expect(board.clears == 1)
    }

    /// One integration test on a private named pasteboard (never the general one).
    @Test func writesARealNamedPasteboard() {
        let name = NSPasteboard.Name("app.vigie.tests.\(UUID().uuidString)")
        let board = NSPasteboard(name: name)
        defer { board.releaseGlobally() }
        board.setString("stale", forType: .string)
        let service = CoreClipboardService { board }
        service.copy("COPIED TEXT", clearAfter: nil)
        #expect(board.string(forType: .string) == "COPIED TEXT")
        #expect(board.types?.first == .string)
    }

    @Test func theFactoryHandsModulesTheRealService() {
        let factory = CoreModuleContextFactory(
            environment: makeEnvironment(makeTempDirectory()), eventBus: InProcessEventBus())
        #expect(factory.clipboard is CoreClipboardService)
    }
}
