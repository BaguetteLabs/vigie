import AppKit
import Foundation
import ModuleKit
import Observation

/// The `permissions` service (AD-19). Asks for a permission only when a module that needs it is enabled, caches
/// the last known status for Settings, and re-checks while modules wait: on app activation and every
/// `recheckInterval` (the timer runs only while something waits).
@MainActor @Observable
public final class PermissionsCoordinator: PermissionsService {
    /// Last known status per permission, for Settings and setup cards.
    public private(set) var statuses: [Permission: PermissionStatus] = [:]

    @ObservationIgnored private let checker: any PermissionChecker
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let recheckInterval: Duration
    @ObservationIgnored private var waiting: [Permission: Int] = [:]
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var activationTask: Task<Void, Never>?
    @ObservationIgnored private var subscribers: [UUID: AsyncStream<Permission>.Continuation] = [:]

    /// - Parameter activationNotifications: yields on each app-activation event; defaults to the AppKit
    ///   notifications (tests inject their own).
    public init(
        checker: any PermissionChecker,
        clock: any Clock<Duration> = ContinuousClock(),
        recheckInterval: Duration = .seconds(30),
        activationNotifications: AsyncStream<Void>? = nil
    ) {
        self.checker = checker
        self.clock = clock
        self.recheckInterval = recheckInterval
        let activations = activationNotifications ?? Self.systemActivations()
        activationTask = Task { [weak self] in
            for await _ in activations {
                guard let self else { return }
                await self.recheckIfWaiting()
            }
        }
    }

    isolated deinit {
        activationTask?.cancel()
        timer?.cancel()
        for continuation in subscribers.values { continuation.finish() }
    }

    public func status(of permission: Permission) async -> PermissionStatus {
        let status = await checker.status(of: permission)
        statuses[permission] = status
        return status
    }

    public func request(_ permission: Permission) async -> PermissionStatus {
        let status = await checker.request(permission)
        statuses[permission] = status
        return status
    }

    /// Returns the first permission that is not granted, requesting each undetermined one at this moment only.
    public func ensure(_ permissions: Set<Permission>) async -> Permission? {
        for permission in permissions.sorted(by: { String(describing: $0) < String(describing: $1) }) {
            var current = await status(of: permission)
            if current == .notDetermined { current = await request(permission) }
            if current != .granted { return permission }
        }
        return nil
    }

    /// Grant events found by re-checks. Each access returns a new stream; subscribe before `beginWaiting`.
    public var granted: AsyncStream<Permission> {
        let (stream, continuation) = AsyncStream.makeStream(of: Permission.self)
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.subscribers[id] = nil }
        }
        return stream
    }

    /// A module is waiting on `permission`: re-check on activation and on the timer until `endWaiting`.
    public func beginWaiting(on permission: Permission) {
        waiting[permission, default: 0] += 1
        guard timer == nil else { return }
        timer = Task { [weak self, clock, recheckInterval] in
            while !Task.isCancelled {
                do { try await clock.sleep(for: recheckInterval) } catch { return }
                await self?.recheckIfWaiting()
            }
        }
    }

    public func endWaiting(on permission: Permission) {
        guard let count = waiting[permission] else { return }
        if count <= 1 { waiting[permission] = nil } else { waiting[permission] = count - 1 }
        if waiting.isEmpty {
            timer?.cancel()
            timer = nil
        }
    }

    /// Re-checks every waited-on permission now and emits `granted` for those that became granted.
    public func recheckIfWaiting() async {
        for permission in Array(waiting.keys) {
            let status = await self.status(of: permission)
            if status == .granted, waiting[permission] != nil {
                for continuation in subscribers.values { continuation.yield(permission) }
            }
        }
    }

    private static func systemActivations() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        let own = Bundle.main.bundleIdentifier
        let center = NotificationCenter.default
        let appToken = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in continuation.yield() }
        let workspaceToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == own { continuation.yield() }
        }
        nonisolated(unsafe) let tokens = [appToken, workspaceToken]
        continuation.onTermination = { _ in
            for token in tokens {
                NotificationCenter.default.removeObserver(token)
                NSWorkspace.shared.notificationCenter.removeObserver(token)
            }
        }
        return stream
    }
}
