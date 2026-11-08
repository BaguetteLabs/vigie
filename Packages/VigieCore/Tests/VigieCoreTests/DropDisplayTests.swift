import AppKit
import ModuleKit
import Observation
import SwiftUI
import Synchronization
import Testing
import UniformTypeIdentifiers
import VigieUI

@testable import VigieCore

// MARK: - Fakes

/// A module that only declares drop zones.
@MainActor @Observable
final class DropModule: NotchModule {
    let manifest: ModuleManifest
    var state: ModuleState = .ambient
    var dropZones: [DropZone]

    init(_ id: ModuleID, zones: [DropZone]) {
        manifest = ModuleManifest(id: id, name: "Drop", icon: "tray")
        dropZones = zones
    }

    func start(context: any ModuleContext) async throws {}
    func stop() async {}
}

@MainActor
final class RecordingDropDriver: DropDisplayPanelDriver {
    private(set) var presented: [(model: DropDisplayModel, anchor: IslandAnchor)] = []
    private(set) var retracts = 0

    func present(_ model: DropDisplayModel, anchor: IslandAnchor) { presented.append((model, anchor)) }
    func retract() { retracts += 1 }
}

@MainActor
final class FakeEscape: DropEscapeMonitoring {
    private(set) var handler: (@MainActor () -> Void)?
    private(set) var starts = 0
    func start(_ onEscape: @escaping @MainActor () -> Void) {
        handler = onEscape
        starts += 1
    }
    func stop() { handler = nil }
    func press() { handler?() }
}

/// A file promise that writes `name` into the folder it is given.
@MainActor
final class FakePromise: PromisedFileReceiving {
    let name: String
    let contentTypes: [UTType]
    let fileCount = 1
    private(set) var folders: [URL] = []

    init(name: String, type: UTType = .png) {
        self.name = name
        contentTypes = [type]
    }

    func receive(into folder: URL, reader: @escaping @Sendable (Result<URL, any Error>) -> Void) {
        folders.append(folder)
        let url = folder.appendingPathComponent(name)
        DispatchQueue.global().async {
            do {
                try Data("promised".utf8).write(to: url)
                reader(.success(url))
            } catch {
                reader(.failure(error))
            }
        }
    }
}

/// Records handler calls (thread-safe: handlers run off the main actor).
final class HandlerLog: Sendable {
    private let calls = Mutex<[(String, DropPayload)]>([])
    func record(_ id: String, _ payload: DropPayload) { calls.withLock { $0.append((id, payload)) } }
    var all: [(id: String, payload: DropPayload)] { calls.withLock { $0.map { ($0.0, $0.1) } } }
}

enum DropZones {
    static func zone(
        _ id: String, role: DropRole = .secondary, column: Int, row: Int, columns: Int = 1, rows: Int = 1,
        order: Int, accepts: [UTType] = [], enabled: Bool = true, log: HandlerLog? = nil
    ) -> DropZone {
        DropZone(
            id: id, label: LocalizedStringResource(stringLiteral: id.uppercased()), glyph: "drop.stash",
            accentToken: "iris-2", role: role,
            cell: DropCell(preferredColumn: column, preferredRow: row, span: .init(columns: columns, rows: rows)),
            order: order, accepts: accepts,
            handler: { payload in
                log?.record(id, payload)
                return .accepted
            }, isEnabled: enabled)
    }

    static func stash(log: HandlerLog? = nil) -> DropZone {
        zone("stash", role: .primary, column: 1, row: 1, columns: 2, rows: 2, order: 0, log: log)
    }
    static func ask(log: HandlerLog? = nil) -> DropZone {
        zone("ask", column: 3, row: 1, rows: 2, order: 10, log: log)
    }
    static func airdrop(enabled: Bool = true, log: HandlerLog? = nil) -> DropZone {
        zone("airdrop", column: 4, row: 1, order: 20, enabled: enabled, log: log)
    }
    static func imageToText(enabled: Bool = true, log: HandlerLog? = nil) -> DropZone {
        zone("ocr", column: 4, row: 2, order: 30, accepts: [.image, .pdf], enabled: enabled, log: log)
    }
}

