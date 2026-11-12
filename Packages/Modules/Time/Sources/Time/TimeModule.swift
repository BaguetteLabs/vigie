import Foundation
import ModuleKit
import Observation
import SwiftUI
import VigieUI
import os

/// `time` (SPEC §7.7, Story 20.2): Timers and Countdowns, the Time tab and the Timer-end alert.
///
/// Items live in `items.json` in `context.storage` (AD-11) with absolute end times, so they survive a quit and
/// a sleep. One scheduler job waits for the nearest end and is re-armed after every change; the tab adds a 1 s
/// tick only while it is visible. An end is detected at that job, on launch and on wake (`power.sleepWake`);
/// each ended item raises `time.timer_end` once (the transition is persisted) and stays on the tab as
/// `ENDED 14:48` with `DISMISS` until acknowledged, the module in `alert` state (the tab's attention marker).
///
/// Break reminders (Story 20.4, `breaks.*`, off by default): see `TimeBreaks.swift`; ``BreakTracker`` does the
/// accounting on `context.away`, which is subscribed only while they are on.
///
/// Pomodoro (Story 20.5): see `TimePomodoro.swift`; it is saved with the items and holds break reminders while
/// it runs. `context.away` is subscribed while break reminders are on or a Pomodoro runs.
///
/// Disabled (the default, SPEC §11): the Registry never starts it, so there is no hotkey, job or timer.
/// The closed-notch readout (Story 20.6, `closed_notch`, `priority`): see `TimeClosedNotch.swift`; it shares the
/// 1 s tick, which runs only while the tab or the readout shows.
@MainActor @Observable
public final class TimeModule: NotchModule, AlertActionHandler {
    nonisolated static let bundle = TimeText.bundle

    /// The Timer-end alert kind (AD-13 amended 2026-11-06).
    public nonisolated static let timerEndKind = "time.timer_end"
    /// The alert action routed back to the module: open the Time tab.
    public nonisolated static let openTimeAction = "open-time"
    /// State file (`items.json`) and its schema (2: items and the Pomodoro, Story 20.5; 1 read as items).
    nonisolated static let stateFile = "items"
    nonisolated static let stateSchema = 2
    /// SPEC §11 default presets.
    public nonisolated static let defaultPresets = [5, 10, 25]
    /// How long a removed item can be put back.
    public nonisolated static let undoWindow: Duration = .seconds(5)
    /// The tab's tick while it is visible.
    public nonisolated static let uiTick: Duration = .seconds(1)

    public nonisolated static let staticManifest = ModuleManifest(
        id: "time",
        name: LocalizedStringResource("time.module.name", bundle: bundle),
        icon: "timer",
        settings: [
            SettingDescriptor(
                key: "hotkey",
                label: LocalizedStringResource("time.setting.hotkey", bundle: bundle),
                kind: .hotkey(default: nil),
                scope: .synced,
                help: LocalizedStringResource("time.setting.hotkey.help", bundle: bundle)),
            SettingDescriptor(
                key: "presets",
                label: LocalizedStringResource("time.setting.presets", bundle: bundle),
                kind: .list(of: .string, default: defaultPresets.map(String.init)),
                scope: .synced,
                help: LocalizedStringResource("time.setting.presets.help", bundle: bundle)),
        ] + closedNotchDescriptors(bundle: bundle) + PomodoroLengths.descriptors(bundle: bundle)
            + BreakSettings.descriptors(bundle: bundle),
        alertKinds: [timerEndKind, breakReminderKind],
        defaultEnabled: false
    )

    public let manifest = TimeModule.staticManifest
    /// `hidden` with nothing on the board, `active` while an item runs or is paused, `alert` while an ended item
    /// is unacknowledged (SPEC §7.7).
    public private(set) var state: ModuleState = .hidden
    public private(set) var board = TimeBoard()
    /// The time the tab renders at: refreshed by the 1 s tick while the tab shows, and by every change.
    public private(set) var displayNow: Date
    public internal(set) var selectedID: UUID?
    /// The last removed item, for 5 s.
    public private(set) var undoSlot: (item: TimeItem, index: Int)?
    /// Set by the Time hotkey (A87); the tab focuses its quick start and clears it.
    public internal(set) var focusQuickStart = false
    /// Quick-start presets, in minutes.
    public private(set) var presets: [Int] = TimeModule.defaultPresets
    public private(set) var isRunning = false

    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored var context: (any ModuleContext)?
    @ObservationIgnored private var endJob: RegistrationToken?
    @ObservationIgnored private var tickJob: RegistrationToken?
    @ObservationIgnored private var undoJob: RegistrationToken?
    @ObservationIgnored private var hotkey: RegistrationToken?
    @ObservationIgnored var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var visibleTabs = 0
    /// Alerts posted this launch, resolved when their item is dismissed or removed.
    @ObservationIgnored private var handles: [UUID: AlertHandle] = [:]

