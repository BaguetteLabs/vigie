import Foundation
import ModuleKit
import Testing

@testable import Integrations

/// Story 12.2: discovery of `<config folder>/modules/*.md`, the id rules and the setup problems.
@MainActor @Suite struct ScriptDiscoveryTests {
    /// A temp `modules` folder (never the real config folder), removed by `cleanUp()`.
    struct Folder {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "integrations-discovery-\(UUID().uuidString)", isDirectory: true)
        var url: URL { root.appendingPathComponent("modules", isDirectory: true) }

        init(create: Bool = true) throws {
            if create { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        }

        func write(_ name: String, _ text: String) throws {
            try Data(text.utf8).write(to: url.appendingPathComponent(name))
        }

        func remove(_ name: String) throws {
            try FileManager.default.removeItem(at: url.appendingPathComponent(name))
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }

    static func script(id: String, code: String = "echo hi", extra: String = "") -> String {
        """
        ---
        id: \(id)
        name: Test
        interval: 5m
        runtime: bash
        widget: text\(extra)
        ---

        Docs for \(id).

        ```bash
        \(code)
        ```
        """
    }

    func start(_ folder: Folder, enabled: [String: Bool] = [:]) async throws
        -> (IntegrationsModule, FakeModuleContext)
    {
        let context = FakeModuleContext(scriptFolder: FakeScriptFolder(url: folder.url, enabled: enabled))
        let module = IntegrationsModule()
        try await module.start(context: context)
        return (module, context)
    }

    /// Sends a folder change and waits for the rescan it triggers.
    func change(_ module: IntegrationsModule, _ context: FakeModuleContext) async throws {
        let before = module.completedScans
        context.fakeScriptFolder.send()
        let deadline = ContinuousClock.now + .seconds(5)
        while module.completedScans == before {
            guard ContinuousClock.now < deadline else { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func script(_ module: IntegrationsModule, _ name: String) throws -> ScriptModuleDefinition {
        try #require(module.scripts.first { $0.fileName == name })
    }

    // MARK: - Scanning

    @Test func scansAtStartOnlyMarkdownFilesDirectlyInTheFolder() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("b.md", Self.script(id: "test.b"))
        try folder.write("a.MD", Self.script(id: "test.a"))
        try folder.write("notes.txt", "not a script")
        try folder.write(".hidden.md", Self.script(id: "test.hidden"))
        try FileManager.default.createDirectory(
            at: folder.url.appendingPathComponent("sub.md"), withIntermediateDirectories: true)
        try Data(Self.script(id: "test.deep").utf8).write(
            to: folder.url.appendingPathComponent("sub.md").appendingPathComponent("deep.md"))

        let (module, context) = try await start(folder)
        #expect(module.scripts.map(\.fileName) == ["a.MD", "b.md"])
        #expect(module.scripts.allSatisfy { $0.status == .ok })
        #expect(context.fakeNotifier.posted.isEmpty)
        #expect(module.state == .hidden)
        #expect(context.fakeScriptFolder.subscribers == 1)

        let b = try script(module, "b.md")
        #expect(b.moduleID == "test.b")
        #expect(b.code == "echo hi")
        #expect(b.language == "bash")
        #expect(b.documentation == "Docs for test.b.")
        #expect(b.relativePath == "modules/b.md")
        #expect(b.url == folder.url.appendingPathComponent("b.md"))
        await module.stop()
    }

    @Test func missingFolderIsNotCreated() async throws {
        let folder = try Folder(create: false)
        defer { folder.cleanUp() }
        let (module, _) = try await start(folder)
        #expect(module.scripts.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.url.path))
        await module.stop()
    }

    @Test func noFolderMeansNoScan() async throws {
        let module = IntegrationsModule()
        let context = FakeModuleContext()
        try await module.start(context: context)
        #expect(module.scripts.isEmpty)
        #expect(module.completedScans == 0)
        #expect(context.fakeScriptFolder.subscribers == 0)
        await module.stop()
    }

    @Test func addModifyRemoveTriggerRescans() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        let (module, context) = try await start(folder)
        #expect(module.scripts.isEmpty)

        try folder.write("a.md", Self.script(id: "test.a"))
        try await change(module, context)
        #expect(module.scripts.map(\.fileName) == ["a.md"])
        let firstHash = try script(module, "a.md").contentHash

        try folder.write("a.md", Self.script(id: "test.a", code: "echo bye"))
        try await change(module, context)
        #expect(try script(module, "a.md").code == "echo bye")
        #expect(try script(module, "a.md").contentHash != firstHash)

        try folder.remove("a.md")
        try await change(module, context)
        #expect(module.scripts.isEmpty)
        await module.stop()
    }

    // MARK: - Hash

    @Test func contentHashIsSHA256OfTheBytesStableAndByteSensitive() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        let text = Self.script(id: "test.a")
        try folder.write("a.md", text)
        let (module, context) = try await start(folder)
        let hash = try script(module, "a.md").contentHash
        #expect(hash.count == 64)
        #expect(hash == ScriptModuleDefinition.sha256(Data(text.utf8)))

        try await change(module, context)
        #expect(try script(module, "a.md").contentHash == hash)

        // One byte more (a trailing newline) changes it, even though the parse is the same.
        try folder.write("a.md", text + "\n")
        try await change(module, context)
        let changed = try script(module, "a.md")
        #expect(changed.contentHash != hash)
        #expect(changed.code == "echo hi")
        await module.stop()
    }

    // MARK: - Errors and alerts

    @Test(arguments: [
        ("zero.md", "---\nid: t.zero\nname: Z\ninterval: 5m\nruntime: sh\nwidget: text\n---\nNo code.\n"),
        (
            "two.md",
            "---\nid: t.two\nname: T\ninterval: 5m\nruntime: sh\nwidget: text\n---\n```sh\na\n```\n```sh\nb\n```\n"
        ),
        ("yaml.md", "---\nid: [t\n---\n```sh\na\n```\n"),
        ("schema.md", "---\nid: t.schema\nname: S\ninterval: 5m\nruntime: sh\nwidget: chart\n---\n```sh\na\n```\n"),
        ("bare.md", "```sh\na\n```\n"),
    ])
    func brokenFileIsErroredWithOneAlertNamingIt(_ name: String, _ text: String) async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write(name, text)
        let (module, context) = try await start(folder)
        let script = try script(module, name)
        let error = try #require(script.status.error)
        #expect(script.errorMessage == error.message(fileName: name))
        #expect(script.errorMessage?.hasPrefix(name + ": ") == true)

        let alerts = context.fakeNotifier.posted
        try #require(alerts.count == 1)
        let alert = alerts[0]
        #expect(alert.kind == "setup.problem")
        #expect(alert.dedupeKey == "script:" + name)
        #expect(alert.category == "SCRIPTS")
        #expect(alert.action == .openSettings(pane: "integrations"))
        #expect(alert.title.contains(name))
        #expect(alert.body?.contains(folder.url.appendingPathComponent(name).path) == true)
        #expect(alert.body?.contains(error.message) == true)
        #expect(module.state == .hidden)
        await module.stop()
    }

