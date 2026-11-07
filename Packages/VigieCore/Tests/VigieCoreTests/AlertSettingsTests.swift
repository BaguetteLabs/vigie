import AppKit
import ModuleKit
import SwiftUI
import Testing
import VigieUI

@testable import VigieCore

/// `agents.sessions` as Story 4.11 will declare it: the three session kinds.
let alertSessionsManifest = ModuleManifest(
    id: "agents.sessions",
    name: "Sessions",
    icon: "terminal",
    settings: testManifest.settings,
    alertKinds: ["session.blocked", "session.done", "session.failed"])

@MainActor @Suite(.serialized) struct AlertSettingsTests {
    func harness(config: String? = nil) async throws -> SettingsHarness {
        try await SettingsHarness(config: config, sessions: alertSessionsManifest)
    }

    func kind(_ h: SettingsHarness, _ kind: String) throws -> AlertKindSetting {
        try #require(h.controller.alertSettings(for: alertSessionsManifest).first { $0.kind == kind })
    }

    @Test func rowsAreGeneratedPerDeclaredKindWithDefaults() async throws {
        let h = try await harness()
        let settings = h.controller.alertSettings(for: alertSessionsManifest)
        #expect(settings.map(\.kind) == ["session.blocked", "session.done", "session.failed"])
        #expect(settings.map(\.label) == ["Blocked", "Finished", "Failed"])
        for setting in settings {
            #expect(h.store.isAlertEnabled(setting))
            #expect(h.store.alertOutputs(setting) == [.peek, .sound])
            #expect(h.store.alertReminder(setting) == nil)
            #expect(h.store.alertBinding(setting, .mute).get() == .bool(true))
            #expect(h.store.alertBinding(setting, .outputs).get() == .strings(["peek", "sound"]))
            #expect(h.store.alertBinding(setting, .reminder).get() == SettingControlValue.none)
            #expect(String(localized: h.controller.alertEnabledRow(setting).label) == "Enabled")
        }
        #expect(
            settings[1].path(.reminder).description == #"modules."agents.sessions".notify."session.done".reminder"#)
        // An undeclared catalog label falls back to the kind id.
        #expect(AlertKindSetting(module: "dev.sample", kind: "sample.ping").label == "sample.ping")
        await h.tearDown()
    }

