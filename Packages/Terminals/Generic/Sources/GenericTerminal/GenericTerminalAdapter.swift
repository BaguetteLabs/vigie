import AgentKit
import Foundation

/// The fallback terminal adapter (SPEC §7.1.1, FR44, A16): activates the terminal app a session runs in, never a
/// tab. App assembly passes it as `TerminalAdapters(fallback:)`; until Epic 5 adds per-terminal adapters every
/// Focus lands here.
///
/// The app is found in this order: the forwarded `__CFBundleIdentifier`, then the bundle id known for
/// `TERM_PROGRAM` (``knownApps``), then the nearest regular app among the agent process and its ancestors.
public struct GenericTerminalAdapter: TerminalAdapter, TerminalAppNaming {
    public static let terminalID: TerminalID = "generic"

    /// Locator fields written by ``capture(env:pid:tty:)``.
    public enum Field {
        public static let program = "program"
        public static let bundleID = "bundle_id"
        public static let pid = "pid"
    }

    /// A terminal app known by its `TERM_PROGRAM`.
    public struct KnownApp: Sendable, Equatable {
        public let program: String
        public let bundleID: String
        /// Catalog key of the app's display name.
        let nameKey: String
    }

    /// `TERM_PROGRAM` → app. Unknown programs fall back to the process ancestors.
    public static let knownApps: [KnownApp] = [
        KnownApp(program: "Apple_Terminal", bundleID: "com.apple.Terminal", nameKey: "generic.app.terminal"),
        KnownApp(program: "iTerm.app", bundleID: "com.googlecode.iterm2", nameKey: "generic.app.iterm"),
        KnownApp(program: "WarpTerminal", bundleID: "dev.warp.Warp-Stable", nameKey: "generic.app.warp"),
        KnownApp(program: "ghostty", bundleID: "com.mitchellh.ghostty", nameKey: "generic.app.ghostty"),
        KnownApp(program: "vscode", bundleID: "com.microsoft.VSCode", nameKey: "generic.app.vscode"),
    ]

    private let workspace: any TerminalWorkspace

    public init(workspace: any TerminalWorkspace = SystemTerminalWorkspace()) {
        self.workspace = workspace
    }

    public var id: TerminalID { Self.terminalID }

    public var name: LocalizedStringResource { L10n.resource("generic.adapter.name") }

    public var bundleIDs: [String] { Self.knownApps.map(\.bundleID) }

    /// Any env that names a terminal. The generic adapter is the fallback, so App assembly does not list it among
    /// the matching adapters.
    public func matches(env: [String: String]) -> Bool {
        Self.value(env, "TERM_PROGRAM") != nil || Self.value(env, "__CFBundleIdentifier") != nil
    }

    /// Pure: the program, the forwarded bundle id and the agent pid (for the ancestor walk). Nil when there is
    /// nothing to find the app by.
    public func capture(env: [String: String], pid: Int32?, tty: String?) -> TerminalLocator? {
        var fields: [String: String] = [:]
        fields[Field.program] = Self.value(env, "TERM_PROGRAM")
        fields[Field.bundleID] = Self.value(env, "__CFBundleIdentifier")
        fields[Field.pid] = pid.map(String.init)
        guard !fields.isEmpty else { return nil }
        return TerminalLocator(terminalID: id, fields: fields)
    }

    /// Activates the app without selecting a tab: `.appOnly`, or `.failed` when no app could be activated.
    public func focus(_ locator: TerminalLocator, context: any AdapterContext) async -> FocusResult {
        for bundleID in Self.candidateBundleIDs(locator) where await workspace.activateApp(bundleID: bundleID) {
            return .appOnly
        }
        if let pid = locator.fields[Field.pid].flatMap(Int32.init), await workspace.activateAncestorApp(of: pid) {
            return .appOnly
        }
        return .failed(reason: "no terminal app found")
    }

    // MARK: Ask AI (Story 9.6)

    public func openTab(argv: [String], cwd: URL?, context: any AdapterContext) async throws {
        _ = try await openTab(argv: argv, cwd: cwd, typedText: nil, context: context)
    }

    /// A terminal app cannot be told a command without its own adapter: brings the first running known terminal
    /// app forward and returns `.commandNotRun`, so the caller copies the command line
    /// (`docs/decisions/ask-ai-launch.md`). Never throws.
    public func openTab(argv: [String], cwd: URL?, typedText: String?, context: any AdapterContext) async throws
        -> OpenTabOutcome
    {
        for bundleID in bundleIDs where await workspace.activateApp(bundleID: bundleID) {
            return .commandNotRun
        }
        context.log.notice("Ask AI: no running terminal app to bring forward")
        return .commandNotRun
    }

    /// Ghostty, Warp… for the Agents terminal column (A55); the forwarded bundle id wins over `TERM_PROGRAM`.
    public func appName(env: [String: String]) -> String? {
        let bundleID = Self.value(env, "__CFBundleIdentifier")
        let program = Self.value(env, "TERM_PROGRAM")
        let app =
            Self.knownApps.first { $0.bundleID == bundleID }
            ?? Self.knownApps.first { $0.program == program }
        if let app { return String(localized: L10n.resource(String.LocalizationValue(app.nameKey))) }
        return program
    }

    /// Bundle ids to try, most specific first, without duplicates.
    static func candidateBundleIDs(_ locator: TerminalLocator) -> [String] {
        var ids: [String] = []
        if let forwarded = locator.fields[Field.bundleID] { ids.append(forwarded) }
        if let program = locator.fields[Field.program],
            let known = knownApps.first(where: { $0.program == program }), !ids.contains(known.bundleID)
        {
            ids.append(known.bundleID)
        }
        return ids
    }

    private static func value(_ env: [String: String], _ key: String) -> String? {
        guard let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

enum L10n {
    static func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    }
}