    @Test func schemaErrorMessageNamesTheKeyPath() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write(
            "s.md",
            Self.script(id: "test.s", extra: "\nsettings:\n  - { key: token, type: secret, label: T, default: x }"))
        let (module, context) = try await start(folder)
        let s = try script(module, "s.md")
        #expect(s.status.error?.keyPath == "settings[0].default")
        #expect(s.errorMessage?.hasPrefix("s.md: settings[0].default") == true)
        #expect(context.fakeNotifier.posted.first?.body?.contains("settings[0].default") == true)
        await module.stop()
    }

    @Test func hostOwnedSettingKeyErrorsTheFile() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write(
            "h.md", Self.script(id: "test.h", extra: "\nsettings:\n  - { key: surfaces, type: string, label: S }"))
        let (module, context) = try await start(folder)
        #expect(
            try script(module, "h.md").status
                == .errored(.schema(ScriptSchemaError(path: "settings[0].key", reason: .reservedKey("surfaces")))))
        #expect(context.fakeNotifier.posted.map(\.dedupeKey) == ["script:h.md"])
        await module.stop()
    }

    @Test func alertsDedupeAndResolve() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("a.md", "no front matter")
        let (module, context) = try await start(folder)
        #expect(context.fakeNotifier.posted.count == 1)

        // Same problem on rescan: no second alert.
        try await change(module, context)
        #expect(context.fakeNotifier.posted.count == 1)
        #expect(context.fakeNotifier.unresolved.count == 1)

        // Another problem in the same file: the old alert is replaced.
        try folder.write("a.md", "---\nid: t.a\nname: A\ninterval: 5m\nruntime: sh\nwidget: text\n---\nnone\n")
        try await change(module, context)
        #expect(context.fakeNotifier.posted.count == 2)
        #expect(context.fakeNotifier.unresolved.count == 1)
        #expect(context.fakeNotifier.unresolved.first?.body?.contains("no fenced code block") == true)

        // Fixed: resolved.
        try folder.write("a.md", Self.script(id: "t.a"))
        try await change(module, context)
        #expect(try script(module, "a.md").status == .ok)
        #expect(context.fakeNotifier.unresolved.isEmpty)

        // Broken again, then removed: resolved on removal.
        try folder.write("a.md", "broken")
        try await change(module, context)
        #expect(context.fakeNotifier.unresolved.count == 1)
        try folder.remove("a.md")
        try await change(module, context)
        #expect(context.fakeNotifier.unresolved.isEmpty)
        #expect(context.fakeNotifier.posted.count == 3)
        await module.stop()
    }

    @Test func stopResolvesOpenProblems() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("a.md", "broken")
        let (module, context) = try await start(folder)
        #expect(context.fakeNotifier.unresolved.count == 1)
        await module.stop()
        #expect(context.fakeNotifier.unresolved.isEmpty)
    }

    // MARK: - Id rules

    @Test(arguments: ["shelf", "agents.sessions", "integrations"])
    func builtInIDIsErrored(_ id: String) async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("x.md", Self.script(id: id))
        let (module, context) = try await start(folder)
        let moduleID = try #require(ModuleID(id))
        #expect(try script(module, "x.md").status == .errored(.builtInID(moduleID)))
        #expect(try script(module, "x.md").status.error?.keyPath == "id")
        #expect(context.fakeNotifier.posted.map(\.dedupeKey) == ["script:x.md"])
        await module.stop()
    }

    /// The SPEC ids of modules not shipped yet are reserved too (`ModuleID.specBuiltIns`, default service).
    @Test func specBuiltInsAreReserved() {
        #expect(ModuleID.specBuiltIns.isSuperset(of: ["calendar", "notes", "time", "shelf", "integrations"]))
        #expect(NoScriptFolder().builtInModuleIDs == ModuleID.specBuiltIns)
    }

    @Test func agentsPrefixIsErrored() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("x.md", Self.script(id: "agents.mine"))
        let (module, context) = try await start(folder)
        #expect(try script(module, "x.md").status == .errored(.reservedPrefix("agents.mine")))
        #expect(try script(module, "x.md").errorMessage?.contains("agents.") == true)
        #expect(context.fakeNotifier.posted.count == 1)
        await module.stop()
    }

    @Test func duplicateIDErrorsEveryFileWithAnAlertEach() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("one.md", Self.script(id: "test.dup"))
        try folder.write("two.md", Self.script(id: "test.dup", code: "echo 2"))
        try folder.write("other.md", Self.script(id: "test.other"))
        let (module, context) = try await start(folder)
        #expect(try script(module, "one.md").status == .errored(.duplicateID("test.dup", otherFiles: ["two.md"])))
        #expect(try script(module, "two.md").status == .errored(.duplicateID("test.dup", otherFiles: ["one.md"])))
        #expect(try script(module, "other.md").status == .ok)
        #expect(Set(context.fakeNotifier.unresolved.compactMap(\.dedupeKey)) == ["script:one.md", "script:two.md"])
        #expect(try script(module, "one.md").errorMessage?.contains("two.md") == true)

        // Renaming one id resolves both.
        try folder.write("two.md", Self.script(id: "test.dup2"))
        try await change(module, context)
        #expect(module.scripts.allSatisfy { $0.status == .ok })
        #expect(context.fakeNotifier.unresolved.isEmpty)
        await module.stop()
    }

    @Test func fileErroredForAnotherReasonStillCountsAsADuplicate() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write(
            "one.md", "---\nid: test.dup\nname: A\ninterval: 5m\nruntime: sh\nwidget: text\n---\nno code\n")
        try folder.write("two.md", Self.script(id: "test.dup"))
        let (module, context) = try await start(folder)
        #expect(try script(module, "one.md").status == .errored(.noCodeBlock))
        #expect(try script(module, "two.md").status == .errored(.duplicateID("test.dup", otherFiles: ["one.md"])))
        #expect(context.fakeNotifier.unresolved.count == 2)
        await module.stop()
    }

    // MARK: - Enabled

    /// Story 12.6 (AD-8): enabled is this Mac's flag by file, default true; a flag change applies without a rescan.
    @Test func enabledComesFromThisMacsFlagsDefaultingToTrue() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("a.md", Self.script(id: "test.a"))
        try folder.write("b.md", Self.script(id: "test.b"))
        let (module, context) = try await start(folder, enabled: ["modules/b.md": false])
        #expect(try script(module, "a.md").enabled)
        #expect(try !script(module, "b.md").enabled)

        let scans = module.completedScans
        context.fakeScriptFolder.fakeSettings.edit(enabled: nil, for: "modules/b.md")
        #expect(await eventually { (try? script(module, "b.md").enabled) == true })
        #expect(module.completedScans == scans)
        await module.stop()
    }

    // MARK: - Privacy and catalog

    @Test func alertTitleAndBodyAreMaskedInPrivacyMode() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("secret-client.md", "broken")
        let (module, context) = try await start(folder)
        let alert = try #require(context.fakeNotifier.posted.first)
        #expect(alert.body?.contains("secret-client.md") == true)
        #expect(alert.$body.masked == PrivacyMask.text)
        #expect(alert.$title.masked == PrivacyMask.text)
        #expect(alert.$body.value(privacyActive: true)?.contains("secret-client") == false)
        await module.stop()
    }

    @Test func everyShippedLocaleHasTheDiscoveryStrings() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Integrations/Resources/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let strings = try #require(catalog?["strings"] as? [String: Any])
        var locales: Set<String> = []
        for case let entry as [String: Any] in strings.values {
            locales.formUnion((entry["localizations"] as? [String: Any])?.keys ?? [:].keys)
        }
        #expect(locales.contains("en"))
        let keys = strings.keys.filter { $0.hasPrefix("script.parse.") || $0.hasPrefix("script.problem.") }
        #expect(keys.count == 15)
        for key in keys {
            let entry = try #require(strings[key] as? [String: Any])
            let localized = Set((entry["localizations"] as? [String: Any])?.keys ?? [:].keys)
            #expect(localized == locales, "\(key) is missing a locale")
            // The compiled catalog resolves it (not the key echoed back).
            #expect(IntegrationsText.string(key) != key, "\(key) does not resolve")
        }
    }

    @Test func messagesRead() {
        #expect(ScriptParseError.noCodeBlock.message == "no fenced code block; a script needs exactly one.")
        #expect(
            ScriptParseError.severalCodeBlocks(count: 3).message == "3 fenced code blocks; a script needs exactly one.")
        #expect(ScriptParseError.invalidYAML(line: 4).message == "the front matter is not valid YAML (line 4).")
        #expect(
            ScriptParseError.duplicateID("a.b", otherFiles: ["x.md", "y.md"]).message(fileName: "z.md")
                == "z.md: id: “a.b” is also declared by x.md, y.md.")
        #expect(ScriptParseError.builtInID("shelf").message == "id: “shelf” is the id of a built-in module.")
        #expect(
            ScriptParseError.reservedPrefix("agents.x").message
                == "id: “agents.x” starts with agents., which is reserved for built-in modules.")
    }
}
