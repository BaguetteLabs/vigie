import Foundation

/// Generic agent ids (AD-5, FR86): a session reported by `vigie agent --agent <agent>` belongs to
/// `AgentID("generic.<agent>")`, so its identity is `generic.<agent>:<session>`. `<agent>` has the adapter id
/// shape, so the id never contains `:` and `SessionKey.init?(_:)` splits it at its first colon. No adapter is
/// ever registered under a generic id.
extension AgentID {
    /// `generic.`
    public static let genericPrefix = "generic."

    /// `generic.<agent>`; nil when `agent` does not have the adapter id shape.
    public init?(generic agent: String) {
        self.init(Self.genericPrefix + agent)
    }

    /// True for `generic.<agent>` where `<agent>` is a valid adapter id.
    public static func isGeneric(_ value: String) -> Bool {
        guard value.hasPrefix(genericPrefix) else { return false }
        return isValid(String(value.dropFirst(genericPrefix.count)))
    }

    /// The raw `--agent` value of a generic id, e.g. `mytool` for `generic.mytool`; nil for adapter ids.
    public var genericAgentName: String? {
        guard Self.isGeneric(rawValue) else { return nil }
        return String(rawValue.dropFirst(Self.genericPrefix.count))
    }

    /// True for a `generic.<agent>` id.
    public var isGeneric: Bool { genericAgentName != nil }
}
