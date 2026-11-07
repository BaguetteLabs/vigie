import CoreGraphics

/// `[virtual_notch]` (SPEC §5.5, §11; local): how Vigie draws its notch on a display without a hardware notch.
public struct VirtualNotchSettings: Sendable, Equatable {
    /// `virtual_notch.idle`: what the pill does when no module wants either side (FR11).
    public enum Idle: String, Sendable, CaseIterable {
        /// Shrinks to its minimum width: the notch alone, no wings.
        case shrink
        /// Hides (it comes back while the pointer is on the hover strip, and peeks still appear).
        case hide
        /// Keeps its full width, wings empty.
        case keep
    }

    /// `virtual_notch.position` (FR24).
    public enum Position: String, Sendable, CaseIterable {
        /// Centred on the display, like a hardware notch.
        case center
        /// Just left of the status items, away from app menus.
        case right
    }

    /// `virtual_notch.placement` (FR24).
    public enum Placement: String, Sendable, CaseIterable {
        /// Over the menu bar, top edge on the screen edge.
        case menuBar = "menu_bar"
        /// Just under the menu bar, so it never covers menu items.
        case below
    }

    /// `virtual_notch.style` (FR25, UX-DR76).
    public enum Style: String, Sendable, CaseIterable {
        /// Looks like a hardware notch.
        case black
        /// Matches the menu bar: `surface-vn-*` with the light role set in light appearance; the black island
        /// look in dark appearance until dark virtual-notch tokens exist (OQ15).
        case menuBar = "menu_bar"
    }

    /// Defaults from SPEC §11.
    public static let defaultWidth: CGFloat = 200

    /// `virtual_notch.width`: the notch part of the pill, in points (default 200, the MacBook notch size).
    public var width: CGFloat
    public var idle: Idle
    public var position: Position
    public var placement: Placement
    public var style: Style

    public init(
        width: CGFloat = VirtualNotchSettings.defaultWidth, idle: Idle = .shrink, position: Position = .center,
        placement: Placement = .menuBar, style: Style = .black
    ) {
        self.width = width
        self.idle = idle
        self.position = position
        self.placement = placement
        self.style = style
    }

    /// Settings from raw config values; a missing or unknown value takes its default.
    public init(width: Int?, idle: String?, position: String?, placement: String?, style: String?) {
        self.init(
            width: width.map { CGFloat(max($0, 1)) } ?? Self.defaultWidth,
            idle: idle.flatMap(Idle.init(rawValue:)) ?? .shrink,
            position: position.flatMap(Position.init(rawValue:)) ?? .center,
            placement: placement.flatMap(Placement.init(rawValue:)) ?? .menuBar,
            style: style.flatMap(Style.init(rawValue:)) ?? .black)
    }

    public static let `default` = VirtualNotchSettings()
}

extension VirtualNotchSettings {
    /// Reads `[virtual_notch]` from the config store (the App's `virtualNotch` closure).
    @MainActor
    public init(configStore: ConfigStore) {
        func string(_ key: String) -> String? {
            configStore.value(CoreSettings.path("virtual_notch", key), as: String.self)
        }
        self.init(
            width: configStore.value(CoreSettings.path("virtual_notch", "width"), as: Int.self),
            idle: string("idle"), position: string("position"), placement: string("placement"),
            style: string("style"))
    }
}