    @Test func moduleWithoutKindsHasNoSection() async throws {
        let h = try await harness()
        #expect(h.controller.alertSettings(for: customManifest).isEmpty)
        #expect(
            !h.store.schema.entries.keys.contains { $0.hasPrefix(ConfigKeyPath(["modules", "custom.test", "notify"])) })
        await h.tearDown()
    }

    @Test func writesTheSpecTableShape() async throws {
        let h = try await harness()
        let done = try kind(h, "session.done")
        try await h.store.setAlertEnabled(done, false)
        try await h.store.setAlertOutputs(done, [.peek])
        try await h.store.setAlertReminder(done, .seconds(120))
        let text = h.configText()
        let expected = """
            [modules."agents.sessions".notify."session.done"]
            mute = true
            outputs = ["peek"]
            reminder = "2m"

            """
        #expect(text.hasSuffix(expected), "\(text)")
        if let dir = ProcessInfo.processInfo.environment["VIGIE_SETTINGS_SNAPSHOT_DIR"] {
            try text.write(
                to: URL(fileURLWithPath: dir).appendingPathComponent("alert-settings-config.toml"), atomically: true,
                encoding: .utf8)
        }
        #expect(!h.store.isAlertEnabled(done))
        #expect(h.store.alertOutputs(done) == [.peek])
        #expect(h.store.alertReminder(done) == .seconds(120))
        #expect(h.store.isAlertEnabled(try kind(h, "session.blocked")))
        // The keys are known: no problem about them after the write, also after a reload (the default file's
        // other `agents.sessions` keys are unknown to this test manifest and reported as such).
        let notifyProblems = { h.store.problems.filter { $0.key?.contains(".notify.") ?? true } }
        #expect(notifyProblems().isEmpty, "\(notifyProblems())")
        await h.store.reload()
        #expect(notifyProblems().isEmpty)

        // A fresh store reads the same file back.
        let (other, _) = try await h.fixture.makeStore(manifests: [alertSessionsManifest])
        let reread = AlertKindSetting(module: "agents.sessions", kind: "session.done")
        #expect(!other.isAlertEnabled(reread))
        #expect(other.alertOutputs(reread) == [.peek])
        #expect(other.alertReminder(reread) == .seconds(120))
        other.stop()
        await h.tearDown()
    }

    @Test func enabledToggleWritesMuteAndRemovesItWhenBackOn() async throws {
        let h = try await harness()
        let blocked = try kind(h, "session.blocked")
        let row = h.controller.alertEnabledRow(blocked)
        let state = SettingFieldState()
        #expect(row.currentValue == .bool(true))
        #expect(await state.apply(.bool(false), to: row.binding, services: h.controller.services))
        #expect(h.configText().contains("[modules.\"agents.sessions\".notify.\"session.blocked\"]\nmute = true\n"))
        #expect(row.currentValue == .bool(false))
        #expect(await state.apply(.bool(true), to: row.binding, services: h.controller.services))
        #expect(!h.configText().contains("\nmute ="))
        #expect(row.currentValue == .bool(true))
        await h.tearDown()
    }

    @Test func outputsAreWrittenInPeekSystemSoundOrder() async throws {
        let h = try await harness()
        let failed = try kind(h, "session.failed")
        let binding = h.store.alertBinding(failed, .outputs)
        let state = SettingFieldState()
        #expect(
            await state.apply(.strings(["sound", "system", "peek"]), to: binding, services: h.controller.services))
        #expect(h.configText().contains(#"outputs = ["peek", "system", "sound"]"#))
        #expect(h.store.alertOutputs(failed) == [.peek, .system, .sound])
        #expect(await state.apply(.strings([]), to: binding, services: h.controller.services))
        #expect(h.configText().contains("outputs = []"))
        #expect(h.store.alertOutputs(failed).isEmpty)
        #expect(await state.apply(nil, to: binding, services: h.controller.services))
        #expect(!h.configText().contains("\noutputs ="))
        #expect(h.store.alertOutputs(failed) == [.peek, .sound])
        #expect(AlertOutputsRow.label(.system) == SettingsText.resource("settings.alerts.output.system"))
        await h.tearDown()
    }

    @Test func reminderParseErrorShowsLocalizedMessageAndWritesNothing() async throws {
        let h = try await harness()
        let blocked = try kind(h, "session.blocked")
        let binding = h.store.alertBinding(blocked, .reminder)
        let state = SettingFieldState()
        let before = h.configText()
        #expect(
            !(await AlertReminderRow.commit("2 minutes", to: binding, state: state, services: h.controller.services)))
        #expect(state.error == "Enter a duration such as 90s, 15m or 1h30m.")
        #expect(h.configText() == before)
        #expect(await AlertReminderRow.commit("10m", to: binding, state: state, services: h.controller.services))
        #expect(state.error == nil)
        #expect(h.configText().contains("reminder = \"10m\""))
        #expect(AlertReminderRow.text(binding.get(), services: h.controller.services) == "10m")
        // Empty text means no reminder: the key is removed.
        #expect(await AlertReminderRow.commit("  ", to: binding, state: state, services: h.controller.services))
        #expect(!h.configText().contains("\nreminder ="))
        #expect(h.store.alertReminder(blocked) == nil)
        #expect(AlertReminderRow.text(binding.get(), services: h.controller.services) == "")
        await h.tearDown()
    }

    @Test func resetRemovesEveryKey() async throws {
        let h = try await harness()
        let done = try kind(h, "session.done")
        try await h.store.setAlertEnabled(done, false)
        try await h.store.setAlertOutputs(done, [.system])
        try await h.store.setAlertReminder(done, .seconds(60))
        try await h.store.resetAlert(done)
        let text = h.configText()
        for key in ["\nmute =", "\noutputs =", "\nreminder ="] { #expect(!text.contains(key), "\(key)") }
        #expect(h.store.isAlertEnabled(done))
        #expect(h.store.alertOutputs(done) == [.peek, .sound])
        // Row-level reset (context menu) removes one key.
        try await h.store.setAlertReminder(done, .seconds(60))
        try await h.store.alertBinding(done, .reminder).set(nil)
        #expect(!h.configText().contains("\nreminder ="))
        await h.tearDown()
    }

    @Test func schemaValidatesTheKindKeys() async throws {
        let h = try await harness(
            config: """
                [modules."agents.sessions".notify."session.blocked"]
                mute = "yes"
                min_working_time = "30s"

                [modules."agents.sessions".notify."session.done"]
                reminder = "2m"
                """)
        for setting in h.controller.alertSettings(for: alertSessionsManifest) {
            for key in AlertSettingKey.allCases {
                #expect(h.store.schema.entries[setting.path(key)]?.moduleID == "agents.sessions")
            }
        }
        // A wrong type is reported; other rule keys (min_working_time) stay silent, never `unknownKey`.
        #expect(h.store.problems.map(\.kind) == [.invalidValue], "\(h.store.problems)")
        #expect(h.store.problems.first?.key == #"modules."agents.sessions".notify."session.blocked".mute"#)
        #expect(h.store.alertReminder(try kind(h, "session.done")) == .seconds(120))
        // A module cannot read Notifier's keys through its own settings (AD-13).
        let settings = ConfigModuleSettings(store: h.store, moduleID: "agents.sessions")
        #expect(settings.value("notify.session.done.reminder", as: Duration.self) == nil)
        await h.tearDown()
    }

    @Test func specInlineFormIsReadButNotRewritten() async throws {
        let h = try await harness(
            config: """
                [modules."agents.sessions".notify]
                "session.blocked" = { outputs = ["peek", "sound"], reminder = "10m" }
                """)
        let blocked = try kind(h, "session.blocked")
        #expect(h.store.alertReminder(blocked) == .seconds(600))
        #expect(!h.store.problems.contains { $0.key?.contains(".notify.") ?? true })
        let before = h.configText()
        let state = SettingFieldState()
        let ok = await state.apply(
            .bool(false), to: h.controller.alertEnabledRow(blocked).binding,
            services: h.controller.services)
        #expect(!ok)
        #expect(state.error == SettingsText.string("settings.error.unsupportedLocation"))
        #expect(h.configText() == before)
        await h.tearDown()
    }

    @Test func catalogKeysResolve() {
        let keys = [
            "settings.alerts.section", "settings.alerts.enabled", "settings.alerts.mute", "settings.alerts.outputs",
            "settings.alerts.output.peek", "settings.alerts.output.system", "settings.alerts.output.sound",
            "settings.alerts.reminder", "settings.alerts.reminder.none", "settings.alerts.reminder.help",
            "settings.alerts.reset",
        ]
        for key in keys { #expect(SettingsText.string(key) != key, "\(key)") }
        for kind in [
            "session.blocked", "session.done", "session.failed", "usage.quota_warning", "shelf.expiring",
            "time.timer_end", "time.break_reminder", "calendar.reminder", "setup.problem",
        ] {
            #expect(AlertKindSetting(module: "x", kind: kind).label != kind, "\(kind)")
        }
    }

    /// Renders the sessions pane with its Alerts section; with `VIGIE_SETTINGS_SNAPSHOT_DIR` set, writes a PNG.
    @Test func paneWithAlertSectionRendersOffscreen() async throws {
        let h = try await harness()
        try await h.store.setAlertEnabled(try kind(h, "session.failed"), false)
        try await h.store.setAlertReminder(try kind(h, "session.blocked"), .seconds(120))
        h.controller.open(pane: "agents.sessions")
        let window = try #require(h.controller.window)
        window.setContentSize(NSSize(width: 760, height: 1100))
        try await Task.sleep(for: .milliseconds(400))
        let view = try #require(window.contentView)
        view.layoutSubtreeIfNeeded()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        #expect(rep.pixelsWide > 0)
        if let dir = ProcessInfo.processInfo.environment["VIGIE_SETTINGS_SNAPSHOT_DIR"],
            let png = rep.representation(using: .png, properties: [:])
        {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("settings-alerts.png"))
        }
        await h.tearDown()
    }
}
