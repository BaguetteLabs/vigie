import AppKit
import ModuleKit
import SwiftUI
import Testing
import UniformTypeIdentifiers
import VigieUI

@testable import VigieCore

/// Story 9.7: `context.dropZones` lists the running modules' zones with their owner and runs a zone's handler
/// through the host (same readout routing as a drop on the drop display).
@MainActor @Suite struct DropZoneDirectoryTests {
    @Test func listsTheRunningModulesZonesWithTheirOwnerInOrder() async {
        let f = DropFixture(imageToText: false)
        await f.start()
        let directory = CoreDropZoneDirectory(link: NotchHostLink(host: f.host))
        let zones = directory.zones()
        #expect(zones.map(\.id) == ["stash", "ask", "airdrop", "ocr"])
        #expect(zones.map(\.moduleID.rawValue) == ["shelf", "agents.sessions", "shelf", "shelf"])
        #expect(zones.map(\.isEnabled) == [true, true, true, false], "disabled zones listed, flagged")
        #expect(zones[3].accepts(contentTypes: [.png], loose: nil))
        #expect(!zones[3].accepts(contentTypes: [.plainText], loose: nil))
        f.enablement.set("agents.sessions", false)
        #expect(await eventually { !directory.zones().contains { $0.id == "ask" } }, "a stopped module's zones go")
    }

    @Test func performRunsTheHandlerOnceWithThePayloadAndRoutesTheReadout() async {
        let f = DropFixture()
        f.shelf.dropZones = [
            DropReadoutTests.zone("stash", accepts: []),
            DropReadoutTests.zone("airdrop", accepts: [.item]) { _ in .readout("AIRDROP UNAVAILABLE") },
        ]
        await f.start()
        let directory = CoreDropZoneDirectory(link: NotchHostLink(host: f.host))
        let file = URL(fileURLWithPath: "/tmp/a.pdf")
        let result = await directory.perform(
            zoneID: "airdrop", payload: DropPayload(urls: [file], modifiers: .option, source: .stashItem))
        guard case .readout = result else {
            Issue.record("expected the handler's readout")
            return
        }
        #expect(f.host.transient == .message("AIRDROP UNAVAILABLE"))
        #expect(f.display.lastDrop?.zoneID == "airdrop")
        #expect(f.display.lastDrop?.payload.source == .stashItem)
        #expect(f.display.lastDrop?.payload.modifiers == .option)
        #expect(!f.display.isOpen, "no drop display for a non-drag path")
    }

    @Test func unknownDisabledOrEmptyRunsNothing() async {
        let f = DropFixture(imageToText: false)
        await f.start()
        let directory = CoreDropZoneDirectory(link: NotchHostLink(host: f.host))
        let payload = DropPayload(urls: [URL(fileURLWithPath: "/tmp/a.png")], modifiers: [], source: .shelfTab)
        for id in ["nope", "ocr"] {
            guard case .rejected = await directory.perform(zoneID: id, payload: payload) else {
                Issue.record("\(id) should be rejected")
                return
            }
        }
        guard
            case .rejected = await directory.perform(
                zoneID: "stash", payload: DropPayload(urls: [], modifiers: [], source: .shelfTab))
        else {
            Issue.record("empty payload should be rejected")
            return
        }
        #expect(f.log.all.isEmpty)
        let unbound = CoreDropZoneDirectory(link: NotchHostLink())
        #expect(unbound.zones().isEmpty)
        guard case .rejected = await unbound.perform(zoneID: "stash", payload: payload) else {
            Issue.record("unbound directory should reject")
            return
        }
    }

    @Test func theFactoryHandsTheDirectoryToEveryContext() async {
        let f = DropFixture()
        let directory = CoreDropZoneDirectory(link: NotchHostLink(host: f.host))
        let factory = CoreModuleContextFactory(
            environment: makeEnvironment(makeTempDirectory()), eventBus: InProcessEventBus(), dropZones: directory)
        let context = factory.makeContext(
            for: ModuleManifest(id: "shelf", name: "Shelf", icon: "tray"), tracker: RegistrationTracker())
        await f.start()
        #expect(context.dropZones.zones().map(\.id) == directory.zones().map(\.id))
        let bare = CoreModuleContextFactory(
            environment: makeEnvironment(makeTempDirectory()), eventBus: InProcessEventBus()
        )
        .makeContext(for: ModuleManifest(id: "shelf", name: "Shelf", icon: "tray"), tracker: RegistrationTracker())
        #expect(bare.dropZones.zones().isEmpty)
    }
}
