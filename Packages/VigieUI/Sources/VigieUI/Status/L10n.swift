import Foundation

/// Lookups in the VigieUI String Catalog (AD-15). Keys are dynamic here, so this goes through `Bundle`.
enum L10n {
    /// The localized value for `key`, or `key` itself when the catalog has no entry.
    static func string(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }

    /// A catalog value used as a `String(format:)` pattern (`%@`, `%lld`, positional `%1$@`).
    static func format(_ key: String, _ arguments: any CVarArg...) -> String {
        String(format: string(key), locale: catalogLocale, arguments: arguments)
    }

    /// A catalog entry as a resource, so views and callers resolve it in their own locale.
    static func resource(_ key: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(key), bundle: .atURL(Bundle.module.bundleURL))
    }

    /// The locale the catalog strings resolve in (its first preferred localization), so numbers and
    /// durations formatted next to catalog words use the same language.
    static var catalogLocale: Locale {
        Locale(identifier: Bundle.module.preferredLocalizations.first ?? "en")
    }
}
