import Foundation
import ModuleKit
import Testing
import Wire

@testable import VigieCore

@MainActor
@Suite struct ConfigStoreWriteTests {
    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// Lines of `after` that are not at the same place in `before` (a minimal line diff for single edits).
    private func changedLines(_ before: String, _ after: String) -> (removed: [String], added: [String]) {
        let old = before.components(separatedBy: "\n")
        let new = after.components(separatedBy: "\n")
        let diff = new.difference(from: old)
        var removed: [String] = []
        var added: [String] = []
        for change in diff {
            switch change {
            case .remove(_, let line, _): removed.append(line)
            case .insert(_, let line, _): added.append(line)
            }
        }
        return (removed, added)
    }

    @Test func setSyncedKeyChangesOnlyThatLineOfConfig() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore()
        defer { store.stop() }
        let configBefore = try read(fixture.configURL)
        let localBefore = try Data(contentsOf: fixture.localURL)

        try await store.set("closed.slots", to: .int(4))
        let configAfter = try read(fixture.configURL)
        let diff = changedLines(configBefore, configAfter)
        #expect(diff.removed == ["slots = 3                     # items per side, max 4; the rest collapse into +X"])
        #expect(diff.added == ["slots = 4                     # items per side, max 4; the rest collapse into +X"])
        #expect(try Data(contentsOf: fixture.localURL) == localBefore)
        #expect(store.value("closed.slots", as: Int.self) == 4)

