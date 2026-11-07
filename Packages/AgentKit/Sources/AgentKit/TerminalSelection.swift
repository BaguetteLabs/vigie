import Foundation

/// Story 5.1 (AD-23): choosing a session's terminal adapter once, on `session.start`.
extension TerminalAdapters {
    /// A registered adapter or the fallback with this id.
    public func anyAdapter(for id: TerminalID) -> (any TerminalAdapter)? {
        if let adapter = adapter(for: id) { return adapter }
        if let fallback, fallback.id == id { return fallback }
        return nil
    }

    /// The adapter for a session whose hook carried `env`: the first `matches(env:)`; else, when the env names no
    /// terminal at all (no `TERM_PROGRAM`, no `__CFBundleIdentifier`), the adapter whose id is `preferred` (the
    /// `terminal` setting); else ``fallback``. An env that names an unsupported terminal goes to the fallback,
    /// which activates that app, rather than to the preferred terminal.
    public func select(env: [String: String], preferred: TerminalID?) -> (any TerminalAdapter)? {
        if let match = matching(env: env) { return match }
        if !Self.namesTerminal(env), let preferred, let adapter = adapter(for: preferred) { return adapter }
        return fallback
    }

    /// Whether `env` identifies a terminal app (`TERM_PROGRAM` or `__CFBundleIdentifier`, non-empty).
    public static func namesTerminal(_ env: [String: String]) -> Bool {
        ["TERM_PROGRAM", "__CFBundleIdentifier"].contains { env[$0].map { !$0.isEmpty } ?? false }
    }
}
