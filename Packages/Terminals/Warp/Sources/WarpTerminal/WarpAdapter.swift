import AgentKit
import Foundation

/// Which Warp focus technique ships (Story 5.4, `docs/decisions/spike-warp-focus.md`).
public enum WarpFocusDecision: Hashable, Sendable {
    /// Open the pane's `warp://session/<uuid>` URL (`WARP_FOCUS_URL`), then activate Warp. Spike outcome (a).
    case tabViaURL
    /// Activate Warp only (SPEC §14.1). Spike outcome (c).
    case appLevelOnly
}

/// Warp terminal adapter (SPEC §7.1.1, §14.1, AD-23, PRD FR-24). Focus opens Warp's own per-pane session URL,
/// which needs neither Accessibility nor Automation, then activates Warp; without a usable URL it activates
/// Warp only.
public struct WarpAdapter: TerminalAdapter {
    /// The shipped technique. Flip to `.appLevelOnly` if the manual check shows the URL does not switch tabs.
    public static let decision: WarpFocusDecision = .tabViaURL
    /// Whether the manual check in the spike record confirmed `decision`. Set to true once it passes.
    public static let decisionConfirmed = false

    /// The Settings › Agents line describing Warp's focus level (SPEC §14.1).
    public static var focusLevelStatement: LocalizedStringResource {
        statement(decision: decision, confirmed: decisionConfirmed)
    }

    static func statement(decision: WarpFocusDecision, confirmed: Bool) -> LocalizedStringResource {
        switch decision {
        case .appLevelOnly: L10n.resource("warp.focus.statement.appOnly")
        case .tabViaURL:
            confirmed ? L10n.resource("warp.focus.statement.tab") : L10n.resource("warp.focus.statement.tabUnverified")
        }
    }

    /// Warp's bundle ids, preferred first: Stable, the legacy id, Preview.
    public static let bundleIDCandidates = ["dev.warp.Warp-Stable", "dev.warp.Warp", "dev.warp.Warp-Preview"]
    static let previewBundleID = "dev.warp.Warp-Preview"

    /// Locator field names (spike record, "What `capture` stores").
    public enum Field {
        public static let sessionUUID = "sessionUUID"
        public static let focusURL = "focusURL"
        public static let bundleID = "bundleID"
        public static let tty = "tty"
        public static let version = "version"
    }

    private let urlOpener: any URLOpening
    private let activator: any WarpAppActivating
    private let focusDecision: WarpFocusDecision

    public init() {
        let system = WorkspaceSystem()
        self.init(urlOpener: system, activator: system)
    }

    /// `decision` is injectable for tests only; the app always uses `WarpAdapter.decision`.
    public init(
        urlOpener: any URLOpening, activator: any WarpAppActivating, decision: WarpFocusDecision = WarpAdapter.decision
    ) {
        self.urlOpener = urlOpener
        self.activator = activator
        self.focusDecision = decision
    }

    public var id: TerminalID { "warp" }
    public var name: LocalizedStringResource { L10n.resource("warp.adapter.name") }
    public var bundleIDs: [String] { Self.bundleIDCandidates }

    public func matches(env: [String: String]) -> Bool {
        env["TERM_PROGRAM"] == "WarpTerminal" || env["WARP_FOCUS_URL"] != nil
            || env["WARP_TERMINAL_SESSION_UUID"] != nil
    }

    public func capture(env: [String: String], pid: Int32?, tty: String?) -> TerminalLocator? {
        guard matches(env: env) else { return nil }
        var fields: [String: String] = [:]
        let envBundleID = env["__CFBundleIdentifier"]
        fields[Field.bundleID] =
            envBundleID.flatMap { Self.bundleIDCandidates.contains($0) ? $0 : nil } ?? Self.bundleIDCandidates[0]
        fields[Field.sessionUUID] = env["WARP_TERMINAL_SESSION_UUID"]
        fields[Field.focusURL] = env["WARP_FOCUS_URL"]
        fields[Field.version] = env["WARP_CLIENT_VERSION"] ?? env["TERM_PROGRAM_VERSION"]
        fields[Field.tty] = tty
        return TerminalLocator(terminalID: id, fields: fields)
    }

