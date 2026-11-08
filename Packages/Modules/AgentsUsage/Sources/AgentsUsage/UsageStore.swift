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

/// One aggregated row: tokens of one Account, model and project in one 15-minute slot.
struct UsageAggregate: Hashable, Sendable {
    let slotStart: Date
    let provider: AgentID
    let account: AccountID
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
/// Schema v2 (Story 7.10): an `account` column on both tables, `'default'` for every row written before, so a
/// pre-7.10 history is the default Account's. Records of another Account have id provider + account + session +
/// message.
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
        migrator.registerMigration("v2") { db in
            try db.execute(
                sql: """
                    ALTER TABLE ingest_files ADD COLUMN account TEXT NOT NULL DEFAULT 'default';
                    ALTER TABLE usage_records ADD COLUMN account TEXT NOT NULL DEFAULT 'default';
                    CREATE INDEX ingest_files_provider_account ON ingest_files(provider, account);
                    CREATE INDEX usage_records_provider_account_at ON usage_records(provider, account, at);
                    """)
        }
        return migrator
    }

    /// The stored ingest state of every file of one Account of `provider`, by path.
    public func fileStates(provider: AgentID, account: AccountID = .default) async throws
        -> [String: IngestFileState]
    {
        try await pool.read { db in
            var states: [String: IngestFileState] = [:]
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT path, read_offset, size, mtime FROM ingest_files WHERE provider = ? AND account = ?",
                arguments: [provider.rawValue, account.rawValue])
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
    public func commit(
        provider: AgentID, account: AccountID = .default, path: String, state: IngestFileState,
        records: [UsageRecord]
    ) async throws {
        try await pool.write { db in
            let upsert = try db.cachedStatement(
                sql: """
                    INSERT INTO usage_records
                        (id, at, provider, account, model, project, session_id, message_id, request_id,
                         input, output, cache_create, cache_read)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        at = excluded.at, model = excluded.model, project = excluded.project,
                        request_id = excluded.request_id, input = excluded.input, output = excluded.output,
                        cache_create = excluded.cache_create, cache_read = excluded.cache_read
                    """)
            for record in records {
                try upsert.execute(arguments: [
                    Self.recordID(provider: provider, account: account, record: record),
                    record.at.timeIntervalSince1970, provider.rawValue, account.rawValue, record.model, record.project,
                    record.sessionID, record.messageID,
                    record.requestID, record.inputTokens, record.outputTokens, record.cacheCreationTokens,
                    record.cacheReadTokens,
                ])
            }
            try db.execute(
                sql: """
                    INSERT INTO ingest_files (path, provider, account, read_offset, size, mtime)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(path) DO UPDATE SET
                        provider = excluded.provider, account = excluded.account, read_offset = excluded.read_offset,
                        size = excluded.size, mtime = excluded.mtime
                    """,
                arguments: [
                    path, provider.rawValue, account.rawValue, Int64(clamping: state.offset),
                    Int64(clamping: state.size),
                    state.mtime,
                ])
        }
    }

    /// Number of stored records (all providers when nil; every Account of the provider when `account` is nil).
    public func recordCount(provider: AgentID? = nil, account: AccountID? = nil) async throws -> Int {
        try await pool.read { db in
            var sql = "SELECT COUNT(*) FROM usage_records WHERE 1 = 1"
            var arguments: StatementArguments = []
            if let provider {
                sql += " AND provider = ?"
                arguments += [provider.rawValue]
            }
            if let account {
                sql += " AND account = ?"
                arguments += [account.rawValue]
            }
            return try Int.fetchOne(db, sql: sql, arguments: arguments) ?? 0
        }
    }

    /// The Account of each provider's latest record: the one its most recent Session ran under, as far as local
    /// logs tell (Story 7.10: the closed-notch ring shows it).
    public func latestAccounts() async throws -> [AgentID: AccountID] {
        try await pool.read { db in
            var result: [AgentID: AccountID] = [:]
            let providers = try String.fetchAll(db, sql: "SELECT DISTINCT provider FROM usage_records")
            for raw in providers {
                guard let provider = AgentID(raw),
                    let account = try String.fetchOne(
                        db, sql: "SELECT account FROM usage_records WHERE provider = ? ORDER BY at DESC LIMIT 1",
                        arguments: [raw]
                    ).flatMap(AccountID.init)
                else { continue }
                result[provider] = account
            }
            return result
        }
    }

    /// Records in `[since, until)`, summed per 15-minute slot, provider, Account, model and project.
    func aggregates(since: Date, until: Date, provider: AgentID?, account: AccountID? = nil) async throws
        -> [UsageAggregate]
    {
        try await pool.read { db in
            var sql = """
                SELECT CAST(at / \(Int(Self.slotSeconds)) AS INTEGER) AS slot, provider, account, model, project,
                    SUM(input) AS input, SUM(output) AS output, SUM(cache_create) AS cache_create,
                    SUM(cache_read) AS cache_read, COUNT(*) AS records
                FROM usage_records WHERE at >= ? AND at < ?
                """
            var arguments: StatementArguments = [since.timeIntervalSince1970, until.timeIntervalSince1970]
            if let provider {
                sql += " AND provider = ?"
                arguments += [provider.rawValue]
            }
            if let account {
                sql += " AND account = ?"
                arguments += [account.rawValue]
            }
            sql += " GROUP BY slot, provider, account, model, project ORDER BY slot"
            return try Row.fetchAll(db, sql: sql, arguments: arguments).compactMap { row in
                let slot: Int64 = row["slot"]
                let rawProvider: String = row["provider"]
                let rawAccount: String = row["account"]
                guard let provider = AgentID(rawProvider), let account = AccountID(rawAccount) else { return nil }
                return UsageAggregate(
                    slotStart: Date(timeIntervalSince1970: Double(slot) * Self.slotSeconds), provider: provider,
                    account: account, model: row["model"],
                    project: row["project"],
                    tokens: TokenCounts(
                        input: row["input"], output: row["output"], cacheCreation: row["cache_create"],
                        cacheRead: row["cache_read"]),
                    records: row["records"])
            }
        }
    }

    /// `<provider>/<session>/<message>` for the default Account (the v1 id, so its history converges),
    /// `<provider>/<account>/<session>/<message>` for the others.
    static func recordID(provider: AgentID, account: AccountID = .default, record: UsageRecord) -> String {
        account.isDefault
            ? "\(provider.rawValue)/\(record.sessionID)/\(record.messageID)"
            : "\(provider.rawValue)/\(account.rawValue)/\(record.sessionID)/\(record.messageID)"
    }
}
