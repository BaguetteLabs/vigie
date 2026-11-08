import AppKit
import Foundation
import ModuleKit
import Testing

@testable import Shelf

@MainActor
struct ShelfHarness {
    let clock = TestClock()
    let scope = CountingScope()
    let context: FakeModuleContext
    let module: ShelfModule

    init(settings: [String: any SettingValue] = [:], storage: FakeStorage = FakeStorage()) {
        context = FakeModuleContext(settings: settings, storage: storage)
        let clock = clock
        module = ShelfModule(scope: scope, now: { clock.now })
    }

    func start() async throws { try await module.start(context: context) }

    func drop(_ payload: DropPayload) async -> DropResult {
        await module.stashZone.handler(payload)
    }

    static func files(_ urls: URL...) -> DropPayload {
        DropPayload(urls: urls, modifiers: [], source: .dropDisplay)
    }
}

extension DropResult {
    var isAccepted: Bool { if case .accepted = self { true } else { false } }
    var readoutText: String? { if case .readout(let text) = self { String(localized: text) } else { nil } }
}

@MainActor @Suite struct StashTests {
    @Test func manifestDeclaresSettingsAndTheExpiryKind() {
        let manifest = ShelfModule.staticManifest
        #expect(manifest.id == "shelf")
        #expect(manifest.settings.map(\.key) == ["ttl", "mode", "expiry_notification"])
        #expect(manifest.settings[0].kind == .duration(default: .seconds(7 * 86_400)))
        #expect(manifest.settings[1].kind == .enumeration(options: ["reference", "copy"], default: "reference"))
        #expect(manifest.settings[2].kind == .bool(default: false))
        #expect(manifest.alertKinds == ["shelf.expiring"])
    }

    @Test func referenceModeStoresABookmarkAndLeavesTheFile() async throws {
        let h = ShelfHarness()
        try await h.start()
        let file = makeFile("report.pdf", contents: "12345")
        #expect(await h.drop(ShelfHarness.files(file)).isAccepted)
        let item = try #require(h.module.items.first)
        #expect(item.mode == .reference)
        #expect(item.name == "report.pdf")
        #expect(item.size == 5)
        #expect(item.addedAt == h.clock.now)
        #expect(item.bookmark != nil)
        #expect(item.relativePath == nil)
        #expect(item.sourceApp == nil)
        #expect(item.expiresAt == h.clock.now.addingTimeInterval(7 * 86_400))
        #expect(FileManager.default.fileExists(atPath: file.path))
        // Nothing copied into the module folder.
        let itemsFolder = h.context.fakeStorage.directory.appendingPathComponent("items")
        #expect(!FileManager.default.fileExists(atPath: itemsFolder.path))
        #expect(h.context.fakeStorage.writeCount("index") == 1)
    }

