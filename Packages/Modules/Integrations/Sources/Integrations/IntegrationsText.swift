import Foundation

/// Lookups in the Integrations String Catalog (AD-15).
enum IntegrationsText {
    nonisolated static let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)

    static func resource(_ key: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(key), bundle: bundle)
    }

    /// The localized value for `key`, or `key` itself when the catalog has no entry.
    static func string(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }

    /// A catalog value used as a `String(format:)` pattern (`%lld`, positional `%1$@`).
    static func format(_ key: String, _ arguments: any CVarArg...) -> String {
        String(format: string(key), locale: catalogLocale, arguments: arguments)
    }

    static var catalogLocale: Locale {
        Locale(identifier: Bundle.module.preferredLocalizations.first ?? "en")
    }
}
