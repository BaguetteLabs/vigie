import AppKit
import Foundation
import ModuleKit
import Observation
import SwiftUI
import Testing

@testable import VigieCore

// MARK: - Fakes

/// Log lines from a fixed list (never the real log store).
struct FakeLogLines: LogLinesProviding {
    var lines: [String]
    var fails = false

    struct Failure: Error {}

    func recentLines(limit: Int, since: Date) async throws -> [String] {
        if fails { throw Failure() }
        return Array(lines.suffix(limit))
    }
}

/// A module that contributes diagnostics and hands over a script-like secret value. Its lines leak that value on
/// purpose: the redaction gate must catch it.
@MainActor @Observable
final class ContributingModule: NotchModule, DiagnosticsContributing {
    let manifest: ModuleManifest
    var state: ModuleState = .ambient
    let secret: String

    init(manifest: ModuleManifest, secret: String) {
        self.manifest = manifest
        self.secret = secret
    }

    func start(context: any ModuleContext) async throws {}
    func stop() async {}

    func diagnostics() async -> [ModuleDiagnostics] {
        [
            ModuleDiagnostics(
                section: .agents,
                lines: [
                    "adapter claude  version=2.1.3  support=supported  hook=installed", "terminal warp  installed=true",
                ]
            ),
            ModuleDiagnostics(section: .modules, lines: ["script github.prs  status=ok  confirmation=confirmed"]),
            ModuleDiagnostics(section: .modules, lines: ["leaky script setting: \(secret)"]),
        ]
    }

    func diagnosticsSecretValues() async -> [String] { [secret] }
}

/// Holds a note the way the Notes module does; Copy diagnostics must never reach it.
@MainActor @Observable
final class NoteHoldingModule: NotchModule {
    let manifest: ModuleManifest
    var state: ModuleState = .active
    var noteTitle = "SENTINEL-NOTE-TITLE-7Q"
    var noteBody = "SENTINEL-NOTE-BODY-the launch codes are 0000"

    init(manifest: ModuleManifest) { self.manifest = manifest }

    func start(context: any ModuleContext) async throws {}
    func stop() async {}
}

let contributingManifest = ModuleManifest(
    id: "contrib.test", name: "Contrib", icon: "star",
    settings: [SettingDescriptor(key: "folder", label: "Folder", kind: .path(default: "~/Code"))],
    alertKinds: ["contrib.alert"])
let notesLikeManifest = ModuleManifest(id: "notes.test", name: "Notes", icon: "note")

// MARK: - Inputs

func sampleInputs(
    displays: [DiagnosticsInputs.Display] = [], logs: [String] = ["12:00:00 info [modules] Started module x"]
) -> DiagnosticsInputs {
    DiagnosticsInputs(
        app: .init(
            name: "Vigie Dev", version: "1.2.3", build: "45", bundleID: "fr.baguettelabs.vigie.dev", flavor: "dev",
            signing: "ad-hoc", installPath: "~/Applications/Vigie Dev.app"),
        system: .init(
            osVersion: "Version 26.5", model: "Mac15,6", chip: "Apple M3 Pro", architecture: "arm64", locale: "en_FR",
            reduceMotion: false, reduceTransparency: true, increaseContrast: false),
        displays: displays,
        modules: [
            .init(
                id: "agents.sessions", enabled: true, status: "running", state: .active,
                alertKinds: ["session.blocked"], isScript: false),
            .init(id: "github.prs", enabled: true, status: "running", state: nil, alertKinds: [], isScript: true),
        ],
        moduleLines: ["script github.prs  status=ok"], agentLines: ["adapter claude  version=2.1.3"],
        setupProblems: [
            .init(since: Date(timeIntervalSince1970: 1_000), module: "core", category: "CONFIG", title: "Bad value")
        ],
        resolvedProblems: (0..<25).map { .init(at: Date(timeIntervalSince1970: Double($0)), module: "core") },
        config: .init(
            folder: "~/Library/Vigie Dev", syncOn: false, iCloudAvailable: true, problems: 0,
            lines: [.init(key: "general.expand_hotkey", value: "\"opt+cmd+v\"", isLocal: false)]),
        logs: .init(lines: logs), generatedAt: Date(timeIntervalSince1970: 1_800_000_000))
}

// MARK: - Live harness

