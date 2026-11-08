import AgentKit
import Foundation
import ModuleKit
import Observation
import SwiftUI
import os

/// `agents.usage` (SPEC §7.2): token and cost history from agents' local logs (Story 7.1) and opt-in plan limits
/// merged into the same provider (Story 7.3, `PlanUsage.swift`); one quota ring per provider with plan windows on the
/// closed notch's left wing (Story 7.4, `QuotaRings.swift`). The Usage tab (7.7) builds on it.
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
        settings: RingSettings.descriptors(bundle: bundle),
        alertKinds: [setupProblemKind],
        defaultEnabled: true
    )

    public let manifest = AgentsUsageModule.staticManifest
    /// Ambient while a quota ring is offered, else hidden (FR53; Story 7.4 `updateRingState`).
    public internal(set) var state: ModuleState = .hidden

    public let adapters: AgentAdapters
    /// The same per-adapter contexts App assembly gives `agents.sessions` (AD-23): `http` and the adapter-scoped
    /// `secrets` for plan usage.
    public let adapterContexts: [AgentID: any AdapterContext]
    /// Writable adapter settings for the plan block of Settings (`usage_providers`, `plan_auth`).
    @ObservationIgnored let adapterSettingsStores: [AgentID: any AdapterSettingsStore]
    /// Each adapter's read-only settings at `[modules."agents.sessions".adapter.<id>]` (AD-23).
    @ObservationIgnored let adapterSettings: @Sendable (any AgentAdapter) -> any ReadOnlySettings
    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored let now: @Sendable () -> Date

    /// Plan windows per provider (Story 7.3); absent while `plan` is off.
    public internal(set) var planStates: [AgentID: PlanState] = [:] {
        didSet { updateRingState() }
    }
    /// `priority`, `order`, `rings` and the per-provider overrides (Story 7.4); defaults until `start`.
    public internal(set) var ringSettings = RingSettings()
    @ObservationIgnored var ringObservers: [Task<Void, Never>] = []
    @ObservationIgnored var planAlerts: [AgentID: AlertHandle] = [:]
    @ObservationIgnored var planInFlight: Set<AgentID> = []
    @ObservationIgnored var planMissingContextLogged: Set<AgentID> = []
    @ObservationIgnored var planTask: Task<Void, Never>?
    @ObservationIgnored var planJob: RegistrationToken?
    @ObservationIgnored var planObservers: [Task<Void, Never>] = []
    @ObservationIgnored var notifier: (any Notifier)?
    @ObservationIgnored var log: Logger?

    /// The query API, available once started.
    public private(set) var history: UsageHistory?
    /// The last ingest pass.
    public private(set) var lastIngest: IngestReport?
    public private(set) var registry: UsageProviderRegistry?

    @ObservationIgnored var ingestor: UsageIngestor?
    @ObservationIgnored var ingestTask: Task<Void, Never>?
    @ObservationIgnored var ingestToken: RegistrationToken?

    /// - Parameters:
    ///   - contexts: per-adapter contexts (the same as `agents.sessions`'s); an adapter without one gets no plan
    ///     usage.
    ///   - adapterSettingsStores: writable adapter settings for the Settings block.
    ///   - adapterSettings: overrides how adapter settings are read; default: the store, else the context's
    ///     settings, else the declared defaults.
    public init(
        adapters: AgentAdapters,
        contexts: [AgentID: any AdapterContext] = [:],
        adapterSettingsStores: [AgentID: any AdapterSettingsStore] = [:],
        adapterSettings: (@Sendable (any AgentAdapter) -> any ReadOnlySettings)? = nil,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.adapters = adapters
        self.adapterContexts = contexts
        self.adapterSettingsStores = adapterSettingsStores
        self.adapterSettings =
            adapterSettings ?? { adapter in
                if let store = adapterSettingsStores[adapter.id] { return ReadOnlyAdapterSettings(store) }
                if let context = contexts[adapter.id] { return context.settings }
                return DefaultsReadOnlySettings(descriptors: adapter.settings)
            }
        self.calendar = calendar
        self.now = now
    }

    public func start(context: any ModuleContext) async throws {
        let log = context.log
        self.log = log
        notifier = context.notifier
        startRingSettings(context.settings)
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
        startPlanRefresh(scheduler: context.scheduler)
    }

    public func settingsView() -> AnyView? {
        let adapters = planAdapters
        guard !adapters.isEmpty else { return nil }
        return AnyView(PlanSettingsView(module: self, adapters: adapters.map(\.id)))
    }

    public func stop() async {
        stopRingSettings()
        stopPlanRefresh()
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
