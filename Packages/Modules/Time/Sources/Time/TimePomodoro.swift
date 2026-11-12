import Foundation
import ModuleKit
import VigieUI

/// Pomodoro (SPEC §7.7, Story 20.5): one at a time (A87), started from the Time tab, persisted in `items.json`
/// with the Timers.
///
/// - A work period that ends posts `time.break_reminder` with the break peek of Story 20.4 (Start break /
///   Snooze 5m / Skip, kicker `POMODORO · BREAK` or `POMODORO · LONG BREAK`, quiet with `breaks.style =
///   "quiet"`); the module is in `alert` and the left wing shows `BREAK DUE` until the break is started or
///   skipped. Snooze re-raises it after 5 min.
/// - A break that ends posts `time.timer_end` (kicker `BREAK · ENDED`) and the next work period starts on its own.
/// - Away during work pauses it (`AWAY · PAUSED`); Present resumes it, so does Resume.
/// - While it runs, break reminders are paused (``BreakTracker/pause(while:at:)``).
extension TimeModule {
    public nonisolated static let pomodoroKind = "pomodoro"

    // MARK: Settings

    func startPomodoroSettings(_ settings: any ModuleSettings) {
        pomodoroLengths = PomodoroLengths(settings)
        for key in PomodoroLengths.keys {
            let changes = settings.observe(key)
            tasks.append(
                Task { @MainActor [weak self] in
                    for await _ in changes {
                        guard let self, !Task.isCancelled, let settings = self.context?.settings else { return }
                        self.pomodoroLengths = PomodoroLengths(settings)
                        if var pomodoro = self.pomodoro {
                            pomodoro.apply(self.pomodoroLengths)
                            self.pomodoro = pomodoro
                            self.pomodoroChanged()
                        }
                    }
                })
        }
    }

    /// After launch: the restored Pomodoro holds break reminders, follows presence and catches up on what
    /// ended while Vigie was not running (a work end posts its break once; the transition is persisted).
    func restorePomodoro() {
        guard var pomodoro else { return }
        pomodoro.apply(pomodoroLengths)
        self.pomodoro = pomodoro
        holdBreakReminders(true)
        updatePresenceSubscription()
        pomodoroTick()
    }

    // MARK: Actions

    /// The quick start's `POMODORO`: nil when one already runs (A87) or the module is stopped.
    @discardableResult
    public func startPomodoro() -> Pomodoro? {
        guard isRunning, pomodoro == nil else { return nil }
        let pomodoro = Pomodoro(lengths: pomodoroLengths, at: now())
        self.pomodoro = pomodoro
        selectedID = pomodoro.id
        holdBreakReminders(true)
        updatePresenceSubscription()
        pomodoroChanged()
        return pomodoro
    }

    /// Pause or Resume (the row's chip or Space). Resume also ends an Away pause at once.
    public func togglePomodoroPause() {
        guard var pomodoro, !pomodoro.isDue else { return }
        if pomodoro.isPaused {
            pomodoro.resume(at: now())
        } else {
            pomodoro.pause(.user, at: now())
        }
        self.pomodoro = pomodoro
        pomodoroChanged()
    }

    /// Start break, from the break peek, the macOS notification or the Time tab.
    public func startPomodoroBreak() {
        guard var pomodoro, pomodoro.isDue else { return }
        pomodoro.startBreak(at: now())
        self.pomodoro = pomodoro
        resolvePomodoroBreak()
        pomodoroChanged()
    }

    /// Snooze 5m: still due (and on the left wing); raised again in 5 min.
    public func snoozePomodoroBreak() {
        guard var pomodoro, pomodoro.isDue else { return }
        pomodoro.snooze(at: now())
        self.pomodoro = pomodoro
        pomodoroChanged()
    }

    /// Skip the current phase (see ``Pomodoro/skip(at:)``).
    public func skipPomodoroPhase() {
        guard var pomodoro else { return }
        pomodoro.skip(at: now())
        if pomodoro.isWork, isAway { pomodoro.away(since: now(), at: now()) }
        self.pomodoro = pomodoro
        resolvePomodoroBreak()
        resolvePomodoroEnd()
        pomodoroChanged()
    }

    /// Stop: the Pomodoro ends, its alerts are resolved and break reminders resume with a fresh cycle.
    public func stopPomodoro() {
        guard let pomodoro else { return }
        self.pomodoro = nil
        if selectedID == pomodoro.id { selectedID = nil }
        pomodoroJob?.cancel()
        pomodoroJob = nil
        resolvePomodoroBreak()
        resolvePomodoroEnd()
        holdBreakReminders(false)
        updatePresenceSubscription()
        changed()
    }

    /// The break peek's actions while a Pomodoro break is due (break reminders are paused meanwhile).
    func handlePomodoroBreakAction(_ actionID: String) -> Bool {
        guard let pomodoro, pomodoro.isDue else { return false }
        switch actionID {
        case Self.startBreakAction: startPomodoroBreak()
        case Self.snoozeBreakAction: snoozePomodoroBreak()
        case Self.skipBreakAction: skipPomodoroPhase()
        default: return false
        }
        return true
    }