/// A host with fake shelf and agents modules declaring layout-B zones.
@MainActor
final class DropFixture {
    let log = HandlerLog()
    let shelf: DropModule
    let agents: DropModule
    let registry: ModuleRegistry
    let enablement = TestEnablement()
    let clock = TestClock()
    let driver = RecordingDropDriver()
    let escape = FakeEscape()
    let drops = makeTempDirectory().appendingPathComponent("drops", isDirectory: true)
    var modifiers: NSEvent.ModifierFlags = []
    /// VoiceOver announcements the host posted.
    var announced: [String] = []
    var host: NotchHost!

    static let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    static let island = CGRect(x: 536, y: 950, width: 440, height: 32)
    static let notch = CGRect(x: 656, y: 950, width: 200, height: 32)

    init(imageToText: Bool = true) {
        shelf = DropModule(
            "shelf",
            zones: [
                DropZones.stash(log: log), DropZones.airdrop(log: log),
                DropZones.imageToText(enabled: imageToText, log: log),
            ])
        agents = DropModule("agents.sessions", zones: [DropZones.ask(log: log)])
        let made: [ModuleID: DropModule] = ["shelf": shelf, "agents.sessions": agents]
        registry = ModuleRegistry(
            descriptors: ["agents.sessions", "shelf"].map { (id: ModuleID) in
                ModuleDescriptor(manifest: ModuleManifest(id: id, name: "Drop", icon: "tray")) { made[id]! }
            },
            enablement: enablement,
            contextFactory: CoreModuleContextFactory(
                environment: makeEnvironment(makeTempDirectory()), eventBus: InProcessEventBus()),
            logger: testLogger)
        let driver = driver
        let clock = clock
        host = NotchHost(
            themeController: ThemeController(
                library: try! ThemeLoader.loadBundled(), accessibility: .init(reduceMotion: true)),
            registry: registry, contextMenu: NotchContextMenu(), displays: { [] },
            pointerLocation: { CGPoint(x: 700, y: 980) },
            dropsDirectory: drops, dropEscape: escape, dropModifierFlags: { [unowned self] in self.modifiers },
            dropExitGrace: .milliseconds(20), makeDropDisplayPanel: { _ in driver },
            announce: { [unowned self] text in self.announced.append(text) }, clock: clock, logger: testLogger)
        host.anchorsOverride = [IslandAnchor(screenFrame: Self.screen, islandFrame: Self.island, notchRect: Self.notch)]
    }

    func start() async { await registry.start() }
    var display: DropDisplayController { host.dropDisplay }

    /// The centre of a zone, in display coordinates.
    func center(of id: String) -> CGPoint {
        let frames = DropDisplayGeometry.zoneFrames(display.model!.layout, theme: host.themeController.theme)
        let frame = frames[id]!
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// A PNG drag; each name is its own drag session.
    static func png(_ name: String = "screenshot.png") -> DropDragItems {
        DropDragItems(fileURLs: [URL(fileURLWithPath: "/tmp/\(name)")], sequence: abs(name.hashValue % 10_000) + 100)
    }
    static let text = DropDragItems(fileURLs: [URL(fileURLWithPath: "/tmp/notes.txt")], sequence: 8)
}

// MARK: - Layout engine (UX-DR83 reflow table)

@Suite struct DropGridLayoutTests {
    typealias P = DropGridPlacement

    static let all = [
        DropLayoutInput(DropZones.stash()), DropLayoutInput(DropZones.ask()), DropLayoutInput(DropZones.airdrop()),
        DropLayoutInput(DropZones.imageToText()),
    ]

    static func layout(without ids: Set<String>) -> DropGridLayout? {
        DropGridLayoutEngine.layout(all.filter { !ids.contains($0.id) })
    }

