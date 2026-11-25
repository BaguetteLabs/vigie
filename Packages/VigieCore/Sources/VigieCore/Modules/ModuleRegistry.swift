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

/// Why ``ModuleRegistry/registerDynamic(_:owner:)`` refused a dynamic module (AD-18).
public enum DynamicModuleError: Error, Equatable, Sendable {
    /// A built-in module or another dynamic module already uses the id.
    case duplicateID(ModuleID)
    /// The owner is not a module of this registry, or the registry is shut down.
    case unavailable
}

/// Starts, stops and tracks modules (SPEC §4.3, FR1, FR3, NFR15).
///
/// Transitions run one at a time, in order. A module whose `start` throws is marked `.errored` and the host
/// keeps going. On stop: `stop()`, then every registration tracked by its context is cancelled, then its
/// storage is flushed.
///
/// Dynamic modules (AD-18, Story 12.5): a running module (only `integrations` today) registers one module per
/// script with ``registerDynamic(_:owner:)``. A dynamic module is built and driven by its owner (the registry
/// never calls its `start` or `stop`), is listed in ``runningModules`` right after its owner, so arbitration,
/// Home, the tabs and Settings › Home see it like any other module, reads ``ModuleStatus/running`` in
/// ``statuses`` while registered, and goes away when its token is cancelled or its owner stops.
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
    @ObservationIgnored let contextFactory: any ModuleContextFactory
    @ObservationIgnored private let logger: Logger
    @ObservationIgnored private let permissions: PermissionsCoordinator
    @ObservationIgnored private var waiters: [ModuleID: (permission: Permission, task: Task<Void, Never>)] = [:]
    @ObservationIgnored private var running: [ModuleID: Running] = [:]
    @ObservationIgnored private var lastTransition: Task<Void, Never>?
    @ObservationIgnored private var changesTask: Task<Void, Never>?
    /// Enablement changes taken off the stream so far (a test seam for the stream hop).
    @ObservationIgnored private(set) var changesObserved = 0
    @ObservationIgnored private var isShutDown = false
    /// Dynamic modules by owner, in registration order (AD-18).
    @ObservationIgnored private var dynamic: [ModuleID: [DynamicEntry]] = [:]

    private struct DynamicEntry {
        let token: UUID
        let module: any NotchModule
    }

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
                self.changesObserved += 1
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

    /// The running instance of `id` (a built-in or a dynamic module), if any.
    public func module(_ id: ModuleID) -> (any NotchModule)? {
        running[id]?.module ?? dynamicEntry(id)?.module
    }

    /// Running modules in assembly order, each owner's dynamic modules right after it.
    public var runningModules: [any NotchModule] {
        descriptors.flatMap { descriptor -> [any NotchModule] in
            let id = descriptor.manifest.id
            return (running[id].map { [$0.module] } ?? []) + (dynamic[id] ?? []).map(\.module)
        }
    }

    /// The ids of the dynamic modules registered now, in ``runningModules`` order.
    public var dynamicModuleIDs: [ModuleID] {
        descriptors.flatMap { (dynamic[$0.manifest.id] ?? []).map(\.module.manifest.id) }
    }

    // MARK: Dynamic modules (AD-18)

    /// Registers `module` on behalf of `owner` (`context.host.registerDynamicModule`, through
    /// ``CoreHostControl``). Its id must be free: not a built-in id, not another dynamic module's. Cancelling
    /// the token (on the main actor, or from elsewhere through a hop) unregisters it; stopping `owner` does too.
    public func registerDynamic(_ module: any NotchModule, owner: ModuleID) throws -> RegistrationToken {
        guard !isShutDown, descriptors.contains(where: { $0.manifest.id == owner }) else {
            throw DynamicModuleError.unavailable
        }
        let id = module.manifest.id
        guard !descriptors.contains(where: { $0.manifest.id == id }), dynamicEntry(id) == nil else {
            throw DynamicModuleError.duplicateID(id)
        }
        let token = UUID()
        dynamic[owner, default: []].append(DynamicEntry(token: token, module: module))
        statuses[id] = .running
        logger.info(
            "Registered dynamic module \(id.rawValue, privacy: .public) for \(owner.rawValue, privacy: .public)")
        return RegistrationToken(id: token) { [weak self] in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.unregisterDynamic(token) }
            } else {
                Task { @MainActor in self?.unregisterDynamic(token) }
            }
        }
    }

    private func dynamicEntry(_ id: ModuleID) -> DynamicEntry? {
        for entries in dynamic.values {
            if let entry = entries.first(where: { $0.module.manifest.id == id }) { return entry }
        }
        return nil
    }

    private func unregisterDynamic(_ token: UUID) {
        for (owner, entries) in dynamic {
            guard let index = entries.firstIndex(where: { $0.token == token }) else { continue }
            let id = entries[index].module.manifest.id
            dynamic[owner]?.remove(at: index)
            if dynamic[owner]?.isEmpty == true { dynamic[owner] = nil }
            statuses[id] = nil
            logger.info("Unregistered dynamic module \(id.rawValue, privacy: .public)")
            return
        }
    }

    /// Drops every dynamic module of `owner` (it stopped or failed to start).
    private func removeDynamicModules(of owner: ModuleID) {
        guard let entries = dynamic.removeValue(forKey: owner) else { return }
        for entry in entries { statuses[entry.module.manifest.id] = nil }
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
        // A module that handles its own missing permission (setup card, Story 13.1) asks for it in `start`.
        if !descriptor.manifest.startsWithoutPermissions,
            let missing = await permissions.ensure(descriptor.manifest.permissions)
        {
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
            removeDynamicModules(of: id)
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
        removeDynamicModules(of: id)
        await entry.context.storage.flush()
        statuses[id] = finalStatus
        logger.info("Stopped module \(id.rawValue, privacy: .public)")
    }
}