@MainActor
struct DiagnosticsHarness {
    let fixture = ConfigFixture()
    let store: ConfigStore
    let registry: ModuleRegistry
    let secretStore: KeychainSecretStore
    let alertCenter = AlertCenter(rules: StaticNotifyRules(), log: testLogger)
    let scriptSecret = "script-secret-Zq9-hunter"
    let keychainSecret = "keychain-SEEDED-k3y-value"
    let collector: DiagnosticsCollector

    init(config: String? = nil, logs: [String] = []) async throws {
        let manifests = [customManifest, contributingManifest, notesLikeManifest]
        (store, _) = try await fixture.makeStore(manifests: manifests, config: config)
        secretStore = KeychainSecretStore(identity: testSecretIdentity, client: FakeKeychainClient(), log: testLogger)
        try await secretStore.set(keychainSecret, owner: "custom.test", key: "token")
        let scriptSecret = scriptSecret
        let checker = FakePermissionChecker()
        let (stream, _) = AsyncStream.makeStream(of: Void.self)
        let coordinator = PermissionsCoordinator(checker: checker, activationNotifications: stream)
        registry = ModuleRegistry(
            descriptors: [
                ModuleDescriptor(manifest: customManifest) { CustomSettingsModule(manifest: customManifest) },
                ModuleDescriptor(manifest: contributingManifest) {
                    ContributingModule(manifest: contributingManifest, secret: scriptSecret)
                },
                ModuleDescriptor(manifest: notesLikeManifest) { NoteHoldingModule(manifest: notesLikeManifest) },
            ],
            enablement: TestEnablement(["custom.test": true, "contrib.test": true, "notes.test": true]),
            contextFactory: CoreModuleContextFactory(
                environment: fixture.environment, eventBus: InProcessEventBus(), permissions: coordinator,
                secretStore: secretStore),
            logger: testLogger, permissions: coordinator)
        await registry.start()
        let center = alertCenter
        let live = DiagnosticsCollector.live(
            configStore: store, registry: registry, secretStore: secretStore, alertCenter: { center },
            syncOn: { false }, iCloudAvailable: { true })
        var sources = live.sources
        sources.logs = FakeLogLines(lines: logs)
        collector = DiagnosticsCollector(sources: sources)
    }

    func tearDown() async {
        await registry.shutdown()
        store.stop()
    }
}

@MainActor @Suite(.serialized) struct DiagnosticsTests {
    // MARK: Report

    @Test func sectionsArePresentAndOrdered() {
        let text = DiagnosticsReport.render(sampleInputs())
        var cursor = text.startIndex
        for name in DiagnosticsReport.sections {
            let range = text.range(of: "== \(name) ==", range: cursor..<text.endIndex)
            #expect(range != nil, "\(name) missing or out of order")
            if let range { cursor = range.upperBound }
        }
        #expect(text.contains("version: 1.2.3 (45)"))
        #expect(text.contains("signing: ad-hoc"))
        #expect(text.contains("model: Mac15,6"))
        #expect(text.contains("reduce transparency: true"))
        #expect(text.contains("agents.sessions  enabled=true  status=running  state=active  alerts=session.blocked"))
        #expect(text.contains("github.prs  script  status=running"))
        #expect(text.contains("adapter claude  version=2.1.3"))
        #expect(text.contains("general.expand_hotkey = \"opt+cmd+v\""))
        let footer = text.split(separator: "\n").last
        #expect(footer?.hasPrefix("Generated 2027-01-15T08:00:00Z") == true)
        #expect(footer?.hasSuffix("Vigie diagnostics contain no secrets; review before sharing.") == true)
    }

    @Test func modulesListEnabledAndDisabledHonestly() {
        var inputs = sampleInputs()
        inputs.modules.append(
            .init(id: "notes.off", enabled: false, status: "disabled", state: nil, alertKinds: [], isScript: false))
        let text = DiagnosticsReport.render(inputs)
        #expect(text.contains("notes.off  enabled=false  status=disabled"))
        #expect(!text.contains("notes.off  enabled=true"))
        #expect(text.contains("agents.sessions  enabled=true"))
    }

    @Test func agentsSectionSaysWhenTheModuleIsNotRunning() {
        var inputs = sampleInputs()
        inputs.agentLines = []
        let text = DiagnosticsReport.render(inputs)
        #expect(text.contains("== AGENTS ==\n(agents.sessions not running)"))
        #expect(DiagnosticsReport.render(sampleInputs()).contains("adapter claude  version=2.1.3"))
    }