    @Test func fullLayoutB() throws {
        let l = try #require(Self.layout(without: []))
        #expect(l.columns == 4 && l.rows == 2)
        #expect(l.placement(of: "stash") == P(column: 1, row: 1, columnSpan: 2, rowSpan: 2))
        #expect(l.placement(of: "ask") == P(column: 3, row: 1, columnSpan: 1, rowSpan: 2))
        #expect(l.placement(of: "airdrop") == P(column: 4, row: 1))
        #expect(l.placement(of: "ocr") == P(column: 4, row: 2))
    }

    @Test func imageToTextOffAirDropSpansColumnFour() throws {
        let l = try #require(Self.layout(without: ["ocr"]))
        #expect(l.columns == 4)
        #expect(l.placement(of: "airdrop") == P(column: 4, row: 1, columnSpan: 1, rowSpan: 2))
        #expect(l.placement(of: "stash") == P(column: 1, row: 1, columnSpan: 2, rowSpan: 2))
    }

    @Test func airDropOffImageToTextSpansColumnFour() throws {
        let l = try #require(Self.layout(without: ["airdrop"]))
        #expect(l.columns == 4)
        #expect(l.placement(of: "ocr") == P(column: 4, row: 1, columnSpan: 1, rowSpan: 2))
    }

    @Test func bothOffGivesThreeColumns() throws {
        let l = try #require(Self.layout(without: ["airdrop", "ocr"]))
        #expect(l.columns == 3 && l.rows == 2)
        #expect(l.placement(of: "stash") == P(column: 1, row: 1, columnSpan: 2, rowSpan: 2))
        #expect(l.placement(of: "ask") == P(column: 3, row: 1, columnSpan: 1, rowSpan: 2))
    }

    @Test func shelfOffShowsOnlyAskAI() throws {
        let l = try #require(Self.layout(without: ["stash", "airdrop", "ocr"]))
        #expect(l.zoneIDs == ["ask"])
        #expect(l.columns == 1)
        #expect(l.placement(of: "ask") == P(column: 1, row: 1, columnSpan: 1, rowSpan: 2))
    }

    @Test func askOffLetsTheShelfZonesCloseUp() throws {
        let l = try #require(Self.layout(without: ["ask"]))
        #expect(l.columns == 3)
        #expect(l.placement(of: "airdrop") == P(column: 3, row: 1))
        #expect(l.placement(of: "ocr") == P(column: 3, row: 2))
    }

    @Test func nothingEnabledGivesNoDisplay() {
        #expect(Self.layout(without: ["stash", "ask", "airdrop", "ocr"]) == nil)
        #expect(DropGridLayoutEngine.layout([]) == nil)
    }

    @Test func primaryAndOrderWinAContestedCell() throws {
        // Two zones want column 4 row 1: the lower order keeps it, the other takes the next free cell.
        let a = DropLayoutInput(id: "a", role: .secondary, cell: DropZones.airdrop().cell, order: 5)
        let b = DropLayoutInput(id: "b", role: .secondary, cell: DropZones.airdrop().cell, order: 1)
        let stash = DropLayoutInput(DropZones.stash())
        let l = try #require(DropGridLayoutEngine.layout([a, b, stash]))
        #expect(l.zoneIDs == ["stash", "b", "a"])
        #expect(l.placement(of: "b")?.row == 1)
        #expect(l.placement(of: "a")?.column != l.placement(of: "b")?.column || l.placement(of: "a")?.row == 2)
    }

