import AgentKit
import Foundation
import ModuleKit

/// The remote plan windows of one provider Account (Story 7.3, per Account since 7.10), for the Usage card (7.4)
/// and Home (11.2).
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
    /// `plan:<provider>` for the default Account (the 7.3 key), `plan:<provider>.<account>` for another.
    nonisolated static func planDedupeKey(_ key: UsageAccountKey) -> String { "plan:\(key)" }

    /// Adapters that offer a usage provider (whether or not `plan` is on).
    var planAdapters: [any AgentAdapter] { adapters.adapters.filter { $0.usageProvider != nil } }

    /// Every Account of every adapter with a usage provider, default Accounts first per adapter.
    var planAccounts: [UsageAccountKey] {
        planAdapters.flatMap { adapter in
            accounts(adapter).map { UsageAccountKey(provider: adapter.id, account: $0.id) }
        }
    }

    /// Whether the Account's `usage_providers` contains `plan` (opt-in per Account, PRD FR-30).
    public func isPlanEnabled(_ key: UsageAccountKey) -> Bool {
        guard let adapter = adapters.adapter(for: key.provider), let account = account(key) else { return false }
        let sources = adapterSettings(adapter).value(
            account.settingKey(UsageProviderRegistry.usageProvidersKey), as: [String].self)
        return sources?.contains(PlanSettings.planSource) ?? false
    }

    /// One Account's plan state (`"claude"`: the default Account); nil while `plan` is off or before the first
    /// refresh.
    public func planState(for key: UsageAccountKey) -> PlanState? { planStates[key] }

    /// Usage from local logs merged with the Account's plan windows (one `claude` provider, AD-23). `account`
    /// nil: every Account's tokens, the default Account's windows.
    public func usage(
        since: Date, until: Date, bucket: UsageBucket, provider: AgentID, account: AccountID? = nil
    ) async throws -> UsageSeries? {
        guard let history else { return nil }
        let series = try await history.usage(
            since: since, until: until, bucket: bucket, provider: provider, account: account)
        return series.merging(plan: planStates[UsageAccountKey(provider: provider, account: account ?? .default)])
    }

    /// Call from the Usage card or tab `.task` when the expanded view opens: refreshes each enabled Account
    /// whose last attempt is older than a minute.
    public func expandedViewDidAppear() async {
        let now = self.now()
        for key in planAccounts where isPlanEnabled(key) {
            if let last = planStates[key]?.attemptedAt, now.timeIntervalSince(last) < Self.expandedRefreshMinimumAge {
                continue
            }
            await refreshPlan(key)
        }
    }

    /// Refreshes every Account whose `usage_providers` has `plan`. No network for the others. Forgets the
    /// state of Accounts that no longer exist.
    public func refreshPlans() async {
        let known = Set(planAccounts)
        for key in planStates.keys where !known.contains(key) { dropPlan(key) }
        for key in planAccounts {
            await refreshPlan(key)
        }
    }

    /// One refresh of one Account: `plan` off → state and alert dropped, no request; else fetch and merge, or
    /// keep the last good values stale (on that Account only) and raise one setup problem.
    public func refreshPlan(_ key: UsageAccountKey) async {
        let id = key.provider
        guard let adapter = adapters.adapter(for: id), let provider = adapter.usageProvider else { return }
        guard let account = account(key), isPlanEnabled(key) else {
            dropPlan(key)
            return
        }
        guard let context = adapterContexts[id] else {
            if planMissingContextLogged.insert(id).inserted {
                log?.error("No adapter context for \(id.rawValue, privacy: .public): plan usage off")
            }
            return
        }
        guard planInFlight.insert(key).inserted else { return }
        defer { planInFlight.remove(key) }
        let attempted = now()
        do {
            let snapshot = try await provider.fetch(context: context, account: account)
            guard isPlanEnabled(key) else { return dropPlan(key) }
            planStates[key] = PlanState(
                windows: snapshot.windows, fetchedAt: snapshot.fetchedAt, isStale: false, lastError: nil,
                attemptedAt: attempted)
            planAlerts.removeValue(forKey: key)?.resolve()
            log?.info("Plan usage for \(key.description, privacy: .public): \(snapshot.windows.count) windows")
        } catch is CancellationError {
            return
        } catch {
            guard isPlanEnabled(key) else { return dropPlan(key) }
            let failure = (error as? PlanUsageError) ?? .unavailable(status: nil)
            var state = planStates[key] ?? PlanState()
            state.isStale = true
            state.lastError = failure
            state.attemptedAt = attempted
            planStates[key] = state
            log?.notice(
                "Plan usage for \(key.description, privacy: .public) failed: \(String(describing: failure), privacy: .public)"
            )
            raisePlanProblem(adapter, account: account, provider: provider, error: failure)
        }
    }

    /// `plan` turned off or consent revoked: forget the windows and resolve the alert.
    func dropPlan(_ key: UsageAccountKey) {
        if planStates[key] != nil { planStates[key] = nil }
        planAlerts.removeValue(forKey: key)?.resolve()
    }

    /// The default Account's `plan_auth`.
    func planAuth(_ adapter: any AgentAdapter) -> String {
        planAuth(adapter, account: AgentAccount(id: .default, label: "", location: nil))
    }

    func planAuth(_ adapter: any AgentAdapter, account: AgentAccount) -> String {
        adapterSettings(adapter).value(account.settingKey(PlanSettings.authKey), as: String.self)
            ?? PlanSettings.tokenAuth
    }

    /// Raised once per Account (dedupe `plan:<id>[.<account>]`) until the next success. Choices the user has not
    /// finished (no consent yet, no token pasted yet) are shown in Settings only.
    private func raisePlanProblem(
        _ adapter: any AgentAdapter, account: AgentAccount, provider: any UsageProvider, error: PlanUsageError
    ) {
        if error == .consentRequired { return }
        if error == .credentialMissing, planAuth(adapter, account: account) == PlanSettings.tokenAuth { return }
        let key = UsageAccountKey(provider: adapter.id, account: account.id)
        guard planAlerts[key] == nil, let notifier else { return }
        let name = Self.displayName(
            String(localized: provider.name), account: account, several: hasSeveralAccounts(adapter.id))
        planAlerts[key] = notifier.post(
            Self.planProblemEvent(key, name: name, credential: provider.externalCredential(for: account), error: error))
    }

    nonisolated static func planProblemEvent(_ id: AgentID, provider: any UsageProvider, error: PlanUsageError)
        -> NotifierEvent
    {
        planProblemEvent(
            UsageAccountKey(provider: id), name: String(localized: provider.name),
            credential: provider.externalCredential, error: error)
    }

    nonisolated static func planProblemEvent(
        _ key: UsageAccountKey, name: String, credential: ExternalCredentialDescriptor?, error: PlanUsageError
    ) -> NotifierEvent {
        let body: String
        switch error {
        case .formatChanged: body = UsageText.string("agentsUsage.plan.problem.formatChanged")
        case .unavailable: body = UsageText.string("agentsUsage.plan.problem.network")
        case .credentialDenied: body = UsageText.string("agentsUsage.plan.error.denied")
        case .unauthorized, .credentialExpired, .credentialMissing, .consentRequired:
            body =
                credential.map {
                    UsageText.format("agentsUsage.plan.problem.signIn", $0.displayName)
                } ?? UsageText.string("agentsUsage.plan.problem.token")
        }
        return NotifierEvent(
            kind: setupProblemKind, severity: .warn,
            title: UsageText.format("agentsUsage.plan.problem.title", name), body: body,
            action: .openSettings(pane: staticManifest.id.rawValue), dedupeKey: planDedupeKey(key),
            category: UsageText.string("agentsUsage.plan.problem.category"))
    }

    // MARK: Settings actions

    /// Adds or removes `plan` in the Account's `usage_providers`; the key observer then refreshes or drops the
    /// state.
    public func setPlanEnabled(_ enabled: Bool, for key: UsageAccountKey) async throws {
        guard let store = adapterSettingsStores[key.provider], let adapter = adapters.adapter(for: key.provider),
            let account = account(key)
        else {
            throw ModuleServiceError.notAvailable
        }
        let current = usageSources(adapter, account: account)
        var next = current.filter { $0 != PlanSettings.planSource }
        if enabled { next.append(PlanSettings.planSource) }
        // The key observers (``restartPlanObservers()``) refresh or drop the state.
        if next != current {
            try await store.set(next, for: account.settingKey(UsageProviderRegistry.usageProvidersKey))
        }
    }

    /// Writes the Account's `plan_auth` (local); the key observer then refreshes.
    public func setPlanAuth(_ value: String, for key: UsageAccountKey) async throws {
        guard let store = adapterSettingsStores[key.provider], let account = account(key) else {
            throw ModuleServiceError.notAvailable
        }
        try await store.set(value, for: account.settingKey(PlanSettings.authKey))
    }

    func planCredential(_ key: UsageAccountKey) -> (any AdapterContext, ExternalCredentialDescriptor)? {
        guard let context = adapterContexts[key.provider], let account = account(key),
            let descriptor = adapters.adapter(for: key.provider)?.usageProvider?.externalCredential(for: account)
        else { return nil }
        return (context, descriptor)
    }

    /// The user clicked Allow: records the consent (local.toml), clears what the provider held (a held login,
    /// a refused-prompt back-off), then refreshes (macOS may prompt now). One consent per Account: its own consent
    /// record (`claude.claude_code_login.<account>` past the default).
    public func grantPlanConsent(for key: UsageAccountKey) async throws {
        guard let (context, descriptor) = planCredential(key) else { throw ModuleServiceError.notAvailable }
        try await context.secrets.grantConsent(for: descriptor)
        await resetPlanCredential(key)
        await refreshPlan(key)
    }

    /// `Stop using …'s login`: revokes the Account's consent at once, drops its in-memory plan state and what
    /// the provider held for it.
    public func revokePlanConsent(for key: UsageAccountKey) async throws {
        guard let (context, descriptor) = planCredential(key) else { throw ModuleServiceError.notAvailable }
        dropPlan(key)
        try await context.secrets.revokeConsent(for: descriptor)
        await resetPlanCredential(key)
    }

    private func resetPlanCredential(_ key: UsageAccountKey) async {
        guard let account = account(key), let provider = adapters.adapter(for: key.provider)?.usageProvider else {
            return
        }
        await provider.resetExternalCredential(for: account)
    }

    /// Whether the user allowed reading the Account's external credential on this Mac.
    public func hasPlanConsent(for key: UsageAccountKey) async -> Bool {
        guard let (context, descriptor) = planCredential(key) else { return false }
        return await context.secrets.hasConsent(for: descriptor)
    }

    // MARK: Lifecycle

    /// At start: one refresh now, one job every provider interval (5 min), and a refresh whenever an Account's
    /// plan keys or the Account list change. Nothing at all when no adapter has a usage provider.
    func startPlanRefresh(scheduler: any Scheduler) {
        let providers = planAdapters.compactMap(\.usageProvider)
        guard let interval = providers.map(\.refreshInterval).min() else { return }
        planTask = Task { [weak self] in await self?.refreshPlans() }
        planJob = scheduler.every(interval) { [weak self] in await self?.refreshPlans() }
        restartPlanObservers()
    }

    /// (Re)subscribes to `accounts` and to each current Account's `usage_providers` and `plan_auth`.
    func restartPlanObservers() {
        for task in planObservers { task.cancel() }
        planObservers.removeAll()
        guard planJob != nil else { return }
        for adapter in planAdapters {
            guard let store = adapterSettingsStores[adapter.id] else { continue }
            let id = adapter.id
            let list = store.observe(AgentAccounts.listKey)
            planObservers.append(
                Task { [weak self] in
                    for await _ in list {
                        self?.restartPlanObservers()
                        await self?.refreshPlans()
                    }
                })
            for account in accounts(adapter) {
                let key = UsageAccountKey(provider: id, account: account.id)
                for field in [UsageProviderRegistry.usageProvidersKey, PlanSettings.authKey] {
                    let stream = store.observe(account.settingKey(field))
                    planObservers.append(
                        Task { [weak self] in
                            for await _ in stream {
                                await self?.refreshPlan(key)
                            }
                        })
                }
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
