/// A system permission a module may need (AD-20). Requested only through `context.permissions`,
/// only when a module that declares it is enabled (SPEC §4.3).
public enum Permission: Hashable, Sendable, Codable {
    case accessibility
    case automation(bundleID: String)
    case calendar
    case notifications
    case screenRecording
}