    @Test func framesFollowTheGridTokens() throws {
        let theme = try ThemeLoader.loadBundled().resolve(themeID: ThemeLibrary.defaultVariantID, look: .dark).theme
        let l = try #require(Self.layout(without: []))
        let frames = DropDisplayGeometry.zoneFrames(l, theme: theme)
        // 700 wide, 16 side insets, 8 gaps: (668 - 24) / 4 = 161 per column; 196 - 44 - 16 = 136 tall, rows 64.
        #expect(frames["stash"] == CGRect(x: 16, y: 44, width: 330, height: 136))
        #expect(frames["ask"] == CGRect(x: 354, y: 44, width: 161, height: 136))
        #expect(frames["airdrop"] == CGRect(x: 523, y: 44, width: 161, height: 64))
        #expect(frames["ocr"] == CGRect(x: 523, y: 116, width: 161, height: 64))
        #expect(DropDisplayGeometry.zone(at: CGPoint(x: 600, y: 150), in: frames) == "ocr")
        #expect(DropDisplayGeometry.zone(at: CGPoint(x: 350, y: 100), in: frames) == nil)  // the gap
        #expect(DropDisplayGeometry.zone(at: CGPoint(x: 100, y: 20), in: frames) == nil)  // the band
    }
}

// MARK: - Zone contract

@Suite struct DropZoneAcceptsTests {
    @Test func acceptsGatesByContentType() {
        let ocr = DropZones.imageToText()
        #expect(ocr.accepts(contentTypes: [.png]))
        #expect(ocr.accepts(contentTypes: [.pdf, .jpeg]))
        #expect(!ocr.accepts(contentTypes: [.plainText]))
        #expect(!ocr.accepts(contentTypes: [.png, .plainText]))
        #expect(!ocr.accepts(contentTypes: []))
        #expect(DropZones.stash().accepts(contentTypes: [.plainText]))
    }
}

// MARK: - Host

@MainActor @Suite(.serialized) struct DropDisplayHostTests {
    @Test func zonesComeFromStartedModulesInOrderAndFollowStartStop() async {
        let f = DropFixture(imageToText: false)
        #expect(f.display.enabledZones().isEmpty)
        await f.start()
        #expect(f.display.enabledZones().map(\.id) == ["ask", "stash", "airdrop"])
        _ = f.display.islandDragEntered(displayID: nil, items: DropFixture.png())
        #expect(f.display.model?.layout.zoneIDs == ["stash", "ask", "airdrop"])
        #expect(f.display.model?.layout.placement(of: "airdrop")?.rowSpan == 2)
        f.display.cancel()
        f.enablement.set("shelf", false)
        #expect(await eventually { f.display.enabledZones().map(\.id) == ["ask"] })
        _ = f.display.islandDragEntered(displayID: nil, items: DropFixture.png("b.png"))
        #expect(f.display.model?.layout.zoneIDs == ["ask"])
    }

    @Test func nothingHappensWithoutAZoneOrWithoutFiles() async {
        let f = DropFixture()
        // No module started: no zone, no display.
        #expect(f.display.islandDragEntered(displayID: nil, items: DropFixture.png()) == [])
        #expect(!f.display.isOpen)
        await f.start()
        #expect(f.display.islandDragEntered(displayID: nil, items: DropDragItems(sequence: 3)) == [])
        #expect(f.driver.presented.isEmpty)
    }

    @Test func fileDragOverTheIslandOpensTheDisplayUnderTheNotch() async throws {
        let f = DropFixture()
        await f.start()
        let operation = f.display.islandDragEntered(displayID: nil, items: DropFixture.png())
        #expect(operation == .copy)
        #expect(f.display.isOpen)
        let shown = try #require(f.driver.presented.first)
        #expect(shown.anchor.notchRect == DropFixture.notch)
        #expect(shown.model.itemCount == 1)
        #expect(shown.model.layout.columns == 4)
        #expect(f.escape.starts == 1)
        // Never the expanded view, never focus.
        #expect(!f.host.isExpanded)
    }

    @Test func hoverLightsOnlyAZoneThatAccepts() async {
        let f = DropFixture()
        await f.start()
        _ = f.display.islandDragEntered(displayID: nil, items: DropFixture.text)
        #expect(f.display.displayDragEntered(at: f.center(of: "stash")) == .copy)
        #expect(f.display.model?.isLit("stash") == true)
        // Image to Text does not take a text file: unlit, drop refused.
        #expect(f.display.displayDragUpdated(at: f.center(of: "ocr")) == [])
        #expect(f.display.model?.hoveredZoneID == "ocr")
        #expect(f.display.model?.isLit("ocr") == false)
        #expect(!f.display.performDrop(at: f.center(of: "ocr"), items: DropFixture.text))
        #expect(f.log.all.isEmpty)
        #expect(!f.display.isOpen)
    }

