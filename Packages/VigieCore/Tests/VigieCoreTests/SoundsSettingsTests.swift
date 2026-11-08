import AppKit
import Foundation
import ModuleKit
import Testing

@testable import VigieCore

/// Duration of a PCM WAV from its header (`fmt ` byte rate, `data` size).
func wavDuration(_ url: URL) throws -> (seconds: Double, rate: Int, bits: Int, channels: Int) {
    let data = try Data(contentsOf: url)
    func u32(_ at: Int) -> Int {
        Int(data[at]) | Int(data[at + 1]) << 8 | Int(data[at + 2]) << 16 | Int(data[at + 3]) << 24
    }
    func u16(_ at: Int) -> Int { Int(data[at]) | Int(data[at + 1]) << 8 }
    #expect(String(decoding: data[0..<4], as: UTF8.self) == "RIFF")
    #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
    var offset = 12
    var format: (rate: Int, byteRate: Int, bits: Int, channels: Int)?
    while offset + 8 <= data.count {
        let id = String(decoding: data[offset..<offset + 4], as: UTF8.self)
        let size = u32(offset + 4)
        if id == "fmt " {
            format = (u32(offset + 12), u32(offset + 16), u16(offset + 22), u16(offset + 10))
        } else if id == "data", let format {
            return (Double(size) / Double(format.byteRate), format.rate, format.bits, format.channels)
        }
        offset += 8 + size + size % 2
    }
    throw CocoaError(.fileReadCorruptFile)
}

@MainActor @Suite(.serialized) struct SoundsSettingsTests {
    // MARK: Built-ins

    @Test func bundleShipsFourShortBuiltIns() throws {
        let catalog = SoundCatalog.bundled
        #expect(catalog.builtIns.map(\.name) == ["blocked", "failed", "done", "warn"])
        for sound in catalog.builtIns {
            guard case .play(let url) = catalog.resolve(.builtIn(sound.name)) else {
                Issue.record("\(sound.name) is not in the bundle")
                continue
            }
            let info = try wavDuration(url)
            #expect(info.seconds > 0.1 && info.seconds < 1, "\(sound.name): \(info.seconds) s")
            #expect(info.rate == 44100 && info.bits == 16 && info.channels == 1)
            #expect(SettingsText.string("sounds.builtin.\(sound.name)") != "sounds.builtin.\(sound.name)")
        }
    }

    @Test func schemaDefaultsResolveToBuiltIns() {
        for setting in CoreSettings.all where setting.path.segments.first == "sounds" {
            guard let raw = setting.descriptor.defaultValue as? String else { continue }
            let resolution = SoundCatalog.bundled.resolve(SoundValue(raw))
            #expect(resolution == .silent || { if case .play = resolution { true } else { false } }(), "\(raw)")
        }
    }

    // MARK: Problems

    @Test func missingFileRaisesOneSetupProblemNamingTheKey() async throws {
        let notifier = SetupRecordingNotifier()
        let reporter = SoundProblemReporter(notifier: notifier, log: testLogger)
        let h = SoundSinkHarness()
        let sink = NotifierSoundSink(
            config: { [unowned h] in h.settings }, player: h.player, catalog: fakeSoundCatalog,
            onProblem: reporter.report, onRecovered: reporter.clear(key:), log: testLogger)
        let missing = "/nonexistent/vigie/ping.aiff"
        h.settings.values["blocked"] = missing
        let alert = ActiveAlert(
            id: UUID(), module: "agents.sessions",
            event: NotifierEvent(kind: "session.blocked", severity: .critical, title: "x"), outputs: [.sound],
            postedAt: Date())
        sink.play(for: alert)
        sink.play(for: alert)
        #expect(h.player.played.isEmpty)
        #expect(notifier.events.count == 1)
        let event = try #require(notifier.events.first)
        #expect(event.kind == SetupProblemReporter.alertKind)
        #expect(event.title == "Sound file for sounds.blocked not found: \(missing)")
        #expect(event.category == "SOUND")
        #expect(event.action == .openSettings(pane: "sounds"))
        #expect(event.dedupeKey == "sound:blocked")
        #expect(reporter.openKeys == ["blocked"])

        // Fixed: the next play resolves the alert.
        h.settings.values["blocked"] = "builtin:blocked"
        sink.play(for: alert)
        await sink.pending?.value
        #expect(notifier.resolveCount == 1)
        #expect(reporter.openKeys.isEmpty)
        #expect(h.player.played.count == 1)
    }

