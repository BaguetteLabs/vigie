import Foundation
import ModuleKit
import Observation
import SwiftUI
import Synchronization
import VigieUI

/// The one Privacy mode state (AD-24, Story 21.2): `isActive = isForced || isDetected`.
///
/// - Sources: the user's force-on (``setForced(_:)``; Story 21.3 binds it to General › Privacy mode, the Debug
///   launch flag `-VigiePrivacy YES` sets it at launch) and automatic detection through one
///   ``ScreenSharingDetecting`` (spike 21.1: ``NoScreenSharingDetection`` until 21.3 decides otherwise).
///   ``refreshDetection()`` asks the detector once; 21.3 polls it while automatic detection is on.
/// - Surfaces read ``isActive`` (observable): the host sets `privacyActive` at every surface root, so a change
///   redraws every surface on the next frame (well under the 1 s budget).
/// - A change is not an alert: nothing is posted, no peek shows and no sound plays (UX-DR98).
/// - Modules get ``context`` (`context.privacy`): a read-only snapshot plus a change stream, usable from any
///   isolation. There is no API for a module to change the state or opt a field out.
@MainActor @Observable
public final class CorePrivacyService {
    /// True while Privacy mode is on.
    public private(set) var isActive = false
    /// The user's force-on.
    public private(set) var isForced = false
    /// The detector's last verdict says sharing.
    public private(set) var isDetected = false

    /// `context.privacy` for every module.
    public nonisolated let context: PrivacyServiceBroadcast
    public let detector: any ScreenSharingDetecting

    public init(forced: Bool = false, detector: any ScreenSharingDetecting = NoScreenSharingDetection()) {
        self.detector = detector
        self.context = PrivacyServiceBroadcast(initial: forced)
        self.isForced = forced
        self.isActive = forced
    }

    /// Forces Privacy mode on (or releases the force-on). Story 21.3's `Force on` setting.
    public func setForced(_ forced: Bool) {
        isForced = forced
        update()
    }

    /// Asks the detector once and applies its verdict (`.unavailable` counts as not detected).
    public func refreshDetection() async {
        let verdict = await detector.detect()
        setDetected(verdict.isSharing)
    }

    /// Applies a detection result (the detector's, or a test's).
    public func setDetected(_ detected: Bool) {
        isDetected = detected
        update()
    }

    private func update() {
        let active = isForced || isDetected
        guard active != isActive else { return }
        isActive = active
        context.publish(active)
    }
}

/// `context.privacy` (ModuleKit `PrivacyService`): the state readable from any isolation, and a stream per
/// subscriber that yields each change. Written only by ``CorePrivacyService``.
public final class PrivacyServiceBroadcast: PrivacyService {
    private struct State {
        var isActive: Bool
        var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]
    }

    private let state: Mutex<State>

    init(initial: Bool) {
        state = Mutex(State(isActive: initial))
    }

    public var isActive: Bool { state.withLock { $0.isActive } }

    public var changes: AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        state.withLock { $0.continuations[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            _ = self?.state.withLock { $0.continuations.removeValue(forKey: id) }
        }
        return stream
    }

    func publish(_ active: Bool) {
        let continuations = state.withLock { state -> [AsyncStream<Bool>.Continuation] in
            state.isActive = active
            return Array(state.continuations.values)
        }
        for continuation in continuations { continuation.yield(active) }
    }
}

/// Sets `privacyActive` from a ``CorePrivacyService`` for a surface root, following its changes.
struct PrivacyScope<Content: View>: View {
    let privacy: CorePrivacyService?
    @ViewBuilder let content: () -> Content

    var body: some View {
        content().privacyActive(privacy?.isActive ?? false)
    }
}