    @Test func copyModeCopiesIntoTheModuleFolder() async throws {
        let h = ShelfHarness(settings: ["mode": "copy"])
        try await h.start()
        let file = makeFile("notes.md", contents: "# hi")
        #expect(await h.drop(ShelfHarness.files(file)).isAccepted)
        let item = try #require(h.module.items.first)
        #expect(item.mode == .copy)
        #expect(item.bookmark == nil)
        #expect(item.relativePath == "items/\(item.id.uuidString)/notes.md")
        let copy = try #require(h.module.store?.fileURL(for: item))
        #expect(try String(contentsOf: copy, encoding: .utf8) == "# hi")
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func folderSizeSumsItsFiles() async throws {
        let h = ShelfHarness()
        try await h.start()
        let folder = makeTempDirectory().appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("abc".utf8).write(to: folder.appendingPathComponent("a.txt"))
        try Data("defg".utf8).write(to: folder.appendingPathComponent("b.txt"))
        #expect(await h.drop(ShelfHarness.files(folder)).isAccepted)
        #expect(h.module.items.first?.size == 7)
    }

    @Test func textIsSavedAsATextFile() async throws {
        let h = ShelfHarness()
        try await h.start()
        let payload = DropPayload(urls: [], modifiers: [], source: .dropDisplay, text: "Shopping list\neggs")
        #expect(await h.drop(payload).isAccepted)
        let item = try #require(h.module.items.first)
        #expect(item.mode == .saved)
        #expect(item.name == "Shopping list.txt")
        let url = try #require(h.module.store?.fileURL(for: item))
        #expect(try String(contentsOf: url, encoding: .utf8) == "Shopping list\neggs")
        #expect(item.size == Int64("Shopping list\neggs".utf8.count))
    }

    @Test func blankFirstLineTextUsesTheCatalogName() async throws {
        let h = ShelfHarness()
        try await h.start()
        let payload = DropPayload(urls: [], modifiers: [], source: .dropDisplay, text: "   ")
        #expect(await h.drop(payload).isAccepted)
        #expect(h.module.items.first?.name == "Text.txt")
    }

    @Test func linkIsSavedAsAWebloc() async throws {
        let h = ShelfHarness()
        try await h.start()
        let link = try #require(URL(string: "https://example.com/a/b?c=1"))
        #expect(await h.drop(DropPayload(urls: [], modifiers: [], source: .dropDisplay, url: link)).isAccepted)
        let item = try #require(h.module.items.first)
        #expect(item.mode == .saved)
        #expect(item.name == "example.com.webloc")
        let url = try #require(h.module.store?.fileURL(for: item))
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        #expect((plist as? [String: String])?["URL"] == "https://example.com/a/b?c=1")
    }

    @Test func imageIsSavedAsPNGEvenFromTIFF() async throws {
        let h = ShelfHarness()
        try await h.start()
        let rep = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let tiff = try #require(rep.tiffRepresentation)
        #expect(await h.drop(DropPayload(urls: [], modifiers: [], source: .dropDisplay, imageData: tiff)).isAccepted)
        let item = try #require(h.module.items.first)
        #expect(item.mode == .saved)
        #expect(item.name == "Image.png")
        let data = try Data(contentsOf: try #require(h.module.store?.fileURL(for: item)))
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func indexRoundTripsThroughStorage() async throws {
        let storage = FakeStorage()
        let first = ShelfHarness(settings: ["mode": "copy"], storage: storage)
        try await first.start()
        _ = await first.drop(ShelfHarness.files(makeFile("a.txt")))
        _ = await first.drop(DropPayload(urls: [], modifiers: [], source: .dropDisplay, text: "memo"))
        let saved = first.module.items
        #expect(saved.count == 2)
        #expect(saved.first?.name == "memo.txt")  // newest first
        await first.module.stop()

        let second = ShelfHarness(storage: storage)
        try await second.start()
        #expect(second.module.items == saved)
    }

    @Test func stateIsAmbientWithItemsAndHiddenWhenEmpty() async throws {
        let h = ShelfHarness()
        try await h.start()
        #expect(h.module.state == .hidden)
        #expect(h.module.itemCount == 0)
        _ = await h.drop(ShelfHarness.files(makeFile("a.txt"), makeFile("b.txt")))
        #expect(h.module.state == .ambient)
        #expect(h.module.itemCount == 2)
        for item in h.module.items { await h.module.store?.remove(item.id) }
        await h.module.refresh()
        #expect(h.module.state == .hidden)
    }

    @Test func unreadableFileStoresNothingAndShowsNotStashed() async throws {
        let h = ShelfHarness(settings: ["mode": "copy"])
        try await h.start()
        let good = makeFile("good.txt")
        let missing = makeTempDirectory().appendingPathComponent("gone.txt")
        let result = await h.drop(ShelfHarness.files(good, missing))
        #expect(result.readoutText == "NOT STASHED")
        #expect(h.module.items.isEmpty)
        #expect(h.module.state == .hidden)
        #expect(h.context.fakeStorage.writeCount("index") == 0)
        // The copy made for the good file was taken back.
        let itemsFolder = h.context.fakeStorage.directory.appendingPathComponent("items")
        let left = (try? FileManager.default.contentsOfDirectory(atPath: itemsFolder.path)) ?? []
        #expect(left.isEmpty)
        let entry = try #require(h.context.fakeActivity.entries.first)
        #expect(entry.kind == "shelf.stash")
        #expect(entry.category == .module)
        #expect(entry.outcome == .custom("failed"))
        #expect(entry.detail["reason"] == "unreadable")
        #expect(h.context.fakeNotifier.posted.isEmpty)
    }

    @Test func bookmarkFailureIsNotStashed() async throws {
        let h = ShelfHarness()
        try await h.start()
        h.scope.failBookmarks = true
        let result = await h.drop(ShelfHarness.files(makeFile()))
        #expect(result.readoutText == "NOT STASHED")
        #expect(h.module.items.isEmpty)
        #expect(h.context.fakeActivity.entries.first?.detail["reason"] == "bookmarkFailed")
        #expect(h.context.fakeNotifier.posted.isEmpty)
    }

    @Test func diskFullErrorsMapToDiskFull() {
        let full = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteOutOfSpace.rawValue)
        #expect(ShelfStore.failure(for: full) == .diskFull)
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        #expect(ShelfStore.failure(for: posix) == .diskFull)
        let wrapped = NSError(
            domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue,
            userInfo: [NSUnderlyingErrorKey: posix])
        #expect(ShelfStore.failure(for: wrapped) == .diskFull)
        #expect(ShelfStore.failure(for: NSError(domain: "x", code: 1)) == .writeFailed)
    }

    @Test func emptyPayloadIsNotStashed() async throws {
        let h = ShelfHarness()
        try await h.start()
        let result = await h.drop(DropPayload(urls: [], modifiers: [], source: .dropDisplay))
        #expect(result.readoutText == "NOT STASHED")
        #expect(h.context.fakeActivity.entries.first?.detail["reason"] == "nothingToStash")
    }

    @Test func securityScopedAccessIsBalanced() async throws {
        let h = ShelfHarness()
        try await h.start()
        let file = makeFile("scoped.txt", contents: "inside")
        _ = await h.drop(ShelfHarness.files(file))
        let store = try #require(h.module.store)
        let id = try #require(h.module.items.first?.id)
        let text = try await store.withSecurityScopedAccess(id) { url in
            try String(contentsOf: url, encoding: .utf8)
        }
        #expect(text == "inside")
        #expect(h.scope.starts == 1 && h.scope.stops == 1)
        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await store.withSecurityScopedAccess(id) { _ in throw Boom() }
        }
        #expect(h.scope.starts == 2 && h.scope.stops == 2)
    }

    @Test func staleBookmarkIsRefreshed() async throws {
        let h = ShelfHarness()
        try await h.start()
        _ = await h.drop(ShelfHarness.files(makeFile()))
        let store = try #require(h.module.store)
        let id = try #require(h.module.items.first?.id)
        h.scope.reportStale = true
        let before = h.scope.bookmarks
        let writes = h.context.fakeStorage.writeCount("index")
        _ = try await store.withSecurityScopedAccess(id) { $0.lastPathComponent }
        #expect(h.scope.bookmarks == before + 1)
        #expect(h.context.fakeStorage.writeCount("index") == writes + 1)
        #expect(h.scope.starts == h.scope.stops)
    }

    @Test func copiesNeedNoScope() async throws {
        let h = ShelfHarness(settings: ["mode": "copy"])
        try await h.start()
        _ = await h.drop(ShelfHarness.files(makeFile("c.txt", contents: "copy")))
        let store = try #require(h.module.store)
        let id = try #require(h.module.items.first?.id)
        let text = try await store.withSecurityScopedAccess(id) { try String(contentsOf: $0, encoding: .utf8) }
        #expect(text == "copy")
        #expect(h.scope.starts == 0)
    }

    @Test func zoneMetaAndLabelFollowTTLAndCount() async throws {
        let h = ShelfHarness()
        #expect(!h.module.stashZone.isEnabled)
        try await h.start()
        let zone = h.module.stashZone
        #expect(zone.isEnabled)
        #expect(zone.id == "shelf.stash")
        #expect(zone.role == .primary)
        #expect(zone.order == 0)
        #expect(zone.glyph == "drop.stash")
        #expect(zone.accentToken == "iris-2")
        #expect(zone.cell == DropCell(preferredColumn: 1, preferredRow: 1, span: .init(columns: 2, rows: 2)))
        #expect(zone.accepts.isEmpty)
        #expect(String(localized: zone.label) == "Stash")
        #expect(zone.meta.map { String(localized: $0) } == "KEEP 7 DAYS · 0 ITEMS")
        #expect(zone.releaseLine.map { String(localized: $0) } == "RELEASE TO STASH")
        for _ in 0..<5 { _ = await h.drop(ShelfHarness.files(makeFile())) }
        #expect(h.module.stashZone.meta.map { String(localized: $0) } == "KEEP 7 DAYS · 5 ITEMS")
        #expect(
            h.module.stashZone.accessibilityLabel.map { String(localized: $0) } == "Stash, keep 7 days, 5 items")
        try await h.context.fakeSettings.set(Duration.seconds(86_400), for: "ttl")
        await h.module.ttlChanged()
        #expect(h.module.stashZone.meta.map { String(localized: $0) } == "KEEP 1 DAY · 5 ITEMS")
        try await h.context.fakeSettings.set(Duration.seconds(12 * 3600), for: "ttl")
        await h.module.ttlChanged()
        #expect(h.module.stashZone.meta.map { String(localized: $0) } == "KEEP 12 HOURS · 5 ITEMS")
        await h.module.stop()
        #expect(!h.module.stashZone.isEnabled)
    }

    @Test func singularItemWording() async throws {
        let h = ShelfHarness()
        try await h.start()
        _ = await h.drop(ShelfHarness.files(makeFile()))
        #expect(h.module.stashZone.meta.map { String(localized: $0) } == "KEEP 7 DAYS · 1 ITEM")
        #expect(
            h.module.stashZone.accessibilityLabel.map { String(localized: $0) } == "Stash, keep 7 days, 1 item")
    }
}
