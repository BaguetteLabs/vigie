import Foundation

/// Resolved bundled themes for `#Preview`s (Chrome Hologram by default).
enum PreviewThemes {
    static func theme(_ look: Look, variant: String = ThemeLibrary.defaultVariantID) -> Theme {
        guard let library = try? ThemeLoader.loadBundled() else { return .empty }
        return library.resolve(themeID: variant, look: look).theme
    }
}

/// Sample data for `#Preview`s (not motion: elapsed times shown in labels).
enum PreviewSamples {
    static func minutes(_ count: Int) -> Duration { .seconds(count * 60) }
}
