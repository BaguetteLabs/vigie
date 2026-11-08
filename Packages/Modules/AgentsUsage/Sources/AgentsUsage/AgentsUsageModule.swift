import AgentKit
import Foundation
import ModuleKit
import Observation
import os

/// `agents.usage` (SPEC §7.2): token and cost history from agents' local logs (Story 7.1). Plan limits (7.3),
/// the Usage tab and rings (7.4+) build on it.
///
/// App assembly passes the same `AgentAdapters` value as `agents.sessions` (AD-4, AD-23). The module owns the
/// only SQLite database (AD-11), `usage.sqlite` in its `context.storage` folder, filled by ``UsageIngestor`` off
/// the main actor at start and every 60 s (timer only: no file watch yet).
@MainActor @Observable
public final class AgentsUsageModule: NotchModule {
    nonisolated static let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)

    /// How often logs are ingested.
    nonisolated static let ingestInterval: Duration = .seconds(60)

    public nonisolated static let staticManifest = ModuleManifest(
        id: "agents.usage",
        name: LocalizedStringResource("agentsUsage.module.name", bundle: bundle),
        icon: "chart.bar",
        defaultEnabled: true
    )

    public let manifest = AgentsUsageModule.staticManifest
    /// No closed-notch presence until the rings arrive (Story 7.4).
    public private(set) var state: ModuleState = .hidden

    public let adapters: AgentAdapters
    /// Each adapter's read-only settings at `[modules."agents.sessions".adapters.<id>]` (AD-23).
    @ObservationIgnored let adapterSettings: @Sendable (any AgentAdapter) -> any ReadOnlySettings
    @ObservationIgnored let calendar: Calendar

    /// The query API, available once started.
    public private(set) var history: UsageHistory?
    /// The last ingest pass.
    public private(set) var lastIngest: IngestReport?
    public private(set) var registry: UsageProviderRegistry?

    @ObservationIgnored var ingestor: UsageIngestor?
    @ObservationIgnored var ingestTask: Task<Void, Never>?
    @ObservationIgnored var ingestToken: RegistrationToken?

    public init(
        adapters: AgentAdapters,
        adapterSettings: (@Sendable (any AgentAdapter) -> any ReadOnlySettings)? = nil,
        calendar: Calendar = .current
    ) {
        self.adapters = adapters
        self.adapterSettings =
            adapterSettings ?? { adapter in DefaultsReadOnlySettings(descriptors: adapter.settings) }
        self.calendar = calendar
    }

    public func start(context: any ModuleContext) async throws {
        let log = context.log
        let store = try UsageStore(directory: context.storage.directory)
        let estimator = try CostEstimator.bundled()
        let registry = UsageProviderRegistry(adapters: adapters, settings: adapterSettings)
        self.registry = registry
        history = UsageHistory(store: store, estimator: estimator, calendar: calendar)
        let ingestor = UsageIngestor(store: store, registry: registry, log: log)
        self.ingestor = ingestor
        log.info(
            "agents.usage started: providers \(registry.ids.map(\.rawValue).joined(separator: ","), privacy: .public)"
        )
        ingestTask = Task.detached { [weak self] in
            let report = await ingestor.ingest()
            await self?.finished(report)
        }
        ingestToken = context.scheduler.every(Self.ingestInterval) { [weak self] in
            let report = await ingestor.ingest()
            await self?.finished(report)
        }
    }

    public func stop() async {
        ingestTask?.cancel()
        ingestTask = nil
        ingestToken?.cancel()
        ingestToken = nil
    }

    /// Runs one ingest pass now (tests, and later a manual refresh).
    @discardableResult
    public func ingestNow() async -> IngestReport? {
        guard let ingestor else { return nil }
        let report = await ingestor.ingest()
        finished(report)
        return report
    }

    /// Waits for the ingest started by `start` (tests).
    func waitForInitialIngest() async {
        await ingestTask?.value
    }

    private func finished(_ report: IngestReport) {
        lastIngest = report
    }
}
