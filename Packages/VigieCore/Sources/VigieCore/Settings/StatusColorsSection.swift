import AppKit
import ModuleKit
import Observation
import SwiftUI
import VigieUI

/// The contrast of a custom color against the surfaces of the current look (UX-DR13, Story 17.2).
///
/// Information only: a low ratio never blocks the choice (DESIGN "Contrast": user-configured colors are not
/// checked automatically in v1; the Settings window shows the ratio).
public struct CustomColorContrast: Equatable, Sendable {
    /// WCAG minimum for text.
    public static let textMinimum = 4.5
    /// WCAG 1.4.11 minimum for non-text meaning (glyphs, rings, bars).
    public static let nonTextMinimum = 3.0

    /// The worst ratio over the surfaces, 1...21.
    public let ratio: Double

    public init(ratio: Double) {
        self.ratio = ratio
    }

    /// The ratio of `color` against each of `surfaces`; nil without surfaces.
    public init?(color: ThemeColor, surfaces: [ThemeColor]) {
        guard !surfaces.isEmpty else { return nil }
        ratio = color.worstContrast(against: surfaces)
    }

    public var meetsText: Bool { ratio >= Self.textMinimum }
    public var meetsNonText: Bool { ratio >= Self.nonTextMinimum }

    /// `4.8:1`, one decimal, rounded down so a ratio just under a minimum never reads as passing.
    public var ratioText: String {
        let tenths = (ratio * 10).rounded(.down) / 10
        return String(format: "%.1f:1", tenths)
    }
}

/// Settings › Appearance › Status colors (Story 17.2, UX-DR13): a color per status, pace and warning role.
/// Each choice is written to `[appearance.colors]` through `ConfigStore` and its contrast against the current
/// look's surfaces is shown next to it, without blocking the choice.
public enum StatusColors {
    /// The configurable roles, in display order (SPEC §10.2: every status color, pace on / ahead, quota warning).
    public static let roles: [ColorRole] = [
        .statusIdle, .statusWorking, .statusDone, .statusBlocked, .statusFailed, .paceOn, .paceAhead, .quotaWarning,
    ]

    /// `appearance.colors.<role>`.
    public static func path(_ role: ColorRole) -> ConfigKeyPath {
        ConfigKeyPath(["appearance", "colors", role.rawValue])
    }

    /// The surfaces a status color is drawn on: the current look's panel and cards.
    static let surfaceRoles: [ColorRole] = [.surfacePanel, .surfaceCard]

    /// Catalog key of a role's label (`Config` table).
    static func labelKey(_ role: ColorRole) -> String { "config.appearance.colors.\(role.rawValue)" }
}

extension SettingsController {
    /// The custom color configured for `role` in `[appearance.colors]`, nil when none or not `#RRGGBB`.
    public func customColor(for role: ColorRole) -> ThemeColor? {
        configStore.value(StatusColors.path(role), as: String.self).flatMap(ThemeColor.init(hex:))
    }

    /// The contrast of `color` against the current look's surfaces; nil while no theme is attached.
    public func contrast(of color: ThemeColor) -> CustomColorContrast? {
        guard let theme = theme?.theme else { return nil }
        return CustomColorContrast(
            color: color, surfaces: StatusColors.surfaceRoles.filter(theme.defines).map(theme.themeColor))
    }

    /// The contrast of the custom color of `role`, nil without a custom color or a theme.
    public func contrast(for role: ColorRole) -> CustomColorContrast? {
        customColor(for: role).flatMap(contrast(of:))
    }

    /// Writes the user's choice for `role`. Never refuses a low contrast.
    public func setCustomColor(_ color: ThemeColor, for role: ColorRole) async throws {
        do throws(ConfigError) {
            try await configStore.set(StatusColors.path(role), to: .string(color.hex))
        } catch {
            throw SettingWriteError(error)
        }
    }

    /// Back to the look's own color.
    public func resetCustomColor(for role: ColorRole) async throws {
        do throws(ConfigError) {
            try await configStore.remove(StatusColors.path(role))
        } catch {
            throw SettingWriteError(error)
        }
    }

    /// Whether the Reduce motion note shows next to Presence: macOS Reduce motion is on (UX-DR64).
    public var showsReduceMotionNote: Bool { reduceMotion() }
}

/// The Status colors block of Settings › Appearance.
struct StatusColorsSection: View {
    let controller: SettingsController

    var body: some View {
        Section {
            ForEach(StatusColors.roles, id: \.self) { role in
                StatusColorRow(controller: controller, role: role)
            }
        } header: {
            Text(SettingsText.resource("settings.section.statusColors"))
        }
    }
}

private struct StatusColorRow: View {
    let controller: SettingsController
    let role: ColorRole
    @State private var error: String?

    var body: some View {
        let custom = controller.customColor(for: role)
        let current = controller.theme?.theme.themeColor(role)
        LabeledContent {
            HStack {
                if let contrast = custom.flatMap(controller.contrast(of:)) {
                    Text(verbatim: Self.contrastText(contrast))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text(verbatim: Self.contrastText(contrast)))
                }
                ColorPicker(
                    selection: Binding(
                        get: { Self.swiftUIColor(custom ?? current) },
                        set: { newValue in apply(newValue) }),
                    supportsOpacity: false
                ) {
                    Text(SettingsText.resource(StatusColors.labelKey(role)))
                }
                .labelsHidden()
                Button {
                    Task {
                        do { try await controller.resetCustomColor(for: role) } catch {
                            self.error = Self.message(error)
                        }
                    }
                } label: {
                    Text(SettingsText.resource("settings.statusColors.reset"))
                }
                .disabled(custom == nil)
            }
        } label: {
            Text(SettingsText.resource(StatusColors.labelKey(role)))
            if let error { Text(verbatim: error).foregroundStyle(.red) }
        }
    }

    private func apply(_ color: Color) {
        guard let themeColor = Self.themeColor(color) else { return }
        error = nil
        Task {
            do { try await controller.setCustomColor(themeColor, for: role) } catch { self.error = Self.message(error) }
        }
    }

    static func contrastText(_ contrast: CustomColorContrast) -> String {
        let key =
            contrast.meetsText
            ? "settings.statusColors.contrast.text"
            : contrast.meetsNonText ? "settings.statusColors.contrast.nonText" : "settings.statusColors.contrast.low"
        return SettingsText.format(key, contrast.ratioText)
    }

    private static func message(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? SettingsText.string("settings.error.invalidValue")
    }

    private static func swiftUIColor(_ color: ThemeColor?) -> Color {
        guard let color else { return .clear }
        return Color(.sRGB, red: color.red, green: color.green, blue: color.blue)
    }

    private static func themeColor(_ color: Color) -> ThemeColor? {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return ThemeColor(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
    }
}
