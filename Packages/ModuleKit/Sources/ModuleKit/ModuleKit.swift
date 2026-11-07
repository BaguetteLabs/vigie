import Foundation

/// Namespace for the module contract (NotchModule, ModuleContext, services).
/// Real types arrive in later stories (AD-1, AD-19).
public enum ModuleKit {
    /// Localized sample string (AD-15 sample lookup).
    public static var localizedSampleName: String {
        String(localized: "modulekit.sample.name", bundle: .module)
    }
}
