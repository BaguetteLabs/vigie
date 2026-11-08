import AgentKit
import Foundation
import GRDB

/// Where ingest left off in one log file.
public struct IngestFileState: Hashable, Sendable {
    /// Byte offset after the last complete line read.
    public let offset: UInt64
    public let size: UInt64
    /// Modification time, seconds since 1970.
    public let mtime: Double

    public init(offset: UInt64, size: UInt64, mtime: Double) {
        self.offset = offset
        self.size = size
        self.mtime = mtime
    }
}

/// One aggregated row: tokens of one model and project in one 15-minute slot.
struct UsageAggregate: Hashable, Sendable {
    let slotStart: Date
    let model: String
    let project: String
    let tokens: TokenCounts
    let records: Int
}

/// The usage history database (AD-11): the only SQLite database in Vigie, `usage.sqlite` in the `agents.usage`
/// storage folder, GRDB `DatabasePool` (WAL). Only `agents.usage` opens it.
///
/// Schema v1: `ingest_files` (per-file ingest offset, size, mtime) and `usage_records` (one row per model
/// response, id = provider + session + message, so streaming repeats of a response replace each other).
public final class UsageStore: Sendable {
    public static let fileName = "usage.sqlite"
    /// Aggregation slot: 15 minutes, so local-time buckets work in every time zone.
    static let slotSeconds: Double = 900

    public let url: URL
    let pool: DatabasePool

    /// Opens (creating if needed) `<directory>/usage.sqlite` and migrates it.
    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(Self.fileName)
        var configuration = Configuration()
        configuration.label = "agents.usage"
        pool = try DatabasePool(path: url.path, configuration: configuration)
        try Self.migrator.migrate(pool)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(
                sql: """
                    CREATE TABLE ingest_files (
                        path TEXT PRIMARY KEY NOT NULL,
                        provider TEXT NOT NULL,
                        read_offset INTEGER NOT NULL,
                        size INTEGER NOT NULL,
                        mtime DOUBLE NOT NULL
                    );
                    CREATE TABLE usage_records (
                        id TEXT PRIMARY KEY NOT NULL,
                        at DOUBLE NOT NULL,
                        provider TEXT NOT NULL,
                        model TEXT NOT NULL,
                        project TEXT NOT NULL,
                        session_id TEXT NOT NULL,
                        message_id TEXT NOT NULL,
                        request_id TEXT,
                        input INTEGER NOT NULL,
                        output INTEGER NOT NULL,
                        cache_create INTEGER NOT NULL,
                        cache_read INTEGER NOT NULL
                    );
                    CREATE INDEX usage_records_at ON usage_records(at);
                    CREATE INDEX usage_records_provider_at ON usage_records(provider, at);
                    """)
        }
        return migrator
    }

    /// The stored ingest state of every file of `provider`, by path.
    public func fileStates(provider: AgentID) async throws -> [String: IngestFileState] {
        try await pool.read { db in
            var states: [String: IngestFileState] = [:]
            let rows = try Row.fetchAll(
                db, sql: "SELECT path, read_offset, size, mtime FROM ingest_files WHERE provider = ?",
                arguments: [provider.rawValue])
            for row in rows {
                let offset: Int64 = row["read_offset"]
                let size: Int64 = row["size"]
                states[row["path"]] = IngestFileState(
                    offset: UInt64(max(0, offset)), size: UInt64(max(0, size)), mtime: row["mtime"])
            }
            return states
        }
    }

    /// Upserts `records` (a later write of a response replaces the earlier one) and records `state` for `path`,
    /// in one transaction.
    public func commit(provider: AgentID, path: String, state: IngestFileState, records: [UsageRecord])
        async throws
    {
        try await pool.write { db in
            let upsert = try db.cachedStatement(
                sql: """
                    INSERT INTO usage_records
                        (id, at, provider, model, project, session_id, message_id, request_id,
                         input, output, cache_create, cache_read)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        at = excluded.at, model = excluded.model, project = excluded.project,
                        request_id = excluded.request_id, input = excluded.input, output = excluded.output,
                        cache_create = excluded.cache_create, cache_read = excluded.cache_read
                    """)
            for record in records {
                try upsert.execute(arguments: [
                    Self.recordID(provider: provider, record: record), record.at.timeIntervalSince1970,
                    provider.rawValue, record.model, record.project, record.sessionID, record.messageID,
                    record.requestID, record.inputTokens, record.outputTokens, record.cacheCreationTokens,
                    record.cacheReadTokens,
                ])
            }
            try db.execute(
                sql: """
                    INSERT INTO ingest_files (path, provider, read_offset, size, mtime) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(path) DO UPDATE SET
                        provider = excluded.provider, read_offset = excluded.read_offset,
                        size = excluded.size, mtime = excluded.mtime
                    """,
                arguments: [
                    path, provider.rawValue, Int64(clamping: state.offset), Int64(clamping: state.size),
                    state.mtime,
                ])
        }
    }

    /// Number of stored records (all providers when nil).
    public func recordCount(provider: AgentID? = nil) async throws -> Int {
        try await pool.read { db in
            if let provider {
                return try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM usage_records WHERE provider = ?",
                    arguments: [provider.rawValue]) ?? 0
            }
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM usage_records") ?? 0
        }
    }

    /// Records in `[since, until)`, summed per 15-minute slot, model and project.
    func aggregates(since: Date, until: Date, provider: AgentID?) async throws -> [UsageAggregate] {
        try await pool.read { db in
            var sql = """
                SELECT CAST(at / \(Int(Self.slotSeconds)) AS INTEGER) AS slot, model, project,
                    SUM(input) AS input, SUM(output) AS output, SUM(cache_create) AS cache_create,
                    SUM(cache_read) AS cache_read, COUNT(*) AS records
                FROM usage_records WHERE at >= ? AND at < ?
                """
            var arguments: StatementArguments = [since.timeIntervalSince1970, until.timeIntervalSince1970]
            if let provider {
                sql += " AND provider = ?"
                arguments += [provider.rawValue]
            }
            sql += " GROUP BY slot, model, project ORDER BY slot"
            return try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
                let slot: Int64 = row["slot"]
                return UsageAggregate(
                    slotStart: Date(timeIntervalSince1970: Double(slot) * Self.slotSeconds), model: row["model"],
                    project: row["project"],
                    tokens: TokenCounts(
                        input: row["input"], output: row["output"], cacheCreation: row["cache_create"],
                        cacheRead: row["cache_read"]),
                    records: row["records"])
            }
        }
    }

    static func recordID(provider: AgentID, record: UsageRecord) -> String {
        "\(provider.rawValue)/\(record.sessionID)/\(record.messageID)"
    }
}
