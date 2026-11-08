import AgentKit
import Foundation
import ModuleKit
import Testing
import Wire

@testable import AgentsSessions

// MARK: - Fakes

/// An agent with a launch command: typed mentions, and the same text as prompt arguments unless `promptless`.
struct LaunchAdapter: AgentAdapter {
    var promptless = false
    var id: AgentID { "claude" }
    var name: LocalizedStringResource { "Claude Code" }
    var capabilities: Set<AgentCapability> { [.launch] }
    func normalize(_ hook: HookPayload, sentAt: Date) -> [AgentEvent] { [] }
    func launchCommand(files: [URL], cwd: URL?) -> LaunchCommand? {
        let text = files.map { "@" + $0.path }.joined(separator: " ") + " "
        return LaunchCommand(
            executable: "claude", arguments: [], typedText: text, promptArguments: promptless ? nil : [text])
    }
}

final class RecordingLaunchTerminal: PermissionReportingTerminalAdapter, @unchecked Sendable {
    struct Call: Equatable {
        let argv: [String]
        let cwd: URL?
        let typedText: String?
    }

    let id: TerminalID = "rec"
    var name: LocalizedStringResource { "Recorder" }
    let bundleIDs: [String] = []
    let types: Bool
    let outcome: OpenTabOutcome
    let deniesPermission: Bool
    private let lock = NSLock()
    private var _calls: [Call] = []
    var calls: [Call] { lock.withLock { _calls } }

    init(types: Bool = true, outcome: OpenTabOutcome = .running, deniesPermission: Bool = false) {
        self.types = types
        self.outcome = outcome
        self.deniesPermission = deniesPermission
    }

    var supportsTypedText: Bool { types }
    func matches(env: [String: String]) -> Bool { false }
    func capture(env: [String: String], pid: Int32?, tty: String?) -> TerminalLocator? { nil }
    func attemptFocus(_ locator: TerminalLocator, context: any AdapterContext) async throws(TerminalFocusError)
        -> FocusResult
    { .appOnly }

    func openTab(argv: [String], cwd: URL?, typedText: String?, context: any AdapterContext) async throws
        -> OpenTabOutcome
    {
        lock.withLock { _calls.append(Call(argv: argv, cwd: cwd, typedText: typedText)) }
        if deniesPermission { throw TerminalFocusError.permissionRequired(.automation(bundleID: "com.example")) }
        return outcome
    }
}

final class RecordingClipboard: ClipboardService, @unchecked Sendable {
    private let lock = NSLock()
    private var _copied: [String] = []
    var copied: [String] { lock.withLock { _copied } }
    func copy(_ text: String, clearAfter: Duration?) { lock.withLock { _copied.append(text) } }
}

struct PathResolver: ExecutableResolver {
    let paths: [String: URL]
    func resolve(_ name: String) async -> URL? { paths[name] }
}

// MARK: - Tests

