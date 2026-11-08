import AgentKit
import Foundation
import ModuleKit
import UniformTypeIdentifiers

/// Story 9.6: the Ask AI drop zone (SPEC §7.1, FR40, UX-DR70, A72). Dropping files opens a new terminal tab
/// running `ask_default_agent` in `ask_cwd` (`ask_alt_cwd` with ⌥), with the files attached or typed into an
/// unsent prompt, per `docs/decisions/ask-ai-launch.md`. No dialog.
extension AgentsSessionsModule {
    nonisolated static let askZoneID = "agents.sessions.ask"
    nonisolated static let defaultAskAgent = "claude"
    nonisolated static let defaultAskCwd = AskFolderSetting.fileFolder
    nonisolated static let defaultAskAltCwd = "~"

    /// `ask_default_agent`, `ask_cwd`, `ask_alt_cwd` (SPEC §11, synced).
    nonisolated static var askSettings: [SettingDescriptor] {
        [
            SettingDescriptor(
                key: "ask_default_agent",
                label: LocalizedStringResource("agentsSessions.setting.askDefaultAgent", bundle: bundle),
                kind: .string(default: defaultAskAgent),
                scope: .synced,
                help: LocalizedStringResource("agentsSessions.setting.askDefaultAgent.help", bundle: bundle)),
            SettingDescriptor(
                key: "ask_cwd",
                label: LocalizedStringResource("agentsSessions.setting.askCwd", bundle: bundle),
                kind: .string(default: defaultAskCwd),
                scope: .synced,
                help: LocalizedStringResource("agentsSessions.setting.askCwd.help", bundle: bundle)),
            SettingDescriptor(
                key: "ask_alt_cwd",
                label: LocalizedStringResource("agentsSessions.setting.askAltCwd", bundle: bundle),
                kind: .path(default: defaultAskAltCwd),
                scope: .synced,
                help: LocalizedStringResource("agentsSessions.setting.askAltCwd.help", bundle: bundle)),
        ]
    }

    // MARK: Zone

    public var dropZones: [DropZone] { [askZone] }

    /// Column 3 rows 1–2, secondary, order 10, `.target` (DESIGN drop display, Story 9.1). Files only: the
    /// handler rejects drags that carry no file.
    public var askZone: DropZone {
        DropZone(
            id: Self.askZoneID,
            label: LocalizedStringResource("agentsSessions.ask.label", bundle: Self.bundle),
            glyph: "plus",
            accentToken: "iris-2",
            role: .secondary,
            cell: DropCell(preferredColumn: 3, preferredRow: 1, span: .init(columns: 1, rows: 2)),
            order: 10,
            accepts: [.item],
            handler: { [weak self] payload in await self?.askAI(payload) ?? .rejected },
            meta: askMeta,
            releaseLine: LocalizedStringResource("agentsSessions.ask.release", bundle: Self.bundle),
            accessibilityLabel: askAccessibilityLabel,
            modifierHint: DropModifierHint(
                modifiers: .option,
                idle: LocalizedStringResource("agentsSessions.ask.hint", bundle: Self.bundle),
                active: LocalizedStringResource("agentsSessions.ask.hintActive", bundle: Self.bundle)),
            style: .target,
            isEnabled: isRunning)
    }

    /// `ask_default_agent`.
    var askAgentID: String {
        let raw = settings?.value("ask_default_agent", as: String.self)?.trimmingCharacters(in: .whitespaces)
        return raw.flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultAskAgent
    }

    var askFolderSetting: AskFolderSetting {
        AskFolderSetting(settings?.value("ask_cwd", as: String.self))
    }

    var askAltFolder: String {
        settings?.value("ask_alt_cwd", as: String.self) ?? Self.defaultAskAltCwd
    }

    /// `CLAUDE · FILE FOLDER`.
    var askMeta: LocalizedStringResource {
        let agent = askAgentID.uppercased()
        let folder = askFolderSetting.metaText(home: homeDirectory)
        return LocalizedStringResource(
            "agentsSessions.ask.meta", defaultValue: "\(agent) · \(folder)", bundle: Self.bundle)
    }

