/// A module's current relevance, observed by the host for closed-notch arbitration (SPEC §4.2, §5).
///
/// Ordered `hidden < ambient < active < alert`.
public enum ModuleState: Int, Comparable, Hashable, Sendable, CaseIterable, Codable {
    case hidden
    case ambient
    case active
    case alert

    public static func < (lhs: ModuleState, rhs: ModuleState) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The closed-notch sizes a module may render at (SPEC §4.2).
public enum CompactSize: Hashable, Sendable, CaseIterable, Codable {
    case icon
    case short
    case wide
}
