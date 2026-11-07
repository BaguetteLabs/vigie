import Foundation
import ModuleKit
import VigieUI
import Wire

/// Namespace for the host and core services (Notch Host, Registry, ConfigStore, ...).
/// Real types arrive in later stories.
public enum VigieCore {
    /// Wire protocol version the Event Server speaks (AD-7).
    public static let wireProtocolVersion = WireProtocol.version

    /// Localized sample string (AD-15 sample lookup).
    public static var localizedHostName: String {
        String(localized: "vigiecore.sample.hostName", bundle: .module)
    }
}
