import Foundation
import ModuleKit
import Synchronization
import Testing

@testable import VigieCore

/// Records what it was asked to play; throws for `failing` URLs (an undecodable file).
final class FakeSoundPlayer: SoundPlayer {
    private let state = Mutex<(played: [URL], stops: Int, failing: Set<URL>)>(([], 0, []))

    var played: [URL] { state.withLock { $0.played } }
    var stops: Int { state.withLock { $0.stops } }
    func fail(_ url: URL) { state.withLock { _ = $0.failing.insert(url) } }

    func play(url: URL) async throws {
        let fails = state.withLock { s -> Bool in
            s.played.append(url)
            return s.failing.contains(url)
        }
        if fails { throw CocoaError(.fileReadCorruptFile) }
    }

    func stop() async { state.withLock { $0.stops += 1 } }
}

/// Built-ins resolved to fake paths, so these tests do not depend on the bundled files (Story 10.2).
let fakeSoundCatalog = SoundCatalog(
    builtIns: ["blocked", "failed", "done", "warn"].map { SoundCatalog.BuiltIn(name: $0, label: "x") },
    locate: { URL(fileURLWithPath: "/builtin/\($0).wav") })

let defaultSoundSettings = SoundSettings(
    enabled: true,
    values: [
        "blocked": "builtin:blocked", "failed": "builtin:failed", "done": "builtin:done",
        "quota_warning": "builtin:warn", "timer_end": "off", "break_reminder": "off", "calendar_reminder": "off",
    ])

@MainActor
final class SoundSinkHarness {
    var settings: SoundSettings
    let player = FakeSoundPlayer()
    var problems: [SoundProblem] = []
    var sink: NotifierSoundSink!

    init(_ settings: SoundSettings = defaultSoundSettings) {
        self.settings = settings
        sink = NotifierSoundSink(
            config: { [unowned self] in self.settings }, player: player, catalog: fakeSoundCatalog,
            onProblem: { [unowned self] in self.problems.append($0) }, log: testLogger)
    }

    func play(_ kind: String) async {
        sink.play(
            for: ActiveAlert(
                id: UUID(), module: "agents.sessions",
                event: NotifierEvent(kind: kind, severity: .critical, title: "x"), outputs: [.sound],
                postedAt: Date()))
        await sink.pending?.value
    }
}

@MainActor @Suite struct SoundOutputTests {
    @Test func tableIsTheAD13Table() {
        #expect(SoundTable.key(for: "session.blocked") == "blocked")
        #expect(SoundTable.key(for: "session.failed") == "failed")
        #expect(SoundTable.key(for: "session.done") == "done")
        #expect(SoundTable.key(for: "usage.quota_warning") == "quota_warning")
        #expect(SoundTable.key(for: "time.timer_end") == "timer_end")
        #expect(SoundTable.key(for: "time.break_reminder") == "break_reminder")
        #expect(SoundTable.key(for: "calendar.reminder") == "calendar_reminder")
        #expect(SoundTable.key(for: "shelf.expiring") == nil)
        #expect(SoundTable.key(for: "setup.problem") == nil)
        // Every key is a [sounds] schema key.
        let schema = Set(CoreSettings.all.map(\.path))
        for key in SoundTable.allSoundKeys { #expect(schema.contains(SoundSettings.path(key)), "\(key)") }
        #expect(Set(SoundTable.keys.values) == Set(SoundTable.allSoundKeys))
    }

    @Test func kindsPlayTheirKeysSound() async {
        let h = SoundSinkHarness()
        await h.play("session.blocked")
        await h.play("session.failed")
        await h.play("session.done")
        await h.play("usage.quota_warning")
        #expect(h.player.played.map(\.lastPathComponent) == ["blocked.wav", "failed.wav", "done.wav", "warn.wav"])
        #expect(h.problems.isEmpty)
    }

    @Test func kindsWithoutAKeyNeverPlay() async {
        let h = SoundSinkHarness()
        await h.play("shelf.expiring")
        await h.play("setup.problem")
        await h.play("usage.pace")
        #expect(h.player.played.isEmpty)
    }

    @Test func futureKindsAreOffByDefault() async {
        let h = SoundSinkHarness()
        await h.play("time.timer_end")
        await h.play("time.break_reminder")
        await h.play("calendar.reminder")
        #expect(h.player.played.isEmpty)
        h.settings.values["timer_end"] = "builtin:done"
        await h.play("time.timer_end")
        #expect(h.player.played.count == 1)
    }

    @Test func disabledOrOffPlaysNothing() async {
        let h = SoundSinkHarness()
        h.settings.enabled = false
        await h.play("session.blocked")
        #expect(h.player.played.isEmpty)
        h.settings.enabled = true
        h.settings.values["blocked"] = "off"
        await h.play("session.blocked")
        #expect(h.player.played.isEmpty)
        h.settings.values["blocked"] = nil
        await h.play("session.blocked")
        #expect(h.player.played.isEmpty)
        #expect(h.problems.isEmpty)
    }

    @Test func valueForms() {
        #expect(SoundValue("off") == .off)
        #expect(SoundValue("builtin:blocked") == .builtIn("blocked"))
        #expect(SoundValue("/tmp/a.aiff") == .file(URL(fileURLWithPath: "/tmp/a.aiff")))
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(SoundValue("~/Sounds/a.aiff") == .file(URL(fileURLWithPath: home + "/Sounds/a.aiff")))
        #expect(SoundValue("~/Sounds/a.aiff").raw == "~/Sounds/a.aiff")
        #expect(SoundValue("Sounds/a.aiff") == .invalid("Sounds/a.aiff"))
        #expect(SoundValue("builtin:") == .invalid("builtin:"))
    }

    @Test func customFilePlaysAndTildeExpands() async throws {
        let dir = makeTempDirectory()
        let file = dir.appendingPathComponent("custom.aiff")
        try Data([0]).write(to: file)
        let h = SoundSinkHarness()
        h.settings.values["failed"] = file.path
        await h.play("session.failed")
        #expect(h.player.played == [file])

        let home = FileManager.default.homeDirectoryForCurrentUser
        let homeFile = home.appendingPathComponent(".vigie-sound-test-\(UUID().uuidString).aiff")
        try Data([0]).write(to: homeFile)
        defer { try? FileManager.default.removeItem(at: homeFile) }
        h.settings.values["failed"] = "~/" + homeFile.lastPathComponent
        await h.play("session.failed")
        #expect(h.player.played.last?.standardizedFileURL == homeFile.standardizedFileURL)
    }

    @Test func unplayableValuesReportProblems() async throws {
        let h = SoundSinkHarness()
        h.settings.values["blocked"] = "/nonexistent/vigie/blocked.aiff"
        await h.play("session.blocked")
        h.settings.values["blocked"] = "builtin:nope"
        await h.play("session.blocked")
        h.settings.values["blocked"] = "relative.aiff"
        await h.play("session.blocked")
        #expect(h.player.played.isEmpty)
        #expect(
            h.problems == [
                SoundProblem(key: "blocked", reason: .fileNotFound("/nonexistent/vigie/blocked.aiff")),
                SoundProblem(key: "blocked", reason: .unknownBuiltIn("nope")),
                SoundProblem(key: "blocked", reason: .invalidValue("relative.aiff")),
            ])

        let file = makeTempDirectory().appendingPathComponent("broken.aiff")
        try Data([1, 2, 3]).write(to: file)
        h.player.fail(file)
        h.settings.values["blocked"] = file.path
        await h.play("session.blocked")
        #expect(h.problems.last == SoundProblem(key: "blocked", reason: .unreadable(file.path)))
    }

