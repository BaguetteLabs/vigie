import AgentKit
import Foundation
import os

/// What one ingest pass did.
public struct IngestReport: Hashable, Sendable {
    public var files = 0
    /// Files read this pass (new, grown, shrunk or touched); the rest were unchanged (same size and mtime).
    public var changedFiles = 0
    /// Files read again from the start because they shrank.
    public var restartedFiles = 0
    /// Records upserted this pass (a streaming repeat of a known response counts again).
    public var records = 0
    public var skippedLines = 0
    public var malformedLines = 0
    /// Files that could not be read; retried next pass.
    public var failedFiles = 0

    public init() {}
}

/// Incremental ingest of agent logs into `UsageStore` (AD-11, Story 7.1), off the main actor. Per file it keeps
/// the read offset, size and mtime: an unchanged file is skipped, a grown one is read from its offset, a shrunk
/// one from the start. Records are upserted by provider + session + message, so a pass over unchanged files
/// adds nothing and re-reading converges.
public actor UsageIngestor {
    public let store: UsageStore
    public let registry: UsageProviderRegistry
    let log: Logger

    public init(store: UsageStore, registry: UsageProviderRegistry, log: Logger) {
        self.store = store
        self.registry = registry
        self.log = log
    }

    /// One pass over every source. Never throws: failures are logged and counted.
    @discardableResult
    public func ingest() async -> IngestReport {
        var report = IngestReport()
        for source in registry.sources {
            await ingest(source, into: &report)
        }
        log.info(
            """
            agents.usage ingest: \(report.files, privacy: .public) files, \(report.changedFiles, privacy: .public) \
            changed, \(report.records, privacy: .public) records, \(report.skippedLines, privacy: .public) \
            skipped, \(report.malformedLines, privacy: .public) malformed, \(report.failedFiles, privacy: .public) \
            failed
            """)
        return report
    }

    private func ingest(_ source: UsageSource, into report: inout IngestReport) async {
        let files: [URL]
        let states: [String: IngestFileState]
        do {
            files = try await source.reader.logFiles()
            states = try await store.fileStates(provider: source.id)
        } catch {
            log.error(
                "agents.usage ingest \(source.id.rawValue, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            report.failedFiles += 1
            return
        }
        for file in files {
            report.files += 1
            let path = file.path
            guard let attributes = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                let size = attributes.fileSize
            else {
                report.failedFiles += 1
                continue
            }
            let mtime = attributes.contentModificationDate?.timeIntervalSince1970 ?? 0
            let stored = states[path]
            if let stored, stored.size == UInt64(size), stored.mtime == mtime { continue }
            var offset = stored?.offset ?? 0
            if let stored, UInt64(size) < stored.size || UInt64(size) < stored.offset {
                offset = 0
                report.restartedFiles += 1
            }
            do {
                let chunk = try await source.reader.readUsage(from: file, offset: offset)
                try await store.commit(
                    provider: source.id, path: path,
                    state: IngestFileState(offset: chunk.nextOffset, size: UInt64(size), mtime: mtime),
                    records: chunk.records)
                report.changedFiles += 1
                report.records += chunk.records.count
                report.skippedLines += chunk.skippedLines
                report.malformedLines += chunk.malformedLines
            } catch {
                report.failedFiles += 1
                log.error(
                    "agents.usage ingest failed for a file: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
