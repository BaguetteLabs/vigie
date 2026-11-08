import AgentKit
import Foundation
import ModuleKit

/// The remote plan windows of one provider (Story 7.3), for the Usage card (7.4) and Home (11.2).
///
/// After a failed refresh the last good `windows` and `fetchedAt` stay and `isStale` is true: the card shows
/// `STALE · HH:MM` with `fetchedAt`, the ring keeps its value, never a wrong number (PRD FR-30).
public struct PlanState: Hashable, Sendable {
    public var windows: [UsageWindow]
    /// Time of the last good fetch; nil before the first.
    public var fetchedAt: Date?
    /// The last refresh failed (values, if any, are from `fetchedAt`).
    public var isStale: Bool
    public var lastError: PlanUsageError?
    /// Time of the last refresh attempt.
    public var attemptedAt: Date?

    public init(
        windows: [UsageWindow] = [], fetchedAt: Date? = nil, isStale: Bool = false, lastError: PlanUsageError? = nil,
        attemptedAt: Date? = nil
    ) {
        self.windows = windows
        self.fetchedAt = fetchedAt
        self.isStale = isStale
        self.lastError = lastError
        self.attemptedAt = attemptedAt
    }
}

/// The plan-usage keys at `[modules."agents.sessions".adapter.<id>]` (SPEC §11) and their values.
public enum PlanSettings {
    /// `usage_providers` entry for remote plan limits.
    public static let planSource = "plan"
    public static let authKey = "plan_auth"
    public static let tokenKey = "plan_token"
    /// `plan_auth` value for a pasted token; any other declared value reads the provider's external credential.
    public static let tokenAuth = "token"
}

extension UsageSeries {
    /// This series with the provider's plan windows (AD-23: one provider, local and remote merged).
    public func merging(plan: PlanState?) -> UsageSeries {
        var merged = self
        merged.windows = plan?.windows ?? []
        return merged
    }
}

// MARK: - Refresh loop

extension AgentsUsageModule {
    /// The minimum age of the last attempt before an expanded-view open refreshes again.
    nonisolated static let expandedRefreshMinimumAge: TimeInterval = 60
    nonisolated static let setupProblemKind = "setup.problem"
    nonisolated static func planDedupeKey(_ id: AgentID) -> String { "plan:\(id.rawValue)" }

    /// Adapters that offer a usage provider (whether or not `plan` is on).
    var planAdapters: [any AgentAdapter] { adapters.adapters.filter { $0.usageProvider != nil } }

    /// Whether `usage_providers` contains `plan` for `id`.
    public func isPlanEnabled(_ id: AgentID) -> Bool {
        guard let adapter = adapters.adapter(for: id) else { return false }
        let sources = adapterSettings(adapter).value(UsageProviderRegistry.usageProvidersKey, as: [String].self)
        return sources?.contains(PlanSettings.planSource) ?? false
    }

    /// The plan state for `id`; nil while `plan` is off or before the first refresh.
    public func planState(for id: AgentID) -> PlanState? { planStates[id] }

    /// Usage from local logs merged with the provider's plan windows (one `claude` provider, AD-23).
    public func usage(since: Date, until: Date, bucket: UsageBucket, provider: AgentID) async throws -> UsageSeries? {
        guard let history else { return nil }
        let series = try await history.usage(since: since, until: until, bucket: bucket, provider: provider)
        return series.merging(plan: planStates[provider])
    }

    /// Call from the Usage card or tab `.task` when the expanded view opens: refreshes each enabled provider
    /// whose last attempt is older than a minute.
    public func expandedViewDidAppear() async {
        let now = self.now()
        for adapter in planAdapters where isPlanEnabled(adapter.id) {
            if let last = planStates[adapter.id]?.attemptedAt,
                now.timeIntervalSince(last) < Self.expandedRefreshMinimumAge
            {
                continue
            }
            await refreshPlan(adapter.id)
        }
    }

    /// Refreshes every provider whose `usage_providers` has `plan`. No network for the others.
    public func refreshPlans() async {
        for adapter in planAdapters {
            await refreshPlan(adapter.id)
        }
    }