    @Test func optionHeldIsReadDuringTheDrag() async {
        let f = DropFixture()
        await f.start()
        _ = f.display.islandDragEntered(displayID: nil, items: DropFixture.png())
        _ = f.display.displayDragEntered(at: f.center(of: "ask"))
        #expect(f.display.model?.optionHeld == false)
        f.modifiers = [.option]
        _ = f.display.displayDragUpdated(at: f.center(of: "ask"))
        #expect(f.display.model?.optionHeld == true)
        #expect(f.display.model?.isLit("ask") == true)
    }

    @Test func dropCallsExactlyOneHandlerWithPayloadSourceAndModifiers() async throws {
        let f = DropFixture()
        await f.start()
        let items = DropFixture.png()
        _ = f.display.islandDragEntered(displayID: nil, items: items)
        f.display.islandDragExited()
        _ = f.display.displayDragEntered(at: f.center(of: "ask"))
        f.modifiers = [.option]
        #expect(f.display.performDrop(at: f.center(of: "ask"), items: items))
        #expect(!f.display.isOpen)
        #expect(f.driver.retracts == 1)
        let result = await f.display.pendingDrop?.value
        guard case .accepted = result else {
            Issue.record("expected accepted, got \(String(describing: result))")
            return
        }
        let calls = f.log.all
        #expect(calls.count == 1)
        #expect(calls.first?.id == "ask")
        #expect(calls.first?.payload.urls == items.fileURLs)
        #expect(calls.first?.payload.source == .dropDisplay)
        #expect(calls.first?.payload.modifiers == .option)
        f.display.dragEnded()
        #expect(f.log.all.count == 1)
    }

    @Test func escRetractsWithoutActionAndTheSameDragDoesNotReopen() async {
        let f = DropFixture()
        await f.start()
        let items = DropFixture.png()
        _ = f.display.islandDragEntered(displayID: nil, items: items)
        f.escape.press()
        #expect(!f.display.isOpen)
        #expect(f.driver.retracts == 1)
        #expect(f.display.islandDragEntered(displayID: nil, items: items) == [])
        #expect(!f.display.isOpen)
        f.display.dragEnded()
        // A new drag opens it again.
        _ = f.display.islandDragEntered(displayID: nil, items: DropFixture.png("next.png"))
        #expect(f.display.isOpen)
        #expect(f.log.all.isEmpty)
    }

    @Test func leavingTheNotchAndTheDisplayRetractsWithoutAction() async {
        let f = DropFixture()
        await f.start()
        _ = f.display.islandDragEntered(displayID: nil, items: DropFixture.png())
        // The island reports an exit when the display opens over it; the drag lands on the display in time.
        f.display.islandDragExited()
        _ = f.display.displayDragEntered(at: f.center(of: "stash"))
        try? await Task.sleep(for: .milliseconds(60))
        #expect(f.display.isOpen)
        f.display.displayDragExited()
        #expect(await eventually { !f.display.isOpen })
        #expect(f.log.all.isEmpty)
    }

    @Test func dragEndedOrReleaseOutsideZonesRetractsWithoutAction() async {
        let f = DropFixture()
        await f.start()
        _ = f.display.islandDragEntered(displayID: nil, items: DropFixture.png())
        f.display.dragEnded()
        #expect(!f.display.isOpen)
        _ = f.display.islandDragEntered(displayID: nil, items: DropFixture.png("b.png"))
        #expect(!f.display.performDrop(at: CGPoint(x: 350, y: 100), items: DropFixture.png("b.png")))
        #expect(!f.display.isOpen)
        #expect(f.log.all.isEmpty)
    }

