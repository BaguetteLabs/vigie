import Foundation
import ModuleKit
import Synchronization
import Testing

@testable import VigieCore

/// A detector whose verdict the test flips.
final class FakeDetector: ScreenSharingDetecting {
    private let sharing = Mutex(false)
    private let calls = Mutex(0)
    let requiredPermission: Permission?
    init(permission: Permission? = nil) { requiredPermission = permission }
    var isSharing: Bool {
        get { sharing.withLock { $0 } }
        set { sharing.withLock { $0 = newValue } }
    }
    var detectCalls: Int { calls.withLock { $0 } }
    func detect() async -> ScreenSharingVerdict {
        calls.withLock { $0 += 1 }
        return isSharing ? .possiblySharing(evidence: ["fake"]) : .notDetected
    }
}

final class FakePermissionsService: PermissionsService {
    private let state = Mutex((requests: [Permission](), status: PermissionStatus.notDetermined))
    var requests: [Permission] { state.withLock { $0.requests } }
    func status(of permission: Permission) async -> PermissionStatus { state.withLock { $0.status } }
    func request(_ permission: Permission) async -> PermissionStatus {
        state.withLock {
            $0.requests.append(permission)
            return $0.status
        }
    }
}

@MainActor @Suite struct PrivacyConfigBridgeTests {
    let fixture = ConfigFixture()

    func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func descriptorsAreLocalAndOffByDefault() {
        let schema = ConfigSchema()
        let force = schema.entries[CoreSettings.path("privacy", "force")]
        let auto = schema.entries[CoreSettings.path("privacy", "auto")]
        #expect(force?.descriptor.scope == .local && auto?.descriptor.scope == .local)
        #expect(force?.descriptor.kind == .bool(default: false) && auto?.descriptor.kind == .bool(default: false))
    }

    @Test func forceFlipsPrivacyAndLandsInLocalToml() async throws {
        let (store, _) = try await fixture.makeStore()
        let privacy = CorePrivacyService()
        let bridge = PrivacyConfigBridge(store: store, privacy: privacy)
        bridge.start()
        #expect(!privacy.isActive)
        try await store.set(CoreSettings.path("privacy", "force"), to: .bool(true))
        try await wait { privacy.isActive }
        #expect(privacy.isActive && privacy.isForced)
        let local = (try? String(contentsOf: fixture.localURL, encoding: .utf8)) ?? ""
        let main = (try? String(contentsOf: fixture.configURL, encoding: .utf8)) ?? ""
        #expect(local.contains("force = true") && !main.contains("force = true"))
        try await store.set(CoreSettings.path("privacy", "force"), to: .bool(false))
        try await wait { !privacy.isActive }
        #expect(!privacy.isActive)
        bridge.stop()
    }

    @Test func forceFromLocalTomlAppliesAtStart() async throws {
        let (store, _) = try await fixture.makeStore(local: "[privacy]\nforce = true\n")
        let privacy = CorePrivacyService()
        let bridge = PrivacyConfigBridge(store: store, privacy: privacy)
        bridge.start()
        #expect(privacy.isActive)
        bridge.stop()
    }

    @Test func autoWithTheNullDetectorDoesNothing() async throws {
        let (store, _) = try await fixture.makeStore(local: "[privacy]\nauto = true\n")
        let privacy = CorePrivacyService()
        #expect(!privacy.detector.isAvailable)
        let permissions = FakePermissionsService()
        let bridge = PrivacyConfigBridge(
            store: store, privacy: privacy, permissions: permissions, pollInterval: .milliseconds(5))
        bridge.start()
        try await Task.sleep(for: .milliseconds(50))
        #expect(!bridge.isPolling && !privacy.isActive && permissions.requests.isEmpty)
        bridge.stop()
    }

    @Test func autoWithADetectorPollsRequestsPermissionOnceAndStops() async throws {
        let (store, _) = try await fixture.makeStore()
        let detector = FakeDetector(permission: .screenRecording)
        let privacy = CorePrivacyService(detector: detector)
        let permissions = FakePermissionsService()
        let bridge = PrivacyConfigBridge(
            store: store, privacy: privacy, permissions: permissions, pollInterval: .milliseconds(5))
        bridge.start()
        #expect(!bridge.isPolling && permissions.requests.isEmpty)  // auto off: no permission asked

        try await store.set(CoreSettings.path("privacy", "auto"), to: .bool(true))
        try await wait { detector.detectCalls >= 2 }
        #expect(bridge.isPolling)
        #expect(permissions.requests == [.screenRecording])
        #expect(!privacy.isActive)

        detector.isSharing = true
        try await wait { privacy.isDetected }
        #expect(privacy.isActive && privacy.isDetected)
        detector.isSharing = false
        try await wait { !privacy.isDetected }
        #expect(!privacy.isActive)

        detector.isSharing = true
        try await wait { privacy.isDetected }
        try await store.set(CoreSettings.path("privacy", "auto"), to: .bool(false))
        try await wait { !bridge.isPolling }
        #expect(!privacy.isDetected && !privacy.isActive)  // detected state cleared
        let calls = detector.detectCalls
        try await Task.sleep(for: .milliseconds(60))
        #expect(detector.detectCalls == calls)  // polling stopped
        #expect(permissions.requests == [.screenRecording])
        bridge.stop()
    }

    @Test func settingsRowIsDisabledWithTheCopyWhenNoDetector() async throws {
        let h = try await SettingsHarness()
        h.controller.privacy = CorePrivacyService()
        #expect(!h.controller.privacyDetectionAvailable)
        #expect(
            SettingsText.string("settings.privacy.unavailable")
                == "Screen sharing can't be detected on this macOS version.")
        #expect(
            String(localized: h.controller.rowModel(for: CoreSettings.path("privacy", "auto"))!.label)
                == "Automatic (when sharing or recording)")
        #expect(
            String(localized: h.controller.rowModel(for: CoreSettings.path("privacy", "force"))!.label) == "Force on")
        h.controller.privacy = CorePrivacyService(detector: FakeDetector())
        #expect(h.controller.privacyDetectionAvailable)
        await h.tearDown()
    }
}