    // Break reminders (Story 20.4).
    /// The work / break accounting while break reminders are on; nil when they are off.
    internal(set) var breaks: BreakTracker?
    public internal(set) var breakSettings = BreakSettings()
    @ObservationIgnored var breakHandle: AlertHandle?
    @ObservationIgnored var breakJob: RegistrationToken?
    @ObservationIgnored var presenceTask: Task<Void, Never>?
    /// Raises this launch, for unique dedupe keys (a re-raise is a new alert).
    @ObservationIgnored var breakRaises = 0
    /// The last presence `context.away` reported (Away pauses a Pomodoro work period).
    @ObservationIgnored var isAway = false

    // Pomodoro (Story 20.5).
    /// The one Pomodoro (A87), nil when none runs.
    public internal(set) var pomodoro: Pomodoro?
    /// `[modules.time] pomodoro` lengths, applied to the next phase of a running Pomodoro.
    public internal(set) var pomodoroLengths = PomodoroLengths()
    @ObservationIgnored var pomodoroJob: RegistrationToken?
    /// Its work-end break alert (`time.break_reminder`) and break-end alert (`time.timer_end`).
    @ObservationIgnored var pomodoroBreakHandle: AlertHandle?
    @ObservationIgnored var pomodoroEndHandle: AlertHandle?
    @ObservationIgnored var pomodoroRaises = 0

    // Closed-notch readout (Story 20.6).
    /// `[modules.time] closed_notch`.
    public internal(set) var closedVariant: TimeClosedVariant = .off
    /// `[modules.time] priority`: the left-wing priority of the Time item (readout or `BREAK DUE`).
    public internal(set) var wingPriority = TimeModule.defaultWingPriority
    /// Closed readouts on screen (one per display); the 1 s tick runs while one shows.
    @ObservationIgnored var visibleReadouts = 0

    public init(now: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
        self.displayNow = now()
    }

    // MARK: Lifecycle

    public func start(context: any ModuleContext) async throws {
        self.context = context
        presets = Self.resolvedPresets(context.settings)
        do {
            let state = try await context.storage.readJSON(
                Self.stateFile, as: TimeState.self, schema: Self.stateSchema)
            board = TimeBoard(items: state?.items ?? [])
            pomodoro = state?.pomodoro
        } catch {
            context.log.error("Time items unreadable: \(String(describing: error), privacy: .public)")
        }
        isRunning = true
        // An end that passed while Vigie was not running alerts once, now.
        evaluate()
        do {
            hotkey = try context.hotkeys.register(name: "hotkey", default: nil) { [weak self] intent in
                self?.openFromHotkey(intent)
            }
        } catch {
            context.log.error("Time hotkey not registered: \(String(describing: error), privacy: .public)")
        }
        let wakes = context.power.sleepWake
        tasks.append(
            Task { @MainActor [weak self] in
                for await event in wakes {
                    guard !Task.isCancelled else { return }
                    self?.sleepWake(event)
                }
            })
        startPomodoroSettings(context.settings)
        startBreakSettings(context.settings)
        startClosedNotchSettings(context.settings)
        restorePomodoro()
        let presetChanges = context.settings.observe("presets")
        tasks.append(
            Task { @MainActor [weak self] in
                for await _ in presetChanges {
                    guard let self, !Task.isCancelled, let settings = self.context?.settings else { return }
                    self.presets = Self.resolvedPresets(settings)
                }
            })
    }

