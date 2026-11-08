import Foundation
import ModuleKit

/// One Timer (for a duration) or Countdown (to a clock time) (SPEC §7.7, PRD FR-45).
///
/// Times are absolute (`endsAt`), so a relaunch or a sleep restores the item from the state file and an end
/// that passed meanwhile is detected on launch or wake.
public struct TimeItem: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: Codable, Hashable, Sendable {
        /// A Timer of `duration` seconds.
        case timer(duration: TimeInterval)
        /// A Countdown to a clock time. Countdowns cannot be paused or reset.
        case countdown(to: Date)
    }

    public enum State: Codable, Hashable, Sendable {
        case running
        /// Paused with ``TimeItem/pausedRemaining`` left; `endsAt` is stale until it resumes.
        case paused
        /// Ended at `at` (its `endsAt`, even when noticed later, after a sleep or a quit). It stays on the tab,
        /// with the attention marker, until the user acknowledges it; acknowledging removes it.
        case ended(at: Date)
    }

    public let id: UUID
    public var kind: Kind
    /// User text (AD-24): shown as dots while Privacy mode is active.
    @Sensitive public var label: String
    public var startedAt: Date
    public var endsAt: Date
    public var pausedRemaining: TimeInterval?
    public var state: State

    public init(
        id: UUID = UUID(), kind: Kind, label: String, startedAt: Date, endsAt: Date,
        pausedRemaining: TimeInterval? = nil, state: State = .running
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.pausedRemaining = pausedRemaining
        self.state = state
    }

    public var isTimer: Bool {
        if case .timer = kind { return true }
        return false
    }

    public var isEnded: Bool {
        if case .ended = state { return true }
        return false
    }

    /// The Timer's length; nil for a Countdown.
    public var duration: TimeInterval? {
        if case .timer(let duration) = kind { return duration }
        return nil
    }

    /// Seconds left at `now` (0 once ended).
    public func remaining(now: Date) -> TimeInterval {
        switch state {
        case .running: max(0, endsAt.timeIntervalSince(now))
        case .paused: max(0, pausedRemaining ?? 0)
        case .ended: 0
        }
    }

    /// When it ends (or would, if resumed now): sorts the running list.
    public func effectiveEnd(now: Date) -> Date {
        switch state {
        case .running: endsAt
        case .paused: now.addingTimeInterval(remaining(now: now))
        case .ended(let at): at
        }
    }

    /// The share of the Timer still to run (1 at the start), for the ring; a Countdown's runs from its start.
    public func fractionLeft(now: Date) -> Double {
        let total: TimeInterval =
            switch kind {
            case .timer(let duration): duration
            case .countdown(let date): date.timeIntervalSince(startedAt)
            }
        guard total > 0 else { return 0 }
        return min(max(remaining(now: now) / total, 0), 1)
    }
}

/// Every item and the transitions on them. A plain value: ``TimeModule`` holds one, persists it and arms the
/// scheduler after each change.
public struct TimeBoard: Hashable, Sendable {
    public private(set) var items: [TimeItem]

    public init(items: [TimeItem] = []) {
        self.items = items
    }

    /// The longest Timer accepted (24 h).
    public static let maxTimerMinutes = 24 * 60

    public subscript(id: UUID) -> TimeItem? { items.first { $0.id == id } }

    /// Starts a Timer of `minutes` (1...24 h); nil when out of range.
    @discardableResult
    public mutating func startTimer(minutes: Int, label: String, now: Date) -> TimeItem? {
        guard (1...Self.maxTimerMinutes).contains(minutes) else { return nil }
        let duration = TimeInterval(minutes * 60)
        let item = TimeItem(
            kind: .timer(duration: duration), label: label, startedAt: now, endsAt: now.addingTimeInterval(duration))
        items.append(item)
        return item
    }

    /// Starts a Countdown to `date`; nil when `date` is not in the future.
    @discardableResult
    public mutating func startCountdown(to date: Date, label: String, now: Date) -> TimeItem? {
        guard date > now else { return nil }
        let item = TimeItem(kind: .countdown(to: date), label: label, startedAt: now, endsAt: date)
        items.append(item)
        return item
    }

    /// Pauses a running Timer. Countdowns do not pause.
    @discardableResult
    public mutating func pause(_ id: UUID, now: Date) -> Bool {
        update(id) { item in
            guard item.isTimer, item.state == .running else { return false }
            item.pausedRemaining = max(0, item.endsAt.timeIntervalSince(now))
            item.state = .paused
            return true
        }
    }

    @discardableResult
    public mutating func resume(_ id: UUID, now: Date) -> Bool {
        update(id) { item in
            guard item.state == .paused else { return false }
            item.endsAt = now.addingTimeInterval(item.pausedRemaining ?? 0)
            item.pausedRemaining = nil
            item.state = .running
            return true
        }
    }

    /// Pause on a running Timer, Resume on a paused one.
    @discardableResult
    public mutating func togglePause(_ id: UUID, now: Date) -> Bool {
        self[id]?.state == .paused ? resume(id, now: now) : pause(id, now: now)
    }

    /// Restarts a Timer's full length from `now`; a paused Timer stays paused with its full length left.
    @discardableResult
    public mutating func reset(_ id: UUID, now: Date) -> Bool {
        update(id) { item in
            guard let duration = item.duration, !item.isEnded else { return false }
            item.startedAt = now
            if item.state == .paused {
                item.pausedRemaining = duration
            } else {
                item.endsAt = now.addingTimeInterval(duration)
            }
            return true
        }
    }

    /// Takes an item off the board; returns it and where it was, for an undo.
    public mutating func remove(_ id: UUID) -> (item: TimeItem, index: Int)? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return (items.remove(at: index), index)
    }

    /// Puts a removed item back (undo).
    public mutating func restore(_ item: TimeItem, at index: Int) {
        guard self[item.id] == nil else { return }
        items.insert(item, at: min(max(index, 0), items.count))
    }

    /// Acknowledges an ended item: it leaves the board. Returns false when `id` has not ended.
    @discardableResult
    public mutating func acknowledge(_ id: UUID) -> Bool {
        guard let item = self[id], item.isEnded else { return false }
        items.removeAll { $0.id == id }
        return true
    }

    /// Ends every running item whose end is at or before `now`, at its own `endsAt`; returns them, once each.
    public mutating func evaluate(now: Date) -> [TimeItem] {
        var ended: [TimeItem] = []
        for index in items.indices where items[index].state == .running && items[index].endsAt <= now {
            items[index].state = .ended(at: items[index].endsAt)
            ended.append(items[index])
        }
        return ended
    }

    /// The nearest end among running items: the one scheduler job.
    public var nextEnd: Date? {
        items.filter { $0.state == .running }.map(\.endsAt).min()
    }

    public var hasUnacknowledgedEnd: Bool { items.contains(where: \.isEnded) }

    public var hasRunning: Bool { items.contains { $0.state == .running || $0.state == .paused } }

    /// The tab order: ended items first (oldest end first), then running and paused by end time.
    public func sorted(now: Date) -> [TimeItem] {
        items.sorted { lhs, rhs in
            if lhs.isEnded != rhs.isEnded { return lhs.isEnded }
            let l = lhs.effectiveEnd(now: now)
            let r = rhs.effectiveEnd(now: now)
            if l != r { return l < r }
            return lhs.startedAt < rhs.startedAt
        }
    }

    private mutating func update(_ id: UUID, _ change: (inout TimeItem) -> Bool) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        return change(&items[index])
    }
}
