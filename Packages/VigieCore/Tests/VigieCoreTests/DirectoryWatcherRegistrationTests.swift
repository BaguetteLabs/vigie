import Foundation
import Testing

@testable import VigieCore

/// Records the order of arms (a directory source built, not yet resumed) and handler calls.
@MainActor
private final class Trace {
    var entries: [String] = []
    var handlers: Int { entries.filter { $0 == "handler" }.count }
    /// Handler calls after the last arm.
    var handlersAfterLastArm: Int {
        guard let last = entries.lastIndex(of: "arm") else { return 0 }
        return entries[(last + 1)...].filter { $0 == "handler" }.count
    }
}

/// Wraps the real watcher and counts `watch` and `stopAll` calls.
@MainActor
private final class CountingWatcher: DirectoryWatching {
    let inner = DispatchDirectoryWatcher(retryInterval: .milliseconds(50))
    private(set) var watchCalls = 0
    private(set) var stopCalls = 0

    func watch(_ directory: URL, files: [String], handler: @escaping @MainActor () -> Void) {
        watchCalls += 1
        inner.watch(directory, files: files, handler: handler)
    }

    func stopAll() {
        stopCalls += 1
        inner.stopAll()
    }
}

@MainActor
@Suite struct DirectoryWatcherRegistrationTests {
    private func settle(_ milliseconds: Int = 300) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    /// Waits until `value` has not changed for 500 ms (a loaded machine delivers events late), at most 15 s;
    /// returns whether it settled.
    private func settles(_ value: () -> Int) async -> Bool {
        var last = value()
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(500))
            let now = value()
            if now == last { return true }
            last = now
        }
        return false
    }

    private func traced(_ watcher: DispatchDirectoryWatcher, directory: URL, trace: Trace) {
        let path = directory.path
        watcher.beforeResume = { source in if source == path { trace.entries.append("arm") } }
    }

    @Test func aFileChangedBeforeTheFirstRegistrationReachesTheHandler() async throws {
        let directory = makeTempDirectory()
        let trace = Trace()
        let watcher = DispatchDirectoryWatcher()
        defer { watcher.stopAll() }
        let path = directory.path
        var wrote = false
        watcher.beforeResume = { [trace] source in
            guard source == path else { return }
            trace.entries.append("arm")
            guard !wrote else { return }
            wrote = true
            try? Data("x".utf8).write(to: directory.appendingPathComponent("early.md"))
        }
        watcher.watch(directory, files: []) { trace.entries.append("handler") }
        #expect(await eventually(timeout: .seconds(2)) { trace.handlersAfterLastArm >= 1 })
        await settle()
        #expect(trace.entries.first == "arm")
        #expect(trace.handlers == 1, "\(trace.entries)")
    }

    @Test func aChangeAfterAReArmReachesTheHandler() async throws {
        let directory = makeTempDirectory()
        let file = directory.appendingPathComponent("a.md")
        try Data("a".utf8).write(to: file)
        let trace = Trace()
        let watcher = DispatchDirectoryWatcher()
        defer { watcher.stopAll() }
        traced(watcher, directory: directory, trace: trace)
        watcher.watch(directory, files: ["a.md"]) { trace.entries.append("handler") }
        #expect(await eventually(timeout: .seconds(2)) { trace.handlers == 1 })
        await settle()

        trace.entries = []
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("b".utf8))
        try handle.close()
        #expect(await eventually(timeout: .seconds(2)) { trace.entries.contains("arm") })
        await settle()
        // The fired event re-armed and read at once; the registration of the new watch reads once more.
        #expect(trace.handlersAfterLastArm == 2, "\(trace.entries)")
    }

    @Test func aChangeAfterTheRetryReopenedADirectoryReachesTheHandler() async throws {
        let root = makeTempDirectory()
        let directory = root.appendingPathComponent("later", isDirectory: true)
        let trace = Trace()
        let watcher = DispatchDirectoryWatcher(retryInterval: .milliseconds(50))
        defer { watcher.stopAll() }
        traced(watcher, directory: directory, trace: trace)
        watcher.watch(directory, files: []) { trace.entries.append("handler") }
        await settle(150)
        #expect(trace.entries.isEmpty)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #expect(await eventually(timeout: .seconds(2)) { trace.entries.contains("arm") })
        await settle()
        #expect(trace.handlersAfterLastArm == 2, "\(trace.entries)")
    }

    @Test func stoppingBeforeTheRegistrationCallsNothing() async throws {
        let directory = makeTempDirectory()
        let trace = Trace()
        let watcher = DispatchDirectoryWatcher()
        watcher.watch(directory, files: []) { trace.entries.append("handler") }
        watcher.stopAll()
        #expect(await eventually(timeout: .seconds(2)) { watcher.openDescriptors == 0 })
        try Data("x".utf8).write(to: directory.appendingPathComponent("after.md"))
        await settle()
        #expect(trace.entries.isEmpty && watcher.openDescriptors == 0)
    }

    @Test func repeatedWatchAndStopLeakNoDescriptor() async throws {
        let directory = makeTempDirectory()
        try Data("x".utf8).write(to: directory.appendingPathComponent("a.md"))
        let watcher = DispatchDirectoryWatcher()
        for _ in 0..<50 {
            watcher.watch(directory, files: ["a.md"]) {}
            watcher.stopAll()
        }
        watcher.watch(directory, files: ["a.md"]) {}
        try Data("y".utf8).write(to: directory.appendingPathComponent("b.md"))
        #expect(await eventually(timeout: .seconds(2)) { watcher.openDescriptors == 2 })
        await settle()
        #expect(watcher.openDescriptors == 2)
        watcher.stopAll()
        #expect(await eventually(timeout: .seconds(2)) { watcher.openDescriptors == 0 })
    }

    @Test func aWatcherDroppedWithoutStopIsDeallocated() async throws {
        let directory = makeTempDirectory()
        weak var weakWatcher: DispatchDirectoryWatcher?
        do {
            let watcher = DispatchDirectoryWatcher()
            weakWatcher = watcher
            watcher.watch(directory, files: []) {}
            await settle(50)
        }
        #expect(await eventually(timeout: .seconds(2)) { weakWatcher == nil })
    }

    @Test func aBurstOfChangesGivesABoundedNumberOfCalls() async throws {
        let directory = makeTempDirectory()
        let trace = Trace()
        let watcher = DispatchDirectoryWatcher()
        defer { watcher.stopAll() }
        watcher.watch(directory, files: []) { trace.entries.append("handler") }
        await settle()
        let before = trace.handlers
        for index in 0..<100 { try Data("x".utf8).write(to: directory.appendingPathComponent("f\(index).md")) }
        #expect(await settles { trace.handlers }, "a steady state calls nothing")
        let burst = trace.handlers - before
        #expect(burst >= 1 && burst <= 205, "\(burst)")
    }

    // MARK: FolderWatch over the real watcher

    private func makeFolder(_ names: [String]) throws -> URL {
        let folder = makeTempDirectory()
        for name in names { try Data("x".utf8).write(to: folder.appendingPathComponent(name)) }
        return folder
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    @Test func folderWatchSettlesAfterStartAndAfterAnEvent() async throws {
        let folder = try makeFolder(["a.md"])
        let watcher = CountingWatcher()
        let changes = Counter()
        let watch = FolderWatch(folder: folder, watcher: watcher) { changes.increment() }
        defer { watch.stop() }
        watch.arm()
        await settle(500)
        // Start: the registration reads once; nothing is re-armed since the list did not change.
        #expect(changes.count == 1 && watcher.watchCalls == 1 && watcher.stopCalls == 1, "\(changes.count)")

        try append("b", to: folder.appendingPathComponent("a.md"))
        #expect(await eventually(timeout: .seconds(5)) { changes.count >= 2 })
        // One in-place write: a fired read plus a registration read, bounded at 4 with extra kernel events.
        #expect(changes.count >= 2 && changes.count <= 4, "\(changes.count)")
        #expect(watcher.watchCalls == 1 && watcher.stopCalls == 1)
        #expect(await settles { changes.count }, "a steady state calls nothing")
        #expect(changes.count <= 4 && watcher.watchCalls == 1 && watcher.stopCalls == 1)
    }

    @Test func aFileAddedBetweenTheListingAndTheRegistrationEndsUpWatched() async throws {
        let folder = try makeFolder(["a.md"])
        let watcher = CountingWatcher()
        let path = folder.path
        var added = false
        watcher.inner.beforeResume = { source in
            guard source == path, !added else { return }
            added = true
            try? Data("x".utf8).write(to: folder.appendingPathComponent("b.md"))
        }
        let changes = Counter()
        let watch = FolderWatch(folder: folder, watcher: watcher) { changes.increment() }
        defer { watch.stop() }
        watch.arm()
        #expect(await eventually(timeout: .seconds(2)) { watcher.watchCalls == 2 })
        await settle()
        let before = changes.count
        try append("more", to: folder.appendingPathComponent("b.md"))
        #expect(await eventually(timeout: .seconds(2)) { changes.count > before })
        #expect(watcher.watchCalls == 2)
    }

    @Test func anAtomicallyReplacedFileFollowedByAnInPlaceWriteIsStillSeen() async throws {
        let folder = try makeFolder(["a.md"])
        let watcher = CountingWatcher()
        let changes = Counter()
        let watch = FolderWatch(folder: folder, watcher: watcher) { changes.increment() }
        defer { watch.stop() }
        watch.arm()
        await settle()
        let file = folder.appendingPathComponent("a.md")
        let temp = folder.appendingPathComponent(".tmp")
        try Data("new".utf8).write(to: temp)
        #expect(rename(temp.path, file.path) == 0)
        await settle(500)
        let before = changes.count
        try append("more", to: file)
        #expect(await eventually(timeout: .seconds(2)) { changes.count > before })
    }

    // MARK: ConfigStore: the extra call is an idempotent read

    @Test func aReloadOfUnchangedBytesWritesNothingAndSaysNothing() async throws {
        let fixture = ConfigFixture()
        let (store, watcher) = try await fixture.makeStore(config: "[closed]\nslots = 2\n")
        defer { store.stop() }
        func snapshot() throws -> [String] {
            try [fixture.configURL, fixture.localURL].map { url in
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let data = try Data(contentsOf: url)
                return "\(attributes[.modificationDate] ?? "")|\(attributes[.systemFileNumber] ?? "")|\(data.hashValue)"
            }
        }
        let before = try snapshot()
        let problems = store.problems
        let changes = StreamCounter(store.changes)
        let observed = StreamCounter(store.observe("closed.slots"))
        let revision = store.revision

        // What the post-registration call does: events with no change in the files, one racing a write.
        for _ in 0..<3 { await store.fireAndSettle(watcher) }
        let write = Task { @MainActor in try await store.set("closed.slots", to: .int(3)) }
        watcher.fire()
        try await write.value
        await store.waitForScheduledReload()
        await store.reload()

        #expect(store.value("closed.slots", as: Int.self) == 3)
        #expect(try String(contentsOf: fixture.configURL, encoding: .utf8).contains("slots = 3"))
        #expect(store.problems == problems)
        #expect(changes.count == 1 && observed.count == 1, "only the write is reported")
        #expect(store.revision == revision + 1)
        #expect(try snapshot()[1] == before[1], "local.toml untouched")
    }
}
