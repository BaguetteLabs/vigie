import Foundation
import ModuleKit
import Wire
import os

/// Per-day totals for the Settings activity pane (PRD §8 metrics).
public struct DaySummary: Equatable, Sendable {
    public var alertsByKind: [String: Int] = [:]
    public var peeks = 0
    public var reminders = 0
    public var focusExact = 0
    public var focusAppOnly = 0
    public var focusFailed = 0
    public var suppressedByReason: [String: Int] = [:]

    public init() {}
}

/// The local activity log (AD-26): JSON Lines, one file per UTC day under `<app support>/activity/`,
/// append-only. Each entry is one `write(2)` on an `O_APPEND` descriptor, so concurrent or crashing writers
/// never interleave or tear a line (entries are far below the size the kernel writes atomically for regular
/// files in practice); a crash loses at most the last entry. Never throws to callers.
public actor ActivityStore {
    public nonisolated let directory: URL
    private let now: @Sendable () -> Date
    private let retention: Duration
    private let logger: Logger
    private var lastErrorLog: Date?
    private var pruningTask: Task<Void, Never>?
    /// Unparsable lines met by the read calls so far.
    public private(set) var skippedLines = 0

    public init(
        environment: AppEnvironment, now: @escaping @Sendable () -> Date = Date.init,
        retention: Duration = .seconds(30 * 24 * 3600),
        logger: Logger = Logger(subsystem: "fr.baguettelabs.vigie", category: "activity")
    ) {
        self.directory = environment.applicationSupportURL.appendingPathComponent("activity", isDirectory: true)
        self.now = now
        self.retention = retention
        self.logger = logger
    }

    // MARK: Format

    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(Self.makeISO().string(from: date))
        }
        return e
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            guard let d = Self.makeISO().date(from: s) else {
                throw DecodingError.dataCorruptedError(in: try dec.singleValueContainer(), debugDescription: s)
            }
            return d
        }
        return d
    }

    private static func makeISO() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = .gmt
        return f
    }

    private static var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .gmt
        return c
    }

    static func fileName(for day: Date) -> String {
        let p = utc.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d.jsonl", p.year ?? 0, p.month ?? 0, p.day ?? 0)
    }

    static func date(fromFileName name: String) -> Date? {
        guard name.hasSuffix(".jsonl") else { return nil }
        let parts = name.dropLast(6).split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        return utc.date(from: DateComponents(year: y, month: m, day: d))
    }

    // MARK: Writing

    /// Appends one line to the file of the entry's UTC day.
    public func append(_ entry: ActivityEntry) {
        do {
            var data = try Self.makeEncoder().encode(entry)
            data.removeAll { $0 == 0x0A }  // JSON encoding escapes newlines; belt and braces
            data.append(0x0A)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let path = directory.appendingPathComponent(Self.fileName(for: entry.at)).path
            let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
            guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            defer { close(fd) }
            let written = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            guard written == data.count else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        } catch {
            logFailure(error)
        }
    }

    private func logFailure(_ error: any Error) {
        let t = now()
        if let last = lastErrorLog, t.timeIntervalSince(last) < 60 { return }
        lastErrorLog = t
        logger.error("Activity log write failed: \(String(describing: error), privacy: .public)")
    }

    // MARK: Reading

    private func read(file name: String) -> [ActivityEntry] {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return [] }
        let decoder = Self.makeDecoder()
        var out: [ActivityEntry] = []
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let e = try? decoder.decode(ActivityEntry.self, from: Data(line)) {
                out.append(e)
            } else {
                skippedLines += 1
            }
        }
        return out
    }

    /// Entries of the UTC day containing `day`, in file order (oldest first).
    public func entries(on day: Date) -> [ActivityEntry] { read(file: Self.fileName(for: day)) }

    /// Entries at or after `since`, newest first, at most `limit`.
    public func entries(since: Date, limit: Int = 5_000) -> [ActivityEntry] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .compactMap { n in Self.date(fromFileName: n).map { (n, $0) } }
            .filter { $0.1 >= Self.utc.startOfDay(for: since) }
            .sorted { $0.1 > $1.1 }
        var out: [ActivityEntry] = []
        for (name, _) in names {
            out += read(file: name).filter { $0.at >= since }.sorted { $0.at > $1.at }
            if out.count >= limit { break }
        }
        return Array(out.prefix(limit))
    }

    public func summary(for day: Date) -> DaySummary {
        var s = DaySummary()
        for e in entries(on: day) {
            switch e.outcome {
            case .suppressed(let reason): s.suppressedByReason[reason, default: 0] += 1
            case .focusExact: s.focusExact += 1
            case .focusAppOnly: s.focusAppOnly += 1
            case .focusFailed: s.focusFailed += 1
            case .shown: s.peeks += 1
            case .repeated: s.reminders += 1
            case .posted where e.category == .alert: s.alertsByKind[e.kind, default: 0] += 1
            default: break
            }
        }
        return s
    }

    /// Plain text, one line per entry (oldest first): `HH:mm:ss  module  kind  outcome`.
    public func copyAsText(day: Date) -> String {
        entries(on: day).map { e in
            let time = e.at.formatted(Date.ISO8601FormatStyle(timeZone: .gmt).time(includingFractionalSeconds: false))
            return "\(time)  \(e.module?.rawValue ?? "core")  \(e.kind)  \(e.outcome.encoded)"
        }.joined(separator: "\n")
    }

    // MARK: Retention

    /// Deletes day files older than the retention (by file name; unknown names are ignored).
    @discardableResult
    public func prune() -> Int {
        let cutoff = Self.utc.startOfDay(for: now().addingTimeInterval(-retention.timeInterval))
        var removed = 0
        for name in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] {
            guard let d = Self.date(fromFileName: name), d < cutoff else { continue }
            if (try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))) != nil {
                removed += 1
            }
        }
        return removed
    }

    /// Prunes now, then every 24 h until `stopPruning()`.
    public func startDailyPruning(clock: any Clock<Duration> = ContinuousClock()) {
        pruningTask?.cancel()
        pruningTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.prune()
                do { try await clock.sleep(for: .seconds(24 * 3600)) } catch { return }
            }
        }
    }

    public func stopPruning() {
        pruningTask?.cancel()
        pruningTask = nil
    }
}

extension Duration {
    fileprivate var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
