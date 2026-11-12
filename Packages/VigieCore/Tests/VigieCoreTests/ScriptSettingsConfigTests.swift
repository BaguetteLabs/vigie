import Foundation
import ModuleKit
import Testing
import Wire

@testable import VigieCore

/// Story 12.6: `context.scriptFolder.settings`, the per-Mac enabled flags of script files in `local.toml` (AD-8)
/// and the scripts' configured values under `[modules."<script id>"]` in the synced `config.toml`, both through
/// ConfigStore. Secrets never reach a config file.
@MainActor @Suite struct ScriptSettingsConfigTests {
    let path = "modules/github.md"
    let id: ModuleID = "github.prs"

    var descriptors: [SettingDescriptor] {
        [
            SettingDescriptor(key: "repo", label: "Repository", kind: .string(default: "")),
            SettingDescriptor(key: "warn_at", label: "Warn at", kind: .int(default: 5, min: 1, max: 99)),
            SettingDescriptor(key: "every", label: "Every", kind: .duration(default: .seconds(300))),
            SettingDescriptor(key: "folder", label: "Folder", kind: .path(default: nil)),
            SettingDescriptor(key: "token", label: "Token", kind: .secret),
        ]
    }

    @Test func enabledDefaultsToTrueAndRoundTripsInLocalTomlOnly() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(config: "[general]\nopen_on_hover = false\n")
        let syncedBefore = try Data(contentsOf: fixture.configURL)
        let settings = ConfigScriptSettings(store: store, tracker: RegistrationTracker())
        #expect(settings.isEnabled(path))

        try await settings.setEnabled(false, for: path)
        #expect(!settings.isEnabled(path))
        var local = try String(contentsOf: fixture.localURL, encoding: .utf8)
        #expect(local.contains("[scripts.enabled]"))
        #expect(local.contains(#""modules/github.md" = false"#))
        #expect(try Data(contentsOf: fixture.configURL) == syncedBefore)
        #expect(store.problems.isEmpty)

        // The next launch reads the same flag.
        let (reloaded, _) = try await fixture.makeStore()
        #expect(!ConfigScriptSettings(store: reloaded, tracker: RegistrationTracker()).isEnabled(path))
        #expect(reloaded.problems.isEmpty)
        reloaded.stop()

