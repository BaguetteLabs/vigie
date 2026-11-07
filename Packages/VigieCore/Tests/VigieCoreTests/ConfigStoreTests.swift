import Foundation
import ModuleKit
import Synchronization
import Testing
import Wire

@testable import VigieCore

@Suite struct ConfigKeyPathTests {
    @Test func parsesQuotedModuleIDs() throws {
        let path = try #require(ConfigKeyPath(parsing: #"modules."agents.sessions".local.foo"#))
        #expect(path.segments == ["modules", "agents.sessions", "local", "foo"])
        #expect(path.description == #"modules."agents.sessions".local.foo"#)
    }

    @Test(arguments: [
        ("general.hover_delay", ["general", "hover_delay"], "general.hover_delay"),
        (#"modules . shelf . ttl"#, ["modules", "shelf", "ttl"], "modules.shelf.ttl"),
        (#"a.'b.c'.d"#, ["a", "b.c", "d"], #"a."b.c".d"#),
        (#""q\"x".y"#, [#"q"x"#, "y"], #""q\"x".y"#),
    ])
    func canonicalForm(input: String, segments: [String], printed: String) throws {
        let path = try #require(ConfigKeyPath(parsing: input))
        #expect(path.segments == segments)
        #expect(path.description == printed)
        #expect(ConfigKeyPath(parsing: printed) == path)
    }

    @Test(arguments: ["", "a..b", "a.", ".a", #""open"#, "a b", "a.b c"])
    func rejectsBadSyntax(input: String) {
        #expect(ConfigKeyPath(parsing: input) == nil)
    }

    @Test func modulePathsFollowScope() {
        #expect(
            ConfigKeyPath.module("agents.sessions", "terminal", scope: .local).description
                == #"modules."agents.sessions".local.terminal"#)
        #expect(ConfigKeyPath.module("time", "breaks.work").description == "modules.time.breaks.work")
        #expect(ConfigKeyPath.moduleEnabled("shelf").description == "modules.shelf.enabled")
    }
}

@Suite struct ConfigDurationTests {
    @Test(arguments: [
        ("20m", Duration.seconds(1200)),
        ("2h", .seconds(7200)),
        ("90s", .seconds(90)),
        ("1h30m", .seconds(5400)),
        ("150ms", .milliseconds(150)),
        ("7d", .seconds(7 * 86_400)),
        ("0s", .zero),
        ("1.5h", .seconds(5400)),
    ])
    func parses(text: String, expected: Duration) {
        #expect(ConfigDuration.parse(text) == expected)
    }

    @Test(arguments: ["20", "", "m", "20 m", "-5m", "5x", "1h 30m", "h1"])
    func rejects(text: String) {
        #expect(ConfigDuration.parse(text) == nil)
    }

    @Test(arguments: [
        (Duration.seconds(5400), "1h30m"), (.milliseconds(150), "150ms"), (.zero, "0s"), (.seconds(86_400 * 7), "7d"),
    ])
    func formats(duration: Duration, text: String) {
        #expect(ConfigDuration.format(duration) == text)
        #expect(ConfigDuration.parse(text) == duration)
    }
}

@Suite struct ConfigDocumentTests {
    @Test func parsesTree() throws {
        let doc = try ConfigDocument.parse(
            """
            [general]
            hover_delay = "150ms"
            [modules."agents.sessions"]
            enabled = true
            adapters = ["claude", "codex"]
            ratio = 0.5
            [modules.time]
            pomodoro = { work = "25m", long_every = 4 }
            """)
        #expect(doc.value(at: "general.hover_delay") == .string("150ms"))
        #expect(doc.value(at: #"modules."agents.sessions".enabled"#) == .bool(true))
        #expect(doc.value(at: #"modules."agents.sessions".adapters"#) == .array([.string("claude"), .string("codex")]))
        #expect(doc.value(at: #"modules."agents.sessions".ratio"#) == .double(0.5))
        #expect(doc.value(at: "modules.time.pomodoro.long_every") == .int(4))
        #expect(doc.value(at: "general.hover_delay.nope") == nil)
    }

    @Test func parseErrorReportsLine() {
        #expect(throws: ConfigParseError.self) { try ConfigDocument.parse("[general]\nhover_delay = \n") }
        do {
            _ = try ConfigDocument.parse("[general]\nok = true\nbroken = = 1\n")
            Issue.record("expected a parse error")
        } catch {
            #expect(error.line == 3)
        }
    }
}

@MainActor
@Suite struct ConfigStoreTests {
    // MARK: Fresh start and defaults

    @Test func freshStartWritesDefaultsThatResolveToDeclaredDefaults() async throws {
        let fixture = ConfigFixture()
        let (store, watcher) = try await fixture.makeStore()
        defer { store.stop() }

        let written = try String(contentsOf: fixture.configURL, encoding: .utf8)
        #expect(written == ConfigStore.defaultConfigText)
        let document = try ConfigDocument.parse(written)
        let local = try String(contentsOf: fixture.localURL, encoding: .utf8)
        #expect(try ConfigDocument.parse(local) == .empty)

        #expect(store.problems.isEmpty, "\(store.problems)")
        for setting in CoreSettings.all {
            #expect(store.resolvedValue(setting.path) == ConfigResolvedValue(defaultOf: setting.descriptor.kind))
            if setting.descriptor.scope == .synced {
                #expect(document.value(at: setting.path) != nil, "\(setting.path) missing from the default file")
            } else {
                #expect(document.value(at: setting.path) == nil, "\(setting.path) is local")
            }
        }
        // Both folders are watched.
        #expect(Set(watcher.watchedDirectories.map(\.path)) == [fixture.configFolder.path, fixture.support.path])
    }

    /// The commented local block at the end of the default file, uncommented into `local.toml`, gives every
    /// `.local` key its declared default (catches typos in the reference block).
    @Test func defaultLocalReferenceBlockResolvesToDefaults() async throws {
        let text = try #require(ConfigStore.defaultConfigText)
        let block = try #require(text.components(separatedBy: "# == local.toml ==\n").last)
        let uncommented = block.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let body = String(line.dropFirst(2))
                guard line.hasPrefix("# "), body.wholeMatch(of: /(\[.*\]|[a-z_]+ = .*)/) != nil else { return "" }
                return body
            }
            .joined(separator: "\n")
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(manifests: [testManifest], local: uncommented)
        defer { store.stop() }
        let localDoc = try ConfigDocument.parse(uncommented)
        #expect(store.problems.filter { $0.path == fixture.localURL }.isEmpty, "\(store.problems)")
        for setting in CoreSettings.all where setting.descriptor.scope == .local {
            #expect(localDoc.value(at: setting.path) != nil, "\(setting.path) missing from the local block")
            #expect(store.resolvedValue(setting.path) == ConfigResolvedValue(defaultOf: setting.descriptor.kind))
        }
        #expect(store.value(.module("agents.sessions", "terminal", scope: .local), as: String.self) == "warp")
    }

    @Test func existingFilesAreNotOverwritten() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(
            config: "[closed]\nslots = 2\n", local: "[display]\ndisplay = \"main\"\n")
        defer { store.stop() }
        #expect(try String(contentsOf: fixture.configURL, encoding: .utf8) == "[closed]\nslots = 2\n")
        #expect(store.value("closed.slots", as: Int.self) == 2)
        #expect(store.value("display.display", as: String.self) == "main")
        #expect(store.value("closed.peek", as: Bool.self) == true)
    }

    // MARK: Scope routing

    @Test func localKeyInBothFilesLocalWins() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(
            manifests: [testManifest],
            config: """
                [virtual_notch]
                width = 300
                [modules."agents.sessions".local]
                terminal = "iterm"
                """,
            local: """
                [virtual_notch]
                width = 250
                [modules."agents.sessions".local]
                terminal = "ghostty"
                """)
        defer { store.stop() }
        #expect(store.value("virtual_notch.width", as: Int.self) == 250)
        #expect(store.value(.module("agents.sessions", "terminal", scope: .local), as: String.self) == "ghostty")
        let wrong = store.problems.filter { $0.kind == .wrongFile }
        #expect(wrong.map(\.key) == [#"modules."agents.sessions".local.terminal"#, "virtual_notch.width"])
        #expect(wrong.allSatisfy { $0.path == fixture.configURL })
    }

    @Test func localKeyOnlyInConfigIsIgnored() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(
            config: "[sync]\nicloud = true\n[general]\nlaunch_at_login = true\n")
        defer { store.stop() }
        #expect(store.value("sync.icloud", as: Bool.self) == false)
        #expect(store.value("general.launch_at_login", as: Bool.self) == false)
        #expect(
            store.problems
                == [
                    ConfigProblem(
                        kind: .wrongFile, path: fixture.configURL, key: "general.launch_at_login",
                        message: "general.launch_at_login is machine-specific and is read only from local.toml"),
                    ConfigProblem(
                        kind: .wrongFile, path: fixture.configURL, key: "sync.icloud",
                        message: "sync.icloud is machine-specific and is read only from local.toml"),
                ])
    }

