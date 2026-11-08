import AgentKit
import Foundation
import ModuleKit
import VigieUI

/// `warn_action` (SPEC §11, FR15, FR51): what crossing `warn_threshold` does.
public enum WarnAction: String, Sendable, CaseIterable {
    /// The quota-warning peek (plus the optional sound) and module state `alert`.
    case alert
    /// The visual change only, module state `active`.
    case visual
}

extension QuotaDialModel.Window {
    /// At or over `threshold` % used (the whole percent shown), and the window has not reset at `now`.
    func isAtOrOver(_ threshold: Int, now: Date) -> Bool {
        if let resetsAt, resetsAt <= now { return false }
        return percent >= threshold
    }
}

// MARK: - Quota warning (Story 7.6)

extension AgentsUsageModule: AlertActionHandler {
    /// AD-13 canonical kind of the quota warning.
    nonisolated static let quotaWarningKind = "usage.quota_warning"
    /// The peek's primary action: open the Usage tab (payload: the provider id, UTF-8).
    nonisolated static let openUsageActionID = "open-usage"

    /// `quota:<provider>:<window>:<resets_at ISO 8601>` (`none` without a reset time): one alert per provider,
    /// window and reset.
    nonisolated static func quotaDedupeKey(_ id: AgentID, window: QuotaDialModel.Window) -> String {
        let reset = window.resetsAt.map { $0.formatted(.iso8601) } ?? "none"
        return "quota:\(id.rawValue):\(window.kind.rawValue):\(reset)"
    }

    /// A provider window in quota warning.
    struct QuotaCrossing {
        let provider: AgentID
        let name: String
        let window: QuotaDialModel.Window
    }

    /// Re-evaluates every provider window against its threshold at the dial clock: resolves the alerts of
    /// windows that dropped below or reset (and every alert when `warn_action` is `visual`), then posts each new
    /// crossing once when `warn_action` is `alert`. Pace plays no part (FR51: % only).
    func evaluateQuotaWarnings() {
        let settings = ringSettings
        let now = clock
        var crossings: [String: QuotaCrossing] = [:]
        var current: Set<String> = []
        for adapter in adapters.adapters {
            guard let provider = adapter.usageProvider, let plan = planStates[adapter.id] else { continue }
            let threshold = settings.warnThreshold(for: adapter.id)
            var seen: Set<QuotaWindowKind> = []
            for raw in plan.windows {
                guard let window = QuotaDialModel.Window(raw), seen.insert(window.kind).inserted else { continue }
                let key = Self.quotaDedupeKey(adapter.id, window: window)
                current.insert(key)
                if window.isAtOrOver(threshold, now: now) {
                    crossings[key] = QuotaCrossing(
                        provider: adapter.id, name: String(localized: provider.name), window: window)
                }
            }
        }
        for (key, handle) in quotaAlerts where crossings[key] == nil || settings.warnAction != .alert {
            quotaAlerts[key] = nil
            handle.resolve()
        }
        // A key leaves the record once its window is gone (the next window has a new reset time).
        postedQuotaKeys.formIntersection(current)
        guard settings.warnAction == .alert, let notifier else { return }
        for (key, crossing) in crossings.sorted(by: { $0.key < $1.key }) where !postedQuotaKeys.contains(key) {
            postedQuotaKeys.insert(key)
            quotaAlerts[key] = notifier.post(quotaWarningEvent(crossing, key: key, now: now))
        }
    }

    func resolveAllQuotaWarnings() {
        let open = quotaAlerts.values
        quotaAlerts.removeAll()
        for handle in open { handle.resolve() }
    }

    /// The `usage.quota_warning` event (UX-DR91): title `CLAUDE · 5H 82 %`, detail `RESET 16:40 · IN 1H52`,
    /// primary action Open usage. The kicker (`QUOTA · WARN`), triangle beacon and `quota-warning` hue come from
    /// the host's peek mapping for the kind.
    func quotaWarningEvent(_ crossing: QuotaCrossing, key: String, now: Date) -> NotifierEvent {
        NotifierEvent(
            kind: Self.quotaWarningKind,
            severity: .warn,
            title: Self.quotaTitle(provider: crossing.name, window: crossing.window),
            body: crossing.window.resetsAt.map {
                Self.quotaDetail(resetsAt: $0, now: now, timeZone: calendar.timeZone)
            },
            action: .module(
                id: manifest.id, actionID: Self.openUsageActionID, payload: Data(crossing.provider.rawValue.utf8)),
            dedupeKey: key)
    }

    /// `CLAUDE · 5H 82 %`.
    nonisolated static func quotaTitle(provider: String, window: QuotaDialModel.Window) -> String {
        UsageText.format(
            "agentsUsage.quota.title", provider.uppercased(with: UsageText.locale), window.label, window.percent)
    }

    /// `RESET 16:40 · IN 1H52` in local time; a reset a day or more away names the weekday
    /// (`RESET THU 09:00 · IN 3D04`).
    nonisolated static func quotaDetail(resetsAt: Date, now: Date, timeZone: TimeZone) -> String {
        let parts = resetParts(resetsAt: resetsAt, now: now, timeZone: timeZone)
        return UsageText.format("agentsUsage.quota.detail", parts.time, parts.remaining)
    }

    /// The two parts of a reset line: the local time (`16:40`, or `THU 09:00` a day or more away) and the time
    /// left (`1H52`, `3D04`). Shared by the quota-warning peek and the Usage tab bars.
    nonisolated static func resetParts(resetsAt: Date, now: Date, timeZone: TimeZone) -> UsageReset {
        let minutes = max(0, Int(resetsAt.timeIntervalSince(now) / 60))
        let hours = minutes / 60
        let formatter = DateFormatter()
        formatter.locale = UsageText.locale
        formatter.timeZone = timeZone
        let remaining: String
        if hours >= 24 {
            formatter.dateFormat = UsageText.string("agentsUsage.quota.resetDayTime")
            remaining = UsageText.format("agentsUsage.quota.in.days", hours / 24, hours % 24)
        } else {
            formatter.dateFormat = UsageText.string("agentsUsage.quota.resetTime")
            remaining = UsageText.format("agentsUsage.quota.in.hours", hours, minutes % 60)
        }
        let time = formatter.string(from: resetsAt).uppercased(with: UsageText.locale)
        return UsageReset(time: time, remaining: remaining)
    }

    /// Alert action (AD-13, `AlertActionHandler`): `open-usage` opens this module's tab (the Usage tab, Story
    /// 7.7).
    public func handleAlertAction(_ actionID: String, payload: Data, intent: UserIntent?) {
        guard actionID == Self.openUsageActionID else {
            log?.notice("alert action \(actionID, privacy: .public) ignored")
            return
        }
        host?.openOwnTab(focus: intent)
    }
}
