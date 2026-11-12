import Foundation

/// A `vigie://install` link the app received (AD-18 "Install from link", AD-20, Story 12.9), handed to the
/// integrations module through ``ScriptFolderService/installRequests()``. Nothing has been fetched yet: the module
/// downloads the file (HTTPS only), verifies it and shows the Script Confirmation.
public struct ScriptInstallRequest: Hashable, Sendable {
    /// The link's action: `vigie://install?…`.
    public static let action = "install"
    /// Query parameter naming the script file's URL.
    public static let fileParameter = "url"
    /// Optional query parameter naming the detached signature's URL (default `<url>.sig`).
    public static let signatureParameter = "sig"

    /// The `url` parameter as given: any scheme, so the module can refuse a non-HTTPS one with a visible message.
    public let fileURL: URL
    /// The `sig` parameter, if any (any scheme; the module fetches HTTPS only).
    public let signatureURL: URL?
    /// Minted by the host from the open-URL event (the user clicked the link), so the module may bring Settings
    /// forward on its Script Confirmation (AD-13). Nil in tests.
    public let intent: UserIntent?

    public init(fileURL: URL, signatureURL: URL? = nil, intent: UserIntent? = nil) {
        self.fileURL = fileURL
        self.signatureURL = signatureURL
        self.intent = intent
    }

    /// Why a link is not an install request. The host logs it and ignores the link (nothing is shown).
    public enum LinkProblem: Error, Equatable, Sendable {
        /// Not this app's scheme (`vigie`, or `vigie-dev` in dev builds, AD-17).
        case otherScheme(String?)
        /// A host or path other than `install`.
        case unknownAction(String)
        /// No `url` parameter, or an empty one.
        case missingFileURL
        /// A `url` parameter that is not a URL with a scheme.
        case unreadableFileURL(String)
    }

    /// Parses `<scheme>://install?url=<URL>[&sig=<URL>]` (also `<scheme>:install?…`). The parameter values must be
    /// percent-encoded in the link; they are decoded here. A `sig` that is not a URL is dropped (the file is then
    /// treated as unsigned, with the stronger warning).
    public static func parse(link: URL, scheme: String, intent: UserIntent? = nil) -> Result<Self, LinkProblem> {
        guard link.scheme?.lowercased() == scheme.lowercased() else { return .failure(.otherScheme(link.scheme)) }
        guard let components = URLComponents(url: link, resolvingAgainstBaseURL: false) else {
            return .failure(.unknownAction(link.absoluteString))
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let action: String
        if let host = components.host, !host.isEmpty {
            guard path.isEmpty else { return .failure(.unknownAction(host + "/" + path)) }
            action = host
        } else {
            action = path
        }
        guard action.lowercased() == Self.action else { return .failure(.unknownAction(action)) }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        guard let raw = value(fileParameter) else { return .failure(.missingFileURL) }
        guard let fileURL = URL(string: raw), fileURL.scheme != nil else { return .failure(.unreadableFileURL(raw)) }
        let signatureURL = value(signatureParameter).flatMap(URL.init(string:)).flatMap { $0.scheme == nil ? nil : $0 }
        return .success(ScriptInstallRequest(fileURL: fileURL, signatureURL: signatureURL, intent: intent))
    }
}

/// Where a script installed from a link came from (Story 12.9), kept per file on this Mac in `local.toml`
/// (`[scripts.sources."modules/<file>"]`). Story 12.10's update checks re-fetch ``url``.
public struct ScriptSourceRecord: Hashable, Sendable {
    /// The HTTPS URL the file was downloaded from (after redirects).
    public var url: URL
    /// The signature URL that was fetched, or nil when none was found.
    public var signatureURL: URL?
    public var installedAt: Date

    public init(url: URL, signatureURL: URL?, installedAt: Date) {
        self.url = url
        self.signatureURL = signatureURL
        self.installedAt = installedAt
    }
}