    @Test func setupProblemsListCurrentAndLastTwentyResolved() {
        let text = DiagnosticsReport.render(sampleInputs())
        #expect(text.contains("current: 1"))
        #expect(text.contains("core [CONFIG]  Bad value"))
        #expect(text.contains("resolved this launch (last 20): 20"))
        #expect(text.contains(Date(timeIntervalSince1970: 24).formatted(.iso8601)))
        #expect(!text.contains(Date(timeIntervalSince1970: 4).formatted(.iso8601)))
    }

    @Test func displayKindsAndTheDrawnDisplay() {
        func metrics(_ frame: CGRect, notch: Bool) -> ScreenMetrics {
            ScreenMetrics(
                frame: frame, safeAreaTop: notch ? 32 : 0,
                auxiliaryTopLeftArea: notch ? CGRect(x: 0, y: 0, width: 10, height: 32) : nil,
                auxiliaryTopRightArea: notch ? CGRect(x: 0, y: 0, width: 10, height: 32) : nil)
        }
        let notched = DisplayInfo(
            id: 1, name: "Built-in", kind: .physical, isMain: false, isBuiltIn: true,
            metrics: metrics(CGRect(x: 0, y: 0, width: 1512, height: 982), notch: true))
        let external = DisplayInfo(
            id: 2, name: "Studio Display", kind: .plain, isMain: true, isBuiltIn: false,
            metrics: metrics(CGRect(x: 1512, y: 0, width: 2560, height: 1440), notch: false))
        let plainBuiltIn = DisplayInfo(
            id: 3, name: "Old MacBook", kind: .plain, isMain: false, isBuiltIn: true,
            metrics: metrics(CGRect(x: 0, y: 0, width: 1440, height: 900), notch: false))
        let displays = DiagnosticsCollector.displays(
            [notched, external, plainBuiltIn], scales: [1: 2, 2: 2, 3: 1], selection: .notched)
        #expect(displays.map(\.isDrawn) == [true, false, false])
        let text = DiagnosticsReport.render(sampleInputs(displays: displays))
        #expect(text.contains("count: 3"))
        #expect(text.contains("display 1: physical notch (built-in)  1512x982 pt  @2x  vigie"))
        #expect(text.contains("display 2: virtual notch (external)  2560x1440 pt  @2x  main"))
        #expect(text.contains("display 3: virtual notch (built-in without notch)  1440x900 pt  @1x"))
        // Display names are not collected.
        #expect(!text.contains("Studio Display"))
    }

    // MARK: Logs

    @Test func logLinesComeFromTheSeamCappedAtTwoHundred() async throws {
        let lines = (0..<250).map { "line \($0)" }
        let h = try await DiagnosticsHarness(logs: lines)
        let result = await h.collector.makeText()
        #expect(!result.logsUnavailable)
        #expect(result.text.contains("last 200 lines (max 200, last 15 minutes):"))
        #expect(result.text.contains("line 249\n"))
        #expect(result.text.contains("line 50\n"))
        #expect(!result.text.contains("line 49\n"))
        await h.tearDown()
    }

    @Test func unreadableLogIsReportedNotFatal() async throws {
        let h = try await DiagnosticsHarness()
        var sources = h.collector.sources
        sources.logs = FakeLogLines(lines: [], fails: true)
        let result = await DiagnosticsCollector(sources: sources).makeText()
        #expect(result.logsUnavailable)
        #expect(result.text.contains("unavailable: Failure"))
        #expect(result.text.contains("== CONFIG =="))
        await h.tearDown()
    }

    /// The real `OSLogStore` path: reading this process's own log must not throw (it may well be empty here).
    @Test func osLogStoreReadsWithoutThrowing() async throws {
        let provider = OSLogLinesProvider(subsystems: ["fr.baguettelabs.vigie.tests"])
        let lines = try await provider.recentLines(limit: 200, since: Date().addingTimeInterval(-60))
        #expect(lines.count <= 200)
        #expect(DiagnosticsCollector.logSubsystems(makeEnvironment(makeTempDirectory())).contains("vigie"))
    }

    // MARK: Secrets and redaction (AC 2)

