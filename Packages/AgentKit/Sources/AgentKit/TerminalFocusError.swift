import Foundation

/// Why a terminal adapter could not select the session's tab (SPEC §7.1.1, Story 5.1).
public enum TerminalFocusError: Error, Equatable, Sendable {
    /// A permission is missing (e.g. Automation for the terminal app). The app has already been activated
    /// (app-level fallback); `agents.sessions` raises `SETUP · PERMISSION` for `permission`.
    case permissionRequired(Permission)
}

/// A terminal adapter that can report a missing permission as a typed error instead of folding it into
/// `FocusResult` (Story 5.1). `focus(_:context:)` stays the protocol entry point: it calls `attemptFocus` and
/// maps `permissionRequired` to `.appOnly`.
public protocol PermissionReportingTerminalAdapter: TerminalAdapter {
    /// Like `focus`, but throws `TerminalFocusError.permissionRequired` (after activating the app) when the
    /// terminal refused the Apple Event for lack of permission. Every other failure activates the app and
    /// returns `.appOnly`.
    func attemptFocus(_ locator: TerminalLocator, context: any AdapterContext) async throws(TerminalFocusError)
        -> FocusResult
}

extension PermissionReportingTerminalAdapter {
    /// Default `focus`: `attemptFocus`, with a missing permission reported as `.appOnly` (the app is in front).
    public func focus(_ locator: TerminalLocator, context: any AdapterContext) async -> FocusResult {
        do {
            return try await attemptFocus(locator, context: context)
        } catch {
            context.log.notice("Focus fell back to the app: permission missing")
            return .appOnly
        }
    }
}

/// AppleScript string literal helpers for terminal adapters.
public enum AppleScriptText {
    /// `value` as a quoted AppleScript string literal (backslashes and quotes escaped).
    public static func literal(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
