import CoreGraphics
import Foundation
import ModuleKit

// Story 21.1 spike prototype (docs/decisions/spike-privacy-detection.md). `PrivacyService` asks a
// `ScreenSharingDetecting`; Story 21.2 plugs in `NoScreenSharingDetection` (manual only), Story 21.3 decides
// whether the window-title heuristic is offered behind the Screen Recording permission (AD-20, AD-24).

/// What a detector concluded.
public enum ScreenSharingVerdict: Hashable, Sendable {
    /// Nothing suggests the screen is shared or recorded.
    case notDetected
    /// Something suggests it. `evidence` names what matched (owner or window title), for the log only.
    case possiblySharing(evidence: [String])
    /// The method cannot run (a permission is missing, or the macOS version offers no signal).
    case unavailable

    public var isSharing: Bool {
        if case .possiblySharing = self { return true }
        return false
    }
}

/// One way of telling whether the screen is shared or recorded. Modules never detect sharing themselves
/// (AD-24): only `PrivacyService` holds a detector.
public protocol ScreenSharingDetecting: Sendable {
    /// The permission the method needs; nil when it needs none.
    var requiredPermission: Permission? { get }
    func detect() async -> ScreenSharingVerdict
}

/// The default: no automatic detection (spike decision "manual only"). Always `.notDetected`.
public struct NoScreenSharingDetection: ScreenSharingDetecting {
    public init() {}
    public var requiredPermission: Permission? { nil }
    public func detect() async -> ScreenSharingVerdict { .notDetected }
}

/// One on-screen window as `CGWindowListCopyWindowInfo` reports it. Without the Screen Recording permission
/// `name` is nil for every other app's window (macOS 10.15+) and `sharingState` reads 0 for them.
public struct WindowSnapshot: Hashable, Sendable {
    public var owner: String
    public var ownerPID: Int32
    public var name: String?
    public var layer: Int
    public var bounds: CGRect
    /// `kCGWindowSharingState`: 0 none, 1 read-only, 2 read-write.
    public var sharingState: Int

    public init(
        owner: String, ownerPID: Int32 = 0, name: String? = nil, layer: Int = 0, bounds: CGRect = .zero,
        sharingState: Int = 0
    ) {
        self.owner = owner
        self.ownerPID = ownerPID
        self.name = name
        self.layer = layer
        self.bounds = bounds
        self.sharingState = sharingState
    }
}

/// The spike's prototype detector (Story 21.1). Two heuristics over the window list; neither uses private API.
///
/// - ``Mode/ownerHeuristic``: needs no permission. "Possibly sharing" when a normal (layer 0) window belongs
///   to a conferencing or recording app. It cannot tell an open Zoom from a Zoom that shares, so it fires
///   whenever such an app has a window: rejected for production (false positives), kept for the record.
/// - ``Mode/titleHeuristic``: needs Screen Recording (window names are blank without it). "Possibly sharing"
///   when a window title matches a known sharing indicator (Zoom's share toolbar, a browser's "is sharing your
///   screen" bar...). The patterns are unverified until Romain runs the spike checklist.
public struct PrivacyDetectionProbe: ScreenSharingDetecting {
    public enum Mode: Hashable, Sendable {
        case ownerHeuristic
        case titleHeuristic
    }

    public let mode: Mode
    private let windows: @Sendable () -> [WindowSnapshot]
    private let hasScreenRecording: @Sendable () -> Bool

    /// - Parameters:
    ///   - windows: the on-screen window list; by default ``systemWindows()``.
    ///   - hasScreenRecording: `CGPreflightScreenCaptureAccess()` by default (never prompts).
    public init(
        mode: Mode,
        windows: @escaping @Sendable () -> [WindowSnapshot] = { PrivacyDetectionProbe.systemWindows() },
        hasScreenRecording: @escaping @Sendable () -> Bool = { CGPreflightScreenCaptureAccess() }
    ) {
        self.mode = mode
        self.windows = windows
        self.hasScreenRecording = hasScreenRecording
    }

    public var requiredPermission: Permission? { mode == .titleHeuristic ? .screenRecording : nil }

    public func detect() async -> ScreenSharingVerdict {
        if mode == .titleHeuristic && !hasScreenRecording() { return .unavailable }
        return Self.evaluate(windows(), mode: mode)
    }

    /// App names (`kCGWindowOwnerName`) the owner heuristic watches.
    public static let conferencingOwners: Set<String> = [
        "zoom.us", "Microsoft Teams", "Microsoft Teams (work or school)", "Webex", "Cisco Webex Meetings",
        "OBS", "OBS Studio", "QuickTime Player", "Slack", "Google Meet", "FaceTime", "Loom",
    ]

    /// Lowercased title fragments the title heuristic matches (candidates from public reports, unverified).
    public static let sharingTitleFragments: [String] = [
        "zoom share toolbar window", "zoom share statusbar window", "sharetoolbar",
        "is sharing your screen", "is sharing a window", "is sharing this tab", "is sharing your tab",
        "sharing control bar", "huddle", "screen recording", "obs is recording",
    ]

    /// The verdict for a window list (pure; the tests feed it fixtures).
    public static func evaluate(_ windows: [WindowSnapshot], mode: Mode) -> ScreenSharingVerdict {
        let evidence: [String]
        switch mode {
        case .ownerHeuristic:
            evidence = windows.filter { $0.layer == 0 && conferencingOwners.contains($0.owner) }.map(\.owner)
        case .titleHeuristic:
            evidence = windows.compactMap { window in
                guard let name = window.name?.lowercased(), !name.isEmpty else { return nil }
                return sharingTitleFragments.contains(where: name.contains) ? "\(window.owner): \(name)" : nil
            }
        }
        let unique = Array(Set(evidence)).sorted()
        return unique.isEmpty ? .notDetected : .possiblySharing(evidence: unique)
    }

    /// The on-screen windows (`.optionOnScreenOnly`, desktop elements excluded). About 40 ms for ~70 windows
    /// on the spike Mac.
    public static func systemWindows() -> [WindowSnapshot] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []
        return list.map { info in
            let bounds = (info[kCGWindowBounds as String] as? [String: Any]).flatMap { dict in
                CGRect(dictionaryRepresentation: dict as CFDictionary)
            }
            return WindowSnapshot(
                owner: info[kCGWindowOwnerName as String] as? String ?? "",
                ownerPID: (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0,
                name: (info[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 },
                layer: info[kCGWindowLayer as String] as? Int ?? 0,
                bounds: bounds ?? .zero,
                sharingState: info[kCGWindowSharingState as String] as? Int ?? 0)
        }
    }
}
