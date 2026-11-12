import AppIntents
import VigieCore

/// Vigie's Focus filter (Story 3.10, spike `docs/decisions/spike-focus-detection.md`): the user adds it under
/// System Settings › Focus › *mode* › Focus Filters. macOS runs `perform()` with the user's `silence` when that
/// Focus turns on, and with the default (`false`) when it turns off. No entitlement, permission, usage string or
/// extension target (AD-20).
///
/// It sits in the App target because App Intents metadata is extracted from the app's own sources at build time;
/// a type declared in a Swift package is not reliably picked up. It is assembly only: `perform()` forwards to
/// VigieCore's `FocusFilterMonitor`, registered with `AppDependencyManager` by `AppDelegate.init`. Strings come
/// from the App's `Localizable` String Catalog (`Resources/Localizable.xcstrings`); the English text is the key
/// so the Focus pane never shows a raw key.
struct SilenceVigieFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Silence Vigie"
    static let description: IntentDescription? = IntentDescription(
        "Keeps Vigie's peeks and sounds quiet while this Focus is on. The notch still updates.")

    @Parameter(title: "Silence Vigie", default: false)
    var silence: Bool

    @Dependency private var monitor: FocusFilterMonitor

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Silence Vigie", subtitle: silence ? "On" : "Off")
    }

    /// Offered pre-filled when the user adds the filter.
    static func suggestedFocusFilters(for context: FocusFilterSuggestionContext) async -> [SilenceVigieFilter] {
        var suggestion = SilenceVigieFilter()
        suggestion.silence = true
        return [suggestion]
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        monitor.filterDidRun(silence: silence)
        return .result()
    }
}

/// `SetFocusFilterIntent.current` for `FocusFilterMonitor.start()`: the filter of the Focus that is on now.
struct SilenceVigieFilterSource: FocusFilterSource {
    func currentSilence() async throws -> Bool? {
        do {
            return try await SilenceVigieFilter.current.silence
        } catch SetFocusFilterIntentError.notFound {
            return nil
        }
    }
}
