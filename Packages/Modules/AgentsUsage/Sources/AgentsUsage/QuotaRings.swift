import AgentKit
import Foundation
import ModuleKit
import SwiftUI
import VigieUI

/// `rings` (SPEC §11, UX-DR73): which windows a provider ring draws.
public enum RingsMode: String, Sendable, CaseIterable {
    /// The 5h window only (a plan without 5h still shows its only window).
    case fiveHour = "5h"
    /// 5h inside, weekly around it (default).
    case fiveHourAndWeekly = "5h+weekly"
}

/// The ring keys of `[modules."agents.usage"]` (Story 7.4; `pace`, `pace_tolerance` Story 7.5), read through
/// `context.settings`.
public struct RingSettings: Equatable, Sendable {
    nonisolated static let priorityKey = "priority"
    nonisolated static let orderKey = "order"
    nonisolated static let ringsKey = "rings"
    nonisolated static let paceKey = "pace"
    nonisolated static let paceToleranceKey = "pace_tolerance"
    /// `pace_tolerance` default and bounds, in points (SPEC §11).
    public nonisolated static let defaultPaceTolerance = QuotaDialModel.defaultPaceTolerance
    nonisolated static let maxPaceTolerance = 50
    nonisolated static let warnThresholdKey = "warn_threshold"
    nonisolated static let warnActionKey = "warn_action"
    /// `warn_threshold` default, in % used (SPEC §11).
    public nonisolated static let defaultWarnThreshold = 80
    nonisolated static func providerWarnThresholdKey(_ id: AgentID) -> String {
        "providers.\(id.rawValue).warn_threshold"
    }
    /// Default left-wing priority of every provider ring (SPEC §11).
    public nonisolated static let defaultPriority = 2
    /// Per-provider overrides are declared for these providers (`providers.<id>.priority`). Codex and Gemini
    /// join when their adapters land (Epic 8).
    nonisolated static let overridableProviders: [AgentID] = ["claude"]
    nonisolated static func providerPriorityKey(_ id: AgentID) -> String { "providers.\(id.rawValue).priority" }

    public var priority: Int
    /// Provider ids in the user's order; unlisted providers follow in adapter registration order (A69).
    public var order: [String]
    public var rings: RingsMode
    /// Overrides from `providers.<id>.priority`; 0 (the declared default) means "use `priority`".
    public var providerPriority: [AgentID: Int]
    /// `pace`: draw the pace tick and the ahead-of-pace fill (FR52; default on).
    public var pace: Bool
    /// `pace_tolerance` in points: ahead only when used > elapsed + tolerance.
    public var paceTolerance: Int
    /// `warn_threshold`: a window at or over this % used is in quota warning (FR51).
    public var warnThreshold: Int
    /// `warn_action`: peek + state `alert`, or the visual change only (state `active`).
    public var warnAction: WarnAction
    /// Overrides from `providers.<id>.warn_threshold`; 0 (the declared default) means "use `warn_threshold`".
    public var providerWarnThreshold: [AgentID: Int]

    public init(
        priority: Int = RingSettings.defaultPriority, order: [String] = [], rings: RingsMode = .fiveHourAndWeekly,
        providerPriority: [AgentID: Int] = [:], pace: Bool = true,
        paceTolerance: Int = RingSettings.defaultPaceTolerance, warnThreshold: Int = RingSettings.defaultWarnThreshold,
        warnAction: WarnAction = .alert, providerWarnThreshold: [AgentID: Int] = [:]
    ) {
        self.priority = priority
        self.order = order
        self.rings = rings
        self.providerPriority = providerPriority
        self.pace = pace
        self.paceTolerance = min(Self.maxPaceTolerance, max(0, paceTolerance))
        self.warnThreshold = min(100, max(1, warnThreshold))
        self.warnAction = warnAction
        self.providerWarnThreshold = providerWarnThreshold.filter { $0.value > 0 }.mapValues { min(100, $0) }
    }

