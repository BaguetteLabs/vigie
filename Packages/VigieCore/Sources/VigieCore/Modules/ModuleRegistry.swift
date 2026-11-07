import Foundation
import ModuleKit
import Observation
import os

/// A module as App assembly lists it (AD-4): its manifest, available without instantiating it, and a factory
/// called only when the module is enabled, so a disabled module's work never exists (FR1, NFR4).
public struct ModuleDescriptor: Sendable {
    public let manifest: ModuleManifest
    public let make: @MainActor @Sendable () -> any NotchModule

    public init(manifest: ModuleManifest, make: @escaping @MainActor @Sendable () -> any NotchModule) {
        self.manifest = manifest
        self.make = make
    }
}

/// Source of `[modules."<id>"] enabled` (ConfigStore from Story 2.3).
public protocol ModuleEnablement: Sendable {
    /// The configured value, or nil when the key is absent (the manifest's `defaultEnabled` applies).
    func isEnabled(_ id: ModuleID) -> Bool?
    /// Yields a module id whenever its `enabled` value may have changed. Consumed once, by the Registry.
    var changes: AsyncStream<ModuleID> { get }
}

public enum ModuleStatus: Equatable, Sendable {
    case disabled
    case running
    /// Stopped by shutdown.
    case stopped
    /// `start` failed; the message is for Settings and logs.
    case errored(String)
    /// Stopped until the user grants the permission (Story 2.12); retried on grant.
    case needsPermission(Permission)
}

/// Starts, stops and tracks modules (SPEC §4.3, FR1, FR3, NFR15).
///
/// Transitions run one at a time, in order. A module whose `start` throws is marked `.errored` and the host
/// keeps going. On stop: `stop()`, then every registration tracked by its context is cancelled, then its
/// storage is flushed.
@MainActor @Observable
public final class ModuleRegistry {
    public let descriptors: [ModuleDescriptor]
    public private(set) var statuses: [ModuleID: ModuleStatus] = [:]

    private struct Running {
        let module: any NotchModule
        let context: any ModuleContext
        let tracker: RegistrationTracker
    }

    @ObservationIgnored private let enablement: any ModuleEnablement
    @ObservationIgnored private let contextFactory: any ModuleContextFactory
    @ObservationIgnored private let logger: Logger
    @ObservationIgnored private let permissions: PermissionsCoordinator
    @ObservationIgnored private var waiters: [ModuleID: (permission: Permission, task: Task<Void, Never>)] = [:]
    @ObservationIgnored private var running: [ModuleID: Running] = [:]
    @ObservationIgnored private var lastTransition: Task<Void, Never>?
    @ObservationIgnored private var changesTask: Task<Void, Never>?
    @ObservationIgnored private var isShutDown = false

    public init(
        descriptors: [ModuleDescriptor],
        enablement: any ModuleEnablement,
        contextFactory: any ModuleContextFactory,
        logger: Logger,
        permissions: PermissionsCoordinator? = nil
    ) {
        self.permissions = permissions ?? PermissionsCoordinator(checker: SystemPermissionChecker())
        var seen = Set<ModuleID>()
        var unique: [ModuleDescriptor] = []
        for descriptor in descriptors {
            if seen.insert(descriptor.manifest.id).inserted {
                unique.append(descriptor)
            } else {
                logger.fault("Duplicate module id \(descriptor.manifest.id.rawValue, privacy: .public) ignored")
            }
        }
        self.descriptors = unique
        self.enablement = enablement
        self.contextFactory = contextFactory
        self.logger = logger
    }

    /// Starts every enabled module, then follows enablement changes until `shutdown()`.
    public func start() async {
        guard changesTask == nil, !isShutDown else { return }
        for descriptor in descriptors where !isEnabled(descriptor) {
            statuses[descriptor.manifest.id] = .disabled
        }
        for descriptor in descriptors where isEnabled(descriptor) {
            enqueue(descriptor.manifest.id)
        }
        let changes = enablement.changes
        changesTask = Task { [weak self] in
            for await id in changes {
                guard let self else { return }
                self.enqueue(id)
            }
        }
        await settle()
    }