    func performPomodoro(_ control: TimeRowModel.Control) {
        switch control {
        case .pause, .resume: togglePomodoroPause()
        case .startBreak: startPomodoroBreak()
        case .snooze: snoozePomodoroBreak()
        case .skip: skipPomodoroPhase()
        case .stop, .remove: stopPomodoro()
        case .reset, .dismiss: break
        }
    }

    // MARK: Inputs

    func pomodoroPresence(_ presence: Presence) {
        guard var pomodoro else { return }
        let date = now()
        switch presence {
        case .away(let since): pomodoro.away(since: since, at: date)
        case .present: pomodoro.present(at: date)
        }
        self.pomodoro = pomodoro
        pomodoroChanged()
    }

    /// The deadline job, the tab tick, wake and launch.
    func pomodoroTick() {
        guard var pomodoro else { return }
        let events = pomodoro.tick(at: now(), away: isAway)
        self.pomodoro = pomodoro
        for event in events { handle(event) }
        pomodoroChanged(save: !events.isEmpty)
    }

    private func handle(_ event: Pomodoro.Event) {
        switch event {
        case .workEnded(let cycle, let long, let worked, let since):
            resolvePomodoroEnd()
            raisePomodoroBreak(cycle: cycle, long: long, worked: worked, since: since)
        case .reRaise:
            guard let pomodoro, case .breakDue = pomodoro.phase else { return }
            raisePomodoroBreak(
                cycle: pomodoro.cycle, long: pomodoro.longBreakNext, worked: pomodoro.workedInSet,
                since: pomodoro.setStartedAt)
        case .breakEnded(let long, let startedAt, let endedAt):
            resolvePomodoroBreak()
            postBreakEnd(long: long, startedAt: startedAt, endedAt: endedAt)
        }
    }

    /// After a change: the deadline job, the state and the file.
    func pomodoroChanged(save: Bool = true) {
        rearmPomodoroJob()
        changed(save: save)
    }

    private func rearmPomodoroJob() {
        pomodoroJob?.cancel()
        pomodoroJob = nil
        guard isRunning, let context, let deadline = pomodoro?.nextDeadline else { return }
        pomodoroJob = context.scheduler.at(deadline) { [weak self] in
            await MainActor.run { self?.pomodoroTick() }
        }
    }

    /// Break reminders pause while a Pomodoro runs (SPEC §7.7, PRD FR-49) and restart fresh when it stops.
    func holdBreakReminders(_ hold: Bool) {
        guard var tracker = breaks else { return }
        let events = tracker.pause(while: hold, at: now())
        breaks = tracker
        if events.contains(.cleared) {
            breakHandle?.resolve()
            breakHandle = nil
        }
        breakTick()
    }

    // MARK: Alerts

    private func raisePomodoroBreak(cycle: Int, long: Bool, worked: TimeInterval, since: Date) {
        guard let context, let pomodoro else { return }
        pomodoroBreakHandle?.resolve()
        pomodoroRaises += 1
        let id = manifest.id
        let event = NotifierEvent(
            kind: Self.breakReminderKind, severity: .info,
            title: TimeFormat.pomodoroBreakTitle(cycles: cycle, length: pomodoro.breakLength),
            body: TimeFormat.breakBody(worked: worked, since: since, calendar: calendar),
            action: .module(id: id, actionID: Self.startBreakAction, payload: Data()),
            dedupeKey: "\(Self.breakReminderKind).pomodoro.\(pomodoroRaises)",
            secondaryAction: .module(id: id, actionID: Self.skipBreakAction, payload: Data()),
            tertiaryAction: .module(id: id, actionID: Self.snoozeBreakAction, payload: Data()),
            kicker: TimeText.string(long ? "time.pomodoro.kicker.longBreak" : "time.pomodoro.kicker.break"),
            quiet: breakSettings.style == .quiet)
        pomodoroBreakHandle = context.notifier.post(event)
    }

    private func postBreakEnd(long: Bool, startedAt: Date, endedAt: Date) {
        guard let context, let pomodoro else { return }
        pomodoroEndHandle?.resolve()
        pomodoroRaises += 1
        let event = NotifierEvent(
            kind: Self.timerEndKind, severity: .info,
            title: TimeFormat.pomodoroBreakEndTitle(pomodoro),
            body: TimeFormat.pomodoroBreakEndBody(startedAt: startedAt, endedAt: endedAt, calendar: calendar),
            action: .module(
                id: manifest.id, actionID: Self.openTimeAction, payload: Data(pomodoro.id.uuidString.utf8)),
            dedupeKey: "\(Self.timerEndKind).pomodoro.\(pomodoroRaises)",
            kicker: TimeText.string("time.pomodoro.kicker.breakEnded"))
        pomodoroEndHandle = context.notifier.post(event)
    }

    private func resolvePomodoroBreak() {
        pomodoroBreakHandle?.resolve()
        pomodoroBreakHandle = nil
    }

    private func resolvePomodoroEnd() {
        pomodoroEndHandle?.resolve()
        pomodoroEndHandle = nil
    }

    // MARK: Surfaces

    func pomodoroRow(now date: Date) -> TimeRowModel? {
        pomodoro.map { TimeFormat.pomodoroRow($0, now: date, calendar: calendar) }
    }
}
