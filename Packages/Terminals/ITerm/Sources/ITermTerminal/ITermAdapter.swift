import AgentKit
import Foundation

/// iTerm2 support (SPEC §7.1.1, Story 5.3, UX-DR69): the session is found by the UUID in `ITERM_SESSION_ID`
/// over AppleScript, which selects its window, tab and split pane.
public struct ITermAdapter: PermissionReportingTerminalAdapter {
    public static let bundleID = "com.googlecode.iterm2"

    /// Locator field keys.
    public enum Field {
        /// iTerm2's session `unique ID`: the UUID after `:` in `ITERM_SESSION_ID` (`w0t1p0:<UUID>`).
        public static let sessionID = "session_id"
        /// The session's controlling terminal, e.g. `/dev/ttys003`; used to find the session when the env
        /// carried no `ITERM_SESSION_ID`.
        public static let tty = "tty"
    }

    /// Text the focus script returns.
    enum Outcome {
        static let found = "found"
        static let notFound = "notfound"
        static let notRunning = "notrunning"
    }

    public let id: TerminalID = "iterm"
    public var name: LocalizedStringResource { L10n.resource("iterm.adapter.name") }
    public let bundleIDs = [ITermAdapter.bundleID]
    public var requiredPermissions: Set<Permission> { [.automation(bundleID: Self.bundleID)] }

    private let scripts: any AppleScriptRunning
    private let activator: any AppActivating

    public init(
        scripts: any AppleScriptRunning = NSAppleScriptRunner(),
        activator: any AppActivating = WorkspaceAppActivator()
    ) {
        self.scripts = scripts
        self.activator = activator
    }

    public func matches(env: [String: String]) -> Bool {
        if let session = env["ITERM_SESSION_ID"], !session.isEmpty { return true }
        return env["TERM_PROGRAM"] == "iTerm.app"
    }

    /// Pure: stores the session UUID and the normalized tty. nil when neither is usable.
    public func capture(env: [String: String], pid: Int32?, tty: String?) -> TerminalLocator? {
        var fields: [String: String] = [:]
        if let session = env["ITERM_SESSION_ID"].flatMap(Self.sessionUUID) { fields[Field.sessionID] = session }
        if let tty = tty.flatMap(TTY.normalized) { fields[Field.tty] = tty }
        return fields.isEmpty ? nil : TerminalLocator(terminalID: id, fields: fields)
    }

    public func attemptFocus(_ locator: TerminalLocator, context: any AdapterContext) async throws(TerminalFocusError)
        -> FocusResult
    {
        let match: Match
        if let session = locator.fields[Field.sessionID].flatMap(Self.sessionUUID) {
            match = .sessionID(session)
        } else if let tty = locator.fields[Field.tty].flatMap(TTY.normalized) {
            match = .tty(tty)
        } else {
            return await activateApp()
        }
        let output: String?
        do {
            output = try await scripts.run(source: Self.focusScript(match))
        } catch let error as AppleScriptError where error.isPermissionDenied {
            context.log.notice("iTerm2 refused Apple Events (\(error.number))")
            _ = await activateApp()
            throw .permissionRequired(.automation(bundleID: Self.bundleID))
        } catch {
            context.log.error("iTerm2 focus script failed: \(String(describing: error), privacy: .public)")
            return await activateApp()
        }
        switch output {
        case Outcome.found: return .exact
        case Outcome.notFound: return .appOnly  // the script already activated iTerm2
        default: return await activateApp()
        }
    }

    // MARK: Ask AI (Story 9.6)

    /// iTerm2 types text without Return (`write text … newline no`).
    public var supportsTypedText: Bool { true }
    /// Seconds between running the command and typing `typedText`, so the shell has handed the tty to the agent
    /// (`docs/decisions/ask-ai-launch.md`, unverified).
    static let typedTextDelay = "1.5"

    public func openTab(argv: [String], cwd: URL?, context: any AdapterContext) async throws {
        _ = try await openTab(argv: argv, cwd: cwd, typedText: nil, context: context)
    }

    /// Opens a new tab (a window when none is open) with the default profile, runs `cd <cwd> && <argv>` in it,
    /// then types `typedText` with no Return. Throws `permissionRequired` when Automation is denied (after
    /// activating the app); any other script failure is rethrown.
    public func openTab(argv: [String], cwd: URL?, typedText: String?, context: any AdapterContext) async throws
        -> OpenTabOutcome
    {
        let source = Self.openTabScript(
            command: ShellQuote.commandLine(argv: argv, cwd: cwd), typedText: typedText)
        do {
            _ = try await scripts.run(source: source)
            return .running
        } catch let error as AppleScriptError where error.isPermissionDenied {
            context.log.notice("iTerm2 refused Apple Events (\(error.number))")
            _ = await activateApp()
            throw TerminalFocusError.permissionRequired(.automation(bundleID: Self.bundleID))
        }
    }

    static func openTabScript(command: String, typedText: String?) -> String {
        let typing =
            typedText.map {
                """

                        delay \(typedTextDelay)
                        write text \(AppleScriptText.literal($0)) newline no
                """
            } ?? ""
        return """
            tell application id "\(bundleID)"
                activate
                if (count of windows) is 0 then
                    create window with default profile
                else
                    tell current window to create tab with default profile
                end if
                tell current session of current window
                    write text \(AppleScriptText.literal(command))\(typing)
                end tell
            end tell
            """
    }

    private func activateApp() async -> FocusResult {
        await activator.activate(bundleIDs: bundleIDs) ? .appOnly : .failed(reason: "iTerm2 is not available")
    }

    /// What identifies the session in the focus script.
    enum Match: Equatable {
        case sessionID(String)
        case tty(String)

        var condition: String {
            switch self {
            case .sessionID(let id): "unique ID of s is \(AppleScriptText.literal(id))"
            case .tty(let tty): "tty of s is \(AppleScriptText.literal(tty))"
            }
        }
    }

    /// Selects the matching session (split pane), its tab and its window, then activates iTerm2; activates the
    /// app alone when no session matches. Never launches iTerm2 (`is running` sends no Apple Event).
    static func focusScript(_ match: Match) -> String {
        """
        if application id "\(bundleID)" is not running then return "\(Outcome.notRunning)"
        tell application id "\(bundleID)"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if \(match.condition) then
                            tell w to select
                            tell t to select
                            tell s to select
                            activate
                            return "\(Outcome.found)"
                        end if
                    end repeat
                end repeat
            end repeat
            activate
            return "\(Outcome.notFound)"
        end tell
        """
    }

    /// The UUID in `w0t1p0:<UUID>` (or a bare UUID); nil unless it is hex digits and dashes, so nothing
    /// unexpected ever reaches a script.
    static func sessionUUID(_ raw: String) -> String? {
        let candidate = raw.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
        guard !candidate.isEmpty, candidate.count <= 64,
            candidate.unicodeScalars.allSatisfy({ $0.properties.isASCIIHexDigit || $0 == "-" })
        else { return nil }
        return candidate
    }
}

/// tty path validation shared by capture and focus.
enum TTY {
    /// `/dev/<name>` for `ttys003` or `/dev/ttys003`; nil for anything else (`??`, empty, odd characters).
    static func normalized(_ raw: String) -> String? {
        let name = raw.hasPrefix("/dev/") ? String(raw.dropFirst("/dev/".count)) : raw
        guard !name.isEmpty, name.count <= 32,
            name.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) })
        else { return nil }
        return "/dev/\(name)"
    }
}

enum L10n {
    static func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    }
}