    public func stop() async {
        for task in tasks { task.cancel() }
        tasks = []
        stopBreaks()
        presenceTask?.cancel()
        presenceTask = nil
        for token in [endJob, tickJob, undoJob, hotkey, pomodoroJob] { token?.cancel() }
        pomodoroJob = nil
        endJob = nil
        tickJob = nil
        undoJob = nil
        hotkey = nil
        visibleTabs = 0
        visibleReadouts = 0
        isRunning = false
        await saveTask?.value
    }

    /// Ends what is due, alerts once per ended item, persists, re-arms the end job and refreshes the state.
    func evaluate() {
        guard isRunning else { return }
        let date = now()
        let ended = board.evaluate(now: date)
        for item in ended { postEnd(item) }
        changed(save: !ended.isEmpty)
    }

    /// After any change: the end job at the nearest end, the state, the tab time, and (when asked) the file.
    func changed(save: Bool = true) {
        displayNow = now()
        state =
            board.hasUnacknowledgedEnd || breaks?.isDue == true || pomodoro?.isDue == true
            ? .alert : (board.hasRunning || breaks?.breakEndsAt != nil || pomodoro != nil ? .active : .hidden)
        armEndJob()
        updateTick()
        if save { persist() }
    }

    private func armEndJob() {
        endJob?.cancel()
        endJob = nil
        guard isRunning, let context, let next = board.nextEnd else { return }
        endJob = context.scheduler.at(next) { [weak self] in
            await MainActor.run { self?.evaluate() }
        }
    }

