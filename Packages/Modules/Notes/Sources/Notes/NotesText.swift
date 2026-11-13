import Foundation

/// Lookups in the Notes String Catalog (AD-15).
enum NotesText {
    nonisolated static let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)

    static func resource(_ key: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(key), bundle: bundle)
    }

    /// `N NOTES` (plural).
    static func noteCount(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("notes.count.notes \(count)", bundle: bundle)
    }

    /// `N LOCKED`.
    static func lockedCount(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("notes.count.locked \(count)", bundle: bundle)
    }

    /// `N DOWNLOADING`.
    static func downloadingCount(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("notes.count.downloading \(count)", bundle: bundle)
    }

    /// "N notes in this folder." (plural).
    static func folderCount(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("notes.settings.count \(count)", bundle: bundle)
    }

    /// The localized value for `key`, or `key` itself when the catalog has no entry.
    static func string(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }

    /// A catalog value used as a `String(format:)` pattern (`%@`).
    static func format(_ key: String, _ arguments: any CVarArg...) -> String {
        String(format: string(key), locale: catalogLocale, arguments: arguments)
    }

    static var catalogLocale: Locale {
        Locale(identifier: Bundle.module.preferredLocalizations.first ?? "en")
    }
}