    @Test func seededSecretsNeverAppear() async throws {
        let configToken = "sk-proj-ABCDEFGH12345678abcd"
        let config = """
            [modules."custom.test"]
            name = "\(configToken)"
            ratio = 0.7

            [modules."contrib.test"]
            folder = "~/Secret Projects"
            """
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let h = try await DiagnosticsHarness(
            config: config,
            logs: [
                "12:00:01 info [secrets] stored keychain-SEEDED-k3y-value by mistake",
                "12:00:02 info [http] Authorization: Bearer abc.def.ghi",
                "12:00:03 info [files] opened \(home)/Documents/plan.txt",
            ])
        let text = await h.collector.makeText().text

        // Exact-match scrub of the Keychain value and the module's (script) secret value.
        #expect(!text.contains(h.keychainSecret))
        #expect(!text.contains(h.scriptSecret))
        #expect(text.contains("leaky script setting: <redacted>"))
        #expect(text.contains("stored <redacted> by mistake"))
        // A token-looking config value is redacted by shape; plain values stay.
        #expect(!text.contains(configToken))
        #expect(text.contains("modules.\"custom.test\".name = \"<redacted>\""))
        #expect(text.contains("modules.\"custom.test\".ratio = 0.7"))
        // Secret settings print set/unset only; paths print `<path>`.
        #expect(text.contains("modules.\"custom.test\".token = <set>"))
        #expect(text.contains("modules.\"contrib.test\".folder = <path>"))
        #expect(!text.contains("Secret Projects"))
        // Headers and home folder.
        #expect(text.contains("Authorization: <redacted>"))
        #expect(!text.contains(home + "/"))
        #expect(text.contains("opened ~/Documents/plan.txt"))
        // Contributions land in their sections.
        #expect(text.contains("adapter claude  version=2.1.3  support=supported  hook=installed"))
        #expect(text.contains("terminal warp  installed=true"))
        #expect(text.contains("contrib.test  enabled=true  status=running  state=ambient  alerts=contrib.alert"))
        await h.tearDown()
    }

    /// Note content is never collected: a running module holding a note contributes nothing but its id and state.
    @Test func noteContentNeverAppears() async throws {
        let h = try await DiagnosticsHarness()
        let notes = try #require(h.registry.module("notes.test") as? NoteHoldingModule)
        let text = await h.collector.makeText().text
        #expect(!text.contains(notes.noteTitle))
        #expect(!text.contains(notes.noteBody))
        #expect(!text.contains("SENTINEL"))
        #expect(text.contains("notes.test  enabled=true  status=running  state=active"))
        await h.tearDown()
    }

    @Test func setupProblemsComeFromTheNotifier() async throws {
        let h = try await DiagnosticsHarness()
        let notifier = h.alertCenter.makeNotifier(for: SetupProblemReporter.manifest)
        let open = NotifierEvent(
            kind: SetupProblemReporter.alertKind, severity: .warn, title: "Unknown key closed.foo", dedupeKey: "a",
            category: "CONFIG")
        _ = notifier.post(open)
        let gone = notifier.post(
            NotifierEvent(kind: SetupProblemReporter.alertKind, severity: .warn, title: "Old problem", dedupeKey: "b"))
        gone.resolve()
        let text = await h.collector.makeText().text
        #expect(text.contains("current: 1"))
        #expect(text.contains("core [CONFIG]  Unknown key closed.foo"))
        #expect(!text.contains("Old problem"))
        #expect(text.contains("resolved this launch (last 20): 1"))
        await h.tearDown()
    }

