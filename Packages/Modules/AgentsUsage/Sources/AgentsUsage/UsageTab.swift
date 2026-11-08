import AgentKit
import Foundation
import ModuleKit
import SwiftUI
import VigieUI

/// Story 7.7: the Usage tab (FR54, UX-DR31, UX-DR41, UX-DR44, UX-DR58, UX-DR78, UX-DR100).
extension AgentsUsageModule {
    /// Settings pane of the `NO USAGE PROVIDER` button: this module's pane (Settings › Usage).
    nonisolated static let settingsPane = "agents.usage"

    /// The Usage tab bound to the live snapshot: `usageTabSnapshot()` reads observed state (plan windows, ring
    /// settings, the dial clock, the last ingest), so the tab re-renders on each change and clock tick. Opening
    /// it refreshes plan windows older than a minute (`expandedViewDidAppear`). The `open-usage` peek action
    /// lands here through `host.openOwnTab`.
    public func expandedView() -> AnyView? {
        var settingsAction: (@MainActor () -> Void)?
        if let open = openSettings {
            settingsAction = { open(Self.settingsPane) }
        }
        return AnyView(
            UsageTabView(
                snapshot: { [weak self] in self?.usageTabSnapshot() ?? UsageTabSnapshot(providers: []) },
                onOpenSettings: settingsAction,
                onReorder: { [weak self] ids in
                    guard let self else { return }
                    Task { await self.setProviderOrder(shown: ids) }
                }
            )
            .task { [weak self] in
                await self?.refreshOverview()
                await self?.expandedViewDidAppear()
            })
    }

    /// The Home card (Story 11.2): one compact row per provider, bound to the live snapshot. Appearing is the
    /// expanded view opening, so it refreshes plan windows the same way the tab does. The Home grid's button
    /// around the card opens the tab (and its empty state's Settings button).
    public func homeCard() -> AnyView? {
        AnyView(
            UsageHomeCardView(snapshot: { [weak self] in
                self?.usageTabSnapshot() ?? UsageTabSnapshot(providers: [])
            })
            .task { [weak self] in
                await self?.refreshOverview()
                await self?.expandedViewDidAppear()
            })
    }

    /// What the tab shows at the dial clock: one card per Account, grouped under its provider (Story 7.10).
    public func usageTabSnapshot() -> UsageTabSnapshot {
        UsageTabSnapshot(
            providers: tabProviders.flatMap { adapter in tabAccounts(adapter).map { providerCard(adapter, account: $0) }
            },
            history: historyPanel, cost: costPanel)
    }

    /// The sources as the settings stand now (an Account added since start included).
    var currentRegistry: UsageProviderRegistry { UsageProviderRegistry(adapters: adapters, settings: adapterSettings) }

    /// The Accounts of a shown provider that have something to show: local logs read, or plan limits on. The
    /// default Account always shows when the provider has a single Account.
    func tabAccounts(_ adapter: any AgentAdapter) -> [AgentAccount] {
        let all = accounts(adapter)
        guard all.count > 1 else { return all }
        let local = currentRegistry
        let shown = all.filter { account in
            local.source(for: adapter.id, account: account.id) != nil
                || hasPlan(adapter, key: UsageAccountKey(provider: adapter.id, account: account.id))
        }
        return shown.isEmpty ? [all[0]] : shown
    }

    /// Every usage provider in the user's order (`order`, then registration order, A69): an adapter whose
    /// local logs are ingested (`usage_providers` has `local`) or whose plan limits are on.
    var tabProviders: [any AgentAdapter] {
        let local = currentRegistry
        let settings = ringSettings
        return adapters.adapters.enumerated()
            .filter { _, adapter in local.source(for: adapter.id) != nil || hasPlan(adapter) }
            .sorted {
                settings.orderIndex(of: $0.element.id, registrationIndex: $0.offset)
                    < settings.orderIndex(of: $1.element.id, registrationIndex: $1.offset)
            }
            .map(\.element)
    }

    /// Every provider the user can order, in the current order: those the tab shows plus the ones with plan
    /// limits available but off, so Settings lists them all.
    var orderableProviders: [any AgentAdapter] {
        let local = currentRegistry
        let settings = ringSettings
        return adapters.adapters.enumerated()
            .filter { _, adapter in
                local.source(for: adapter.id) != nil || adapter.usageProvider != nil || hasPlan(adapter)
            }
            .sorted {
                settings.orderIndex(of: $0.element.id, registrationIndex: $0.offset)
                    < settings.orderIndex(of: $1.element.id, registrationIndex: $1.offset)
            }
            .map(\.element)
    }

    /// Writes `[modules."agents.usage"] order` (Story 7.9) through the settings service: `shown` in its new
    /// order, then the other known providers, then ids already stored, so no provider is lost. The settings
    /// observer re-sorts the tab and the rings.
    public func setProviderOrder(shown: [String]) async {
        guard let moduleSettings else { return }
        let next = UsageProviderOrder.merged(
            shown: shown, current: orderableProviders.map(\.id.rawValue), existing: ringSettings.order)
        guard next != ringSettings.order else { return }
        do {
            try await moduleSettings.set(next, for: RingSettings.orderKey)
        } catch {
            log?.error("agents.usage could not write order: \(String(describing: error), privacy: .public)")
        }
    }