    @Test func problemTitlesAreLocalized() {
        for reason: SoundProblem.Reason in [
            .fileNotFound("/a"), .unreadable("/a"), .unknownBuiltIn("x"), .invalidValue("y"),
        ] {
            let title = SoundProblemText.title(SoundProblem(key: "done", reason: reason))
            #expect(title.contains("sounds.done") && !title.contains("vigiecore."), "\(title)")
        }
        #expect(SoundProblemText.string("vigiecore.setup.body.sound") != "vigiecore.setup.body.sound")
    }

    // MARK: Pane model

    @Test func pickerWritesValueForms() async throws {
        let h = try await SettingsHarness()
        let model = h.controller.sounds
        #expect(model.keys == ["blocked", "failed", "done", "quota_warning", "timer_end", "break_reminder"])
        #expect(model.isEnabled)
        #expect(model.value(for: "done") == .off)
        #expect(model.displayedValue(for: "done") == .builtIn("done"))

        await model.select("blocked", .builtIn("warn"))
        #expect(h.configText().contains("blocked = \"builtin:warn\""))
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        await model.select("failed", SoundValue("\(home)/Sounds/fail.aiff"))
        #expect(h.configText().contains("failed = \"~/Sounds/fail.aiff\""))

        await model.setOn("blocked", false)
        #expect(h.configText().contains("blocked = \"off\""))
        #expect(!model.isOn("blocked"))
        await model.setOn("blocked", true)
        #expect(h.configText().contains("blocked = \"builtin:warn\""))
        await model.setOn("done", true)
        #expect(h.configText().contains("done = \"builtin:done\""))

        model.chooseFile = { "~/Music/chime.m4a" }
        await model.chooseFile(for: "quota_warning")
        #expect(h.configText().contains("quota_warning = \"~/Music/chime.m4a\""))
        model.chooseFile = { nil }
        await model.chooseFile(for: "quota_warning")
        #expect(h.configText().contains("quota_warning = \"~/Music/chime.m4a\""))

        await model.setEnabled(false)
        #expect(h.configText().contains("enabled = false"))
        #expect(!model.isEnabled)
        #expect(model.errors.isEmpty)
        await h.tearDown()
    }

    @Test func previewPlaysThroughThePlayer() async throws {
        let h = try await SettingsHarness()
        let player = FakeSoundPlayer()
        let model = h.controller.sounds
        model.player = player
        await model.preview("blocked")
        #expect(player.played.map(\.lastPathComponent) == ["blocked.wav"])
        // Off: previews what switching on would play.
        await model.preview("done")
        #expect(player.played.last?.lastPathComponent == "done.wav")

        await model.select("failed", .file(URL(fileURLWithPath: "/nonexistent/vigie/x.aiff")))
        await model.preview("failed")
        #expect(player.played.count == 2)
        #expect(model.errors["failed"] == "Sound file for sounds.failed not found: /nonexistent/vigie/x.aiff")
        await h.tearDown()
    }

    @Test func paneStringsAreInTheCatalog() {
        for key in ["sounds.chooseFile", "sounds.chooseFile.prompt", "sounds.preview", "sounds.footer"] {
            #expect(SettingsText.string(key) != key, "\(key)")
        }
    }

    /// Renders Settings › Sounds; with `VIGIE_SETTINGS_SNAPSHOT_DIR` set, writes `settings-sounds.png`.
    @Test func soundsPaneRendersOffscreen() async throws {
        let h = try await SettingsHarness()
        let custom = makeTempDirectory().appendingPathComponent("my-alert.aiff")
        try Data([0]).write(to: custom)
        await h.controller.sounds.select("failed", .file(custom))
        await h.controller.sounds.select("blocked", .file(URL(fileURLWithPath: "/nonexistent/vigie/x.aiff")))
        await h.controller.sounds.preview("blocked")
        h.controller.open(pane: "sounds")
        let window = try #require(h.controller.window)
        try await Task.sleep(for: .milliseconds(400))
        let view = try #require(window.contentView)
        view.layoutSubtreeIfNeeded()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        #expect(rep.pixelsWide > 0)
        if let dir = ProcessInfo.processInfo.environment["VIGIE_SETTINGS_SNAPSHOT_DIR"],
            let png = rep.representation(using: .png, properties: [:])
        {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("settings-sounds.png"))
        }
        await h.tearDown()
    }
}
