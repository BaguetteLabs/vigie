// SPIKE: replaced by the Event Server in Story 4.1
// Listens on AppEnvironment.current.socketURL (build in debug for the dev flavor), prints each
// envelope as pretty JSON and saves it to captured/<hook_event_name>-<n>.json.
import Foundation
import Synchronization
import VigieCore
import Wire

setvbuf(stdout, nil, _IOLBF, 0)
let socketPath = CommandLine.arguments.dropFirst().first ?? AppEnvironment.current.socketURL.path
let capturedURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("captured", isDirectory: true)
try FileManager.default.createDirectory(at: capturedURL, withIntermediateDirectories: true)
let counter = Mutex(0)

let listener = try SocketListener(
    path: socketPath,
    onError: { print("decode error: \($0)") },
    onEnvelope: { envelope in
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(envelope) else { return }
        let event = envelope.payload["raw"]?["hook_event_name"]?.stringValue ?? envelope.topic
        let n = counter.withLock { value -> Int in
            value += 1
            return value
        }
        try? data.write(to: capturedURL.appendingPathComponent("\(event)-\(n).json"))
        print("--- #\(n) \(event)\n" + String(decoding: data, as: UTF8.self))
    })
listener.start()
print("listening on \(socketPath)")
signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let stop = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
for source in [stop, term] {
    source.setEventHandler {
        listener.stop()
        exit(0)
    }
    source.resume()
}
dispatchMain()
