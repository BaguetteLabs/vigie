/// One block a module adds to Settings › General › Copy diagnostics (Story 17.4, AD-16).
///
/// Plain, already formatted lines (`claude  version=2.1.3  support=supported  hook=connected`). They must never
/// hold secret values, tokens, note titles or bodies, raw script output or environment variables (AD-9, AD-26);
/// the host also runs every line through its redaction gate before the text leaves the process.
public struct ModuleDiagnostics: Sendable, Equatable {
    /// Where the host prints the lines.
    public enum Section: String, Sendable, Equatable {
        /// Under `== MODULES ==`, after the module list (e.g. script ids and confirmation state).
        case modules
        /// Under `== AGENTS ==` (adapter versions, support status, hooks, terminals).
        case agents
    }

    public let section: Section
    public let lines: [String]

    public init(section: Section, lines: [String]) {
        self.section = section
        self.lines = lines
    }
}

/// A running module that contributes to Copy diagnostics (Story 17.4). Optional: the host asks only modules
/// that conform, only while they run, and only when the user clicks the button.
@MainActor
public protocol DiagnosticsContributing: AnyObject {
    /// In-process state only: no network, no process launch, no Keychain prompt.
    func diagnostics() async -> [ModuleDiagnostics]

    /// Secret values this module holds (e.g. script `secret` settings) for the host's exact-match scrub. They are
    /// used only to redact the text and never printed. Default: none.
    func diagnosticsSecretValues() async -> [String]
}

extension DiagnosticsContributing {
    public func diagnosticsSecretValues() async -> [String] { [] }
}
