import Foundation
import ModuleKit
import Synchronization
import Wire
import os

@testable import VigieCore

final class Counter: Sendable {
    private let value = Mutex(0)
    func increment() { value.withLock { $0 += 1 } }
    var count: Int { value.withLock { $0 } }
}

/// Polls `condition` until it holds or `timeout` elapses.
func eventually(timeout: Duration = .seconds(3), _ condition: @MainActor () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}

func makeTempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("VigieCoreTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeEnvironment(_ root: URL) -> AppEnvironment {
    AppEnvironment(flavor: .dev, applicationSupportURL: root, configFolderOverride: root)
}

let testLogger = Logger(subsystem: "fr.baguettelabs.vigie.tests", category: "tests")

/// `[modules."<id>"] enabled` for tests.
final class TestEnablement: ModuleEnablement {
    private let values: Mutex<[ModuleID: Bool]>
    let changes: AsyncStream<ModuleID>
    private let continuation: AsyncStream<ModuleID>.Continuation

    init(_ values: [ModuleID: Bool] = [:]) {
        self.values = Mutex(values)
        (changes, continuation) = AsyncStream.makeStream(of: ModuleID.self)
    }

    func isEnabled(_ id: ModuleID) -> Bool? { values.withLock { $0[id] } }

    func set(_ id: ModuleID, _ enabled: Bool) {
        values.withLock { $0[id] = enabled }
        continuation.yield(id)
    }
}
