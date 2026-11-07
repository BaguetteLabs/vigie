import Foundation
import ModuleKit

/// Namespace for shared UI: theme loading, tokens, glyphs, shared components (AD-14).
/// Real types arrive in later stories.
public enum VigieUI {
    /// Localized product name (AD-15 sample lookup).
    public static var localizedAppName: String {
        String(localized: "vigieui.sample.appName", bundle: .module)
    }
}