    init(_ settings: any ModuleSettings) {
        var overrides: [AgentID: Int] = [:]
        var thresholds: [AgentID: Int] = [:]
        for id in Self.overridableProviders {
            if let value = settings.value(Self.providerPriorityKey(id), as: Int.self), value > 0 {
                overrides[id] = value
            }
            if let value = settings.value(Self.providerWarnThresholdKey(id), as: Int.self), value > 0 {
                thresholds[id] = value
            }
        }
        self.init(
            priority: settings.value(Self.priorityKey, as: Int.self) ?? Self.defaultPriority,
            order: settings.value(Self.orderKey, as: [String].self) ?? [],
            rings: settings.value(Self.ringsKey, as: String.self).flatMap(RingsMode.init(rawValue:))
                ?? .fiveHourAndWeekly,
            providerPriority: overrides,
            pace: settings.value(Self.paceKey, as: Bool.self) ?? true,
            paceTolerance: settings.value(Self.paceToleranceKey, as: Int.self) ?? Self.defaultPaceTolerance,
            warnThreshold: settings.value(Self.warnThresholdKey, as: Int.self) ?? Self.defaultWarnThreshold,
            warnAction: settings.value(Self.warnActionKey, as: String.self).flatMap(WarnAction.init(rawValue:))
                ?? .alert,
            providerWarnThreshold: thresholds)
    }

    /// Every key whose change re-reads the settings.
    static var observedKeys: [String] {
        [priorityKey, orderKey, ringsKey, paceKey, paceToleranceKey, warnThresholdKey, warnActionKey]
            + overridableProviders.flatMap { [providerPriorityKey($0), providerWarnThresholdKey($0)] }
    }

    func priority(for id: AgentID) -> Int { providerPriority[id] ?? priority }

    /// The provider's threshold: its override, else `warn_threshold`.
    func warnThreshold(for id: AgentID) -> Int { providerWarnThreshold[id] ?? warnThreshold }

    /// The provider's rank among rings: its position in `order`, else after every listed one in registration
    /// order.
    func orderIndex(of id: AgentID, registrationIndex: Int) -> Int {
        order.firstIndex(of: id.rawValue) ?? (order.count + registrationIndex)
    }

    /// The manifest descriptors (generated Settings › Usage).
    nonisolated static func descriptors(bundle: LocalizedStringResource.BundleDescription) -> [SettingDescriptor] {
        // Keys are built at run time (per provider), so no interpolation: the catalog key is the whole string.
        func text(_ key: String) -> LocalizedStringResource {
            LocalizedStringResource(String.LocalizationValue(key), bundle: bundle)
        }
        return [
            SettingDescriptor(
                key: priorityKey, label: text("agentsUsage.setting.priority"),
                kind: .int(default: defaultPriority, min: 1, max: 99), scope: .synced,
                help: text("agentsUsage.setting.priority.help")),
            SettingDescriptor(
                key: orderKey, label: text("agentsUsage.setting.order"), kind: .list(of: .string, default: []),
                scope: .synced, help: text("agentsUsage.setting.order.help")),
            SettingDescriptor(
                key: ringsKey, label: text("agentsUsage.setting.rings"),
                kind: .enumeration(
                    options: RingsMode.allCases.map(\.rawValue), default: RingsMode.fiveHourAndWeekly.rawValue),
                scope: .synced, help: text("agentsUsage.setting.rings.help")),
            SettingDescriptor(
                key: paceKey, label: text("agentsUsage.setting.pace"), kind: .bool(default: true), scope: .synced,
                help: text("agentsUsage.setting.pace.help")),
            SettingDescriptor(
                key: paceToleranceKey, label: text("agentsUsage.setting.paceTolerance"),
                kind: .int(default: defaultPaceTolerance, min: 0, max: maxPaceTolerance), scope: .synced,
                help: text("agentsUsage.setting.paceTolerance.help")),
            SettingDescriptor(
                key: warnThresholdKey, label: text("agentsUsage.setting.warnThreshold"),
                kind: .int(default: defaultWarnThreshold, min: 1, max: 100), scope: .synced,
                help: text("agentsUsage.setting.warnThreshold.help")),
            SettingDescriptor(
                key: warnActionKey, label: text("agentsUsage.setting.warnAction"),
                kind: .enumeration(options: WarnAction.allCases.map(\.rawValue), default: WarnAction.alert.rawValue),
                scope: .synced, help: text("agentsUsage.setting.warnAction.help")),
        ]
            + overridableProviders.map { id in
                SettingDescriptor(
                    key: providerPriorityKey(id),
                    label: text("agentsUsage.setting.providerPriority.\(id.rawValue)"),
                    kind: .int(default: 0, min: 0, max: 99), scope: .synced,
                    help: text("agentsUsage.setting.providerPriority.help"))
            }
            + overridableProviders.map { id in
                SettingDescriptor(
                    key: providerWarnThresholdKey(id),
                    label: text("agentsUsage.setting.providerWarnThreshold.\(id.rawValue)"),
                    kind: .int(default: 0, min: 0, max: 100), scope: .synced,
                    help: text("agentsUsage.setting.providerWarnThreshold.help"))
            }
    }
}

