import AppKit
import Observation
import SwiftUI

/// Reads the macOS accessibility display settings. Injectable so tests drive the flags (Story 2.15).
@MainActor public protocol AccessibilitySettingsProvider: AnyObject {
    func currentAdjustments() -> AccessibilityAdjustments
}

/// The live macOS settings from `NSWorkspace` (Increase contrast, Reduce transparency, Reduce motion).
@MainActor public final class SystemAccessibilitySettings: AccessibilitySettingsProvider {
    public init() {}

    public func currentAdjustments() -> AccessibilityAdjustments {
        let workspace = NSWorkspace.shared
        return AccessibilityAdjustments(
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            reduceMotion: workspace.accessibilityDisplayShouldReduceMotion)
    }
}

/// Holds the active theme for the app (AD-14). Owned by the host and injected into views with
/// ``SwiftUICore/View/vigieTheme(_:)``; views read it with `@Environment(\.vigieTheme)`.
///
/// `theme` is the look the panels use (follows `mode`, live with macOS when `system`);
/// `islandTheme` is always the dark look of the active variant (the physical notch is black).
@MainActor @Observable public final class ThemeController {
    public private(set) var library: ThemeLibrary
    public var variantID: String { didSet { resolve() } }
    public var mode: AppearanceMode { didSet { resolve() } }
    /// The presence level the user chose.
    public var presence: PresenceLevel { didSet { resolve() } }
    public var overrides: ColorOverrides { didSet { resolve() } }

    /// macOS appearance (dark/light), updated live while observing.
    public private(set) var systemIsDark: Bool
    /// macOS accessibility display settings, updated live while observing.
    public private(set) var accessibility: AccessibilityAdjustments

    public private(set) var theme: Theme
    public private(set) var islandTheme: Theme
    public private(set) var problems: [ThemeProblem]

    @ObservationIgnored private var observers = ObserverBag()
    @ObservationIgnored private let accessibilityProvider: any AccessibilitySettingsProvider

    public init(
        library: ThemeLibrary,
        variantID: String = ThemeLibrary.defaultVariantID,
        mode: AppearanceMode = .system,
        presence: PresenceLevel = .full,
        overrides: ColorOverrides = .none,
        systemIsDark: Bool = false,
        accessibility: AccessibilityAdjustments = .none,
        accessibilityProvider: (any AccessibilitySettingsProvider)? = nil
    ) {
        self.accessibilityProvider = accessibilityProvider ?? SystemAccessibilitySettings()
        self.library = library
        self.variantID = variantID
        self.mode = mode
        self.presence = presence
        self.overrides = overrides
        self.systemIsDark = systemIsDark
        self.accessibility = accessibility
        self.theme = .empty
        self.islandTheme = .empty
        self.problems = []
        resolve()
    }

    /// The look panels use: the forced mode, or the macOS appearance in `system` mode.
    public var activeLook: Look {
        switch mode {
        case .dark: .dark
        case .light: .light
        case .system: systemIsDark ? .dark : .light
        }
    }

    /// Calm when the user chose calm or macOS Reduce motion is on (Stories 2.15 / 18.3 use it).
    public var effectivePresence: PresenceLevel {
        accessibility.reduceMotion ? .calm : presence
    }

    public func replaceLibrary(_ library: ThemeLibrary) {
        self.library = library
        resolve()
    }

    /// Records a macOS appearance change.
    public func updateSystemAppearance(isDark: Bool) {
        guard isDark != systemIsDark else { return }
        systemIsDark = isDark
        resolve()
    }

    /// Re-reads the accessibility flags from the provider and re-resolves both themes when any of the
    /// three changed. Called on `accessibilityDisplayOptionsDidChangeNotification` while observing.
    public func refreshAccessibility() {
        updateAccessibility(accessibilityProvider.currentAdjustments())
    }

    /// Records a macOS accessibility display settings change.
    public func updateAccessibility(_ adjustments: AccessibilityAdjustments) {
        guard adjustments != accessibility else { return }
        accessibility = adjustments
        resolve()
    }

    /// Starts following macOS appearance and accessibility settings. Reads the current values first.
    public func startObservingSystem() {
        guard observers.isEmpty else { return }
        readSystem()
        let center = DistributedNotificationCenter.default()
        observers.add(
            center: center,
            token: center.addObserver(
                forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.readSystem() }
            })
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.add(
            center: workspaceCenter,
            token: workspaceCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.readSystem() }
            })
        if let app = NSApp {
            observers.keyValue = app.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.readSystem() }
            }
        }
    }

    public func stopObservingSystem() {
        observers = ObserverBag()
    }

    private func readSystem() {
        updateSystemAppearance(isDark: Self.currentSystemIsDark())
        refreshAccessibility()
    }

    /// Reads the macOS appearance: the app's effective appearance when running, else the global default.
    public static func currentSystemIsDark() -> Bool {
        if let app = NSApp {
            return app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    private func resolve() {
        let main = library.resolve(
            themeID: variantID, look: activeLook, overrides: overrides, accessibility: accessibility)
        let island = library.resolve(
            themeID: variantID, look: .dark, overrides: overrides, accessibility: accessibility)
        var mainTheme = main.theme
        mainTheme.presence = effectivePresence
        var islandResolved = island.theme
        islandResolved.presence = effectivePresence
        theme = mainTheme
        islandTheme = islandResolved
        problems = library.problems + main.problems
    }
}

/// Notification tokens and KVO observation, released together.
private final class ObserverBag {
    private var tokens: [(NotificationCenter, any NSObjectProtocol)] = []
    var keyValue: NSKeyValueObservation?

    var isEmpty: Bool { tokens.isEmpty && keyValue == nil }

    func add(center: NotificationCenter, token: any NSObjectProtocol) {
        tokens.append((center, token))
    }

    deinit {
        for (center, token) in tokens { center.removeObserver(token) }
        keyValue?.invalidate()
    }
}

// MARK: - Environment

private struct VigieThemeKey: EnvironmentKey {
    static let defaultValue: Theme = ThemeEnvironmentDefaults.theme
}

enum ThemeEnvironmentDefaults {
    /// Chrome Hologram dark from the bundle, so previews and un-themed views still draw.
    static let theme: Theme = {
        guard let library = try? ThemeLoader.loadBundled() else { return .empty }
        return library.resolve(themeID: ThemeLibrary.defaultVariantID, look: .dark).theme
    }()
}

extension EnvironmentValues {
    /// The active resolved theme. Views read colors, metrics, motion and fonts only from here (AD-14).
    public var vigieTheme: Theme {
        get { self[VigieThemeKey.self] }
        set { self[VigieThemeKey.self] = newValue }
    }
}

extension View {
    /// Injects a resolved theme (`controller.theme` for panels, `controller.islandTheme` for the notch).
    public func vigieTheme(_ theme: Theme) -> some View {
        environment(\.vigieTheme, theme)
    }
}
