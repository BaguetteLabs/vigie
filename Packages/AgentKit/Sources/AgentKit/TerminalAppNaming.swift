import Foundation

/// A terminal adapter that serves several apps (the generic fallback) names the app a session runs in, so the
/// Agents terminal column shows `Warp` or `iTerm2` rather than the adapter's own name (A55).
public protocol TerminalAppNaming: Sendable {
    /// The app's display name for a session whose hook carried `env`; nil when unknown.
    func appName(env: [String: String]) -> String?
}

extension TerminalHint {
    /// The terminal env keys this hint was extracted from, rebuilt so terminal adapters can run
    /// `matches(env:)` / `capture(env:pid:tty:)` on a stored session. The session id goes back under the key its
    /// terminal uses (`ITERM_SESSION_ID` for iTerm2, `WARP_TERMINAL_SESSION_UUID` for Warp, else
    /// `TERM_SESSION_ID`).
    public var environment: [String: String] {
        var env: [String: String] = [:]
        env["TERM_PROGRAM"] = program
        env["__CFBundleIdentifier"] = bundleID
        env["WARP_FOCUS_URL"] = warpFocusURL
        if let sessionID {
            switch program {
            case "iTerm.app": env["ITERM_SESSION_ID"] = sessionID
            case "WarpTerminal": env["WARP_TERMINAL_SESSION_UUID"] = sessionID
            default: env["TERM_SESSION_ID"] = sessionID
            }
        }
        if insideTmux { env["TMUX"] = "1" }
        return env
    }
}