    /// Stops every running module (quit).
    public func shutdown() async {
        guard !isShutDown else { return }
        isShutDown = true
        changesTask?.cancel()
        changesTask = nil
        for id in Array(waiters.keys) { clearWaiter(id) }
        for descriptor in descriptors.reversed() where running[descriptor.manifest.id] != nil {
            enqueue(descriptor.manifest.id)
        }
        await settle()
    }

    public func status(of id: ModuleID) -> ModuleStatus {
        statuses[id] ?? .disabled
    }

    /// The running instance of `id`, if any.
    public func module(_ id: ModuleID) -> (any NotchModule)? {
        running[id]?.module
    }

    /// Running modules in assembly order.
    public var runningModules: [any NotchModule] {
        descriptors.compactMap { running[$0.manifest.id]?.module }
    }

    /// Waits until every queued transition has finished.
    func settle() async {
        while let task = lastTransition {
            await task.value
            if lastTransition == task { break }
        }
    }

    @discardableResult
    func enqueue(_ id: ModuleID) -> Task<Void, Never> {
        let previous = lastTransition
        let task = Task {
            await previous?.value
            await self.reconcile(id)
        }
        lastTransition = task
        return task
    }

    private func isEnabled(_ descriptor: ModuleDescriptor) -> Bool {
        enablement.isEnabled(descriptor.manifest.id) ?? descriptor.manifest.defaultEnabled
    }

    private func reconcile(_ id: ModuleID) async {
        guard let descriptor = descriptors.first(where: { $0.manifest.id == id }) else {
            logger.error("Enablement change for unknown module \(id.rawValue, privacy: .public)")
            return
        }
        let wanted = !isShutDown && isEnabled(descriptor)
        let isRunning = running[id] != nil
        switch (wanted, isRunning) {
        case (true, false):
            if case .errored = statuses[id] { return }  // stays errored until switched off and on again
            await startModule(descriptor)
        case (false, true):
            await stopModule(id, finalStatus: isShutDown ? .stopped : .disabled)
        case (false, false):
            clearWaiter(id)
            if !isShutDown { statuses[id] = .disabled }
        case (true, true):
            break
        }
    }

    private func startModule(_ descriptor: ModuleDescriptor) async {
        let id = descriptor.manifest.id
        clearWaiter(id)
        if let missing = await permissions.ensure(descriptor.manifest.permissions) {
            statuses[id] = .needsPermission(missing)
            await waitForGrant(of: missing, module: id)
            logger.info("Module \(id.rawValue, privacy: .public) waits for a permission")
            return
        }
        let tracker = RegistrationTracker()
        let context = contextFactory.makeContext(for: descriptor.manifest, tracker: tracker)
        let module = descriptor.make()
        guard module.manifest.id == id else {
            logger.fault(
                "Module built for \(id.rawValue, privacy: .public) reports id \(module.manifest.id.rawValue, privacy: .public)"
            )
            statuses[id] = .errored("Manifest id mismatch: \(module.manifest.id.rawValue)")
            return
        }
        do {
            try await module.start(context: context)
            running[id] = Running(module: module, context: context, tracker: tracker)
            statuses[id] = .running
            logger.info("Started module \(id.rawValue, privacy: .public)")
        } catch {
            tracker.cancelAll()
            await context.storage.flush()
            statuses[id] = .errored(String(describing: error))
            logger.error("Module \(id.rawValue, privacy: .public) failed to start: \(error, privacy: .public)")
        }
    }

    /// Retries the start once when `permission` is granted (the coordinator re-checks while we wait).
    private func waitForGrant(of permission: Permission, module id: ModuleID) async {
        let granted = permissions.granted
        permissions.beginWaiting(on: permission)
        let task = Task { [weak self] in
            for await p in granted where p == permission {
                self?.enqueue(id)
                return
            }
        }
        waiters[id] = (permission, task)
    }

    private func clearWaiter(_ id: ModuleID) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.task.cancel()
        permissions.endWaiting(on: waiter.permission)
    }

    private func stopModule(_ id: ModuleID, finalStatus: ModuleStatus) async {
        guard let entry = running.removeValue(forKey: id) else { return }
        await entry.module.stop()
        entry.tracker.cancelAll()
        await entry.context.storage.flush()
        statuses[id] = finalStatus
        logger.info("Stopped module \(id.rawValue, privacy: .public)")
    }
}
