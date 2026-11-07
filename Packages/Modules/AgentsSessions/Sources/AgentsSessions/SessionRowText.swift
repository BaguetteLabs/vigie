import AgentKit
import Foundation
import VigieUI

/// Text for a session in a row, a glyph or a peek (SPEC §7.1, DESIGN "Status glyph" stale rows, UX-DR63,
/// UX-DR81). Pure formatting from the VigieUI and AgentsSessions catalogs; the Agents tab row (Story 4.10)
/// and the closed-notch glyphs (Story 4.9) read it.
public struct SessionRowText: Sendable {
    public var timeZone: TimeZone
    public var staleAfter: Duration

    public init(timeZone: TimeZone = .current, staleAfter: Duration = Session.defaultStaleAfter) {
        self.timeZone = timeZone
        self.staleAfter = staleAfter
    }

    /// The project name, or the agent id when the session has no `cwd` yet.
    public func project(_ session: Session) -> String {
        session.projectName ?? session.agentID.rawValue
    }

    /// `IDLE`, `WORKING · 14M`, `BLOCKED · 12M`; a stale session reads `STALE · 18M`, the time since its
    /// last event.
    /// A session failed by sleep reads `FAILED · HOST SLEPT` (Story 4.12, UX-DR57).
    public func statusLabel(_ session: Session, now: Date) -> String {
        let status = session.displayStatus(now: now, staleAfter: staleAfter)
        if status == .failed, session.failureReason == .hostSlept {
            return Self.format("agentsSessions.row.hostSlept")
        }
        return StatusLabelFormatter(timeZone: timeZone).label(for: status, elapsed: elapsed(session, status, now))
    }

    /// The last-action line: the last tool, or for a stale session `LAST EVENT 14:30 · <action>`
    /// (`LAST EVENT 14:30` without one). Nil when there is nothing to show.
    public func lastActionLine(_ session: Session, now: Date) -> String? {
        guard session.isStale(now: now, staleAfter: staleAfter) else { return session.lastAction }
        let clock = clock(session.lastEventAt)
        guard let action = session.lastAction, !action.isEmpty else {
            return Self.format("agentsSessions.row.lastEvent", clock)
        }
        return Self.format("agentsSessions.row.lastEventAction", clock, action)
    }

    /// `Run interrupted during Bash` for a session failed by sleep; `Run interrupted by sleep` without a last
    /// action (Story 4.12, UX-DR57). The Agents tab row detail and the single wake alert's body.
    public func interruptedLine(_ session: Session) -> String {
        guard let action = session.lastAction, !action.isEmpty else {
            return Self.format("agentsSessions.row.interrupted")
        }
        return Self.format("agentsSessions.row.interruptedDuring", action)
    }

    /// "vigie, blocked, 2 minutes" (UX-DR63); "vigie, idle"; a stale session reads
    /// "vigie, stale, no event for 18 minutes" (UX-DR81).
    public func accessibilityLabel(_ session: Session, now: Date) -> String {
        let status = session.displayStatus(now: now, staleAfter: staleAfter)
        let project = project(session)
        let elapsed = elapsed(session, status, now)
        guard status == .stale else {
            return AccessibilityLabel.session(project: project, status: status, elapsed: elapsed)
        }
        let noEvent = Self.format("agentsSessions.a11y.noEventFor", AccessibilityLabel.duration(elapsed))
        return AccessibilityLabel.item(
            name: AccessibilityLabel.session(project: project, status: .stale), status: noEvent)
    }

    /// Time in status; for stale, time since the last event.
    func elapsed(_ session: Session, _ status: SessionStatus, _ now: Date) -> Duration {
        let since = status == .stale ? session.lastEventAt : session.statusSince
        return .seconds(max(0, Int(now.timeIntervalSince(since))))
    }

    /// `14:30` (24-hour clock, as everywhere in Vigie).
    func clock(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let style = Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            timeZone: timeZone, calendar: calendar)
        return style.format(date)
    }

    static func format(_ key: String, _ arguments: any CVarArg...) -> String {
        let pattern = Bundle.module.localizedString(forKey: key, value: nil, table: nil)
        let locale = Locale(identifier: Bundle.module.preferredLocalizations.first ?? "en")
        return String(format: pattern, locale: locale, arguments: arguments)
    }
}
