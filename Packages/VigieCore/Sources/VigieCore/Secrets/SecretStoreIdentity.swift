import Foundation
import Security
import Wire

/// Where Vigie's secrets live (AD-9): access group `<TeamID>.<bundle id>`, service `<bundle id>.secrets`.
/// Dev and release builds differ by bundle id, so Vigie Dev has its own group.
public struct SecretStoreIdentity: Equatable, Sendable {
    /// The signing team; nil when the build has none (ad-hoc signed), which makes secrets unavailable.
    public let teamID: String?
    public let bundleID: String

    public init(teamID: String?, bundleID: String) {
        self.teamID = teamID
        self.bundleID = bundleID
    }

    /// The running app's team (from its code signature) and the environment's bundle id.
    public init(environment: AppEnvironment) {
        self.init(teamID: SigningTeam.current(), bundleID: environment.bundleID)
    }

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