    @Test func syncedKeyInLocalIsIgnored() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(local: "[appearance]\nmode = \"dark\"\n")
        defer { store.stop() }
        #expect(store.value("appearance.mode", as: String.self) == "system")
        #expect(store.problems.map(\.kind) == [.wrongFile])
        #expect(store.problems.first?.path == fixture.localURL)
        #expect(store.problems.first?.key == "appearance.mode")
    }

    // MARK: Parse errors

    @Test func parseErrorKeepsLastValidConfigUntilFixed() async throws {
        let fixture = ConfigFixture()
        let (store, watcher) = try await fixture.makeStore(config: "[closed]\nslots = 2\n")
        defer { store.stop() }
        #expect(store.value("closed.slots", as: Int.self) == 2)

        try fixture.writeConfig("[closed]\nslots = 4\npeek = = false\n")
        await store.fireAndSettle(watcher)
        #expect(store.value("closed.slots", as: Int.self) == 2)
        let problem = try #require(store.problems.first)
        #expect(store.problems.count == 1)
        #expect(problem.kind == .invalidFile(line: 3))
        #expect(problem.path == fixture.configURL)
        #expect(problem.key == nil)

        try fixture.writeConfig("[closed]\nslots = 4\npeek = false\n")
        await store.fireAndSettle(watcher)
        #expect(store.problems.isEmpty)
        #expect(store.value("closed.slots", as: Int.self) == 4)
        #expect(store.value("closed.peek", as: Bool.self) == false)
    }

    @Test func parseErrorOnFirstLoadUsesDefaults() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(config: "[closed\nslots = 2\n")
        defer { store.stop() }
        #expect(store.value("closed.slots", as: Int.self) == 3)
        #expect(store.problems.map(\.kind) == [.invalidFile(line: 1)])
    }

    // MARK: Invalid values and unknown keys

    @Test func wrongTypeAndOutOfRangeFallBackPerKey() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(
            manifests: [testManifest],
            config: """
                [general]
                hide_in_fullscreen = "yes"
                open_on_hover = true
                [closed]
                slots = 9
                max_side_width = 150
                [appearance]
                mode = "neon"
                [modules."agents.sessions"]
                priority = 3
                done_to_idle = "20"
                """)
        defer { store.stop() }
        #expect(store.value("general.hide_in_fullscreen", as: Bool.self) == true)
        #expect(store.value("general.open_on_hover", as: Bool.self) == true)
        #expect(store.value("closed.slots", as: Int.self) == 3)
        #expect(store.value("closed.max_side_width", as: Int.self) == 150)
        #expect(store.value("appearance.mode", as: String.self) == "system")
        #expect(store.value(.module("agents.sessions", "priority"), as: Int.self) == 3)
        #expect(store.value(.module("agents.sessions", "done_to_idle"), as: Duration.self) == .seconds(900))
        let invalid = store.problems.filter { $0.kind == .invalidValue }
        #expect(
            invalid.map(\.key) == [
                "appearance.mode", "closed.slots", "general.hide_in_fullscreen",
                #"modules."agents.sessions".done_to_idle"#,
            ])
        #expect(invalid.allSatisfy { $0.path == fixture.configURL })
        #expect(store.problems.count == invalid.count)
    }

    @Test(arguments: [
        ("20m", Duration.seconds(1200)), ("2h", .seconds(7200)), ("90s", .seconds(90)), ("1h30m", .seconds(5400)),
    ])
    func durationValues(text: String, expected: Duration) async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(config: "[closed]\npeek_duration = \"\(text)\"\n")
        defer { store.stop() }
        #expect(store.value("closed.peek_duration", as: Duration.self) == expected)
        #expect(store.problems.isEmpty)
    }

    @Test func unknownKeysAreReportedOnceAndIgnored() async throws {
        let fixture = ConfigFixture()
        let config = """
            [general]
            hover_delay = "1s"
            no_such_key = 1
            [appearance.colors]
            blocked = "#FF0000"
            [modules."not.registered"]
            anything = true
            [modules."agents.sessions".notify]
            min_severity = "warn"
            """
        let (store, watcher) = try await fixture.makeStore(manifests: [testManifest], config: config)
        defer { store.stop() }
        #expect(store.value("general.hover_delay", as: Duration.self) == .seconds(1))
        #expect(store.problems.map(\.kind) == [.unknownKey])
        #expect(store.problems.first?.key == "general.no_such_key")

        try fixture.writeConfig(config + "\n# touched\n")
        await store.fireAndSettle(watcher)
        await store.reload()
        #expect(store.problems.map(\.kind) == [.unknownKey])
    }

    @Test func pathsReadAsStringOrURL() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(manifests: [testManifest])
        defer { store.stop() }
        let key = ConfigKeyPath.module("agents.sessions", "ask_alt_cwd")
        #expect(store.value(key, as: String.self) == "~/Code")
        let url = try #require(store.value(key, as: URL.self))
        #expect(url.path.hasSuffix("/Code"))
        #expect(!url.path.contains("~"))
    }

    // MARK: Live reload

    @Test func atomicReplaceNotifiesOnlyChangedKeys() async throws {
        let fixture = ConfigFixture()
        let (store, watcher) = try await fixture.makeStore(
            manifests: [testManifest], config: "[closed]\nslots = 2\npeek = true\n")
        defer { store.stop() }
        let changedKey = StreamCounter(store.observe("closed.slots"))
        let unchangedKey = StreamCounter(store.observe("closed.peek"))
        let unchangedDefault = StreamCounter(store.observe("general.hover_delay"))
        let changeSets = Mutex<[Set<ConfigKeyPath>]>([])
        let allChanges = StreamCounter(store.changes) { set in changeSets.withLock { $0.append(set) } }
        let enablement = ConfigModuleEnablement(store: store)
        let enabledIDs = Mutex<[ModuleID]>([])
        let enabledCounter = StreamCounter(enablement.changes) { id in enabledIDs.withLock { $0.append(id) } }

        // Same value written with a different layout: nothing changes.
        try fixture.writeConfig("# comment\n[closed]\npeek = true\nslots = 2\n")
        await store.fireAndSettle(watcher)
        try await Task.sleep(for: .milliseconds(50))
        #expect(changedKey.count == 0)
        #expect(allChanges.count == 0)

        try fixture.writeConfig("[closed]\nslots = 4\npeek = true\n")
        await store.fireAndSettle(watcher)
        #expect(await eventually { changedKey.count == 1 })
        #expect(await eventually { allChanges.count == 1 })
        try await Task.sleep(for: .milliseconds(50))
        #expect(changedKey.count == 1)
        #expect(unchangedKey.count == 0)
        #expect(unchangedDefault.count == 0)
        #expect(enabledCounter.count == 0)
        #expect(changeSets.withLock { $0 } == [["closed.slots"]])
        #expect(store.value("closed.slots", as: Int.self) == 4)

        // Flip `enabled`: the enablement stream emits the id.
        #expect(enablement.isEnabled("agents.sessions") == nil)
        try fixture.writeConfig("[closed]\nslots = 4\npeek = true\n[modules.\"agents.sessions\"]\nenabled = false\n")
        await store.fireAndSettle(watcher)
        #expect(await eventually { enabledCounter.count == 1 })
        #expect(enabledIDs.withLock { $0 } == ["agents.sessions"])
        #expect(enablement.isEnabled("agents.sessions") == false)
        #expect(store.isModuleEnabled("agents.sessions") == false)

        // Another module key changes: no enablement event.
        try fixture.writeConfig(
            "[closed]\nslots = 4\npeek = true\n[modules.\"agents.sessions\"]\nenabled = false\npriority = 7\n")
        await store.fireAndSettle(watcher)
        #expect(await eventually { allChanges.count == 3 })
        try await Task.sleep(for: .milliseconds(50))
        #expect(enabledCounter.count == 1)
        #expect(changedKey.count == 1)
    }

    @Test func localFileEditsAreReloadedToo() async throws {
        let fixture = ConfigFixture()
        let (store, watcher) = try await fixture.makeStore()
        defer { store.stop() }
        let observed = StreamCounter(store.observe("virtual_notch.idle"))
        try fixture.writeLocal("[virtual_notch]\nidle = \"hide\"\n")
        await store.fireAndSettle(watcher)
        #expect(store.value("virtual_notch.idle", as: String.self) == "hide")
        #expect(await eventually { observed.count == 1 })
    }

    @Test func enablementForUnregisteredModulesComesFromConfig() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(
            config: "[modules.shelf]\nenabled = false\n[modules.time]\nttl = 1\n")
        defer { store.stop() }
        #expect(store.isModuleEnabled("shelf") == false)
        #expect(store.isModuleEnabled("time") == nil)
        #expect(store.isModuleEnabled("calendar") == nil)
    }

    @Test func stopEndsStreams() async throws {
        let fixture = ConfigFixture()
        let (store, watcher) = try await fixture.makeStore()
        let stream = store.observe("closed.slots")
        store.stop()
        #expect(watcher.watchedDirectories.isEmpty)
        for await _ in stream { Issue.record("no element expected") }
    }

    // MARK: ModuleSettings

    @Test func moduleSettingsRouteByScope() async throws {
        let fixture = ConfigFixture()
        let (store, watcher) = try await fixture.makeStore(
            config: "[modules.\"agents.sessions\"]\npriority = 4\n",
            local: "[modules.\"agents.sessions\".local]\nterminal = \"iterm\"\n")
        defer { store.stop() }
        let tracker = RegistrationTracker()
        let factory = CoreModuleContextFactory(
            environment: fixture.environment, eventBus: InProcessEventBus(), configStore: store)
        let settings = factory.makeContext(for: testManifest, tracker: tracker).settings
        #expect(settings.value("priority", as: Int.self) == 4)
        #expect(settings.value("terminal", as: String.self) == "iterm")
        #expect(settings.value("done_to_idle", as: Duration.self) == .seconds(900))
        #expect(settings.value("enabled", as: Bool.self) == true)
        #expect(settings.value("undeclared", as: Int.self) == nil)
        #expect(settings.value("priority", as: String.self) == nil)
        try await settings.set(5, for: "priority")
        #expect(settings.value("priority", as: Int.self) == 5)
        await #expect(throws: ConfigError.unknownSetting("nope")) { try await settings.set(5, for: "nope") }

        let observed = StreamCounter(settings.observe("terminal"))
        try fixture.writeLocal("[modules.\"agents.sessions\".local]\nterminal = \"warp\"\n")
        await store.fireAndSettle(watcher)
        #expect(await eventually { observed.count == 1 })
        #expect(settings.value("terminal", as: String.self) == "warp")

        #expect(store.shared.keyObserverCount == 1)
        tracker.cancelAll()
        #expect(await eventually { observed.task.isCancelled || store.shared.keyObserverCount == 0 })
    }

    @Test func registeringLaterResolvesWithoutChangeEvents() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(config: "[modules.\"agents.sessions\"]\npriority = 11\n")
        defer { store.stop() }
        #expect(store.problems.isEmpty)
        let all = StreamCounter(store.changes)
        store.register(manifest: testManifest)
        #expect(store.value(.module("agents.sessions", "priority"), as: Int.self) == 1)
        #expect(store.problems.map(\.kind) == [.invalidValue])
        try await Task.sleep(for: .milliseconds(50))
        #expect(all.count == 0)
    }

    @Test func coreLabelsAreLocalized() {
        let setting = CoreSettings.all.first { $0.path == "closed.slots" }
        let label = setting.map { String(localized: $0.descriptor.label) }
        #expect(label == "Items per side")
    }
}