        // Enabling removes the key: the default applies again.
        try await settings.setEnabled(true, for: path)
        #expect(settings.isEnabled(path))
        local = try String(contentsOf: fixture.localURL, encoding: .utf8)
        #expect(!local.contains("modules/github.md"))
        #expect(try Data(contentsOf: fixture.configURL) == syncedBefore)
        store.stop()
    }

    /// Another Mac's `config.toml` (sync, git) can never disable a script here, nor can the 12.2 synced key.
    @Test func syncedFlagsAreIgnored() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(
            config: "[scripts.enabled]\n\"modules/github.md\" = false\n[modules.\"github.prs\"]\nenabled = false\n")
        let settings = ConfigScriptSettings(store: store, tracker: RegistrationTracker())
        #expect(settings.isEnabled(path))
        store.stop()
    }

    @Test func registeredValuesRoundTripInConfigTomlAndSecretsAreNeverKeys() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(local: "")
        let localBefore = try Data(contentsOf: fixture.localURL)
        let settings = ConfigScriptSettings(store: store, tracker: RegistrationTracker())
        // Not registered yet: no value, writes refused.
        await #expect(throws: ConfigError.self) { try await settings.setValue("me/project", id: id, key: "repo") }

        settings.register(id, settings: descriptors)
        #expect(store.schema.entries[.module(id, "repo")] != nil)
        #expect(store.schema.entries[.module(id, "token")] == nil)
        #expect(settings.value(id, key: "repo") == nil)  // the default applies: the runner uses the front matter

        try await settings.setValue("me/project", id: id, key: "repo")
        try await settings.setValue(12, id: id, key: "warn_at")
        try await settings.setValue(Duration.seconds(90), id: id, key: "every")
        try await settings.setValue("~/Reports", id: id, key: "folder")
        #expect(settings.value(id, key: "repo") as? String == "me/project")
        #expect(settings.value(id, key: "warn_at") as? Int == 12)
        #expect(settings.value(id, key: "every") as? Duration == .seconds(90))
        let folder = try #require(settings.value(id, key: "folder") as? URL)
        #expect(folder.path == (("~/Reports" as NSString).expandingTildeInPath))

        let config = try String(contentsOf: fixture.configURL, encoding: .utf8)
        #expect(config.contains(#"[modules."github.prs"]"#))
        #expect(config.contains(#"repo = "me/project""#))
        #expect(config.contains("warn_at = 12"))
        #expect(!config.contains("\ntoken"))
        #expect(try Data(contentsOf: fixture.localURL) == localBefore)
        #expect(store.problems.isEmpty)

        // Out of range is refused (nothing written); a secret can never be written to config.
        await #expect(throws: ConfigError.self) { try await settings.setValue(500, id: id, key: "warn_at") }
        await #expect(throws: ConfigError.self) { try await settings.setValue("x", id: id, key: "token") }
        #expect(settings.value(id, key: "warn_at") as? Int == 12)

        // nil resets to the default.
        try await settings.setValue(nil, id: id, key: "repo")
        #expect(settings.value(id, key: "repo") == nil)
        store.stop()
    }

    @Test func reRegisteringReplacesAndUnregisteringForgets() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(config: "[modules.\"github.prs\"]\nrepo = \"a/b\"\nlevel = 3\n")
        let settings = ConfigScriptSettings(store: store, tracker: RegistrationTracker())
        settings.register(id, settings: descriptors)
        #expect(settings.value(id, key: "repo") as? String == "a/b")
        // `level` is not declared: an unknown key of a registered script table is ignored without a problem
        // (the module may register more keys later, Story 12.5).
        #expect(store.problems.isEmpty)

        // The file changed `repo` into an int: the new type wins, the old entry is gone.
        settings.register(id, settings: [SettingDescriptor(key: "level", label: "Level", kind: .int(default: 1))])
        #expect(store.schema.entries[.module(id, "repo")] == nil)
        #expect(settings.value(id, key: "level") as? Int == 3)
        #expect(settings.value(id, key: "repo") == nil)

        settings.unregister(id)
        #expect(store.schema.entries[.module(id, "level")] == nil)
        #expect(store.schema.scriptSettingPaths[id] == nil)
        #expect(settings.value(id, key: "level") == nil)
        // The value stays in the file.
        #expect(try String(contentsOf: fixture.configURL, encoding: .utf8).contains("level = 3"))
        store.stop()
    }

    @Test func aManifestOwnedKeyIsNotTakenOver() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore()
        store.register(
            manifest: ModuleManifest(
                id: id, name: "PRs", icon: "star",
                settings: [SettingDescriptor(key: "repo", label: "Repo", kind: .string(default: "x/y"))]))
        let settings = ConfigScriptSettings(store: store, tracker: RegistrationTracker())
        settings.register(id, settings: descriptors)
        settings.unregister(id)
        #expect(store.schema.entries[.module(id, "repo")] != nil)
        store.stop()
    }

    @Test func changesFollowFlagsAndRegisteredScriptsAndEndOnStop() async throws {
        let fixture = ConfigFixture()
        let (store, watcher) = try await fixture.makeStore(config: "", local: "")
        let tracker = RegistrationTracker()
        let settings = ConfigScriptSettings(store: store, tracker: tracker)
        settings.register(id, settings: descriptors)
        let counter = StreamCounter(settings.changes())

        try await settings.setEnabled(false, for: path)
        #expect(await eventually { counter.count >= 1 })

        var seen = counter.count
        try fixture.writeConfig("[modules.\"github.prs\"]\nrepo = \"c/d\"\n")
        await store.fireAndSettle(watcher)
        #expect(await eventually { counter.count > seen })
        #expect(settings.value(id, key: "repo") as? String == "c/d")

        // A change elsewhere does not wake integrations.
        seen = counter.count
        try fixture.writeConfig("[modules.\"github.prs\"]\nrepo = \"c/d\"\n[general]\nopen_on_hover = true\n")
        await store.fireAndSettle(watcher)
        try await Task.sleep(for: .milliseconds(50))
        #expect(counter.count == seen)

        tracker.cancelAll()
        await counter.task.value
        store.stop()
    }

    @Test func factoryGivesIntegrationsTheConfigBackedSettings() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore()
        let factory = CoreModuleContextFactory(
            environment: fixture.environment, eventBus: InProcessEventBus(), configStore: store)
        let manifest = ModuleManifest(id: "integrations", name: "Integrations", icon: "puzzlepiece.extension")
        let context = factory.makeContext(for: manifest, tracker: RegistrationTracker())
        try await context.scriptFolder.settings.setEnabled(false, for: path)
        #expect(!context.scriptFolder.isEnabled(path))
        #expect(try String(contentsOf: fixture.localURL, encoding: .utf8).contains("modules/github.md"))
        store.stop()
    }

    @Test func withoutAConfigStoreEverythingIsEnabledAndWritesAreRefused() async throws {
        let settings = NoScriptSettings()
        #expect(settings.isEnabled(path))
        #expect(settings.value(id, key: "repo") == nil)
        await #expect(throws: ModuleServiceError.notAvailable) { try await settings.setEnabled(false, for: path) }
        await #expect(throws: ModuleServiceError.notAvailable) { try await settings.setValue(1, id: id, key: "n") }
    }
}