    /// "Ask AI, Claude Code in ~/dev, Option for alternate folder".
    var askAccessibilityLabel: LocalizedStringResource {
        let agent = askAgentName
        let folder = askFolderSetting.spokenText(home: homeDirectory)
        return LocalizedStringResource(
            "agentsSessions.ask.a11y", defaultValue: "Ask AI, \(agent) in \(folder), Option for alternate folder",
            bundle: Self.bundle)
    }

    var askAgentName: String {
        AgentID(askAgentID).flatMap { adapters.adapter(for: $0) }.map { String(localized: $0.name) } ?? askAgentID
    }

    // MARK: Drop

    /// The Ask AI handler. Files only; a missing agent raises the setup problem; a terminal that cannot run the
    /// command (or type the prompt) leaves the command (or the paths) on the clipboard with a readout.
    func askAI(_ payload: DropPayload) async -> DropResult {
        guard isRunning else { return .rejected }
        let files = payload.urls.filter(\.isFileURL)
        guard !files.isEmpty else { return .rejected }
        let agentRaw = askAgentID
        guard let agentID = AgentID(agentRaw), let adapter = adapters.adapter(for: agentID) else {
            reportAskNotInstalled(agent: agentRaw)
            return .failed(LocalizedStringResource("agentsSessions.ask.failed.notInstalled", bundle: Self.bundle))
        }
        let cwd = askFolder(files: files, alternate: payload.modifiers.contains(.option))
        guard let command = adapter.launchCommand(files: files, cwd: cwd) else {
            log?.notice("Ask AI: \(agentRaw, privacy: .public) has no launch command")
            return .failed(LocalizedStringResource("agentsSessions.ask.failed.noLaunch", bundle: Self.bundle))
        }
        let context = adapterContexts[agentID] ?? fallbackAdapterContext(for: adapter)
        guard let executable = await adapter.launchExecutable(for: command, context: context) else {
            reportAskNotInstalled(agent: String(localized: adapter.name))
            return .failed(LocalizedStringResource("agentsSessions.ask.failed.notInstalled", bundle: Self.bundle))
        }
        askAlert?.resolve()
        askAlert = nil

        let copyLine = ShellQuote.commandLine(
            argv: LaunchPlan(command: command, executable: executable, terminalTypesText: false).argv, cwd: cwd)
        guard let terminal = terminals.anyAdapter(for: preferredTerminal) ?? terminals.fallback,
            let terminalContext = terminalContexts[terminal.id] ?? fallbackTerminalContext
        else {
            return copyForPaste(copyLine, readout: "agentsSessions.ask.commandCopied")
        }
        let plan = LaunchPlan(command: command, executable: executable, terminalTypesText: terminal.supportsTypedText)
        do {
            let outcome = try await terminal.openTab(
                argv: plan.argv, cwd: cwd, typedText: plan.typedText, context: terminalContext)
            resolvePermissionAlerts(for: terminal.id)
            switch outcome {
            case .running:
                if let paste = plan.pasteText { return copyForPaste(paste, readout: "agentsSessions.ask.pathsCopied") }
                return .accepted
            case .commandNotRun:
                return copyForPaste(copyLine, readout: "agentsSessions.ask.commandCopied")
            }
        } catch TerminalFocusError.permissionRequired(let permission) {
            reportMissingPermission(permission, adapter: terminal)
            return copyForPaste(copyLine, readout: "agentsSessions.ask.commandCopied")
        } catch {
            log?.error("Ask AI: openTab failed: \(String(describing: error), privacy: .public)")
            return copyForPaste(copyLine, readout: "agentsSessions.ask.commandCopied")
        }
    }

    /// The tab's folder: `ask_alt_cwd` with ⌥, else `ask_cwd`; home when the folder does not exist.
    func askFolder(files: [URL], alternate: Bool) -> URL {
        let folder = AskFolderSetting.resolve(
            setting: askFolderSetting, alternate: alternate ? askAltFolder : nil, files: files, home: homeDirectory)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue
        else {
            log?.notice("Ask AI: folder missing, using home")
            return homeDirectory
        }
        return folder
    }

