import Foundation
import OSLog

/// Where the Logs section of Copy diagnostics comes from (Story 17.4). Tests pass a fake.
public protocol LogLinesProviding: Sendable {
    /// Up to `limit` lines logged since `since` by Vigie's subsystems, oldest first.
    func recentLines(limit: Int, since: Date) async throws -> [String]
}

/// This process's own unified-log entries (`OSLogStore(scope: .currentProcessIdentifier)`, no entitlement, no
/// other process), filtered on Vigie's subsystems. `%{private}` fields are already `<private>` in the composed
/// messages; the redactor still runs over every line.
public struct OSLogLinesProvider: LogLinesProviding {
    /// Subsystems kept: equal to one of these, or starting with one of them followed by `.`.
    public let subsystems: [String]

    public init(subsystems: [String]) {
        self.subsystems = subsystems
    }

    public func recentLines(limit: Int, since: Date) async throws -> [String] {
        let subsystems = subsystems
        return try await Task.detached(priority: .utility) {
            try Self.read(subsystems: subsystems, limit: limit, since: since)
        }.value
    }

    static func read(subsystems: [String], limit: Int, since: Date) throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let position = store.position(date: since)
        let predicate = NSCompoundPredicate(
            orPredicateWithSubpredicates: subsystems.flatMap { subsystem in
                [
                    NSPredicate(format: "subsystem == %@", subsystem),
                    NSPredicate(format: "subsystem BEGINSWITH %@", subsystem + "."),
                ]
            })
        var lines: [String] = []
        for entry in try store.getEntries(at: position, matching: predicate) {
            guard let log = entry as? OSLogEntryLog else { continue }
            lines.append(format(log))
            if lines.count > limit { lines.removeFirst(lines.count - limit) }
        }
        return lines
    }

    static func format(_ log: OSLogEntryLog) -> String {
        let time = log.date.formatted(.iso8601.time(includingFractionalSeconds: true))
        return "\(time) \(level(log.level)) [\(log.category)] \(log.composedMessage)"
    }

    static func level(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        case .undefined: "-"
        @unknown default: "-"
        }
    }
}
