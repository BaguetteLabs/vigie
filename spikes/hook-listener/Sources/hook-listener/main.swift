// Debug runner for the hook path (Story 1.4 spike, now on the Story 4.1 EventServer).
// Listens on AppEnvironment.current.socketURL (build in debug for the dev flavor) or the path given as the
// first argument, prints each EventMessage as pretty JSON and saves it to
// captured/<hook_event_name>-<n>.json. Quit the dev app first: this takes its instance lock.
import Foundation
import ModuleKit
import Synchronization
import VigieCore
import Wire
import os

setvbuf(stdout, nil, _IOLBF, 0)
let environment = AppEnvironment.current
let socketURL = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) } ?? environment.socketURL
let lockURL =
    CommandLine.arguments.count > 1
    ? socketURL.deletingLastPathComponent().appendingPathComponent("hook-listener.lock")
    : environment.instanceLockURL
let capturedURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("captured", isDirectory: true)
try FileManager.default.createDirectory(at: capturedURL, withIntermediateDirectories: true)

let lock = try InstanceLock.acquire(at: lockURL)
let bus = InProcessEventBus()
let server = EventServer(
    socketURL: socketURL, bus: bus, logger: Logger(subsystem: environment.logSubsystem, category: "hook-listener"))
try server.start(lockHeld: lock)
server.releaseQueue()

let (stream, _) = bus.subscription(topicPrefix: "")
Task {
    var count = 0
    for await message in stream {
        count += 1
        let payload = (try? JSONDecoder().decode(JSONValue.self, from: message.payload)) ?? .null
        let event = payload["raw"]?["hook_event_name"]?.stringValue ?? message.topic
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload) else { continue }
        try? data.write(to: capturedURL.appendingPathComponent("\(event)-\(count).json"))
        print(
            "--- #\(count) \(message.topic) \(event) sent \(WireDate.string(from: message.sentAt))\n"
                + String(decoding: data, as: UTF8.self))
    }
}

print("listening on \(socketURL.path)")
signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let stop = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
for source in [stop, term] {
    source.setEventHandler {
        server.stop()
        lock.release()
        exit(0)
    }
    source.resume()
}
dispatchMain()