    @Test func filePromisesAreMaterializedIntoTheDropsDirectoryBeforeTheHandler() async throws {
        let f = DropFixture()
        await f.start()
        let promise = FakePromise(name: "photo.png")
        let items = DropDragItems(promises: [promise], sequence: 9)
        _ = f.display.islandDragEntered(displayID: nil, items: items)
        _ = f.display.displayDragEntered(at: f.center(of: "ocr"))
        #expect(f.display.model?.isLit("ocr") == true)
        #expect(f.display.performDrop(at: f.center(of: "ocr"), items: items))
        // Asked synchronously, inside the drop.
        let folder = try #require(promise.folders.first)
        #expect(folder.deletingLastPathComponent().standardizedFileURL == f.drops.standardizedFileURL)
        _ = await f.display.pendingDrop?.value
        let call = try #require(f.log.all.first)
        #expect(call.id == "ocr")
        #expect(call.payload.urls == [folder.appendingPathComponent("photo.png")])
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("photo.png").path))
        #expect(call.payload.source == .dropDisplay)
    }

    @Test func materializerWithoutPromisesReturnsAtOnceAndWithoutDirectoryThrows() async throws {
        let none = try FilePromiseMaterializer.start([], in: nil)
        #expect(await none.files().urls.isEmpty)
        #expect(throws: FilePromiseMaterializer.Failure.noDropsDirectory) {
            try FilePromiseMaterializer.start([FakePromise(name: "x.png")], in: nil)
        }
    }

    @Test func bandCountsTheDraggedItems() async {
        let f = DropFixture()
        await f.start()
        let items = DropDragItems(
            fileURLs: [URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/b.png")], sequence: 4)
        _ = f.display.islandDragEntered(displayID: nil, items: items)
        #expect(f.display.model?.itemCount == 2)
        #expect(DropDisplayModel.bandCount(2) == "2 ITEMS")
        #expect(DropDisplayModel.bandCount(1) == "1 ITEM")
        #expect(DropDisplayModel.bandPrefix() == "DROP ·")
        #expect(DropDisplayModel.bandCancel() == "ESC · CANCEL")
    }

    @Test func sampleZonesSimulateTheDisplay() async {
        let f = DropFixture()
        f.display.simulate(zones: DropSampleZones.make(), hovered: "sample.stash", for: .milliseconds(30))
        #expect(f.display.isOpen)
        #expect(f.display.model?.layout.columns == 2, "the sample Stash alone (2 × 2)")
        #expect(DropSampleZones.make().map(\.id) == ["sample.stash"])
        #expect(f.display.model?.isLit("sample.stash") == true)
        #expect(String(localized: DropSampleZones.make()[0].meta!) == "KEEP 7 DAYS · 5 ITEMS")
        #expect(await eventually { !f.display.isOpen })
    }
}

// MARK: - Peeks wait (UX-DR92)

@MainActor @Suite struct DropDisplayPeekTests {
    @Test func peeksWaitWhileTheDropDisplayIsOpenAndShowAfter() async {
        var open = true
        let h = PeekHarness()
        let presenter = PeekPresenter(
            anchors: h.anchors, theme: h.themeController, driver: h.driver, clock: h.clock,
            pointer: { NSPoint(x: 700, y: 980) }, announce: { _ in }, isDropDisplayOpen: { open },
            logger: testLogger)
        _ = presenter.show(PeekHarness.alert("session.done", severity: .info, title: "done"))
        _ = presenter.show(PeekHarness.alert(module: "m2", title: "blocked"))
        #expect(presenter.visible == nil)
        #expect(h.driver.presented.isEmpty)
        #expect(presenter.queuedAlerts.map(\.event.title) == ["blocked", "done"])
        presenter.resume()  // still open: nothing
        #expect(presenter.visible == nil)
        open = false
        presenter.resume()
        // The most urgent shows first; the other follows its dwell (Story 3.9).
        #expect(presenter.visible?.event.title == "blocked")
        #expect(presenter.queuedAlerts.map(\.event.title) == ["done"])
    }

    @Test func aBlockedPeekDoesNotPreemptWhileTheDisplayIsOpen() async {
        var open = false
        let h = PeekHarness()
        let presenter = PeekPresenter(
            anchors: h.anchors, theme: h.themeController, driver: h.driver, clock: h.clock,
            pointer: { NSPoint(x: 700, y: 980) }, announce: { _ in }, isDropDisplayOpen: { open },
            logger: testLogger)
        _ = presenter.show(PeekHarness.alert("session.done", severity: .info, title: "done"))
        #expect(presenter.visible?.event.title == "done")
        open = true
        _ = presenter.show(PeekHarness.alert(module: "m2", title: "blocked"))
        #expect(presenter.visible?.event.title == "done")
        #expect(h.driver.presented.count == 1)
    }

    @Test func hostClosingTheDisplayResumesPeeks() async {
        let f = DropFixture()
        await f.start()
        var resumed = 0
        f.display.onClose = { resumed += 1 }
        _ = f.display.islandDragEntered(displayID: nil, items: DropFixture.png())
        f.display.cancel()
        #expect(resumed == 1)
    }
}

// MARK: - Non-file drags and readouts (Story 9.2)

@MainActor @Suite(.serialized) struct DropDisplayContentTests {
    @Test func textLinkAndImageDragsOpenTheDisplayAndReachTheHandler() async throws {
        let f = DropFixture()
        await f.start()
        let link = try #require(URL(string: "https://example.com"))
        let cases: [(DropDragItems, UTType)] = [
            (DropDragItems(sequence: 21, text: "hello"), .plainText),
            (DropDragItems(sequence: 22, webURL: link), .url),
            (DropDragItems(sequence: 23, imageData: Data([1, 2, 3])), .image),
        ]
        for (items, type) in cases {
            #expect(items.hasContent && !items.hasFiles)
            #expect(items.contentTypes == [type])
            #expect(items.count == 1)
            #expect(f.display.islandDragEntered(displayID: nil, items: items) == .copy)
            #expect(f.display.isOpen)
            _ = f.display.displayDragEntered(at: f.center(of: "stash"))
            #expect(f.display.performDrop(at: f.center(of: "stash"), items: items))
            _ = await f.display.pendingDrop?.value
            f.display.dragEnded()
        }
        let payloads = f.log.all.map(\.payload)
        #expect(payloads.count == 3)
        #expect(payloads.allSatisfy { $0.urls.isEmpty && $0.source == .dropDisplay })
        #expect(payloads[0].text == "hello")
        #expect(payloads[1].url == link)
        #expect(payloads[2].imageData == Data([1, 2, 3]))
        // Image to Text takes the image type but not text.
        #expect(DropZones.imageToText().accepts(contentTypes: cases[2].0.contentTypes))
        #expect(!DropZones.imageToText().accepts(contentTypes: cases[0].0.contentTypes))
    }

    @Test func draggedTypesIncludeLinksImagesAndText() {
        let types = DropDragItems.draggedTypes
        #expect(types.first == .fileURL)
        for type in [NSPasteboard.PasteboardType.URL, .png, .tiff, .string] { #expect(types.contains(type)) }
    }

    @Test func aReadoutResultShowsAsTheTransientReadout() async throws {
        let f = DropFixture()
        let refusing = DropZone(
            id: "refuse", label: "REFUSE", glyph: "drop.stash", accentToken: "iris-2", role: .primary,
            cell: DropCell(preferredColumn: 1, preferredRow: 1, span: .init(columns: 2, rows: 2)), order: 0,
            accepts: [], handler: { _ in .readout("NOT STASHED") })
        f.shelf.dropZones = [refusing]
        await f.start()
        let items = DropFixture.png()
        _ = f.display.islandDragEntered(displayID: nil, items: items)
        #expect(f.display.performDrop(at: f.center(of: "refuse"), items: items))
        _ = await f.display.pendingDrop?.value
        #expect(f.host.transient == .message("NOT STASHED"))
        #expect(TransientReadout.message("NOT STASHED").text == "NOT STASHED")
    }
}
