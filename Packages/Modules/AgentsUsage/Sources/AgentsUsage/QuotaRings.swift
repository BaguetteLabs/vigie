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

/// The ring keys of `[modules."agents.usage"]` (Story 7.4), read through `context.settings`.
public struct RingSettings: Equatable, Sendable {
    nonisolated static let priorityKey = "priority"
    nonisolated static let orderKey = "order"
    nonisolated static let ringsKey = "rings"
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

    public init(
        priority: Int = RingSettings.defaultPriority, order: [String] = [], rings: RingsMode = .fiveHourAndWeekly,
        providerPriority: [AgentID: Int] = [:]
    ) {
        self.priority = priority
        self.order = order
        self.rings = rings
        self.providerPriority = providerPriority
    }

    init(_ settings: any ModuleSettings) {
        var overrides: [AgentID: Int] = [:]
        for id in Self.overridableProviders {
            if let value = settings.value(Self.providerPriorityKey(id), as: Int.self), value > 0 {
                overrides[id] = value
            }
        }
        self.init(
            priority: settings.value(Self.priorityKey, as: Int.self) ?? Self.defaultPriority,
            order: settings.value(Self.orderKey, as: [String].self) ?? [],
            rings: settings.value(Self.ringsKey, as: String.self).flatMap(RingsMode.init(rawValue:))
                ?? .fiveHourAndWeekly,
            providerPriority: overrides)
    }

    /// Every key whose change re-reads the settings.
    static var observedKeys: [String] {
        [priorityKey, orderKey, ringsKey] + overridableProviders.map(providerPriorityKey)
    }

    func priority(for id: AgentID) -> Int { providerPriority[id] ?? priority }

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
        ]
            + overridableProviders.map { id in
                SettingDescriptor(
                    key: providerPriorityKey(id),
                    label: text("agentsUsage.setting.providerPriority.\(id.rawValue)"),
                    kind: .int(default: 0, min: 0, max: 99), scope: .synced,
                    help: text("agentsUsage.setting.providerPriority.help"))
            }
    }
}

/// One provider's ring as offered to the left-wing lane.
public struct QuotaRing: Sendable, Equatable {
    public let provider: AgentID
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
    /// The dial for a plan: the 5h window inside (plus weekly around it with `5h+weekly`), else the plan's only
    /// window (weekly, then daily); nil when the plan has no window the dial knows (A18).
    init?(providerName: String, plan: PlanState, rings: RingsMode) {
        var windows: [QuotaWindowKind: QuotaDialModel.Window] = [:]
        for window in plan.windows {
            if let mapped = QuotaDialModel.Window(window), windows[mapped.kind] == nil { windows[mapped.kind] = mapped }
        }
        if let fiveHour = windows[.fiveHour] {
            self.init(
                providerName: providerName, primary: fiveHour,
                secondary: rings == .fiveHourAndWeekly ? windows[.weekly] : nil, stale: plan.isStale)
        } else if let only = windows[.weekly] ?? windows[.daily] {
            self.init(providerName: providerName, primary: only, stale: plan.isStale)
        } else {
            return nil
        }
    }
}

// MARK: - Left wing

extension AgentsUsageModule {
    /// The rings to show, in lane order: one per provider with plan windows (local-only providers draw none,
    /// A18). Reads `planStates` and `ringSettings`, both observed, so the host re-arbitrates on change.
    public var quotaRings: [QuotaRing] {
        let settings = ringSettings
        return adapters.adapters.enumerated().compactMap { index, adapter -> QuotaRing? in
            guard let provider = adapter.usageProvider, let plan = planStates[adapter.id],
                let model = QuotaDialModel(
                    providerName: String(localized: provider.name), plan: plan, rings: settings.rings)
            else { return nil }
            return QuotaRing(
                provider: adapter.id, model: model, priority: settings.priority(for: adapter.id),
                order: settings.orderIndex(of: adapter.id, registrationIndex: index))
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
            return LeftWingItem(id: "ring.\(ring.provider.rawValue)", priority: ring.priority, order: ring.order) {
                size in
                switch size {
                case .wide: multiple ? nil : AnyView(QuotaReadoutView(model: model))
                case .short: AnyView(QuotaDialView(model: model, size: multiple ? .stacked : .wing))
                case .icon: AnyView(QuotaDialView(model: model, size: .wing, showsName: false))
                }
            }
        }
    }

    /// FR53 as far as rings go: ambient while a ring is offered, hidden otherwise (the quota warning, Story
    /// 7.6, raises it).
    func updateRingState() {
        let next: ModuleState = quotaRings.isEmpty ? .hidden : .ambient
        if state != next { state = next }
    }

    /// Reads the ring keys now and again whenever one changes.
    func startRingSettings(_ settings: any ModuleSettings) {
        ringSettings = RingSettings(settings)
        for key in RingSettings.observedKeys {
            let stream = settings.observe(key)
            ringObservers.append(
                Task { [weak self] in
                    for await _ in stream {
                        self?.ringSettings = RingSettings(settings)
                    }
                })
        }
    }

    func stopRingSettings() {
        for task in ringObservers { task.cancel() }
        ringObservers = []
    }
}