    private func persist() {
        guard let storage = context?.storage else { return }
        let items = TimeState(items: board.items, pomodoro: pomodoro)
        let previous = saveTask
        let log = context?.log
        saveTask = Task {
            await previous?.value
            do {
                try await storage.writeJSON(items, name: Self.stateFile, schema: Self.stateSchema)
            } catch {
                log?.error("Time items not saved: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Waits for pending writes (tests).
    func flushed() async { await saveTask?.value }

    // MARK: Alerts

    private func postEnd(_ item: TimeItem) {
        guard let context else { return }
        let payload = Data(item.id.uuidString.utf8)
        let event = NotifierEvent(
            kind: Self.timerEndKind, severity: .info, title: TimeFormat.alertTitle(item),
            body: TimeFormat.alertBody(item, calendar: calendar),
            action: .module(id: manifest.id, actionID: Self.openTimeAction, payload: payload),
            dedupeKey: "\(Self.timerEndKind).\(item.id.uuidString)",
            category: TimeFormat.clock(item.endsAt, calendar: calendar))
        handles[item.id] = context.notifier.post(event)
    }

    public func handleAlertAction(_ actionID: String, payload: Data, intent: UserIntent?) {
        if handlePomodoroBreakAction(actionID) || handleBreakAction(actionID) { return }
        guard actionID == Self.openTimeAction else { return }
        if let id = UUID(uuidString: String(decoding: payload, as: UTF8.self)), board[id] != nil || pomodoro?.id == id {
            selectedID = id
        }
        context?.host.openOwnTab(focus: intent)
    }

    /// The Time hotkey: the expanded view on the Time tab with the quick start focused (A87).
    func openFromHotkey(_ intent: UserIntent) {
        focusQuickStart = true
        context?.host.openOwnTab(focus: intent)
    }

    // MARK: Actions

    @discardableResult
    public func startTimer(minutes: Int, label: String? = nil) -> TimeItem? {
        guard isRunning else { return nil }
        let name = Self.name(label, fallback: "time.label.timer")
        guard let item = board.startTimer(minutes: minutes, label: name, now: now()) else { return nil }
        selectedID = item.id
        changed()
        return item
    }

    @discardableResult
    public func startCountdown(to date: Date, label: String? = nil) -> TimeItem? {
        guard isRunning else { return nil }
        let name = Self.name(label, fallback: "time.label.countdown")
        guard let item = board.startCountdown(to: date, label: name, now: now()) else { return nil }
        selectedID = item.id
        changed()
        return item
    }

    /// The custom field: `45`, `45m`, `45 min Tea` (minutes, then an optional name).
    @discardableResult
    public func startCustom(_ text: String) -> TimeItem? {
        guard let (minutes, label) = Self.parseCustom(text) else { return nil }
        return startTimer(minutes: minutes, label: label)
    }

    public func togglePause(_ id: UUID) {
        guard board.togglePause(id, now: now()) else { return }
        changed()
    }

    public func reset(_ id: UUID) {
        guard board.reset(id, now: now()) else { return }
        changed()
    }

    /// Takes an item off the tab; `undo()` puts it back within 5 s. An ended item is dismissed instead.
    public func remove(_ id: UUID) {
        if board[id]?.isEnded == true { return dismiss(id) }
        guard let removed = board.remove(id) else { return }
        if selectedID == id { selectedID = nil }
        handles.removeValue(forKey: id)?.resolve()
        undoSlot = removed
        undoJob?.cancel()
        undoJob = context?.scheduler.at(now().addingTimeInterval(Self.undoWindow.timeInterval)) { [weak self] in
            await MainActor.run { self?.expireUndo(removed.item.id) }
        }
        changed()
    }

    public func undo() {
        guard let slot = undoSlot else { return }
        undoSlot = nil
        undoJob?.cancel()
        undoJob = nil
        board.restore(slot.item, at: slot.index)
        selectedID = slot.item.id
        changed()
        evaluate()
    }

    func expireUndo(_ id: UUID) {
        guard undoSlot?.item.id == id else { return }
        undoSlot = nil
        undoJob = nil
    }

    /// Acknowledges an ended item: it leaves the tab and its alert is resolved.
    public func dismiss(_ id: UUID) {
        guard board.acknowledge(id) else { return }
        handles.removeValue(forKey: id)?.resolve()
        if selectedID == id { selectedID = nil }
        changed()
    }

    /// The tab appeared or went away: the 1 s tick runs only while at least one shows.
    func tabVisibility(_ visible: Bool) {
        visibleTabs = max(0, visibleTabs + (visible ? 1 : -1))
        updateTick()
    }

    /// The 1 s tick runs while a tab shows, or a closed readout shows something (Story 20.6); never otherwise.
    func updateTick() {
        let wanted = isRunning && (visibleTabs > 0 || (visibleReadouts > 0 && offersClosedReadout))
        if wanted, tickJob == nil, let context {
            tickJob = context.scheduler.every(Self.uiTick) { [weak self] in
                await MainActor.run { self?.tick() }
            }
            displayNow = now()
        } else if !wanted, let job = tickJob {
            job.cancel()
            tickJob = nil
        }
    }

    /// The tab's 1 s refresh; also ends what is due a little early for the job.
    func tick() {
        if let deadline = breaks?.nextDeadline, deadline <= now() { breakTick() }
        if let deadline = pomodoro?.nextDeadline, deadline <= now() { pomodoroTick() }
        if let next = board.nextEnd, next <= now() { evaluate() } else { displayNow = now() }
    }

    var isTicking: Bool { tickJob != nil }

    // MARK: Helpers

    static func name(_ label: String?, fallback key: String) -> String {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? TimeText.string(key) : trimmed
    }

    /// Minutes then an optional name: `45`, `45m`, `45 min Tea`, ` 5 Tea `. Nil when there is no leading number
    /// or it is outside 1...1440.
    nonisolated static func parseCustom(_ text: String) -> (minutes: Int, label: String?)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 4, let minutes = Int(digits),
            (1...TimeBoard.maxTimerMinutes).contains(minutes)
        else { return nil }
        var rest = trimmed.dropFirst(digits.count).drop { $0 == " " }
        for unit in ["min", "m"] where rest.lowercased().hasPrefix(unit) {
            let after = rest.dropFirst(unit.count)
            if after.isEmpty || after.first == " " {
                rest = after.drop { $0 == " " }
                break
            }
        }
        let label = rest.trimmingCharacters(in: .whitespaces)
        return (minutes, label.isEmpty ? nil : label)
    }

    /// `presets` as whole minutes in 1...1440, duplicates dropped; the default when none is valid.
    nonisolated static func resolvedPresets(_ settings: any ModuleSettings) -> [Int] {
        let raw = settings.value("presets", as: [String].self) ?? defaultPresets.map(String.init)
        var seen = Set<Int>()
        let values = raw.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { (1...TimeBoard.maxTimerMinutes).contains($0) && seen.insert($0).inserted }
        return values.isEmpty ? defaultPresets : values
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
