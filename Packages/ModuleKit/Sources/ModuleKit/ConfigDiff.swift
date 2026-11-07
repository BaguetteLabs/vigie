import Foundation

/// A proposed edit to a file outside Vigie's own data (agent config), produced by adapters and applied only by
/// `IntegrationInstaller` (AD-22).
public struct ConfigDiff: Hashable, Sendable {
    /// The target file.
    public let path: URL
    /// SHA-256 (lowercase hex) of the bytes the diff was computed from; nil when the file did not exist.
    public let baseHash: String?
    public let oldText: String
    public let newText: String
    /// One-line, user-facing summary.
    public let summary: String

    public init(path: URL, baseHash: String?, oldText: String, newText: String, summary: String) {
        self.path = path
        self.baseHash = baseHash
        self.oldText = oldText
        self.newText = newText
        self.summary = summary
    }
}
