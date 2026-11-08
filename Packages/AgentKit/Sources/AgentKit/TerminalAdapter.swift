import Foundation

/// Where a session lives inside one terminal (SPEC §7.1.1). Opaque to everything but its terminal adapter, which
/// writes and reads `fields` (e.g. Warp: `focus_url`; iTerm2: `session_id`; Terminal.app: `tty`).
public struct TerminalLocator: Hashable, Sendable, Codable {
    public let terminalID: TerminalID
    public let fields: [String: String]

    public init(terminalID: TerminalID, fields: [String: String]) {
        self.terminalID = terminalID
        self.fields = fields
    }
}

/// Outcome of a focus attempt (SPEC §7.1.1, §14.1 fallbacks).
public enum FocusResult: Hashable, Sendable {
    /// The session's own tab or pane is in front.
    case exact
    /// Only the terminal app was activated.
    case appOnly
    /// Nothing could be focused; `reason` is for logs and the activity log, never shown raw.
    case failed(reason: String)
}

/// Terminal support (SPEC §7.1.1, AD-23). Each session's terminal adapter is chosen by `matches(env:)` on its
/// captured env; the `terminal` setting is used only for `openTab` and as a fallback. Apple Events and AX calls
/// happen only in `focus` / `openTab`, which are called only from a user action.
public protocol TerminalAdapter: Sendable {
    /// `terminal`, `warp`, `ghostty`, `iterm`.
    var id: TerminalID { get }
    var name: LocalizedStringResource { get }
    /// Bundle ids of the app (all channels), used to activate it as the app-level fallback.
    var bundleIDs: [String] { get }
    /// Asked for through `context.permissions` only when this terminal is in use (AD-20). Default: none.
    var requiredPermissions: Set<Permission> { get }

    /// Pure: whether a session whose hook carried `env` runs in this terminal.
    func matches(env: [String: String]) -> Bool

    /// Pure (no Apple Events, no AX, no I/O beyond the process table): the locator stored on `session.start`.
    /// nil when the env does not identify a tab (focus then falls back to the app).
    func capture(env: [String: String], pid: Int32?, tty: String?) -> TerminalLocator?

    /// Brings the session's tab to the front; falls back to activating the app (SPEC §14.1).
    func focus(_ locator: TerminalLocator, context: any AdapterContext) async -> FocusResult

    /// Opens a new tab running `argv` in `cwd` (Ask AI). `argv[0]` is an absolute path already resolved through
    /// `ExecutableResolver`; shell quoting is this adapter's job. Default: throws `AdapterError.notSupported`.
    func openTab(argv: [String], cwd: URL?, context: any AdapterContext) async throws

    /// Whether ``openTab(argv:cwd:typedText:context:)`` can type text into the new tab without pressing Return
    /// (Story 9.6: iTerm2's `write text … newline no`). Default: false.
    var supportsTypedText: Bool { get }

    /// Ask AI (Story 9.6, `docs/decisions/ask-ai-launch.md`): opens a new tab running `argv` in `cwd`, then types
    /// `typedText` with no Return when ``supportsTypedText`` (callers pass nil otherwise). Returns whether the
    /// command runs; `.commandNotRun` asks the caller to copy the command line for the user to paste. Throws
    /// `TerminalFocusError.permissionRequired` when the terminal refused the Apple Event for lack of permission.
    /// Default: ``openTab(argv:cwd:context:)``, then `.running`.
    func openTab(argv: [String], cwd: URL?, typedText: String?, context: any AdapterContext) async throws
        -> OpenTabOutcome
}

/// What ``TerminalAdapter/openTab(argv:cwd:typedText:context:)`` achieved.
public enum OpenTabOutcome: Hashable, Sendable {
    /// A new tab (or window) runs the command; `typedText`, if any, was typed.
    case running
    /// The terminal cannot run a command (Warp, the generic fallback): it is in front (Warp: a new tab in `cwd`),
    /// and the caller copies the command line for the user to paste.
    case commandNotRun
}

extension TerminalAdapter {
    public var requiredPermissions: Set<Permission> { [] }

    public func openTab(argv: [String], cwd: URL?, context: any AdapterContext) async throws {
        throw AdapterError.notSupported
    }

    public var supportsTypedText: Bool { false }

    public func openTab(argv: [String], cwd: URL?, typedText: String?, context: any AdapterContext) async throws
        -> OpenTabOutcome
    {
        try await openTab(argv: argv, cwd: cwd, context: context)
        return .running
    }
}

/// POSIX shell quoting for terminal adapters and the copied command line (Story 9.6).
public enum ShellQuote {
    /// `value` in single quotes, `'` written as `'\''`: spaces, `"`, `$`, backticks and globs stay literal.
    public static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// `cd '<cwd>' && '<argv0>' '<arg>' …` (no `cd` without a folder).
    public static func commandLine(argv: [String], cwd: URL?) -> String {
        let command = argv.map(quote).joined(separator: " ")
        guard let cwd else { return command }
        return "cd \(quote(cwd.path)) && \(command)"
    }
}