    /// One refresh: `plan` off → state and alert dropped, no request; else fetch and merge, or keep the last
    /// good values stale and raise one setup problem.
    public func refreshPlan(_ id: AgentID) async {
        guard let adapter = adapters.adapter(for: id), let provider = adapter.usageProvider else { return }
        guard isPlanEnabled(id) else {
            dropPlan(id)
            return
        }
        guard let context = adapterContexts[id] else {
            if planMissingContextLogged.insert(id).inserted {
                log?.error("No adapter context for \(id.rawValue, privacy: .public): plan usage off")
            }
            return
        }
        guard planInFlight.insert(id).inserted else { return }
        defer { planInFlight.remove(id) }
        let attempted = now()
        do {
            let snapshot = try await provider.fetch(context: context)
            guard isPlanEnabled(id) else { return dropPlan(id) }
            planStates[id] = PlanState(
                windows: snapshot.windows, fetchedAt: snapshot.fetchedAt, isStale: false, lastError: nil,
                attemptedAt: attempted)
            planAlerts.removeValue(forKey: id)?.resolve()
            log?.info("Plan usage for \(id.rawValue, privacy: .public): \(snapshot.windows.count) windows")
        } catch is CancellationError {
            return
        } catch {
            guard isPlanEnabled(id) else { return dropPlan(id) }
            let failure = (error as? PlanUsageError) ?? .unavailable(status: nil)
            var state = planStates[id] ?? PlanState()
            state.isStale = true
            state.lastError = failure
            state.attemptedAt = attempted
            planStates[id] = state
            log?.notice(
                "Plan usage for \(id.rawValue, privacy: .public) failed: \(String(describing: failure), privacy: .public)"
            )
            raisePlanProblem(adapter, provider: provider, error: failure)
        }
    }

    /// `plan` turned off or consent revoked: forget the windows and resolve the alert.
    func dropPlan(_ id: AgentID) {
        planStates[id] = nil
        planAlerts.removeValue(forKey: id)?.resolve()
    }

    func planAuth(_ adapter: any AgentAdapter) -> String {
        adapterSettings(adapter).value(PlanSettings.authKey, as: String.self) ?? PlanSettings.tokenAuth
    }

    /// Raised once per provider (dedupe `plan:<id>`) until the next success. Choices the user has not finished
    /// (no consent yet, no token pasted yet) are shown in Settings only.
    private func raisePlanProblem(_ adapter: any AgentAdapter, provider: any UsageProvider, error: PlanUsageError) {
        if error == .consentRequired { return }
        if error == .credentialMissing, planAuth(adapter) == PlanSettings.tokenAuth { return }
        guard planAlerts[adapter.id] == nil, let notifier else { return }
        planAlerts[adapter.id] = notifier.post(Self.planProblemEvent(adapter.id, provider: provider, error: error))
    }

    nonisolated static func planProblemEvent(_ id: AgentID, provider: any UsageProvider, error: PlanUsageError)
        -> NotifierEvent
    {
        let name = String(localized: provider.name)
        let body: String
        switch error {
        case .formatChanged: body = UsageText.string("agentsUsage.plan.problem.formatChanged")
        case .unavailable: body = UsageText.string("agentsUsage.plan.problem.network")
        case .unauthorized, .credentialExpired, .credentialMissing, .consentRequired:
            body =
                provider.externalCredential.map {
                    UsageText.format("agentsUsage.plan.problem.signIn", $0.displayName)
                } ?? UsageText.string("agentsUsage.plan.problem.token")
        }
        return NotifierEvent(
            kind: setupProblemKind, severity: .warn,
            title: UsageText.format("agentsUsage.plan.problem.title", name), body: body,
            action: .openSettings(pane: staticManifest.id.rawValue), dedupeKey: planDedupeKey(id),
            category: UsageText.string("agentsUsage.plan.problem.category"))
    }

    // MARK: Settings actions