/// One provider's ring as offered to the left-wing lane: one ring per provider, for the Account of its most
/// recent Session (Story 7.10, AD-23).
public struct QuotaRing: Sendable, Equatable {
    public let provider: AgentID
    /// The Account the ring shows.
    public var account: AccountID = .default
    public let model: QuotaDialModel
    public let priority: Int
    public let order: Int
}

extension QuotaDialModel.Window {
    /// A provider window as a dial window; nil for a window the dial does not know.
    init?(_ window: UsageWindow) {
        guard let kind = QuotaWindowKind(rawValue: window.name) else { return nil }
        let fraction: Double
        if let limit = window.limit {
            fraction = limit > 0 ? window.used / limit : 0
        } else {
            fraction = window.used / 100
        }
        self.init(kind: kind, fraction: fraction, resetsAt: window.resetsAt)
    }
}

extension QuotaDialModel {
    /// The window pace is measured on (FR52): 5h, or weekly when the plan has no 5h; none otherwise.
    static func pacedKind(in kinds: some Collection<QuotaWindowKind>) -> QuotaWindowKind? {
        if kinds.contains(.fiveHour) { return .fiveHour }
        if kinds.contains(.weekly) { return .weekly }
        return nil
    }

    /// The dial for a plan: the 5h window inside (plus weekly around it with `5h+weekly`), else the plan's only
    /// window (weekly, then daily); nil when the plan has no window the dial knows (A18). With `pace` on, the
    /// paced window carries its elapsed share at `now` (Story 7.5).
    ///
    /// With `warnThreshold`, each window at or over it (and not yet reset at `now`) is in quota warning (Story
    /// 7.6); a warning on a window the dial does not draw sets `hiddenWarning`.
    init?(
        providerName: String, plan: PlanState, rings: RingsMode, pace: Bool = false,
        paceTolerance: Int = QuotaDialModel.defaultPaceTolerance, warnThreshold: Int? = nil, now: Date = Date(),
        accountLabel: String? = nil
    ) {
        var windows: [QuotaWindowKind: QuotaDialModel.Window] = [:]
        for window in plan.windows {
            if let mapped = QuotaDialModel.Window(window), windows[mapped.kind] == nil { windows[mapped.kind] = mapped }
        }
        for kind in Array(windows.keys) {
            windows[kind]?.paceTolerance = paceTolerance
            if let warnThreshold, let window = windows[kind] {
                windows[kind]?.isWarning = window.isAtOrOver(warnThreshold, now: now)
            }
        }
        if pace, let paced = Self.pacedKind(in: windows.keys), let window = windows[paced] {
            windows[paced]?.elapsedFraction = paced.elapsedFraction(resetsAt: window.resetsAt, now: now)
        }
        let primary: Window
        let secondary: Window?
        if let fiveHour = windows[.fiveHour] {
            primary = fiveHour
            secondary = rings == .fiveHourAndWeekly ? windows[.weekly] : nil
        } else if let only = windows[.weekly] ?? windows[.daily] {
            primary = only
            secondary = nil
        } else {
            return nil
        }
        let drawn: Set<QuotaWindowKind> = [primary.kind, secondary?.kind].compactMap { $0 }.reduce(into: []) {
            $0.insert($1)
        }
        let hidden = windows.values.contains { !drawn.contains($0.kind) && $0.isWarning }
        self.init(
            providerName: providerName, primary: primary, secondary: secondary, stale: plan.isStale,
            hiddenWarning: hidden, accountLabel: accountLabel)
    }
}

// MARK: - Left wing

