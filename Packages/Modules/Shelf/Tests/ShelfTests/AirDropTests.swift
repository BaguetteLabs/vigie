import Foundation
import ModuleKit
import Testing
import UniformTypeIdentifiers

@testable import Shelf

/// Records shares; never touches `NSSharingService`.
@MainActor
final class FakeAirDrop: AirDropSharing {
    var available = true
    private(set) var asked: [[URL]] = []
    private(set) var shared: [[URL]] = []

    func canShare(_ urls: [URL]) -> Bool {
        asked.append(urls)
        return available
    }

    func share(_ urls: [URL]) { shared.append(urls) }
}

@MainActor @Suite struct AirDropTests {
    static func harness(
        airdrop: Bool = true, imageToText: Bool = false, service: FakeAirDrop = FakeAirDrop()
    ) -> ShelfHarness {
        ShelfHarness(settings: ["airdrop": airdrop, "image_to_text": imageToText], airDrop: service)
    }

    @Test func zoneDeclaration() async throws {
        let h = ShelfHarness()
        try await h.start()
        let zone = h.module.airDropZone
        #expect(zone.id == "shelf.airdrop")
        #expect(zone.cell == DropCell(preferredColumn: 4, preferredRow: 1, span: .init(columns: 1, rows: 1)))
        #expect(zone.order == 20)
        #expect(zone.glyph == "drop.airdrop")
        #expect(String(localized: zone.label) == "AIRDROP")
        #expect(zone.meta.map { String(localized: $0) } == "NEARBY DEVICES")
        #expect(zone.releaseLine.map { String(localized: $0) } == "RELEASE TO SHARE")
        #expect(zone.isEnabled, "on by default")
        #expect(zone.progressReadout == nil)
        let mini = try #require(h.module.airDropMiniZone)
        #expect(mini.meta.map { String(localized: $0) } == "SHARE")
    }

    /// Files of any type (folders and promises too), never loose text, links or images.
    @Test(arguments: [
        ([UTType.png], nil as DropLooseContent?, true), ([.pdf], nil, true), ([.plainText], nil, true),
        ([.folder], nil, true), ([.data], nil, true), ([.plainText], .text, false), ([.url], .link, false),
        ([.image], .image, false),
    ])
    func acceptance(types: [UTType], loose: DropLooseContent?, lit: Bool) async throws {
        let h = Self.harness()
        try await h.start()
        #expect(h.module.airDropZone.accepts(contentTypes: types, loose: loose) == lit)
    }

    @Test func aDropOpensThePickerWithTheFilesAndStashesNothing() async throws {
        let service = FakeAirDrop()
        let h = Self.harness(service: service)
        try await h.start()
        let a = makeFile("a.pdf")
        let b = makeFile("b.png")
        let result = await h.module.airDropZone.handler(ShelfHarness.files(a, b))
        #expect(result.isAccepted)
        #expect(service.shared == [[a, b]])
        #expect(h.module.items.isEmpty)
        #expect(h.context.fakeActivity.entries.isEmpty)
    }

    @Test func unavailableReadsOutAndWritesAnActivityEntry() async throws {
        let service = FakeAirDrop()
        service.available = false
        let h = Self.harness(service: service)
        try await h.start()
        let result = await h.module.airDrop(ShelfHarness.files(makeFile("a.pdf")))
        #expect(result.readoutText == "AIRDROP UNAVAILABLE")
        #expect(service.shared.isEmpty)
        let entry = try #require(h.context.fakeActivity.entries.first)
        #expect(entry.kind == "shelf.airdrop")
        #expect(entry.outcome == .custom("unavailable"))
        #expect(entry.detail["reason"] == "cannot_share")
        #expect(h.context.fakeNotifier.posted.isEmpty, "no alert")
    }

    @Test func anUnreadableFileReadsOutWithoutAskingTheService() async throws {
        let service = FakeAirDrop()
        let h = Self.harness(service: service)
        try await h.start()
        let missing = makeTempDirectory().appendingPathComponent("gone.pdf")
        let result = await h.module.airDrop(ShelfHarness.files(missing))
        #expect(result.readoutText == "AIRDROP UNAVAILABLE")
        #expect(service.asked.isEmpty && service.shared.isEmpty)
        #expect(h.context.fakeActivity.entries.first?.detail["reason"] == "unreadable")
    }

    @Test func settingOffRejectsAndHides() async throws {
        let service = FakeAirDrop()
        let h = Self.harness(airdrop: false, service: service)
        try await h.start()
        #expect(!h.module.airDropZone.isEnabled)
        #expect(h.module.airDropMiniZone == nil)
        #expect(await h.module.airDrop(ShelfHarness.files(makeFile())).readoutText == nil)
        #expect(service.shared.isEmpty)
        let stopped = Self.harness()
        #expect(!stopped.module.airDropZone.isEnabled, "not started")
    }

    /// The Shelf's enabled zones for the host's reflow table (UX-DR83; the placement itself is the host's,
    /// covered by `DropGridLayoutTests`): both on fill column 4; one off leaves the other alone in it (it
    /// spans both rows); both off leave Stash alone (3 columns with Ask AI).
    @Test(arguments: [
        (true, true, ["shelf.stash", "shelf.airdrop", "shelf.image_to_text"]),
        (true, false, ["shelf.stash", "shelf.airdrop"]),
        (false, true, ["shelf.stash", "shelf.image_to_text"]),
        (false, false, ["shelf.stash"]),
    ])
    func gatingForTheReflow(airdrop: Bool, imageToText: Bool, enabled: [String]) async throws {
        let h = Self.harness(airdrop: airdrop, imageToText: imageToText)
        try await h.start()
        let zones = h.module.dropZones.filter(\.isEnabled)
        #expect(zones.map(\.id) == enabled)
        #expect(zones.filter { $0.id != "shelf.stash" }.allSatisfy { $0.cell.preferredColumn == 4 })
        #expect(h.module.sendToMiniZones.map(\.id) == enabled.filter { $0 != "shelf.stash" })
    }

    @Test func moduleOffHidesEveryShelfZone() async throws {
        let h = Self.harness(imageToText: true)
        try await h.start()
        await h.module.stop()
        #expect(h.module.dropZones.filter(\.isEnabled).isEmpty)
        #expect(h.module.sendToMiniZones.isEmpty)
    }
}
