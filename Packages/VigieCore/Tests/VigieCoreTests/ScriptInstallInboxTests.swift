import Foundation
import ModuleKit
import Testing
import Wire

@testable import VigieCore

/// Story 12.9: `vigie://install` links reach the integrations module through the inbox (queued until it subscribes),
/// `context.host.openOwnSettings` opens its pane only with an intent, and the source record lives in `local.toml`.
@MainActor @Suite struct ScriptInstallInboxTests {
    static let link = URL(string: "vigie://install?url=https://example.com/ci.md")!

    static func request(_ name: String) -> ScriptInstallRequest {
        ScriptInstallRequest(fileURL: URL(string: "https://example.com/\(name).md")!)
    }

    @Test func aLinkReceivedWhileLaunchingIsQueuedUntilTheModuleSubscribes() async {
        let inbox = ScriptInstallInbox()
        let router = AppURLRouter(scheme: "vigie", inbox: inbox, logger: testLogger)
        #expect(router.handle([Self.link]) == 1)
        #expect(inbox.pendingCount == 1)

        let (stream, finish) = inbox.subscribe()
        #expect(inbox.pendingCount == 0)
        inbox.submit(Self.request("second"))
        finish()
        var received: [ScriptInstallRequest] = []
        for await request in stream { received.append(request) }
        #expect(received.map(\.fileURL.lastPathComponent) == ["ci.md", "second.md"])
        #expect(received.first?.intent != nil, "the click on the link is a user intent")

        // After the subscription ends, links queue again for the next start.
        #expect(await eventually { !inbox.hasSubscriber })
        inbox.submit(Self.request("third"))
        #expect(inbox.pendingCount == 1)
    }

    @Test func otherURLsAreIgnored() {
        let inbox = ScriptInstallInbox()
        let router = AppURLRouter(scheme: "vigie-dev", inbox: inbox, logger: testLogger)
        let routed = router.handle([
            Self.link,  // the release scheme, in a dev build
            URL(string: "vigie-dev://open?url=https://a.com/x.md")!,
            URL(string: "vigie-dev://install")!,
            URL(string: "vigie-dev://install?url=https://a.com/x.md")!,
        ])
        #expect(routed == 1)
        #expect(inbox.pendingCount == 1)
    }

    @Test func scriptFolderStreamEndsWhenTheModuleStops() async {
        let inbox = ScriptInstallInbox()
        inbox.submit(Self.request("queued"))
        let tracker = RegistrationTracker()
        let folder = CoreScriptFolder(
            url: nil, builtInModuleIDs: [], tracker: tracker, installInbox: inbox)
        let stream = folder.installRequests()
        tracker.cancelAll()
        var received: [String] = []
        for await request in stream { received.append(request.fileURL.lastPathComponent) }
        #expect(received == ["queued.md"])
        // No inbox: an empty, finished stream.
        var none = 0
        for await _ in CoreScriptFolder(url: nil, builtInModuleIDs: [], tracker: tracker).installRequests() {
            none += 1
        }
        #expect(none == 0)
    }

    @Test func factoryHandsTheInboxToScriptFolder() {
        let inbox = ScriptInstallInbox()
        let factory = CoreModuleContextFactory(
            environment: makeEnvironment(makeTempDirectory()), eventBus: InProcessEventBus(), scriptInstalls: inbox)
        let context = factory.makeContext(
            for: ModuleManifest(id: "integrations", name: "Scripts", icon: "circle"), tracker: RegistrationTracker())
        #expect((context.scriptFolder as? CoreScriptFolder)?.installInbox === inbox)
    }

    @Test func openOwnSettingsNeedsAnIntent() async {
        let f = ExpandedFixture()
        await f.start()
        let control = CoreHostControl(moduleID: "integrations", link: NotchHostLink(host: f.host))
        control.openOwnSettings(focus: nil)
        #expect(f.openedPanes.isEmpty)
        control.openOwnSettings(focus: f.intent)
        #expect(f.openedPanes == ["integrations"])
        // Unbound link: nothing happens.
        CoreHostControl(moduleID: "integrations", link: NotchHostLink()).openOwnSettings(focus: f.intent)
        #expect(f.openedPanes == ["integrations"])
    }

    @Test func sourceRecordIsLocalOnly() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(config: "[general]\nopen_on_hover = false\n")
        let syncedBefore = try Data(contentsOf: fixture.configURL)
        let records = ConfigScriptConfirmations(store: store, tracker: RegistrationTracker())
        let path = "modules/ci.md"
        #expect(records.source(for: path) == nil)
        let installedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let source = ScriptSourceRecord(
            url: URL(string: "https://example.com/ci.md")!, signatureURL: URL(string: "https://example.com/ci.md.sig"),
            installedAt: installedAt)
        try await records.recordSource(path, source)
        let local = try String(contentsOf: fixture.localURL, encoding: .utf8)
        #expect(local.contains(#"[scripts.sources."modules/ci.md"]"#))
        #expect(local.contains(#"url = "https://example.com/ci.md""#))
        #expect(records.source(for: path) == source)
        #expect(try Data(contentsOf: fixture.configURL) == syncedBefore, "never synced (PRD FR-39)")
        #expect(store.problems.isEmpty)

        // Without a signature the `sig` key is removed; the next launch reads the record back.
        try await records.recordSource(
            path, ScriptSourceRecord(url: source.url, signatureURL: nil, installedAt: installedAt))
        let (reloaded, _) = try await fixture.makeStore()
        let again = ConfigScriptConfirmations(store: reloaded, tracker: RegistrationTracker())
        #expect(again.source(for: path)?.signatureURL == nil)
        #expect(again.source(for: path)?.installedAt == installedAt)
        #expect(reloaded.problems.isEmpty)
        store.stop()
        reloaded.stop()
    }
}
