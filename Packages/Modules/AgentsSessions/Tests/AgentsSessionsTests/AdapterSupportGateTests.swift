import AgentKit
import Foundation
import ModuleKit
import Testing

@testable import AgentsSessions

@MainActor @Suite struct AdapterSupportGateTests {
    nonisolated static let v = AgentVersion(raw: "9.9.9 (Fake)")

    struct Run {
        let module: AgentsSessionsModule
        let notifier: RecordingNotifier
    }

    /// Starts the module with a fake adapter in `support`, sends one `prompt.submit` and drains.
    func run(_ support: AdapterSupport) async throws -> Run {
        let notifier = RecordingNotifier()
        let context = FakeModuleContext(notifier: notifier)
        let module = AgentsSessionsModule(
            adapters: AgentAdapters([FakeAdapter(supportState: support)]), terminals: TerminalAdapters([]),
            liveness: FakeLiveness())
        try await module.start(context: context)
        // Sent right after start: before the version check finishes, so the gate must buffer, not drop.
        context.fakeEvents.send(try Hook.message("prompt.submit", at: Date()))
        context.fakeEvents.finish()
        await module.eventTask?.value
        return Run(module: module, notifier: notifier)
    }

    func supportAlerts(_ notifier: RecordingNotifier) -> [NotifierEvent] {
        notifier.events.filter { $0.kind == "setup.problem" }
    }

    @Test(arguments: [AdapterSupport.supported(v), .assumed(v)])
    func supportedVersionsLetEventsThrough(_ support: AdapterSupport) async throws {
        let r = try await run(support)
        #expect(r.module.sessions.count == 1)
        #expect(r.module.adapterSupport["fake"] == support)
        #expect(supportAlerts(r.notifier).isEmpty)
    }

    @Test func unsupportedVersionDropsEventsAndAlerts() async throws {
        let r = try await run(.unsupported(Self.v))
        #expect(r.module.sessions.isEmpty)
        let alerts = supportAlerts(r.notifier)
        #expect(alerts.count == 1)
        let alert = try #require(alerts.first)
        #expect(alert.title == "Fake adapter: CLI version 9.9.9 unsupported")
        #expect(alert.category == "AGENT")
        #expect(alert.severity == .warn)
        #expect(alert.dedupeKey == "support:fake")
        #expect(alert.action == .openSettings(pane: "agents.sessions"))
        #expect(alert.body?.isEmpty == false)

        // Checking again does not re-post; a supported version resolves it.
        await r.module.refreshAdapterSupport()
        #expect(supportAlerts(r.notifier).count == 1)
        r.module.updateSupportAlert(FakeAdapter(), support: .supported(Self.v))
        #expect(r.notifier.openKinds.contains("setup.problem") == false)
        await r.module.stop()
    }

    @Test func notInstalledDropsEventsWithoutAlert() async throws {
        let r = try await run(.notInstalled)
        #expect(r.module.sessions.isEmpty)
        #expect(supportAlerts(r.notifier).isEmpty)
    }

    @Test func pipelineGatesPerAdapter() throws {
        let pipeline = HookPipeline(
            adapters: AgentAdapters([FakeAdapter()]), log: .init(subsystem: "test", category: "gate"))
        let message = try Hook.message("prompt.submit", at: Date())
        #expect(pipeline.normalize(message).isEmpty)
        pipeline.setSupport(.assumed(Self.v), for: "fake")
        #expect(pipeline.normalize(message).count == 1)
        pipeline.setSupport(.unsupported(Self.v), for: "fake")
        #expect(pipeline.normalize(message).isEmpty)
    }

    @Test func stopResolvesTheAlert() async throws {
        let r = try await run(.unsupported(Self.v))
        #expect(r.notifier.openKinds.contains("setup.problem"))
        await r.module.stop()
        #expect(r.notifier.openKinds.contains("setup.problem") == false)
    }
}
