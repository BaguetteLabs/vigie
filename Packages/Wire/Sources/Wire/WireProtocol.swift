import Foundation

/// The versioned wire format shared by the app and the `vigie` CLI (AD-7).
public enum WireProtocol {
    /// Current wire protocol version. Bumped only with a migration path (AD-7).
    public static let version = 1

    /// Localized human-readable protocol name (AD-15 sample lookup).
    public static var localizedName: String {
        String(localized: "wire.sample.protocolName", bundle: .module)
    }
}