        try await store.set("closed.peek_duration", to: .duration(.seconds(90)))
        #expect(
            changedLines(configAfter, try read(fixture.configURL)).added == [
                #"peek_duration = "1m30s"          # dwell, paused on hover"#
            ])
        #expect(store.value("closed.peek_duration", as: Duration.self) == .seconds(90))
    }

    @Test func insertedKeyAddsExactlyOneLine() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(
            config: "# mine\n[general]\nhide_in_fullscreen = false\n\n[closed]\n")
        defer { store.stop() }
        try await store.set("general.hover_delay", to: .duration(.milliseconds(300)))
        #expect(
            try read(fixture.configURL)
                == "# mine\n[general]\nhide_in_fullscreen = false\nhover_delay = \"300ms\"\n\n[closed]\n")
    }

    @Test func setLocalKeyWritesLocalTomlOnly() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(manifests: [testManifest])
        defer { store.stop() }
        let configBefore = try Data(contentsOf: fixture.configURL)

        try await store.set("general.launch_at_login", to: .bool(true))
        try await store.set(.module("agents.sessions", "terminal", scope: .local), to: .string("warp"))

        #expect(try Data(contentsOf: fixture.configURL) == configBefore)
        #expect(
            try read(fixture.localURL)
                == ConfigStore.localHeader
                + "\n[general]\nlaunch_at_login = true\n\n[modules.\"agents.sessions\".local]\nterminal = \"warp\"\n")
        #expect(store.value("general.launch_at_login", as: Bool.self) == true)
        #expect(!store.problems.contains { $0.kind != .unknownKey })
    }

    @Test func ownWriteDoesNotTriggerAReload() async throws {
        let fixture = ConfigFixture()
        let (store, watcher) = try await fixture.makeStore(manifests: [testManifest])
        defer { store.stop() }
        let observed = StreamCounter(store.observe("closed.slots"))
        let other = StreamCounter(store.observe("closed.peek"))
        let changes = StreamCounter(store.changes)
        let revision = store.revision

        try await store.set("closed.slots", to: .int(2))
        #expect(store.revision == revision + 1)
        #expect(await eventually { observed.count == 1 && changes.count == 1 })

        await store.fireAndSettle(watcher)
        await store.fireAndSettle(watcher)
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.revision == revision + 1)
        #expect(observed.count == 1)
        #expect(changes.count == 1)
        #expect(other.count == 0)

        // Setting the same value again changes nothing.
        try await store.set("closed.slots", to: .int(2))
        #expect(store.revision == revision + 1)
    }

    @Test func invalidValuesThrowAndLeaveTheFileUntouched() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(manifests: [testManifest])
        defer { store.stop() }
        let before = try Data(contentsOf: fixture.configURL)

        await #expect(throws: ConfigError.invalidValue(key: "closed.slots", reason: "9 is above 4")) {
            try await store.set("closed.slots", to: .int(9))
        }
        await #expect(throws: ConfigError.self) { try await store.set("closed.slots", to: .string("4")) }
        await #expect(throws: ConfigError.self) { try await store.set("appearance.mode", to: .string("neon")) }
        await #expect(throws: ConfigError.self) { try await store.set("closed.peek", to: .none) }
        await #expect(throws: ConfigError.self) { try await store.set("closed.peek", to: .duration(.seconds(1))) }
        await #expect(throws: ConfigError.unknownSetting("closed.nope")) {
            try await store.set("closed.nope", to: .int(1))
        }
        await #expect(throws: ConfigError.unknownSetting("closed.nope")) { try await store.remove("closed.nope") }
        #expect(try Data(contentsOf: fixture.configURL) == before)
        #expect(store.value("closed.slots", as: Int.self) == 3)
    }

    @Test func externalEditBeforeWriteIsKept() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(config: "[closed]\nslots = 3\npeek = true\n")
        defer { store.stop() }
        // Edited on disk; the watcher has not delivered it yet.
        try fixture.writeConfig("[closed]\nslots = 3\npeek = false   # edited elsewhere\n")

        try await store.set("closed.slots", to: .int(1))
        #expect(try read(fixture.configURL) == "[closed]\nslots = 1\npeek = false   # edited elsewhere\n")
        #expect(store.value("closed.peek", as: Bool.self) == false)
        #expect(store.value("closed.slots", as: Int.self) == 1)
    }

    @Test func verificationFailureLeavesTheFileUntouched() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(config: "[closed]\nslots = 3\n")
        defer { store.stop() }
        let before = try Data(contentsOf: fixture.configURL)

        // A patch that writes the wrong value.
        store.patchHook = { $0.replacingOccurrences(of: "slots = 2", with: "slots = 4") }
        await #expect(throws: ConfigError.verificationFailed(key: "closed.slots")) {
            try await store.set("closed.slots", to: .int(2))
        }
        // A patch that breaks the file.
        store.patchHook = { $0 + "[closed\n" }
        await #expect(throws: ConfigError.verificationFailed(key: "closed.slots")) {
            try await store.set("closed.slots", to: .int(2))
        }
        // A patch that also changes another key.
        store.patchHook = { $0 + "peek = false\n" }
        await #expect(throws: ConfigError.verificationFailed(key: "closed.slots")) {
            try await store.set("closed.slots", to: .int(2))
        }
        #expect(try Data(contentsOf: fixture.configURL) == before)
        #expect(store.value("closed.slots", as: Int.self) == 3)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: fixture.configFolder.path)
        #expect(leftovers == ["config.toml"])
    }

    @Test func keysInInlineTablesOrArraysOfTablesAreNotWritten() async throws {
        let fixture = ConfigFixture()
        let manifest = ModuleManifest(
            id: "time", name: "Time", icon: "timer",
            settings: [SettingDescriptor(key: "pomodoro.work", label: "Work", kind: .duration(default: .seconds(1500)))]
        )
        let text = "[modules.time]\npomodoro = { work = \"25m\" }\n"
        let (store, _) = try await fixture.makeStore(manifests: [manifest], config: text)
        defer { store.stop() }
        await #expect(throws: ConfigError.unsupportedLocation(key: "modules.time.pomodoro.work")) {
            try await store.set(.module("time", "pomodoro.work"), to: .duration(.seconds(60)))
        }
        #expect(try read(fixture.configURL) == text)
    }

    @Test func fileWithTOMLErrorIsNotWritten() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(config: "[closed\nslots = 3\n")
        defer { store.stop() }
        await #expect(throws: ConfigError.fileHasErrors(file: "config.toml")) {
            try await store.set("closed.slots", to: .int(2))
        }
        #expect(try read(fixture.configURL) == "[closed\nslots = 3\n")
    }

    @Test func symlinkedConfigRewritesTheTarget() async throws {
        let fixture = ConfigFixture()
        let dotfiles = makeTempDirectory()
        let target = dotfiles.appendingPathComponent("vigie.toml")
        try "[closed]\nslots = 3\n".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: fixture.configFolder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fixture.configURL, withDestinationURL: target)
        let (store, _) = try await fixture.makeStore()
        defer { store.stop() }

        try await store.set("closed.slots", to: .int(2))
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: fixture.configURL.path)
        #expect(destination == target.path)
        #expect(try read(target) == "[closed]\nslots = 2\n")
        #expect(try FileManager.default.contentsOfDirectory(atPath: dotfiles.path) == ["vigie.toml"])
    }

    @Test func posixModeIsPreserved() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(config: "[closed]\nslots = 3\n")
        defer { store.stop() }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fixture.configURL.path)

        try await store.set("closed.slots", to: .int(2))
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.configURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(try read(fixture.configURL) == "[closed]\nslots = 2\n")
    }

    @Test func removeResetsToDefault() async throws {
        let fixture = ConfigFixture()
        let (store, watcher) = try await fixture.makeStore(config: "[closed]\nslots = 2   # mine\npeek = false\n")
        defer { store.stop() }
        let observed = StreamCounter(store.observe("closed.slots"))
        try await store.remove("closed.slots")
        #expect(try read(fixture.configURL) == "[closed]\npeek = false\n")
        #expect(store.value("closed.slots", as: Int.self) == 3)
        #expect(await eventually { observed.count == 1 })
        let revision = store.revision
        await store.fireAndSettle(watcher)
        #expect(store.revision == revision)

        try await store.remove("closed.slots")
        #expect(try read(fixture.configURL) == "[closed]\npeek = false\n")
    }

    @Test func concurrentWritesAreSerialized() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(config: "[closed]\n")
        defer { store.stop() }
        async let a: Void = store.set("closed.slots", to: .int(2))
        async let b: Void = store.set("closed.peek", to: .bool(false))
        async let c: Void = store.set("closed.max_side_width", to: .int(200))
        _ = try await (a, b, c)
        let document = try ConfigDocument.parse(try read(fixture.configURL))
        #expect(document.value(at: "closed.slots") == .int(2))
        #expect(document.value(at: "closed.peek") == .bool(false))
        #expect(document.value(at: "closed.max_side_width") == .int(200))
    }

    @Test func moduleSettingsWriteThroughTheStore() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(manifests: [testManifest])
        defer { store.stop() }
        let settings = ConfigModuleSettings(store: store, moduleID: "agents.sessions")
        let configBefore = try read(fixture.configURL)

        try await settings.set("iterm", for: "terminal")
        try await settings.set(Duration.seconds(1800), for: "done_to_idle")
        try await settings.set(URL(fileURLWithPath: NSHomeDirectory() + "/Projects"), for: "ask_alt_cwd")
        #expect(settings.value("terminal", as: String.self) == "iterm")
        #expect(settings.value("done_to_idle", as: Duration.self) == .seconds(1800))
        #expect(settings.value("ask_alt_cwd", as: String.self) == "~/Projects")
        #expect(try read(fixture.localURL).hasSuffix("[modules.\"agents.sessions\".local]\nterminal = \"iterm\"\n"))
        let diff = changedLines(configBefore, try read(fixture.configURL))
        #expect(
            diff.added == [
                #"done_to_idle = "30m""#, #"ask_alt_cwd = "~/Projects"        # used when ⌥ is held on drop"#,
            ])

        try await settings.set(String?.none, for: "terminal")
        #expect(settings.value("terminal", as: String.self) == "terminal")
        await #expect(throws: ConfigError.unknownSetting("undeclared")) { try await settings.set(1, for: "undeclared") }
        await #expect(throws: ConfigError.self) { try await settings.set(99, for: "priority") }
    }
}
