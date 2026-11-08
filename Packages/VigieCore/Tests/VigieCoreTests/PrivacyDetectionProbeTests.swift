import CoreGraphics
import Foundation
import Testing

@testable import VigieCore

/// Story 21.1: the spike's prototype heuristics, on window-list fixtures.
@Suite struct PrivacyDetectionProbeTests {
    /// The list at rest on the spike Mac without Screen Recording: names blank except the Window Server's.
    static let atRest: [WindowSnapshot] = [
        WindowSnapshot(owner: "Window Server", name: "Menubar", layer: 24, sharingState: 1),
        WindowSnapshot(owner: "Centre de contrôle", layer: 25),
        WindowSnapshot(owner: "Warp", layer: 0),
        WindowSnapshot(owner: "Brave Browser", layer: 0),
        WindowSnapshot(owner: "Finder", layer: 0),
    ]

    @Test func nothingAtRest() {
        #expect(PrivacyDetectionProbe.evaluate(Self.atRest, mode: .ownerHeuristic) == .notDetected)
        #expect(PrivacyDetectionProbe.evaluate(Self.atRest, mode: .titleHeuristic) == .notDetected)
    }

    @Test func ownerHeuristicFiresForAnOpenConferencingAppEvenWhenNotSharing() {
        // The false positive that rules it out: Zoom open, no share.
        let windows = Self.atRest + [WindowSnapshot(owner: "zoom.us", layer: 0)]
        #expect(
            PrivacyDetectionProbe.evaluate(windows, mode: .ownerHeuristic) == .possiblySharing(evidence: ["zoom.us"]))
    }

    @Test func ownerHeuristicIgnoresMenuBarAndPanelLayers() {
        let windows = [WindowSnapshot(owner: "zoom.us", layer: 25)]
        #expect(PrivacyDetectionProbe.evaluate(windows, mode: .ownerHeuristic) == .notDetected)
    }

    @Test func titleHeuristicMatchesSharingBars() {
        let windows =
            Self.atRest + [
                WindowSnapshot(owner: "Google Chrome", name: "meet.google.com is sharing your screen.", layer: 0)
            ]
        let verdict = PrivacyDetectionProbe.evaluate(windows, mode: .titleHeuristic)
        #expect(verdict.isSharing)
    }

    @Test func titleHeuristicIsUnavailableWithoutScreenRecording() async {
        let probe = PrivacyDetectionProbe(
            mode: .titleHeuristic, windows: { [WindowSnapshot(owner: "zoom.us", name: "zoom share toolbar window")] },
            hasScreenRecording: { false })
        #expect(await probe.detect() == .unavailable)
        #expect(probe.requiredPermission == .screenRecording)
    }

    @Test func ownerHeuristicNeedsNoPermission() async {
        let probe = PrivacyDetectionProbe(
            mode: .ownerHeuristic, windows: { [] }, hasScreenRecording: { false })
        #expect(probe.requiredPermission == nil)
        #expect(await probe.detect() == .notDetected)
    }

    @Test func defaultDetectorNeverDetects() async {
        #expect(await NoScreenSharingDetection().detect() == .notDetected)
        #expect(NoScreenSharingDetection().requiredPermission == nil)
    }

    /// Runs both heuristics on this Mac's real window list (the spike's "at rest" record). It asserts only
    /// that the query works; `VIGIE_PRIVACY_PROBE=1` prints what it returned.
    @Test func probeRunsOnTheRealWindowList() async {
        let windows = PrivacyDetectionProbe.systemWindows()
        let owner = await PrivacyDetectionProbe(mode: .ownerHeuristic).detect()
        let title = await PrivacyDetectionProbe(mode: .titleHeuristic).detect()
        if ProcessInfo.processInfo.environment["VIGIE_PRIVACY_PROBE"] == "1" {
            let named = windows.filter { $0.name != nil }.count
            print("privacy probe: \(windows.count) windows, \(named) named; owner=\(owner) title=\(title)")
        }
        #expect(owner != .unavailable)
    }
}
