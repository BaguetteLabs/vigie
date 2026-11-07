import Foundation
import ModuleKit
import Wire

/// Namespace for the adapter contracts (AgentAdapter, TerminalAdapter, AdapterContext).
/// Real types arrive in later stories (AD-23).
public enum AgentKit {
    /// Wire protocol version the adapter contracts are written against.
    public static let wireProtocolVersion = WireProtocol.version

    /// Localized sample string (AD-15 sample lookup).
    public static var localizedSampleName: String {
        String(localized: "agentkit.sample.name", bundle: .module)
    }
}
