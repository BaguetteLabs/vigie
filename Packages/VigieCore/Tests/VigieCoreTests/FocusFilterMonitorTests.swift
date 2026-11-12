import AppKit
import Foundation
import ModuleKit
import SwiftUI
import Synchronization
import Testing

@testable import VigieCore

/// Fake `SetFocusFilterIntent.current`: a value, `notFound` (nil) or an error; optionally held until released.
final class FakeFocusFilterSource: FocusFilterSource {
    enum Answer: Sendable {
        case silence(Bool)
        case notFound
        case failure
    }

    private let state: Mutex<(answer: Answer, gate: CheckedContinuation<Void, Never>?, held: Bool)>

    init(_ answer: Answer, held: Bool = false) {
        state = Mutex((answer, nil, held))
    }

    var isWaiting: Bool { state.withLock { $0.gate != nil } }

    func release() {
        let gate = state.withLock { s -> CheckedContinuation<Void, Never>? in
            s.held = false
            defer { s.gate = nil }
            return s.gate
        }
        gate?.resume()
    }

    func currentSilence() async throws -> Bool? {
        let held = state.withLock { $0.held }
        if held {
            await withCheckedContinuation { c in state.withLock { $0.gate = c } }
        }
        switch state.withLock({ $0.answer }) {
        case .silence(let value): return value
        case .notFound: return nil
        case .failure: throw CocoaError(.fileReadUnknown)
        }
    }
}

final class WallClock: Sendable {
    private let date = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
    var now: Date { date.withLock { $0 } }
    func advance(seconds: TimeInterval) { date.withLock { $0 += seconds } }
}

@MainActor
struct FocusFilterHarness {
    let source: FakeFocusFilterSource
    let clock = TestClock()
    let wall = WallClock()
    let monitor: FocusFilterMonitor

    init(_ answer: FakeFocusFilterSource.Answer = .notFound, held: Bool = false) {
        source = FakeFocusFilterSource(answer, held: held)
        let wall = wall
        monitor = FocusFilterMonitor(source: source, clock: clock, now: { wall.now }, log: testLogger)
    }

    func shortcut(_ active: Bool, sentAgo seconds: TimeInterval = 0) {
        monitor.receiveShortcut(
            EventMessage(
                topic: AppTopics.focusTopic, payload: Data("{\"active\":\(active)}".utf8),
                sentAt: wall.now.addingTimeInterval(-seconds)))
    }
}

@MainActor @Suite struct FocusFilterMonitorTests {
    // MARK: Focus filter

    @Test func filterOnAndOffFlipTheStateAndYield() async {
        let h = FocusFilterHarness()
        var changes = h.monitor.changes.makeAsyncIterator()
        #expect(!h.monitor.isActive)
        h.monitor.filterDidRun(silence: true)
        #expect(h.monitor.isActive)
        #expect(await changes.next() == true)
        // The system runs the intent with its default (`false`) when the Focus turns off.
        h.monitor.filterDidRun(silence: false)
        #expect(!h.monitor.isActive)
        #expect(await changes.next() == false)
        #expect(h.monitor.filterHasRun)
    }

    @Test func filterSetToNotSilenceStaysOff() {
        let h = FocusFilterHarness()
        h.monitor.filterDidRun(silence: false)
        #expect(!h.monitor.isActive)
        #expect(h.monitor.filterHasRun)
    }

    @Test func launchWithAFilteredFocusOnStartsActive() async {
        let h = FocusFilterHarness(.silence(true))
        await h.monitor.start()
        #expect(h.monitor.isActive)
        #expect(h.monitor.filterHasRun)
    }

    @Test func launchWithSilenceFalseIsOff() async {
        let h = FocusFilterHarness(.silence(false))
        await h.monitor.start()
        #expect(!h.monitor.isActive)
        // Found: the filter is set up even though it does not silence this Focus.
        #expect(h.monitor.filterHasRun)
    }

    @Test func launchWithNotFoundIsOff() async {
        let h = FocusFilterHarness(.notFound)
        await h.monitor.start()
        #expect(!h.monitor.isActive)
        #expect(!h.monitor.filterHasRun)
    }

    @Test func launchReadErrorIsOff() async {
        let h = FocusFilterHarness(.failure)
        await h.monitor.start()
        #expect(!h.monitor.isActive)
        #expect(!h.monitor.filterHasRun)
    }

    @Test func performDuringTheLaunchReadWins() async {
        let h = FocusFilterHarness(.silence(true), held: true)
        let start = Task { await h.monitor.start() }
        #expect(await eventually { h.source.isWaiting })
        // The Focus turned off while `current` was being read.
        h.monitor.filterDidRun(silence: false)
        h.source.release()
        await start.value
        #expect(!h.monitor.isActive)
    }