    public func focus(_ locator: TerminalLocator, context: any AdapterContext) async -> FocusResult {
        let preferred = Self.activationOrder(preferred: locator.fields[Field.bundleID])
        if focusDecision == .tabViaURL, let url = Self.sessionURL(from: locator.fields) {
            if await urlOpener.open(url) {
                // Safety net: the URL may switch the pane without raising Warp. If Warp was not running, opening
                // the URL launched it, so a miss here is not a failure.
                _ = await activateRunning(preferred)
                return .exact
            }
            context.log.notice("Warp session URL was not opened; falling back to app activation")
        }
        if await activateRunning(preferred) { return .appOnly }
        for bundleID in preferred where await activator.launch(bundleID: bundleID) {
            return .appOnly
        }
        return .failed(reason: "Warp is not installed or could not be activated")
    }

    // MARK: Ask AI (Story 9.6)

    public func openTab(argv: [String], cwd: URL?, context: any AdapterContext) async throws {
        _ = try await openTab(argv: argv, cwd: cwd, typedText: nil, context: context)
    }

    /// Warp has no scripting: opens `warp://action/new_tab?path=<cwd>` (a new tab in the folder, no permission
    /// needed), brings Warp forward and returns `.commandNotRun` so the caller copies the command line
    /// (`docs/decisions/ask-ai-launch.md`). Never throws.
    public func openTab(argv: [String], cwd: URL?, typedText: String?, context: any AdapterContext) async throws
        -> OpenTabOutcome
    {
        let order = Self.bundleIDCandidates
        if let url = Self.newTabURL(cwd: cwd), await urlOpener.open(url) {
            _ = await activateRunning(order)
            return .commandNotRun
        }
        context.log.notice("Warp new-tab URL was not opened; activating Warp")
        if await activateRunning(order) { return .commandNotRun }
        for bundleID in order where await activator.launch(bundleID: bundleID) {
            return .commandNotRun
        }
        return .commandNotRun
    }

    /// `warp://action/new_tab?path=<cwd>` (`warp://action/new_tab` without a folder).
    static func newTabURL(cwd: URL?) -> URL? {
        var components = URLComponents()
        components.scheme = "warp"
        components.host = "action"
        components.path = "/new_tab"
        if let cwd { components.queryItems = [URLQueryItem(name: "path", value: cwd.path)] }
        return components.url
    }

    /// The session URL to open: `focusURL` verbatim when valid, else built from `sessionUUID` (`warppreview`
    /// scheme for the Preview channel). nil when neither identifies a pane.
    static func sessionURL(from fields: [String: String]) -> URL? {
        if let raw = fields[Field.focusURL], let url = URL(string: raw), isSessionURL(url) { return url }
        guard let uuid = fields[Field.sessionUUID], isSessionUUID(uuid) else { return nil }
        let scheme = fields[Field.bundleID] == previewBundleID ? "warppreview" : "warp"
        return URL(string: "\(scheme)://session/\(uuid)")
    }

    /// `warp://session/<uuid>` or `warppreview://session/<uuid>`, nothing else.
    static func isSessionURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "warp" || scheme == "warppreview",
            url.host == "session", url.query == nil, url.fragment == nil, url.user == nil, url.port == nil
        else { return false }
        let path = url.path
        guard path.hasPrefix("/") else { return false }
        return isSessionUUID(String(path.dropFirst()))
    }

    /// 32 hex characters, as Warp exports `WARP_TERMINAL_SESSION_UUID`.
    static func isSessionUUID(_ value: String) -> Bool {
        value.utf8.count == 32
            && value.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
    }

    /// The captured bundle id first (if it is a Warp id), then the other candidates.
    static func activationOrder(preferred: String?) -> [String] {
        guard let preferred, bundleIDCandidates.contains(preferred) else { return bundleIDCandidates }
        return [preferred] + bundleIDCandidates.filter { $0 != preferred }
    }

    private func activateRunning(_ bundleIDs: [String]) async -> Bool {
        for bundleID in bundleIDs where await activator.activateRunning(bundleID: bundleID) {
            return true
        }
        return false
    }
}

enum L10n {
    static func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    }
}