    /// Moves a provider one place (-1 up, 1 down) in the full list (Settings, VoiceOver).
    public func moveProvider(_ id: String, by offset: Int) async {
        let current = orderableProviders.map(\.id.rawValue)
        await setProviderOrder(shown: UsageProviderOrder.moving(id, by: offset, in: current))
    }

    /// Plan limits are on (or windows are already known) for one of the adapter's Accounts.
    func hasPlan(_ adapter: any AgentAdapter) -> Bool {
        accounts(adapter).contains { hasPlan(adapter, key: UsageAccountKey(provider: adapter.id, account: $0.id)) }
    }

    /// Plan limits are on (or windows are already known) for the Account.
    func hasPlan(_ adapter: any AgentAdapter, key: UsageAccountKey) -> Bool {
        planStates[key] != nil || (adapter.usageProvider != nil && isPlanEnabled(key))
    }

    /// One card: before the first log read `READING LOGS…` (UX-DR100); a provider without plan windows
    /// `NO PLAN WINDOWS` (`LOCAL LOGS ONLY` when plan limits are off); else the dial and one bar per window.
    func providerCard(_ adapter: any AgentAdapter) -> UsageProviderCardModel {
        providerCard(adapter, account: accounts(adapter).first ?? AgentAccount(id: .default, label: "", location: nil))
    }

    /// One Account's card: header `<PROVIDER> · <ACCOUNT>` when the provider has several Accounts, its own
    /// `STALE · HH:MM` (UX-DR99).
    func providerCard(_ adapter: any AgentAdapter, account: AgentAccount) -> UsageProviderCardModel {
        let settings = ringSettings
        let now = clock
        let threshold = settings.warnThreshold(for: adapter.id)
        let key = UsageAccountKey(provider: adapter.id, account: account.id)
        let several = hasSeveralAccounts(adapter.id)
        let plan = planStates[key]
        let windows = Self.tabWindows(plan, settings: settings, threshold: threshold, now: now)
        let kinds = Set(windows.map(\.kind))
        let kind: UsageCardMeta.Kind
        if !hasPlan(adapter, key: key) {
            kind = .localOnly
        } else if kinds.contains(.fiveHour) || kinds.isEmpty {
            kind = .warn(threshold: threshold)
        } else if kinds.contains(.weekly) {
            kind = .weeklyOnly
        } else {
            kind = .dailyOnly
        }
        let meta = UsageCardMeta(kind: kind, stale: plan?.staleLabel)
        // With several Accounts the header reads `<PROVIDER> · <ACCOUNT>` with the plan provider's short name
        // (`CLAUDE · WORK`, UX-DR99), as on the wing and in the peek.
        let name = String(localized: several ? (adapter.usageProvider?.name ?? adapter.name) : adapter.name)
        let content: UsageProviderCardModel.Content
        if lastIngest == nil {
            content = .readingLogs
        } else if windows.isEmpty {
            content = .noPlanWindows
        } else {
            let byKind = Dictionary(windows.map { ($0.kind, $0) }, uniquingKeysWith: { first, _ in first })
            let primary = byKind[.fiveHour] ?? byKind[.weekly] ?? byKind[.daily]
            let secondary = byKind[.fiveHour] == nil ? nil : byKind[.weekly]
            let dial = QuotaDialModel(
                providerName: name, primary: primary, secondary: secondary, stale: plan?.isStale ?? false,
                accountLabel: several ? Self.label(of: account) : nil)
            let timeZone = calendar.timeZone
            let bars = windows.map { window in
                UsageBarModel(
                    window: window, warnThreshold: threshold,
                    elapsed: window.kind.elapsedFraction(resetsAt: window.resetsAt, now: now),
                    reset: window.resetsAt.map { Self.resetParts(resetsAt: $0, now: now, timeZone: timeZone) })
            }
            content = .windows(dial: dial, bars: bars)
        }
        return UsageProviderCardModel(
            id: key.description, name: name, meta: meta, content: content, providerID: adapter.id.rawValue,
            account: several ? Self.label(of: account) : nil)
    }

    /// The plan's windows the tab knows, in `5h`, weekly, daily order. Unlike the closed-notch ring (pace on
    /// the 5h window only, FR52), every bar is paced while `pace` is on (mockup: a pace marker and label per
    /// window); each is in quota warning at or over `threshold` (Story 7.6).
    nonisolated static func tabWindows(
        _ plan: PlanState?, settings: RingSettings, threshold: Int, now: Date
    ) -> [QuotaDialModel.Window] {
        var seen: Set<QuotaWindowKind> = []
        var windows: [QuotaDialModel.Window] = []
        for raw in plan?.windows ?? [] {
            guard var window = QuotaDialModel.Window(raw), seen.insert(window.kind).inserted else { continue }
            window.paceTolerance = settings.paceTolerance
            window.isWarning = window.isAtOrOver(threshold, now: now)
            if settings.pace {
                window.elapsedFraction = window.kind.elapsedFraction(resetsAt: window.resetsAt, now: now)
            }
            windows.append(window)
        }
        let order = QuotaWindowKind.allCases
        return windows.sorted { (order.firstIndex(of: $0.kind) ?? 0) < (order.firstIndex(of: $1.kind) ?? 0) }
    }
}
