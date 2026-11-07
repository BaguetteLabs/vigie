import AgentKit
import Foundation

/// Terminal.app support (SPEC §7.1.1, Story 5.2): the session's tab is found by its `tty` over AppleScript.
public struct TerminalAppAdapter: PermissionReportingTerminalAdapter {
    public static let bundleID = "com.apple.Terminal"

    /// Locator field keys.
    public enum Field {
        /// The session's controlling terminal, e.g. `/dev/ttys003`.
        public static let tty = "tty"
        /// Terminal.app's `TERM_SESSION_ID` (informational; AppleScript cannot address a tab by it).
        public static let sessionID = "term_session_id"
    }

    /// Text the focus script returns.
    enum Outcome {
        static let found = "found"
        static let notFound = "notfound"
        static let notRunning = "notrunning"
    }

    public let id: TerminalID = "terminal"
    public var name: LocalizedStringResource { L10n.resource("terminal.adapter.name") }
    public let bundleIDs = [TerminalAppAdapter.bundleID]
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
        env["TERM_PROGRAM"] == "Apple_Terminal"
    }

    /// Pure: stores the normalized tty (and `TERM_SESSION_ID` when present). nil without a usable tty.
    public func capture(env: [String: String], pid: Int32?, tty: String?) -> TerminalLocator? {
        guard let tty = tty.flatMap(TTY.normalized) else { return nil }
        var fields = [Field.tty: tty]
        if let session = env["TERM_SESSION_ID"], !session.isEmpty { fields[Field.sessionID] = session }
        return TerminalLocator(terminalID: id, fields: fields)
    }

    public func attemptFocus(_ locator: TerminalLocator, context: any AdapterContext) async throws(TerminalFocusError)
        -> FocusResult
    {
        guard let tty = locator.fields[Field.tty].flatMap(TTY.normalized) else {
            return await activateApp()
        }
        let output: String?
        do {
            output = try await scripts.run(source: Self.focusScript(tty: tty))
        } catch let error as AppleScriptError where error.isPermissionDenied {
            context.log.notice("Terminal.app refused Apple Events (\(error.number))")
            _ = await activateApp()
            throw .permissionRequired(.automation(bundleID: Self.bundleID))
        } catch {
            context.log.error("Terminal.app focus script failed: \(String(describing: error), privacy: .public)")
            return await activateApp()
        }
        switch output {
        case Outcome.found: return .exact
        case Outcome.notFound: return .appOnly  // the script already activated Terminal.app
        default: return await activateApp()
        }
    }

    private func activateApp() async -> FocusResult {
        await activator.activate(bundleIDs: bundleIDs) ? .appOnly : .failed(reason: "Terminal.app is not available")
    }

    /// Selects the tab whose `tty` is `tty`, raises its window and activates Terminal.app; activates the app
    /// alone when no tab matches. Never launches Terminal.app (`is running` sends no Apple Event).
    static func focusScript(tty: String) -> String {
        """
        if application id "\(bundleID)" is not running then return "\(Outcome.notRunning)"
        tell application id "\(bundleID)"
            repeat with w in windows
                try
                    repeat with t in tabs of w
                        if tty of t is \(AppleScriptText.literal(tty)) then
                            set selected of t to true
                            set index of w to 1
                            activate
                            return "\(Outcome.found)"
                        end if
                    end repeat
                end try
            end repeat
            activate
            return "\(Outcome.notFound)"
        end tell
        """
    }
}

/// tty path validation shared by capture and focus.
enum TTY {
    /// `/dev/<name>` for `ttys003` or `/dev/ttys003`; nil for anything else (`??`, empty, odd characters), so
    /// nothing unexpected ever reaches a script.
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
