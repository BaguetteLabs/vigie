import Foundation
import Security
import Wire

/// Where Vigie's secrets live (AD-9): access group `<TeamID>.<bundle id>`, service `<bundle id>.secrets`.
/// Dev and release builds differ by bundle id, so Vigie Dev has its own group.
///
/// The notes key (Story 15.1) is the exception: it lives in `<TeamID>.<release bundle id>.notes`, service
/// `<release bundle id>.notes`, shared by Vigie and Vigie Dev. A dev build that cannot read that group keeps its
/// own key in its own group, service `<dev bundle id>.notes` (``KeychainSyncedKeyStore``).
public struct SecretStoreIdentity: Equatable, Sendable {
    /// The signing team; nil when the build has none (ad-hoc signed), which makes secrets unavailable.
    public let teamID: String?
    public let bundleID: String
    /// The release app's bundle id; equal to ``bundleID`` in the release build.
    public let releaseBundleID: String

    /// - Parameter releaseBundleID: the release app's bundle id; nil means `bundleID` (a release identity).
    public init(teamID: String?, bundleID: String, releaseBundleID: String? = nil) {
        self.teamID = teamID
        self.bundleID = bundleID
        self.releaseBundleID = releaseBundleID ?? bundleID
    }

    /// The running app's team (from its code signature) and the environment's bundle id.
    public init(environment: AppEnvironment) {
        self.init(
            teamID: SigningTeam.current(), bundleID: environment.bundleID,
            releaseBundleID: AppEnvironment.releaseBundleID)
    }

    /// True for Vigie Dev (its bundle id is not the release one).
    public var isDevBuild: Bool { bundleID != releaseBundleID }

    /// `<TeamID>.<release bundle id>.notes`, the notes key's group (AD-9); nil without a team.
    public var notesAccessGroup: String? { teamID.map { "\($0).\(releaseBundleID).notes" } }

    /// `<release bundle id>.notes`: the notes key's service in the shared group.
    public var notesService: String { "\(releaseBundleID).notes" }

    /// `<bundle id>.notes`: the dev build's own notes key service, in its own ``accessGroup``.
    public var ownNotesService: String { "\(bundleID).notes" }

    /// `<TeamID>.<bundle id>`; nil without a team.
    public var accessGroup: String? { teamID.map { "\($0).\(bundleID)" } }

    public var service: String { "\(bundleID).secrets" }
}

/// Reads the team identifier from the running process's code signature.
public enum SigningTeam {
    public static func current() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
            let info = info as? [String: Any],
            let team = info[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty
        else { return nil }
        return team
    }
}
