import Foundation
import ModuleKit
import Synchronization
import Testing

@testable import VigieCore

final class FakePermissionChecker: PermissionChecker {
    private struct State {
        var statuses: [Permission: PermissionStatus] = [:]
        var grantOnRequest: Set<Permission> = []
        var requests: [Permission] = []
        var statusCalls = 0
    }
    private let state = Mutex(State())

    func set(_ permission: Permission, _ status: PermissionStatus) {
        state.withLock { $0.statuses[permission] = status }
    }
    func grantOnRequest(_ permission: Permission) { state.withLock { _ = $0.grantOnRequest.insert(permission) } }
    var requests: [Permission] { state.withLock { $0.requests } }
    var statusCalls: Int { state.withLock { $0.statusCalls } }
    var totalCalls: Int { state.withLock { $0.statusCalls + $0.requests.count } }

    func status(of permission: Permission) async -> PermissionStatus {
        state.withLock {
            $0.statusCalls += 1
            return $0.statuses[permission] ?? .notDetermined
        }
    }

    func request(_ permission: Permission) async -> PermissionStatus {
        state.withLock {
            $0.requests.append(permission)
            if $0.grantOnRequest.contains(permission) {
                $0.statuses[permission] = .granted
            } else if $0.statuses[permission] == .notDetermined || $0.statuses[permission] == nil {
                $0.statuses[permission] = .denied
            }
            return $0.statuses[permission] ?? .denied
        }
    }
}