    private func copyForPaste(_ text: String, readout key: String) -> DropResult {
        clipboard?.copy(text, clearAfter: nil)
        return .readout(LocalizedStringResource(String.LocalizationValue(key), bundle: Self.bundle))
    }

    nonisolated static let askDedupeKey = "ask:not-installed"

    /// `SETUP · AGENT`: "Ask AI: <agent> is not installed", Open settings › Agents.
    func reportAskNotInstalled(agent: String) {
        log?.notice("Ask AI: \(agent, privacy: .public) is not installed")
        guard askAlert == nil, let notifier else { return }
        askAlert = notifier.post(Self.askNotInstalledEvent(agent: agent))
    }

    nonisolated static func askNotInstalledEvent(agent: String) -> NotifierEvent {
        NotifierEvent(
            kind: setupProblemKind,
            severity: .warn,
            title: SessionRowText.format("agentsSessions.ask.notInstalled.title", agent),
            body: string("agentsSessions.ask.notInstalled.body"),
            action: .openSettings(pane: settingsPane),
            dedupeKey: askDedupeKey,
            category: string("agentsSessions.support.category"))
    }
}

/// `ask_cwd`: `home`, `file_folder`, or a folder path (`~` expanded; a relative path is under home).
enum AskFolderSetting: Equatable, Sendable {
    nonisolated static let home = "home"
    nonisolated static let fileFolder = "file_folder"

    case homeFolder
    case filesFolder
    case path(String)

    init(_ raw: String?) {
        let value = raw?.trimmingCharacters(in: .whitespaces) ?? ""
        switch value {
        case Self.home: self = .homeFolder
        case Self.fileFolder, "": self = .filesFolder
        default: self = .path(value)
        }
    }

    /// Pure. `alternate` (the `ask_alt_cwd` value) wins when set. The file's folder is the first file's parent,
    /// or the file itself when it is a folder.
    static func resolve(setting: AskFolderSetting, alternate: String?, files: [URL], home: URL) -> URL {
        if let alternate { return expand(alternate, home: home) }
        switch setting {
        case .homeFolder: return home
        case .filesFolder:
            guard let first = files.first else { return home }
            return first.hasDirectoryPath ? first.standardizedFileURL : first.deletingLastPathComponent()
        case .path(let path): return expand(path, home: home)
        }
    }

    static func expand(_ path: String, home: URL) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == "~" { return home }
        if trimmed.hasPrefix("~/") {
            return home.appendingPathComponent(String(trimmed.dropFirst(2)), isDirectory: true)
        }
        if trimmed.hasPrefix("/") { return URL(fileURLWithPath: trimmed, isDirectory: true) }
        return home.appendingPathComponent(trimmed, isDirectory: true)
    }

    /// `~/dev` for a path under home.
    static func abbreviated(_ path: String, home: URL) -> String {
        let full = expand(path, home: home).path
        let homePath = home.path
        if full == homePath { return "~" }
        if full.hasPrefix(homePath + "/") { return "~" + full.dropFirst(homePath.count) }
        return full
    }

    /// `HOME`, `FILE FOLDER`, `~/DEV`.
    func metaText(home: URL) -> String {
        switch self {
        case .homeFolder: AgentsSessionsModule.string("agentsSessions.ask.folder.home")
        case .filesFolder: AgentsSessionsModule.string("agentsSessions.ask.folder.fileFolder")
        case .path(let path): Self.abbreviated(path, home: home).uppercased()
        }
    }

    /// "your home folder", "the file's folder", `~/dev`.
    func spokenText(home: URL) -> String {
        switch self {
        case .homeFolder: AgentsSessionsModule.string("agentsSessions.ask.folder.home.spoken")
        case .filesFolder: AgentsSessionsModule.string("agentsSessions.ask.folder.fileFolder.spoken")
        case .path(let path): Self.abbreviated(path, home: home)
        }
    }
}