    @Test func redactorPatterns() {
        let home = URL(fileURLWithPath: "/Users/romain")
        let r = DiagnosticsRedactor(secretValues: ["my-very-secret", "abc"], homeDirectory: home)
        let cases: [(String, String)] = [
            ("value my-very-secret here", "value <redacted> here"),
            ("short abc stays", "short abc stays"),
            ("key sk-ant-api03-AbCdEf123456", "key <redacted>"),
            ("slack xoxb-1234567890-abcdef", "slack <redacted>"),
            ("gh ghp_ABCDEFGHIJKLMNOPQRSTuvwx1234", "gh <redacted>"),
            ("aws AKIAIOSFODNN7EXAMPLE end", "aws <redacted> end"),
            ("jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.sig", "jwt <redacted>"),
            ("hash 0123456789abcdef0123456789abcdef01", "hash <redacted>"),
            ("b64 QWxhZGRpbjpvcGVuIHNlc2FtZQ9xYWxhZGRpbjpvcGVuIHNl", "b64 <redacted>"),
            ("Authorization: Basic dXNlcjpwYXNz", "Authorization: <redacted>"),
            ("sent with Bearer abc123", "sent with Bearer <redacted>"),
            ("api_key = hello123", "api_key = <redacted>"),
            ("\"password\": \"pw1\"", "\"password\": \"<redacted>\""),
            ("token = <set>", "token = <set>"),
            ("mail romain@example.com ok", "mail <redacted>@example.com ok"),
            ("path /Users/romain/Library/x", "path ~/Library/x"),
            ("other /Users/alice/x and /Users/Shared/y", "other ~/x and /Users/Shared/y"),
            ("home /Users/romain", "home ~"),
            // Ordinary text stays readable.
            ("Started module agents.sessions", "Started module agents.sessions"),
            ("fr.baguettelabs.vigie.dev 550e8400-e29b-41d4", "fr.baguettelabs.vigie.dev 550e8400-e29b-41d4"),
            ("~/www/vigie/Packages/VigieCore/Sources/VigieCore", "~/www/vigie/Packages/VigieCore/Sources/VigieCore"),
        ]
        for (input, expected) in cases {
            #expect(r.redactLine(input) == expected, "\(input)")
        }
    }

    @Test func multiLineSecretIsScrubbedRawAndEscaped() {
        let r = DiagnosticsRedactor(
            secretValues: ["line-one-SENTINEL\nline-two-SENTINEL"], homeDirectory: URL(fileURLWithPath: "/Users/romain")
        )
        let text = r.redact(
            "before line-one-SENTINEL\nline-two-SENTINEL after\n{\"k\":\"line-one-SENTINEL\\nline-two-SENTINEL\"} end")
        #expect(!text.contains("SENTINEL"))
        #expect(text.contains("before <redacted> after"))
        #expect(text.contains("{\"k\":\"<redacted>\"} end"))
    }

    @Test func quotedCredentialIsRedactedToItsClosingQuote() {
        let r = DiagnosticsRedactor(secretValues: [], homeDirectory: URL(fileURLWithPath: "/Users/romain"))
        #expect(r.redactLine("password = \"two words-SENTINEL\" next") == "password = \"<redacted>\" next")
        #expect(r.redactLine("{\"api_key\": \"a b SENTINEL\", \"x\": 1}") == "{\"api_key\": \"<redacted>\", \"x\": 1}")
        #expect(r.redactLine("secret: 'it is SENTINEL") == "secret: '<redacted>")
        #expect(r.redactLine("password = plain-SENTINEL tail") == "password = <redacted> tail")
        for marker in ["<set>", "<unset>", "<redacted>", "<path>"] {
            #expect(r.redactLine("token = \"\(marker)\" ok") == "token = \"\(marker)\" ok")
            #expect(r.redactLine("token = \(marker) ok") == "token = \(marker) ok")
        }
    }

