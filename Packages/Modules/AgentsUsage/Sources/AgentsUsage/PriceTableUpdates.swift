import AgentKit
import Foundation
import ModuleKit

/// `Check now` state in Settings › Usage (Story 6.5).
struct PriceCheckStatus: Hashable, Sendable {
    var isRunning = false
    var last: PriceTableUpdater.Outcome?
}

/// Story 6.5: the signed price table. At start the newest table on disk builds the estimator; then, while
/// `[updates] prices` is on and the build has a release location, the table is checked every `check_interval`
/// (the last check persisted in `context.storage`, so a relaunch does not check early) or on `Check now`. An
/// accepted table rebuilds the estimator live.
extension AgentsUsageModule {
    /// How often the module looks whether `check_interval` has elapsed.
    nonisolated static let priceTickInterval: Duration = .seconds(15 * 60)
    /// The setup problem's dedupe key.
    nonisolated static let priceDedupeKey = "prices"

    /// Builds the estimator from the newest table on disk.
    func startPrices(context: any ModuleContext) async throws -> CostEstimator {
        let updates = context.updates
        self.updates = updates
        let updater = PriceTableUpdater(
            directory: context.storage.directory, bundled: try PriceTable.bundled(), http: priceHTTP, now: now)
        priceUpdater = updater
        if updates.priceTable == nil {
            context.log.info("agents.usage price table updates off in this build (no release location or public key)")
        }
        let loaded = await updater.load(publicKey: updates.priceTable?.publicKey)
        return applyPrices(loaded)
    }

    /// Schedules the interval check and runs the first one (when due) now.
    func startPriceChecks(scheduler: any Scheduler) {
        guard updates?.priceTable != nil else { return }
        priceJob = scheduler.every(Self.priceTickInterval) { [weak self] in await self?.priceTick() }
        priceStartTask = Task { [weak self] in await self?.priceTick() }
    }

    func stopPrices() {
        priceJob?.cancel()
        priceJob = nil
        priceStartTask?.cancel()
        priceStartTask = nil
    }

    /// `Check now` is offered: the build has a location, `prices` is on and no check is running.
    var canCheckPrices: Bool {
        guard let updates else { return false }
        return updates.priceTable != nil && updates.pricesEnabled && !priceCheck.isRunning
    }

    /// Settings › Usage `Check now`: one check right away, whatever the interval.
    public func checkPricesNow() async {
        guard canCheckPrices, let location = updates?.priceTable else { return }
        await runPriceCheck(location)
    }

    /// The scheduled check: only when `prices` is on and `check_interval` has elapsed since the last one.
    func priceTick() async {
        guard canCheckPrices, let updates, let location = updates.priceTable, let priceUpdater else { return }
        if let last = await priceUpdater.lastChecked() {
            let interval = updates.checkInterval.components
            let seconds = TimeInterval(interval.seconds) + TimeInterval(interval.attoseconds) / 1e18
            guard now().timeIntervalSince(last) >= seconds else { return }
        }
        // `prices` or a manual check may have changed while reading the last check.
        guard canCheckPrices else { return }
        await runPriceCheck(location)
    }

    private func runPriceCheck(_ location: PriceTableLocation) async {
        guard let priceUpdater else { return }
        priceCheck.isRunning = true
        let current = history?.estimator.version ?? 0
        let outcome = await priceUpdater.check(location, current: current)
        priceCheck = PriceCheckStatus(isRunning: false, last: outcome)
        switch outcome {
        case .updated(let version):
            log?.info("agents.usage price table updated to version \(version, privacy: .public)")
            let loaded = await priceUpdater.load(publicKey: location.publicKey)
            let estimator = applyPrices(loaded)
            if let store {
                history = UsageHistory(store: store, estimator: estimator, calendar: calendar)
            }
            await refreshOverview()
        case .badSignature:
            postPriceProblem("signature", body: UsageText.string("agentsUsage.prices.problem.signature"))
        case .downgrade(let version):
            postPriceProblem(
                "downgrade", body: UsageText.format("agentsUsage.prices.problem.downgrade", version, current))
        case .upToDate, .unavailable, .unreadable:
            log?.info("agents.usage price table check: \(String(describing: outcome), privacy: .public)")
        }
    }

    @discardableResult
    private func applyPrices(_ loaded: PriceTableUpdater.Loaded) -> CostEstimator {
        priceSource = loaded.source
        priceTableDate = loaded.table.updated
        return CostEstimator(
            table: loaded.table, source: loaded.source, sections: CostEstimator.sections(for: adapters.adapters))
    }

    /// One setup problem per reason and launch.
    private func postPriceProblem(_ reason: String, body: String) {
        log?.error("agents.usage price table rejected: \(reason, privacy: .public)")
        guard postedPriceProblems.insert(reason).inserted, let notifier else { return }
        notifier.post(
            NotifierEvent(
                kind: Self.setupProblemKind, severity: .warn,
                title: UsageText.string("agentsUsage.prices.problem.title"),
                body: body, action: .openSettings(pane: Self.staticManifest.id.rawValue),
                dedupeKey: Self.priceDedupeKey,
                category: UsageText.string("agentsUsage.prices.problem.category")))
    }

    /// The Usage footer: `PRICES <date> · BUNDLED` or `· UPDATED`; nil before start.
    var pricesLabel: String? {
        guard let date = priceTableDate else { return nil }
        return UsageText.format(
            priceSource == .updated ? "agentsUsage.prices.updated" : "agentsUsage.prices.bundled", date)
    }

    /// The last `Check now` result for Settings; nil before any check.
    var priceCheckText: String? {
        if priceCheck.isRunning { return UsageText.string("agentsUsage.prices.check.running") }
        switch priceCheck.last {
        case nil: return nil
        case .updated(let version): return UsageText.format("agentsUsage.prices.check.updated", version)
        case .upToDate: return UsageText.string("agentsUsage.prices.check.upToDate")
        case .unavailable: return UsageText.string("agentsUsage.prices.check.unavailable")
        case .badSignature: return UsageText.string("agentsUsage.prices.check.badSignature")
        case .downgrade: return UsageText.string("agentsUsage.prices.check.downgrade")
        case .unreadable: return UsageText.string("agentsUsage.prices.check.unreadable")
        }
    }

    /// Why `Check now` is off, for its help line; nil when it can run.
    var priceCheckUnavailableText: String? {
        guard let updates, updates.priceTable != nil else {
            return UsageText.string("agentsUsage.prices.check.notSetUp")
        }
        return updates.pricesEnabled ? nil : UsageText.string("agentsUsage.prices.check.off")
    }
}