    @Test func filterRunCallsTheHook() {
        let h = FocusFilterHarness()
        var runs = 0
        h.monitor.onFilterRun = { runs += 1 }
        h.monitor.filterDidRun(silence: true)
        h.monitor.filterDidRun(silence: false)
        #expect(runs == 2)
    }

    // MARK: Shortcuts bridge

    @Test func shortcutOnAndOff() async {
        let h = FocusFilterHarness()
        var changes = h.monitor.changes.makeAsyncIterator()
        h.shortcut(true)
        #expect(h.monitor.isActive)
        #expect(await changes.next() == true)
        h.shortcut(false)
        #expect(!h.monitor.isActive)
        #expect(await changes.next() == false)
        // The bridge never counts as the filter being set up.
        #expect(!h.monitor.filterHasRun)
    }

    @Test func malformedShortcutPayloadsAreIgnored() {
        let h = FocusFilterHarness()
        for payload in ["", "not json", "{\"active\":1}", "{\"active\":\"true\"}", "{}", "[true]"] {
            h.monitor.receiveShortcut(
                EventMessage(topic: AppTopics.focusTopic, payload: Data(payload.utf8), sentAt: h.wall.now))
        }
        #expect(!h.monitor.isActive)
        #expect(FocusFilterMonitor.parseShortcut(Data("{\"active\": true}".utf8)) == true)
        #expect(FocusFilterMonitor.parseShortcut(Data("{\"active\":false}".utf8)) == false)
    }

    @Test func olderShortcutMessageIsIgnored() {
        let h = FocusFilterHarness()
        h.shortcut(false)
        // A spooled "on" sent before the "off" that already arrived.
        h.shortcut(true, sentAgo: 60)
        #expect(!h.monitor.isActive)
    }

    @Test func shortcutOnExpiresAfterTwelveHours() async {
        let h = FocusFilterHarness()
        h.shortcut(true)
        #expect(await eventually { h.clock.sleeperCount == 1 })
        h.clock.advance(by: .seconds(12 * 3600 - 1))
        for _ in 0..<10 { await Task.yield() }
        #expect(h.monitor.isActive)
        h.clock.advance(by: .seconds(1))
        #expect(await eventually { !h.monitor.isActive })
    }

    @Test func laterShortcutMessageRestartsTheCap() async {
        let h = FocusFilterHarness()
        h.shortcut(true)
        #expect(await eventually { h.clock.sleeperCount == 1 })
        h.clock.advance(by: .seconds(11 * 3600))
        h.wall.advance(seconds: 11 * 3600)
        h.shortcut(true)
        #expect(await eventually { h.clock.sleeperCount == 1 })
        h.clock.advance(by: .seconds(2 * 3600))
        for _ in 0..<10 { await Task.yield() }
        #expect(h.monitor.isActive)
        h.clock.advance(by: .seconds(10 * 3600))
        #expect(await eventually { !h.monitor.isActive })
    }

    @Test func spooledOnOlderThanTheCapIsOff() async {
        let h = FocusFilterHarness()
        h.shortcut(true, sentAgo: 13 * 3600)
        #expect(!h.monitor.isActive)
        // A spooled "on" sent 10 h ago holds for the 2 h left.
        let fresh = FocusFilterHarness()
        fresh.shortcut(true, sentAgo: 10 * 3600)
        #expect(fresh.monitor.isActive)
        #expect(await eventually { fresh.clock.sleeperCount == 1 })
        fresh.clock.advance(by: .seconds(2 * 3600))
        #expect(await eventually { !fresh.monitor.isActive })
    }

    @Test func eitherInputKeepsItActive() {
        let h = FocusFilterHarness()
        h.monitor.filterDidRun(silence: true)
        h.shortcut(true)
        h.shortcut(false)
        #expect(h.monitor.isActive)
        h.monitor.filterDidRun(silence: false)
        #expect(!h.monitor.isActive)
    }

    // MARK: Notifier

    @Test func filterDrivesStory35Suppression() async {
        let h = FocusFilterHarness()
        let center = AlertCenter(
            rules: StaticNotifyRules(), sinks: AlertSinks(peek: RecordingPeekSink()), focus: h.monitor,
            log: testLogger)
        h.monitor.filterDidRun(silence: true)
        #expect(await eventually { center.isFocusActive })
        h.monitor.filterDidRun(silence: false)
        #expect(await eventually { !center.isFocusActive })
    }

    // MARK: app.focus topic

    @Test func appFocusTopicReachesTheMonitor() async {
        let h = FocusFilterHarness()
        let bus = InProcessEventBus()
        let monitor = h.monitor
        let topics = AppTopics(
            bus: bus, logger: testLogger, onReload: {}, onExpand: { _ in },
            onFocus: { monitor.receiveShortcut($0) })
        topics.start()
        defer { topics.stop() }
        bus.publish(EventMessage(topic: "app.focus", payload: Data("{\"active\":true}".utf8), sentAt: h.wall.now))
        #expect(await eventually { monitor.isActive })
        bus.publish(EventMessage(topic: "app.focus", payload: Data("{\"active\":false}".utf8), sentAt: h.wall.now))
        #expect(await eventually { !monitor.isActive })
    }
}