@MainActor @Suite("Ask AI (Story 9.6)")
struct AskAITests {
    /// A real folder tree (the module falls back to home for a folder that does not exist).
    let home: URL
    let project: URL
    let file: URL

    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("vigie-ask-\(UUID().uuidString)")
        project = home.appendingPathComponent("my proj", isDirectory: true)
        for folder in [project, home.appendingPathComponent("Code"), home.appendingPathComponent("dev")] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        file = project.appendingPathComponent("a.swift")
        try Data().write(to: file)
    }

    let claude = URL(fileURLWithPath: "/opt/bin/claude")

    struct Harness {
        let module: AgentsSessionsModule
        let context: FakeModuleContext
        let terminal: RecordingLaunchTerminal
        let clipboard: RecordingClipboard
        let notifier: RecordingNotifier
    }

    func start(
        _ settings: [String: any SettingValue] = [:], terminal: RecordingLaunchTerminal = RecordingLaunchTerminal(),
        adapter: LaunchAdapter = LaunchAdapter(), installed: Bool = true
    ) async throws -> Harness {
        let clipboard = RecordingClipboard()
        let notifier = RecordingNotifier()
        let context = FakeModuleContext(
            settings: ["terminal": "rec"].merging(settings) { _, new in new }, notifier: notifier,
            clipboard: clipboard, executables: PathResolver(paths: installed ? ["claude": claude] : [:]))
        let module = AgentsSessionsModule(
            adapters: AgentAdapters([adapter]), terminals: TerminalAdapters([terminal]), liveness: FakeLiveness(),
            homeDirectory: home)
        try await module.start(context: context)
        return Harness(module: module, context: context, terminal: terminal, clipboard: clipboard, notifier: notifier)
    }

    func drop(_ harness: Harness, _ urls: [URL], option: Bool = false) async -> DropResult {
        await harness.module.askZone.handler(
            DropPayload(urls: urls, modifiers: option ? .option : [], source: .dropDisplay))
    }

    func readout(_ result: DropResult) -> String? {
        if case .readout(let text) = result { return String(localized: text) }
        return nil
    }

    // MARK: Folder

    @Test("cwd table: home, file folder, custom, ~, relative, ⌥ alternate, dropped folder")
    func folderTable() {
        let home = URL(fileURLWithPath: "/Users/me")
        let files = [URL(fileURLWithPath: "/Users/me/www/vigie/a.swift")]
        func resolve(_ raw: String?, alt: String? = nil, _ files: [URL] = files) -> String {
            AskFolderSetting.resolve(setting: AskFolderSetting(raw), alternate: alt, files: files, home: home).path
        }
        #expect(resolve("home") == "/Users/me")
        #expect(resolve("file_folder") == "/Users/me/www/vigie")
        #expect(resolve(nil) == "/Users/me/www/vigie")
        #expect(resolve("") == "/Users/me/www/vigie")
        #expect(resolve("/opt/work") == "/opt/work")
        #expect(resolve("~/dev") == "/Users/me/dev")
        #expect(resolve("~") == "/Users/me")
        #expect(resolve("dev") == "/Users/me/dev")
        #expect(resolve("home", alt: "~/Code") == "/Users/me/Code")
        #expect(resolve("file_folder", alt: "~") == "/Users/me")
        #expect(resolve("file_folder", [URL(fileURLWithPath: "/Users/me/www/", isDirectory: true)]) == "/Users/me/www")
        #expect(resolve("file_folder", []) == "/Users/me")
    }

    // MARK: Launch

    @Test("drop → openTab with the bare agent, the file's folder and the typed mentions; no dialog")
    func typingTerminal() async throws {
        let harness = try await start()
        let result = await drop(harness, [file])
        guard case .accepted = result else {
            Issue.record("expected accepted, got \(result)")
            return
        }
        #expect(
            harness.terminal.calls == [
                .init(argv: [claude.path], cwd: project, typedText: "@\(file.path) ")
            ])
        #expect(harness.clipboard.copied.isEmpty)
        #expect(harness.notifier.events.isEmpty)
    }

    @Test("⌥ held → ask_alt_cwd; ask_cwd home and custom paths")
    func folders() async throws {
        let alt = try await start(["ask_alt_cwd": "~/Code"])
        _ = await drop(alt, [file], option: true)
        #expect(alt.terminal.calls.first?.cwd?.path == home.appendingPathComponent("Code").path)

        let atHome = try await start(["ask_cwd": "home"])
        _ = await drop(atHome, [file])
        #expect(atHome.terminal.calls.first?.cwd == home)

        let custom = try await start(["ask_cwd": "~/dev"])
        _ = await drop(custom, [file])
        #expect(custom.terminal.calls.first?.cwd?.path == home.appendingPathComponent("dev").path)

        let missing = try await start(["ask_cwd": "~/nope"])
        _ = await drop(missing, [file])
        #expect(missing.terminal.calls.first?.cwd == home)
    }

    @Test("a terminal that cannot type gets the mentions as the first prompt")
    func promptArguments() async throws {
        let harness = try await start(terminal: RecordingLaunchTerminal(types: false))
        let result = await drop(harness, [file])
        guard case .accepted = result else {
            Issue.record("expected accepted, got \(result)")
            return
        }
        #expect(harness.terminal.calls == [.init(argv: [claude.path, "@\(file.path) "], cwd: project, typedText: nil)])
    }

    @Test("no prompt argument and no typing → the paths are copied, PATHS COPIED")
    func pastePaths() async throws {
        let harness = try await start(
            terminal: RecordingLaunchTerminal(types: false), adapter: LaunchAdapter(promptless: true))
        let result = await drop(harness, [file])
        #expect(readout(result) == "PATHS COPIED")
        #expect(harness.terminal.calls.first?.argv == [claude.path])
        #expect(harness.clipboard.copied == ["@\(file.path) "])
    }

    @Test("a terminal that cannot run the command → the command line is copied, COMMAND COPIED")
    func commandCopied() async throws {
        let harness = try await start(terminal: RecordingLaunchTerminal(types: false, outcome: .commandNotRun))
        let result = await drop(harness, [file])
        #expect(readout(result) == "COMMAND COPIED")
        #expect(
            harness.clipboard.copied == [
                "cd '\(project.path)' && '/opt/bin/claude' '@\(file.path) '"
            ])
    }

    @Test("Automation denied → SETUP · PERMISSION and the command copied")
    func permission() async throws {
        let harness = try await start(terminal: RecordingLaunchTerminal(deniesPermission: true))
        let result = await drop(harness, [file])
        #expect(readout(result) == "COMMAND COPIED")
        #expect(harness.notifier.events.map(\.dedupeKey) == ["permission:rec:automation:com.example"])
        #expect(harness.clipboard.copied.count == 1)
    }

    // MARK: Not installed

    @Test("agent not installed → setup problem with Open settings › Agents, no openTab")
    func notInstalled() async throws {
        let harness = try await start(installed: false)
        let result = await drop(harness, [file])
        guard case .failed = result else {
            Issue.record("expected failed, got \(result)")
            return
        }
        #expect(harness.terminal.calls.isEmpty)
        let event = try #require(harness.notifier.events.first)
        #expect(event.kind == "setup.problem")
        #expect(event.title == "Ask AI: Claude Code is not installed")
        #expect(event.action == .openSettings(pane: "agents.sessions"))
        #expect(event.category == "AGENT")
        _ = await drop(harness, [file])
        #expect(harness.notifier.events.count == 1)
    }

    @Test("an unknown ask_default_agent is reported the same way")
    func unknownAgent() async throws {
        let harness = try await start(["ask_default_agent": "codex"])
        _ = await drop(harness, [file])
        #expect(harness.terminal.calls.isEmpty)
        #expect(harness.notifier.events.first?.title == "Ask AI: codex is not installed")
    }

    // MARK: Zone

    @Test("zone hidden while the module is stopped; drops rejected")
    func hiddenWhenStopped() async throws {
        let stopped = AgentsSessionsModule(
            adapters: AgentAdapters([LaunchAdapter()]), terminals: TerminalAdapters([]), homeDirectory: home)
        #expect(stopped.dropZones.map(\.id) == ["agents.sessions.ask"])
        #expect(!stopped.askZone.isEnabled)
        let harness = try await start()
        #expect(harness.module.askZone.isEnabled)
        await harness.module.stop()
        #expect(!harness.module.askZone.isEnabled)
        guard case .rejected = await drop(harness, [file]) else {
            Issue.record("expected rejected")
            return
        }
        #expect(harness.terminal.calls.isEmpty)
    }

    @Test("text, links and images without a file are rejected")
    func filesOnly() async throws {
        let harness = try await start()
        let payloads = [
            DropPayload(urls: [], modifiers: [], source: .dropDisplay, text: "hello"),
            DropPayload(urls: [], modifiers: [], source: .dropDisplay, url: URL(string: "https://example.com")),
            DropPayload(urls: [], modifiers: [], source: .dropDisplay, imageData: Data([1])),
            DropPayload(urls: [URL(string: "https://example.com")!], modifiers: [], source: .dropDisplay),
        ]
        for payload in payloads {
            guard case .rejected = await harness.module.askZone.handler(payload) else {
                Issue.record("expected rejected")
                continue
            }
        }
        #expect(harness.terminal.calls.isEmpty)
    }

    @Test("zone shape (Story 9.1): secondary 1 × 2 at column 3, order 10, target, ⌥ hint")
    func shape() async throws {
        let zone = try await start(["ask_cwd": "~/dev"]).module.askZone
        #expect(zone.role == .secondary)
        #expect(zone.cell == DropCell(preferredColumn: 3, preferredRow: 1, span: .init(columns: 1, rows: 2)))
        #expect(zone.order == 10)
        #expect(zone.style == .target)
        #expect(String(localized: zone.label) == "ASK AI")
        #expect(zone.releaseLine.map { String(localized: $0) } == "RELEASE TO ASK")
        #expect(zone.modifierHint?.modifiers == .option)
        #expect(zone.modifierHint.map { String(localized: $0.idle) } == "⌥ ALT FOLDER")
        #expect(zone.modifierHint.map { String(localized: $0.active) } == "ALT FOLDER")
        #expect(zone.meta.map { String(localized: $0) } == "CLAUDE · ~/DEV")
        #expect(
            zone.accessibilityLabel.map { String(localized: $0) }
                == "Ask AI, Claude Code in ~/dev, Option for alternate folder")
    }

    @Test("meta for the default folder and home")
    func meta() async throws {
        #expect(try await start().module.askMeta.resolved == "CLAUDE · FILE FOLDER")
        #expect(try await start(["ask_cwd": "home"]).module.askMeta.resolved == "CLAUDE · HOME")
        #expect(
            try await start().module.askAccessibilityLabel.resolved
                == "Ask AI, Claude Code in the file's folder, Option for alternate folder")
    }

    @Test("SEND TO card rows (Story 9.7): agent, folder dimmed by ⌥, alternate folder lit by ⌥")
    func sendToDetails() async throws {
        let details = try await start(["ask_cwd": "~/dev", "ask_alt_cwd": "~/Code"]).module.askZone.details
        #expect(details.map(\.id) == ["agent", "folder", "alt_folder"])
        #expect(details.map { String(localized: $0.label) } == ["AGENT", "FOLDER", "⌥ FOLDER"])
        #expect(details.map(\.value) == ["Claude Code", "~/dev", "~/Code"])
        #expect(details[0].emphasis == .plain)
        #expect(details[1].emphasis == .dimmedWhile(.option))
        #expect(details[2].emphasis == .litWhile(.option))
        #expect(details.filter { $0.isActive(modifiers: []) }.map(\.id) == ["agent", "folder"])
        #expect(details.filter { $0.isActive(modifiers: .option) }.map(\.id) == ["agent", "alt_folder"])
        let defaults = try await start().module.askZone.details
        #expect(defaults.map(\.value) == ["Claude Code", "File's folder", "~"])
        #expect(try await start(["ask_cwd": "home"]).module.askZone.details[1].value == "Home folder")
    }

    // MARK: Settings

    @Test("ask_* keys declared with their SPEC defaults (Romain's config keys)")
    func settingsDeclared() throws {
        let descriptors = AgentsSessionsModule.staticManifest.settings
        // The ask_* keys in Romain's config.toml: ask_default_agent, ask_cwd, ask_alt_cwd.
        for key in ["ask_default_agent", "ask_cwd", "ask_alt_cwd"] {
            let descriptor = try #require(descriptors.first { $0.key == key })
            #expect(descriptor.scope == .synced)
            #expect(!String(localized: descriptor.label).hasPrefix("agentsSessions."))
            #expect(descriptor.help.map { String(localized: $0).hasPrefix("agentsSessions.") } == false)
        }
        #expect(descriptors.first { $0.key == "ask_default_agent" }?.kind == .string(default: "claude"))
        #expect(descriptors.first { $0.key == "ask_cwd" }?.kind == .string(default: "file_folder"))
        #expect(descriptors.first { $0.key == "ask_alt_cwd" }?.kind == .path(default: "~"))
    }
}

extension LocalizedStringResource {
    fileprivate var resolved: String { String(localized: self) }
}