final class TestClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (a: Instant, b: Instant) -> Bool { a.offset < b.offset }
    }
    private struct Sleeper {
        let deadline: Instant
        let continuation: CheckedContinuation<Void, Error>
    }
    private let lock = Mutex<(now: Instant, sleepers: [UUID: Sleeper])>((Instant(offset: .zero), [:]))

    var now: Instant { lock.withLock { $0.now } }
    var minimumResolution: Duration { .zero }
    var sleeperCount: Int { lock.withLock { $0.sleepers.count } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                // A task cancelled before it got here never sees `onCancel` remove its sleeper.
                if Task.isCancelled { return c.resume(throwing: CancellationError()) }
                let due = lock.withLock { state -> Bool in
                    if deadline <= state.now { return true }
                    state.sleepers[id] = Sleeper(deadline: deadline, continuation: c)
                    return false
                }
                if due { c.resume() }
                if Task.isCancelled, let s = lock.withLock({ $0.sleepers.removeValue(forKey: id) }) {
                    s.continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let s = lock.withLock { $0.sleepers.removeValue(forKey: id) }
            s?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(by duration: Duration) {
        let due = lock.withLock { state -> [Sleeper] in
            state.now = state.now.advanced(by: duration)
            let ready = state.sleepers.filter { $0.value.deadline <= state.now }
            for key in ready.keys { state.sleepers[key] = nil }
            return Array(ready.values)
        }
        for sleeper in due { sleeper.continuation.resume() }
    }
}

@MainActor
struct PermissionHarness {
    let checker = FakePermissionChecker()
    let clock = TestClock()
    let activations: AsyncStream<Void>.Continuation
    let coordinator: PermissionsCoordinator
    let root = makeTempDirectory()
    let spies = SpyFactory()
    let enablement: TestEnablement
    let registry: ModuleRegistry

    init(permissions: Set<Permission>, enabled: Bool = true, startsWithoutPermissions: Bool = false) {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        activations = continuation
        coordinator = PermissionsCoordinator(
            checker: checker, clock: clock, activationNotifications: stream)
        let manifest = ModuleManifest(
            id: "perm", name: "Perm", icon: "circle", permissions: permissions, defaultEnabled: true,
            startsWithoutPermissions: startsWithoutPermissions)
        let spies = spies
        let descriptor = ModuleDescriptor(manifest: manifest) {
            let module = SpyModule(manifest: manifest, shouldThrow: false)
            spies.made["perm", default: []].append(module)
            return module
        }
        enablement = TestEnablement(["perm": enabled])
        let contexts = CoreModuleContextFactory(
            environment: makeEnvironment(root), eventBus: InProcessEventBus(), permissions: coordinator)
        registry = ModuleRegistry(
            descriptors: [descriptor], enablement: enablement, contextFactory: contexts,
            logger: testLogger, permissions: coordinator)
    }
}

@MainActor @Suite struct PermissionsTests {
    @Test func requestsOnlyWhenModuleIsEnabled() async {
        let h = PermissionHarness(permissions: [.accessibility])
        h.checker.grantOnRequest(.accessibility)
        #expect(h.checker.requests.isEmpty)
        await h.registry.start()
        #expect(h.checker.requests == [.accessibility])
        #expect(h.registry.status(of: "perm") == .running)
        await h.registry.shutdown()
    }

    @Test func deniedModuleIsNotInstantiated() async {
        let h = PermissionHarness(permissions: [.accessibility])
        await h.registry.start()
        #expect(h.spies.made["perm"] == nil)
        #expect(h.registry.status(of: "perm") == .needsPermission(.accessibility))
        await h.registry.shutdown()
    }

    @Test func disabledModuleNeverTouchesChecker() async {
        let h = PermissionHarness(permissions: [.accessibility, .calendar], enabled: false)
        await h.registry.start()
        h.clock.advance(by: .seconds(120))
        h.activations.yield()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(h.checker.totalCalls == 0)
        #expect(h.registry.status(of: "perm") == .disabled)
        await h.registry.shutdown()
    }

    @Test func grantThenActivationStartsModule() async {
        let h = PermissionHarness(permissions: [.accessibility])
        h.checker.set(.accessibility, .denied)
        await h.registry.start()
        #expect(h.registry.status(of: "perm") == .needsPermission(.accessibility))
        h.checker.set(.accessibility, .granted)
        h.activations.yield()
        #expect(await eventually { h.registry.status(of: "perm") == .running })
        #expect(h.spies.made["perm"]?.count == 1)
        await h.registry.shutdown()
    }

    @Test func grantThenTimerStartsModuleAndTimerStopsAfter() async {
        let h = PermissionHarness(permissions: [.accessibility])
        h.checker.set(.accessibility, .denied)
        await h.registry.start()
        #expect(await eventually { h.clock.sleeperCount == 1 })
        h.checker.set(.accessibility, .granted)
        h.clock.advance(by: .seconds(30))
        #expect(await eventually { h.registry.status(of: "perm") == .running })
        #expect(await eventually { h.clock.sleeperCount == 0 })
        let calls = h.checker.totalCalls
        h.clock.advance(by: .seconds(300))
        h.activations.yield()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(h.checker.totalCalls == calls)
        await h.registry.shutdown()
    }

    @Test func noWaiterMeansNoChecks() async {
        let h = PermissionHarness(permissions: [])
        await h.registry.start()
        let calls = h.checker.totalCalls
        h.clock.advance(by: .seconds(90))
        h.activations.yield()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(h.checker.totalCalls == calls)
        #expect(h.clock.sleeperCount == 0)
        await h.registry.shutdown()
    }

    @Test func onlySecondPermissionMissing() async {
        let first = Permission.accessibility
        let second = Permission.calendar
        let h = PermissionHarness(permissions: [first, second])
        h.checker.set(first, .granted)
        h.checker.set(second, .denied)
        await h.registry.start()
        #expect(h.registry.status(of: "perm") == .needsPermission(second))
        #expect(h.spies.made["perm"] == nil)
        await h.registry.shutdown()
    }

    @Test func selfManagedModuleStartsWithoutAskingAndNeverWaits() async {
        let h = PermissionHarness(permissions: [.calendar], startsWithoutPermissions: true)
        h.checker.set(.calendar, .denied)
        await h.registry.start()
        #expect(h.registry.status(of: "perm") == .running)
        #expect(h.spies.made["perm"]?.count == 1)
        #expect(h.checker.totalCalls == 0)  // the module asks itself, through context.permissions
        #expect(h.clock.sleeperCount == 0)
        await h.registry.shutdown()
    }

    @Test func coordinatorCachesStatuses() async {
        let h = PermissionHarness(permissions: [])
        h.checker.set(.notifications, .granted)
        _ = await h.coordinator.status(of: .notifications)
        #expect(h.coordinator.statuses[.notifications] == .granted)
    }

    @Test func systemCheckerDoesNotCrashUnderTests() async {
        let checker = SystemPermissionChecker()
        _ = await checker.status(of: .accessibility)
        #expect(await checker.status(of: .notifications) == .denied)
        #expect(await checker.request(.notifications) == .denied)
        #expect(await checker.request(.calendar) == .denied)
    }
}