    /// Adds or removes `plan` in `usage_providers`; the key observer then refreshes or drops the state.
    public func setPlanEnabled(_ enabled: Bool, for id: AgentID) async throws {
        guard let store = adapterSettingsStores[id], let adapter = adapters.adapter(for: id) else {
            throw ModuleServiceError.notAvailable
        }
        let current =
            adapterSettings(adapter).value(UsageProviderRegistry.usageProvidersKey, as: [String].self)
            ?? [UsageProviderRegistry.localSource]
        var next = current.filter { $0 != PlanSettings.planSource }
        if enabled { next.append(PlanSettings.planSource) }
        // The key observer started in `startPlanRefresh` refreshes (or drops the state).
        if next != current { try await store.set(next, for: UsageProviderRegistry.usageProvidersKey) }
    }

    /// Writes `plan_auth` (local); the key observer then refreshes.
    public func setPlanAuth(_ value: String, for id: AgentID) async throws {
        guard let store = adapterSettingsStores[id] else { throw ModuleServiceError.notAvailable }
        try await store.set(value, for: PlanSettings.authKey)
    }

    /// The user clicked Allow: records the consent (local.toml), then refreshes (macOS may prompt now).
    public func grantPlanConsent(for id: AgentID) async throws {
        guard let context = adapterContexts[id],
            let descriptor = adapters.adapter(for: id)?.usageProvider?
                .externalCredential
        else { throw ModuleServiceError.notAvailable }
        try await context.secrets.grantConsent(for: descriptor)
        await refreshPlan(id)
    }

    /// `Stop using …'s login`: revokes the consent at once and drops the in-memory plan state.
    public func revokePlanConsent(for id: AgentID) async throws {
        guard let context = adapterContexts[id],
            let descriptor = adapters.adapter(for: id)?.usageProvider?
                .externalCredential
        else { throw ModuleServiceError.notAvailable }
        dropPlan(id)
        try await context.secrets.revokeConsent(for: descriptor)
    }

    /// Whether the user allowed reading the provider's external credential on this Mac.
    public func hasPlanConsent(for id: AgentID) async -> Bool {
        guard let context = adapterContexts[id],
            let descriptor = adapters.adapter(for: id)?.usageProvider?
                .externalCredential
        else { return false }
        return await context.secrets.hasConsent(for: descriptor)
    }

    // MARK: Lifecycle

    /// At start: one refresh now, one job every provider interval (5 min), and a refresh whenever the plan keys
    /// change. Nothing at all when no adapter has a usage provider.
    func startPlanRefresh(scheduler: any Scheduler) {
        let providers = planAdapters.compactMap(\.usageProvider)
        guard let interval = providers.map(\.refreshInterval).min() else { return }
        planTask = Task { [weak self] in await self?.refreshPlans() }
        planJob = scheduler.every(interval) { [weak self] in await self?.refreshPlans() }
        for adapter in planAdapters {
            guard let store = adapterSettingsStores[adapter.id] else { continue }
            for key in [UsageProviderRegistry.usageProvidersKey, PlanSettings.authKey] {
                let stream = store.observe(key)
                let id = adapter.id
                planObservers.append(
                    Task { [weak self] in
                        for await _ in stream {
                            await self?.refreshPlan(id)
                        }
                    })
            }
        }
    }

    func stopPlanRefresh() {
        planTask?.cancel()
        planTask = nil
        planJob?.cancel()
        planJob = nil
        for task in planObservers { task.cancel() }
        planObservers.removeAll()
        let open = planAlerts.values
        planAlerts.removeAll()
        for handle in open { handle.resolve() }
    }

    /// Waits for the refresh started by `start` (tests).
    func waitForInitialPlanRefresh() async {
        await planTask?.value
    }
}

/// Catalog lookups of the `agents.usage` strings.
enum UsageText {
    static func string(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }

    static func format(_ key: String, _ arguments: any CVarArg...) -> String {
        String(format: string(key), locale: .current, arguments: arguments)
    }

    /// The catalog's locale (uppercasing, weekday names).
    static var locale: Locale { Locale(identifier: Bundle.module.preferredLocalizations.first ?? "en") }

    static func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: AgentsUsageModule.bundle)
    }
}
