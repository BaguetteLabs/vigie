import Foundation

/// A third-party app that also draws on the notch (Story 17.5, FR-60).
public struct KnownNotchApp: Hashable, Sendable {
    public let bundleID: String
    /// The product's brand name, shown as is (not localized).
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// The maintained list of notch apps Vigie warns about (Story 17.5). Each id was checked against a primary source
/// on 2026-11-25. Matching is case-insensitive. Add an entry only with a verified bundle id.
public enum KnownNotchApps {
    public static let all: [KnownNotchApp] = [
        // project.pbxproj of TheBoredTeam/boring.notch
        KnownNotchApp(bundleID: "theboringteam.boringnotch", name: "Boring Notch"),
        // Homebrew cask history
        KnownNotchApp(bundleID: "lo.cafe.NotchNook", name: "NotchNook"),
        // project.pbxproj of Lakr233/NotchDrop
        KnownNotchApp(bundleID: "wiki.qaq.NotchDrop", name: "NotchDrop"),
        // Info.plist of wxtsky/CodeIsland
        KnownNotchApp(bundleID: "com.codeisland.app", name: "CodeIsland"),
        // Homebrew cask
        KnownNotchApp(bundleID: "com.Ebullioscopic.Atoll", name: "Atoll"),
        // Homebrew cask
        KnownNotchApp(bundleID: "com.henrikruscon.Alcove", name: "Alcove"),
        // Homebrew cask
        KnownNotchApp(bundleID: "app.vibeisland.macos", name: "Vibe Island"),
    ]

    /// The listed app with this bundle id, ignoring case.
    public static func app(forBundleID bundleID: String, in list: [KnownNotchApp] = all) -> KnownNotchApp? {
        let wanted = bundleID.lowercased()
        return list.first { $0.bundleID.lowercased() == wanted }
    }
}
