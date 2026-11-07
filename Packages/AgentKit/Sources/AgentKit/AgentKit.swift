@_exported import Foundation
// Adapter packages depend on AgentKit only (AD-1); the ModuleKit and Wire types the contracts use
// (`SettingDescriptor`, `ConfigDiff`, `SecretStore`, `HookPayload`, ...) come with it.
@_exported import ModuleKit
@_exported import Wire

/// Namespace for the adapter contracts (AD-23): `AgentAdapter`, `TerminalAdapter`, `UsageProvider`,
/// `AdapterContext` and the normalized `AgentEvent`s.
public enum AgentKit {
    /// Wire protocol version the adapter contracts are written against.
    public static let wireProtocolVersion = WireProtocol.version

    /// Localized sample string (AD-15 sample lookup).
    public static var localizedSampleName: String {
        String(localized: "agentkit.sample.name", bundle: .module)
    }
}

/// Errors shared by adapter contracts.
public enum AdapterError: Error, Equatable, Sendable {
    /// The adapter does not implement this optional operation.
    case notSupported
}
