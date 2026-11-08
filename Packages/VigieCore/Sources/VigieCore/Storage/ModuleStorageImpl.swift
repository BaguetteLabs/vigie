import Darwin
import Foundation
import ModuleKit
import Wire
import os

/// On-disk envelope of every JSON state file (Conventions: JSON state files).
struct StateFile<Value> {
    var schema: Int
    var value: Value
}

extension StateFile: Encodable where Value: Encodable {}
extension StateFile: Decodable where Value: Decodable {}

/// `ModuleStorage` at `<AppEnvironment.applicationSupportURL>/modules/<module id>/` (AD-11).
///
/// Files are `<name>.json` holding `{ "schema": n, "value": ... }`. Writes are encoded immediately, then written
/// atomically (temp file in the same folder + `rename(2)` onto the symlink-resolved path), at most once per
/// `coalesceInterval` per file: the first write goes out at once, later ones within the interval are merged
/// into one trailing write of the latest value. An unreadable or undecodable file is renamed `<file>.corrupt`
/// (`.corrupt.2`, ... if taken), logged once, and read as nil.
public actor ModuleStorageImpl: ModuleStorage {
    public nonisolated let directory: URL
    private let logger: Logger
    private let coalesceInterval: Duration
    private let writeObserver: (@Sendable (URL) -> Void)?
    private let userFolderResolver: @Sendable (String) -> URL?
    private let clock: any Clock<Duration>
    /// Time since the storage was created, read from `clock`.
    private let elapsed: @Sendable () -> Duration

    private var pending: [String: Data] = [:]
    private var scheduled: [String: Task<Void, Never>] = [:]
    private var lastWrite: [String: Duration] = [:]

    /// The storage folder of `moduleID` under `applicationSupportURL`.
    public static func directory(for moduleID: ModuleID, applicationSupportURL: URL) -> URL {
        applicationSupportURL
            .appendingPathComponent("modules", isDirectory: true)
            .appendingPathComponent(moduleID.rawValue, isDirectory: true)
    }

    /// - Parameters:
    ///   - environment: injected by the caller (the App passes `AppEnvironment.current`).
    ///   - writeObserver: called after each disk write with the file URL (tests, diagnostics).
    ///   - userFolderResolver: maps a `path` setting key to its folder; ConfigStore provides it (Story 2.3+).
    public init(
        moduleID: ModuleID,
        environment: AppEnvironment,
        logger: Logger,
        coalesceInterval: Duration = .milliseconds(250),
        clock: any Clock<Duration> = ContinuousClock(),
        writeObserver: (@Sendable (URL) -> Void)? = nil,
        userFolderResolver: @escaping @Sendable (String) -> URL? = { _ in nil }
    ) {
        self.clock = clock
        self.elapsed = Self.stopwatch(clock)
        self.directory = Self.directory(for: moduleID, applicationSupportURL: environment.applicationSupportURL)
        self.logger = logger
        self.coalesceInterval = coalesceInterval
        self.writeObserver = writeObserver
        self.userFolderResolver = userFolderResolver
    }

    public nonisolated func userFolder(setting key: String) -> URL? {
        userFolderResolver(key)
    }

    // MARK: Reading

    public func readJSON<T: Decodable & Sendable>(
        _ name: String,
        as type: T.Type,
        schema: Int,
        migrate: (@Sendable (_ fromSchema: Int, _ value: Data) throws -> T)?
    ) async throws -> T? {
        let file = try fileURL(name)
        let key = file.lastPathComponent

        if let data = pending[key] {
            switch Self.decode(data, as: type, schema: schema, migrate: migrate) {
            case .value(let value): return value
            case .newer(let found): throw ModuleStorageError.newerSchema(found: found, supported: schema)
            case .corrupt(let reason):
                logger.error("Pending state \(key, privacy: .public) does not decode: \(reason, privacy: .public)")
                return nil
            }
        }

        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            setAside(file, reason: String(describing: error))
            return nil
        }
        switch Self.decode(data, as: type, schema: schema, migrate: migrate) {
        case .value(let value):
            return value
        case .newer(let found):
            throw ModuleStorageError.newerSchema(found: found, supported: schema)
        case .corrupt(let reason):
            setAside(file, reason: reason)
            return nil
        }
    }

    private enum Decoded<T> {
        case value(T)
        case newer(Int)
        case corrupt(String)
    }

    private struct Header: Decodable {
        let schema: Int
    }

    private static func decode<T: Decodable>(
        _ data: Data,
        as type: T.Type,
        schema: Int,
        migrate: ((Int, Data) throws -> T)?
    ) -> Decoded<T> {
        let decoder = makeDecoder()
        let header: Header
        do {
            header = try decoder.decode(Header.self, from: data)
        } catch {
            return .corrupt("no schema: \(error)")
        }
        if header.schema > schema { return .newer(header.schema) }
        do {
            if header.schema == schema {
                return .value(try decoder.decode(StateFile<T>.self, from: data).value)
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let value = object["value"]
            else { return .corrupt("no value") }
            let valueData = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
            if let migrate { return .value(try migrate(header.schema, valueData)) }
            return .value(try decoder.decode(T.self, from: valueData))
        } catch {
            return .corrupt(String(describing: error))
        }
    }

    private func setAside(_ file: URL, reason: String) {
        let manager = FileManager.default
        var destination = file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + ".corrupt")
        var index = 2
        while manager.fileExists(atPath: destination.path) {
            destination = file.deletingLastPathComponent()
                .appendingPathComponent(file.lastPathComponent + ".corrupt.\(index)")
            index += 1
        }
        do {
            try manager.moveItem(at: file, to: destination)
            logger.error(
                """
                State file \(file.lastPathComponent, privacy: .public) unreadable (\(reason, privacy: .public)); \
                set aside as \(destination.lastPathComponent, privacy: .public), starting empty
                """)
        } catch {
            logger.error(
                "State file \(file.lastPathComponent, privacy: .public) unreadable and not movable: \(error, privacy: .public)"
            )
        }
    }

    // MARK: Writing

    public func writeJSON<T: Encodable & Sendable>(_ value: T, name: String, schema: Int) async throws {
        let file = try fileURL(name)
        let key = file.lastPathComponent
        pending[key] = try Self.makeEncoder().encode(StateFile(schema: schema, value: value))
        guard scheduled[key] == nil else { return }

        let now = elapsed()
        let delay = lastWrite[key].map { max(.zero, $0 + coalesceInterval - now) } ?? .zero
        let clock = clock
        scheduled[key] = Task {
            if delay > .zero {
                try? await clock.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            self.writeScheduled(key)
        }
    }

    public func flush() async {
        for task in scheduled.values { task.cancel() }
        scheduled.removeAll()
        let items = pending
        pending.removeAll()
        for (key, data) in items { write(data, key: key) }
    }

    private static func stopwatch<C: Clock>(_ clock: C) -> @Sendable () -> Duration where C.Duration == Duration {
        let start = clock.now
        return { start.duration(to: clock.now) }
    }

    private func writeScheduled(_ key: String) {
        scheduled[key] = nil
        guard let data = pending.removeValue(forKey: key) else { return }
        write(data, key: key)
    }

    private func write(_ data: Data, key: String) {
        let manager = FileManager.default
        let target = directory.appendingPathComponent(key).resolvingSymlinksInPath()
        let folder = target.deletingLastPathComponent()
        let temp = folder.appendingPathComponent(".\(key).\(UUID().uuidString).tmp")
        lastWrite[key] = elapsed()
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            guard manager.createFile(atPath: temp.path, contents: data) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let handle = try FileHandle(forWritingTo: temp)
            try handle.synchronize()
            try handle.close()
            guard rename(temp.path, target.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            writeObserver?(target)
        } catch {
            try? manager.removeItem(at: temp)
            logger.error("Writing state \(key, privacy: .public) failed: \(error, privacy: .public)")
        }
    }

    // MARK: Helpers

    private func fileURL(_ name: String) throws -> URL {
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.contains("\0") else {
            throw ModuleStorageError.invalidName(name)
        }
        return directory.appendingPathComponent(name + ".json")
    }

    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(dateStyle.format(date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = try? dateStyle.parse(text) { return date }
            if let date = try? Date.ISO8601FormatStyle().parse(text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date: \(text)")
        }
        return decoder
    }
}