    @Test func readsSoundsFromConfigStore() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(
            manifests: [], config: "[sounds]\nenabled = false\nblocked = \"~/a.aiff\"\n")
        let settings = SoundSettings.read(from: store)
        #expect(settings.enabled == false)
        #expect(settings.values["blocked"] == "~/a.aiff")
        // Schema defaults (SPEC §11) for the keys the file leaves out.
        #expect(settings.values["failed"] == "builtin:failed")
        #expect(settings.values["done"] == "off")
        #expect(settings.values["quota_warning"] == "builtin:warn")
        #expect(settings.values["timer_end"] == "off")
        #expect(settings.values["calendar_reminder"] == "off")
        store.stop()
    }

    // MARK: Through AlertCenter

    @Test func blockedPlaysOnceThenOnceMoreOnReminder() async {
        let h = AlertHarnessWithSound(reminder: .seconds(600))
        h.post()
        #expect(await eventually { h.player.played.count == 1 })
        #expect(await eventually { h.clock.sleeperCount == 1 })
        h.clock.advance(by: .seconds(600))
        #expect(await eventually { h.player.played.count == 2 })
        h.clock.advance(by: .seconds(3600))
        for _ in 0..<10 { await Task.yield() }
        #expect(h.player.played.count == 2)
        #expect(h.player.played.allSatisfy { $0.lastPathComponent == "blocked.wav" })
    }

    @Test func focusPlaysNothing() async {
        let h = AlertHarnessWithSound(focusActive: true, reminder: .seconds(600))
        h.post()
        h.clock.advance(by: .seconds(600))
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(h.player.played.isEmpty)
    }
}

/// `AlertCenter` with the real ``NotifierSoundSink`` over a fake player.
@MainActor
struct AlertHarnessWithSound {
    let clock = TestClock()
    let player = FakeSoundPlayer()
    let center: AlertCenter
    let notifier: any Notifier

    init(focusActive: Bool = false, reminder: Duration? = nil) {
        let rules = StaticNotifyRules(
            global: GlobalNotifyRules(),
            kinds: ["agents.sessions": ["session.blocked": NotifyRule(reminder: reminder, outputs: [.peek, .sound])]])
        let sink = NotifierSoundSink(
            config: { defaultSoundSettings }, player: player, catalog: fakeSoundCatalog, log: testLogger)
        center = AlertCenter(
            rules: rules, clock: clock, now: { parisDate(12, 0) }, calendar: { parisCalendar },
            sinks: AlertSinks(sound: sink), focus: ManualFocusModeMonitor(isActive: focusActive),
            activity: RecordingActivityLog(), log: testLogger)
        notifier = center.makeNotifier(
            for: ModuleManifest(
                id: "agents.sessions", name: "Sessions", icon: "circle", alertKinds: ["session.blocked"]))
    }

    func post() {
        notifier.post(NotifierEvent(kind: "session.blocked", severity: .critical, title: "api-refactor"))
    }
}