extension AgentsUsageModule {
    /// The rings to show, in lane order: one per provider with plan windows (local-only providers draw none,
    /// A18). A provider with several Accounts shows the Account of its most recent Session (``recentAccounts``),
    /// else its first Account with windows, labeled `CLAUDE · WORK` (UX-DR99). Reads `planStates`,
    /// `recentAccounts` and `ringSettings`, all observed, so the host re-arbitrates on change.
    public var quotaRings: [QuotaRing] {
        let settings = ringSettings
        let now = clock
        return adapters.adapters.enumerated().compactMap { index, adapter -> QuotaRing? in
            guard let provider = adapter.usageProvider else { return nil }
            let accounts = accounts(adapter)
            let several = accounts.count > 1
            let recent = recentAccounts[adapter.id]
            let candidates = accounts.filter { $0.id == recent } + accounts.filter { $0.id != recent }
            for account in candidates {
                guard let plan = planStates[UsageAccountKey(provider: adapter.id, account: account.id)],
                    let model = QuotaDialModel(
                        providerName: String(localized: provider.name), plan: plan, rings: settings.rings,
                        pace: settings.pace, paceTolerance: settings.paceTolerance,
                        warnThreshold: settings.warnThreshold(for: adapter.id), now: now,
                        accountLabel: several ? Self.label(of: account) : nil)
                else { continue }
                return QuotaRing(
                    provider: adapter.id, account: account.id, model: model,
                    priority: settings.priority(for: adapter.id),
                    order: settings.orderIndex(of: adapter.id, registrationIndex: index))
            }
            return nil
        }
        .sorted { ($0.priority, $0.order) < ($1.priority, $1.order) }
    }

    /// One `LeftWingItem` per ring (SPEC §5). Sizes: `.wide` is the single-provider readout (only when this
    /// module offers exactly one ring; the lane gives `.wide` only to an entry alone on its side); `.short` is
    /// the dial with the provider name, 23 px when several providers have rings, else 24 px; `.icon` the bare
    /// 24 px dial.
    public func leftWingItems() -> [LeftWingItem] {
        let rings = quotaRings
        let multiple = rings.count > 1
        return rings.map { ring in
            let model = ring.model
            let state = ring.model.hasWarning ? warningState : nil
            return LeftWingItem(
                id: "ring.\(ring.provider.rawValue)", priority: ring.priority, state: state, order: ring.order
            ) { size in
                switch size {
                case .wide: multiple ? nil : AnyView(QuotaReadoutView(model: model))
                case .short: AnyView(QuotaDialView(model: model, size: multiple ? .stacked : .wing))
                case .icon: AnyView(QuotaDialView(model: model, size: .wing, showsName: false))
                }
            }
        }
    }

    /// FR53: hidden without a ring, ambient while rings are offered, and `alert` (`warn_action = "alert"`) or
    /// `active` (`"visual"`) while any provider is in quota warning (Story 7.6). Pace never changes it.
    func updateRingState() {
        let rings = quotaRings
        let next: ModuleState =
            rings.isEmpty ? .hidden : rings.contains(where: \.model.hasWarning) ? warningState : .ambient
        if state != next { state = next }
    }

    /// The state of a ring (and of the module) in quota warning, per `warn_action`.
    var warningState: ModuleState { ringSettings.warnAction == .alert ? .alert : .active }

    /// Moves the dial clock to now: the pace tick advances (Story 7.5) and a window whose reset passed leaves
    /// its quota warning (Story 7.6).
    func tickClock() {
        clock = now()
        updateRingState()
        evaluateQuotaWarnings()
        refreshOverviewIfDayChanged()
    }

    /// Reads the ring keys now and again whenever one changes, and advances the dial clock every
    /// `clockInterval`.
    func startRingSettings(_ settings: any ModuleSettings, scheduler: any Scheduler) {
        ringSettings = RingSettings(settings)
        tickClock()
        clockJob = scheduler.every(Self.clockInterval) { [weak self] in await self?.tickClock() }
        for key in RingSettings.observedKeys {
            let stream = settings.observe(key)
            ringObservers.append(
                Task { [weak self] in
                    for await _ in stream {
                        self?.ringSettings = RingSettings(settings)
                        self?.updateRingState()
                        self?.evaluateQuotaWarnings()
                    }
                })
        }
    }

    func stopRingSettings() {
        for task in ringObservers { task.cancel() }
        ringObservers = []
        clockJob?.cancel()
        clockJob = nil
    }
}