@MainActor @Suite(.serialized) struct FocusFilterSetupTests {
    @Test func flagIsWrittenToLocalTomlOnFirstRun() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore()
        defer { store.stop() }
        let h = FocusFilterHarness()
        let setup = FocusFilterSetup(store: store, monitor: h.monitor, log: testLogger)
        setup.start()
        defer { setup.stop() }
        #expect(!FocusFilterSetup.isSetUp(store))
        h.monitor.filterDidRun(silence: false)
        #expect(await eventually { FocusFilterSetup.isSetUp(store) })
        let local = try String(contentsOf: fixture.localURL, encoding: .utf8)
        #expect(local.contains("focus_filter_ran = true"))
        let config = (try? String(contentsOf: fixture.configURL, encoding: .utf8)) ?? ""
        #expect(!config.contains("focus_filter_ran = true"))
    }

    @Test func runBeforeTheStoreExistedIsRecorded() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore()
        defer { store.stop() }
        let h = FocusFilterHarness(.silence(true))
        await h.monitor.start()
        let setup = FocusFilterSetup(store: store, monitor: h.monitor, log: testLogger)
        setup.start()
        defer { setup.stop() }
        #expect(await eventually { FocusFilterSetup.isSetUp(store) })
    }

    @Test func notFoundAtLaunchAndShortcutsDoNotRecord() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore()
        defer { store.stop() }
        let h = FocusFilterHarness(.notFound)
        await h.monitor.start()
        let setup = FocusFilterSetup(store: store, monitor: h.monitor, log: testLogger)
        setup.start()
        defer { setup.stop() }
        h.shortcut(true)
        for _ in 0..<20 { await Task.yield() }
        #expect(!FocusFilterSetup.isSetUp(store))
    }

    @Test func existingRecordIsRead() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(local: "[notify]\nfocus_filter_ran = true\n")
        defer { store.stop() }
        #expect(FocusFilterSetup.isSetUp(store))
        #expect(store.problems.isEmpty)
    }
}

@MainActor @Suite(.serialized) struct FocusSettingsTests {
    @Test func alertsPaneShowsNeedsSetupUntilTheFilterRan() async throws {
        let h = try await SettingsHarness()
        #expect(h.controller.focusSetupState == .needsSetup)
        // Nothing opens by itself: no window, no System Settings link at launch.
        #expect(h.controller.window == nil)
        #expect(h.openedURLs.isEmpty)
        h.controller.openFocusSettings()
        #expect(h.openedURLs == [SettingsController.focusSettingsURL])
        #expect(
            SettingsController.focusSettingsURL.absoluteString
                == "x-apple.systempreferences:com.apple.Focus-Settings.extension")

        let pane = try #require(h.controller.pane("notify"))
        try await render(h, pane)

        try await h.store.set(FocusFilterSetup.path, to: .bool(true))
        #expect(h.controller.focusSetupState == .ready)
        #expect(h.localText().contains("focus_filter_ran = true"))
        try await render(h, pane)
        await h.tearDown()
    }

    @Test func shortcutCommandsMatchTheTopic() {
        #expect(
            FocusSettingsSection.shortcutCommand(cli: "~/.local/bin/vigie", active: true)
                == "~/.local/bin/vigie event app.focus '{\"active\":true}'")
        #expect(
            FocusSettingsSection.shortcutCommand(cli: "vigie", active: false)
                == "vigie event app.focus '{\"active\":false}'")
        // The command's payload is what the monitor parses.
        #expect(FocusFilterMonitor.parseShortcut(Data("{\"active\":true}".utf8)) == true)
    }

    @Test func focusStringsResolve() {
        let keys = [
            "settings.section.focus", "settings.focus.title", "settings.focus.needsSetup", "settings.focus.step1",
            "settings.focus.step2", "settings.focus.step3", "settings.focus.open", "settings.focus.ready",
            "settings.focus.shortcuts.title", "settings.focus.shortcuts.intro", "settings.focus.shortcuts.on",
            "settings.focus.shortcuts.off", "settings.focus.shortcuts.scripts", "settings.focus.shortcuts.cap",
        ]
        for key in keys { #expect(SettingsText.string(key) != key, "\(key)") }
        #expect(SettingsText.string("settings.focus.open") == "Open Focus settings")
    }

    private func render(_ h: SettingsHarness, _ pane: SettingsPane) async throws {
        let (host, view) = hostOffscreen(
            SettingsPaneView(controller: h.controller, pane: pane)
                .environment(\.settingControlServices, h.controller.services),
            size: SettingsWindowMetrics.size)
        defer { host.close() }
        view.layoutSubtreeIfNeeded()
        #expect(view.fittingSize.height > 0)
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        #expect(rep.pixelsWide > 0)
    }
}