@MainActor
@Suite struct DispatchDirectoryWatcherTests {
    @Test func touchingAFileFiresWithinTwoSeconds() async throws {
        let directory = makeTempDirectory()
        let watcher = DispatchDirectoryWatcher()
        defer { watcher.stopAll() }
        let fired = Counter()
        watcher.watch(directory, files: ["config.toml"]) { fired.increment() }
        try Data("a = 1\n".utf8).write(to: directory.appendingPathComponent("config.toml"))
        #expect(await eventually(timeout: .seconds(2)) { fired.count > 0 })

        // An in-place append to the (now watched) file also fires.
        let before = fired.count
        let handle = try FileHandle(forWritingTo: directory.appendingPathComponent("config.toml"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("b = 2\n".utf8))
        try handle.close()
        #expect(await eventually(timeout: .seconds(2)) { fired.count > before })
    }

    @Test func storeReloadsThroughRealWatcher() async throws {
        let fixture = ConfigFixture()
        try fixture.writeConfig("[closed]\nslots = 2\n")
        let store = ConfigStore(environment: fixture.environment)
        await store.start()
        defer { store.stop() }
        #expect(store.value("closed.slots", as: Int.self) == 2)
        try fixture.writeConfig("[closed]\nslots = 1\n")
        #expect(await eventually(timeout: .seconds(3)) { store.value("closed.slots", as: Int.self) == 1 })
    }
}
