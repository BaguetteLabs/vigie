import Foundation

/// How far an agent adapter supports the installed CLI (AD-23 version gate, FR85, NFR18). Computed by
/// `AgentAdapter.support(for:)` from `detectVersion(context:)`. `agents.sessions` drops every normalized event of an
/// adapter whose support does not `emitsEvents`, and raises `unsupported` as a setup-problem alert.
public enum AdapterSupport: Hashable, Sendable {
    /// Inside the fixture-tested range.
    case supported(AgentVersion)
    /// Outside the tested range but accepted by the adapter's tolerance rule (e.g. a newer patch of a tested
    /// minor). Events flow; the adapter's settings show a warning.
    case assumed(AgentVersion)
    /// Outside the tested range and the tolerance rule, or a version that cannot be parsed. No events.
    case unsupported(AgentVersion)
    /// The CLI was not found. No events.
    case notInstalled

    /// Whether normalized events from this adapter may reach the `SessionStore`.
    public var emitsEvents: Bool {
        switch self {
        case .supported, .assumed: true
        case .unsupported, .notInstalled: false
        }
    }

    /// The detected version, nil when not installed.
    public var version: AgentVersion? {
        switch self {
        case .supported(let version), .assumed(let version), .unsupported(let version): version
        case .notInstalled: nil
        }
    }
}

/// An adapter's fixture-tested CLI versions and its tolerance rule (AD-23). One constant per adapter, updated
/// whenever fixtures for a new CLI version are recorded.
public struct VersionSupportMatrix: Hashable, Sendable {
    /// Versions replayed against recorded fixtures. Each upper bound is a version with a fixture folder.
    public let testedRanges: [ClosedRange<AgentVersion.Semver>]
    /// When true, a version with the same `major.minor` as a tested range's upper bound and a higher patch is
    /// `assumed` rather than `unsupported`.
    public let assumesNewerPatches: Bool

    public init(testedRanges: [ClosedRange<AgentVersion.Semver>], assumesNewerPatches: Bool) {
        self.testedRanges = testedRanges
        self.assumesNewerPatches = assumesNewerPatches
    }

    /// nil → `notInstalled`; unparsable → `unsupported`; in a tested range → `supported`; a newer patch of a
    /// tested range's upper `major.minor` (when allowed) → `assumed`; anything else → `unsupported`.
    public func support(for version: AgentVersion?) -> AdapterSupport {
        guard let version else { return .notInstalled }
        guard let semver = version.semver else { return .unsupported(version) }
        if testedRanges.contains(where: { $0.contains(semver) }) { return .supported(version) }
        if assumesNewerPatches,
            testedRanges.contains(where: {
                $0.upperBound.major == semver.major && $0.upperBound.minor == semver.minor
                    && semver.patch > $0.upperBound.patch
            })
        {
            return .assumed(version)
        }
        return .unsupported(version)
    }
}