    @Test func urlUserinfoIsRedactedHostAndPathStay() {
        let r = DiagnosticsRedactor(secretValues: [], homeDirectory: URL(fileURLWithPath: "/Users/romain"))
        #expect(
            r.redactLine("clone https://bob:p4ss!w:rd-SENTINEL@git.example.com/repo.git ok")
                == "clone https://<redacted>@git.example.com/repo.git ok")
        #expect(r.redactLine("ssh://tok-SENTINEL@host:22/x") == "ssh://<redacted>@host:22/x")
    }

    @Test func plainUrlsAndEmailsAreUnchanged() {
        let r = DiagnosticsRedactor(secretValues: [], homeDirectory: URL(fileURLWithPath: "/Users/romain"))
        #expect(r.redactLine("see https://example.com/a/b@c?x=1 now") == "see https://example.com/a/b@c?x=1 now")
        #expect(r.redactLine("mail user@example.com") == "mail <redacted>@example.com")
        #expect(r.redactLine("https://<redacted>@host/p") == "https://<redacted>@host/p")
    }

    @Test func configValueTextAndSecretOwners() {
        #expect(DiagnosticsCollector.valueText(.path(default: nil), .string("/Users/x/y")) == "<path>")
        #expect(DiagnosticsCollector.valueText(.list(of: .path, default: []), .strings(["a", "b"])) == "<list of 2>")
        #expect(DiagnosticsCollector.valueText(.duration(default: .zero), .duration(.seconds(300))) == "300s")
        #expect(DiagnosticsCollector.valueText(.bool(default: false), .bool(true)) == "true")
        let adapterKey = ConfigSchemaEntry(
            path: CoreSettings.adapterPath(module: "agents.usage", adapter: "claude", "api_key"),
            descriptor: SettingDescriptor(key: "api_key", label: "Key", kind: .secret), moduleID: "agents.usage")
        #expect(DiagnosticsCollector.secretOwner(adapterKey) == "adapter.claude")
        let moduleKey = ConfigSchemaEntry(
            path: .module("custom.test", "token", scope: .synced),
            descriptor: SettingDescriptor(key: "token", label: "Token", kind: .secret), moduleID: "custom.test")
        #expect(DiagnosticsCollector.secretOwner(moduleKey) == "custom.test")
    }

    // MARK: Settings row (AC 1)

    @Test func generalRowCopiesThroughTheClipboardService() async throws {
        let h = try await SettingsHarness()
        let model = h.controller.diagnostics!
        let pasteboard = RecordingPasteboard()
        model.clipboard = CoreClipboardService(pasteboard: { pasteboard })
        var sources = model.collector.sources
        sources.logs = FakeLogLines(lines: ["12:00 info [modules] Started"])
        let copy = DiagnosticsModel(collector: DiagnosticsCollector(sources: sources), clipboard: model.clipboard)
        copy.readoutDuration = { .milliseconds(100) }
        await copy.copy()
        let text = try #require(pasteboard.strings.last)
        for name in DiagnosticsReport.sections { #expect(text.contains("== \(name) ==")) }
        #expect(text.contains("Started"))
        #expect(copy.error == nil)
        #expect(copy.copiedBytes == text.utf8.count)
        #expect(copy.statusText == "COPIED · " + DiagnosticsModel.sizeText(text.utf8.count))
        #expect(DiagnosticsModel.sizeText(12_000) == "12 KB")
        #expect(await eventually(timeout: .seconds(5)) { copy.copiedBytes == nil })
        // No clear timer: the copy stays on the pasteboard.
        #expect(pasteboard.clears == 1)

        let view = NSHostingView(
            rootView: SettingsPaneView(controller: h.controller, pane: try #require(h.controller.pane("general")))
                .environment(\.settingControlServices, h.controller.services))
        view.frame = NSRect(origin: .zero, size: SettingsWindowMetrics.size)
        view.layoutSubtreeIfNeeded()
        #expect(view.fittingSize.height > 0)
        await h.tearDown()
    }

    @Test func rowShowsLogErrorInline() async throws {
        let h = try await DiagnosticsHarness()
        var sources = h.collector.sources
        sources.logs = FakeLogLines(lines: [], fails: true)
        let pasteboard = RecordingPasteboard()
        let model = DiagnosticsModel(
            collector: DiagnosticsCollector(sources: sources),
            clipboard: CoreClipboardService(pasteboard: { pasteboard }))
        await model.copy()
        #expect(pasteboard.strings.count == 1)
        #expect(model.error == SettingsText.string("settings.diagnostics.logsUnavailable"))
        await h.tearDown()
    }

    @Test func catalogStringsResolve() {
        for key in [
            "settings.section.diagnostics", "settings.diagnostics.label", "settings.diagnostics.help",
            "settings.diagnostics.copy", "settings.diagnostics.copied", "settings.diagnostics.logsUnavailable",
        ] {
            #expect(SettingsText.string(key) != key, "\(key)")
        }
        #expect(SettingsText.format("settings.diagnostics.copied", "12 KB") == "COPIED · 12 KB")
    }

    // MARK: No network (AC 3)

    /// The collector only takes closures over in-process state; by construction its sources name no networking
    /// API. This scans the diagnostics sources for any.
    @Test func diagnosticsSourcesUseNoNetworking() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/VigieCore")
        let folder = root.appendingPathComponent("Diagnostics")
        var files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        files.append(root.appendingPathComponent("Settings/DiagnosticsSection.swift"))
        #expect(files.count >= 6)
        let forbidden = [
            "URLSession", "import Network", "NWConnection", "NWPath", "curl", "URLRequest", "CFNetwork", "Process(",
        ]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for word in forbidden {
                #expect(!text.contains(word), "\(file.lastPathComponent) mentions \(word)")
            }
        }
    }
}
