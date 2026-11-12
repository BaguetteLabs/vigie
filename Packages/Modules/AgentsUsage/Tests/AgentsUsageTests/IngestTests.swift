import AgentKit
import Foundation
import Testing
import os

@testable import AgentsUsage

private let log = Logger(subsystem: "test", category: "agents.usage")
private let alpha = "-Users-me-alpha/sess-a1.jsonl"
private let beta = "-Users-me-beta/sess-b1.jsonl"

private func utc(_ stamp: String) throws -> Date {
    try require(ISO8601DateFormatter().date(from: stamp))
}

private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}

/// All-time totals over the fixtures' range.
private func totals(_ store: UsageStore) async throws -> UsageSeries {
    let history = UsageHistory(store: store, estimator: try CostEstimator.bundled(), calendar: utcCalendar)
    return try await history.usage(
        since: try utc("2026-11-01T00:00:00Z"), until: try utc("2026-11-10T00:00:00Z"), bucket: .day)
}

@Suite struct IngestTests {
    @Test func firstPassReadsEveryFixture() async throws {
        let sandbox = try Sandbox()
        let store = try UsageStore(directory: sandbox.storage)
        let report = await UsageIngestor(store: store, registry: sandbox.registry, log: log).ingest()

        #expect(report.files == 3 && report.changedFiles == 3 && report.failedFiles == 0)
        // m1 twice (streaming repeat), m2, m3, m4; the partial m5 line waits.
        #expect(report.records == 5)
        #expect(report.skippedLines == 3)  // user, synthetic, attachment
        #expect(report.malformedLines == 1)
        #expect(try await store.recordCount() == 4)

        let series = try await totals(store)
        #expect(series.total.tokens == TokenCounts(input: 1130, output: 1350, cacheCreation: 10100, cacheRead: 103000))
        // The cumulative repeat converged on its last write.
        #expect(series.byModel["claude-opus-5-5"]?.tokens.output == 50)
        #expect(series.byProject["/Users/me/alpha"]?.records == 3)
        #expect(series.byProject["/Users/me/beta"]?.records == 1)
        #expect(series.windows.isEmpty)
    }

    @Test func secondPassOnUnchangedFilesAddsNothing() async throws {
        let sandbox = try Sandbox()
        let store = try UsageStore(directory: sandbox.storage)
        let ingestor = UsageIngestor(store: store, registry: sandbox.registry, log: log)
        await ingestor.ingest()
        let before = try await totals(store)

        let report = await ingestor.ingest()
        #expect(report.files == 3 && report.changedFiles == 0 && report.records == 0)
        #expect(try await store.recordCount() == 4)
        #expect(try await totals(store) == before)
    }

    @Test func appendedLinesAreTheOnlyNewRecords() async throws {
        let sandbox = try Sandbox()
        let store = try UsageStore(directory: sandbox.storage)
        let ingestor = UsageIngestor(store: store, registry: sandbox.registry, log: log)
        await ingestor.ingest()

        // Complete the partial last line of beta.
        let text = try String(contentsOf: sandbox.file(beta), encoding: .utf8)
        let partial = try require(text.split(separator: "\n", omittingEmptySubsequences: false).last)
        let full =
            #"{"parentUuid":"x","isSidechain":false,"type":"assistant","timestamp":"2026-11-06T16:00:00.000Z","sessionId":"sess-b1","requestId":"req_r5","cwd":"/Users/me/beta","version":"2.1.319","message":{"id":"msg_m5","type":"message","role":"assistant","model":"claude-opus-5-5","content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":1,"cache_creation_input_tokens":1,"cache_read_input_tokens":1,"output_tokens":1,"output_tokens_details":{"thinking_tokens":0}}}}"#
        #expect(full.hasPrefix(partial))
        try sandbox.append(beta, String(full.dropFirst(partial.count)) + "\n")

        let report = await ingestor.ingest()
        #expect(report.changedFiles == 1 && report.records == 1 && report.malformedLines == 0)
        #expect(try await store.recordCount() == 5)
        #expect(try await totals(store).total.tokens.input == 1131)
    }

    @Test func aShrunkFileIsReadAgainFromTheStart() async throws {
        let sandbox = try Sandbox()
        let store = try UsageStore(directory: sandbox.storage)
        let ingestor = UsageIngestor(store: store, registry: sandbox.registry, log: log)
        await ingestor.ingest()

        // Keep the user line and both writes of m1.
        let lines = try String(contentsOf: sandbox.file(alpha), encoding: .utf8).split(separator: "\n")
        try Data((lines.prefix(3).joined(separator: "\n") + "\n").utf8).write(to: sandbox.file(alpha))

        let report = await ingestor.ingest()
        #expect(report.restartedFiles == 1 && report.changedFiles == 1)
        #expect(report.records == 2)
        // Rows already ingested stay (records are not tied to files); m1 converges again.
        #expect(try await store.recordCount() == 4)
        #expect(try await totals(store).byModel["claude-opus-5-5"]?.tokens.output == 50)
    }

    @Test func storeStateSurvivesReopening() async throws {
        let sandbox = try Sandbox()
        await UsageIngestor(store: try UsageStore(directory: sandbox.storage), registry: sandbox.registry, log: log)
            .ingest()
        let reopened = try UsageStore(directory: sandbox.storage)
        let report = await UsageIngestor(store: reopened, registry: sandbox.registry, log: log).ingest()
        #expect(report.changedFiles == 0)
        #expect(try await reopened.recordCount() == 4)
        #expect(try await reopened.fileStates(provider: "claude").count == 3)
    }
}

@Suite struct HistoryTests {
    @Test func bucketsByDayIncludingEmptyOnes() async throws {
        let sandbox = try Sandbox()
        let store = try UsageStore(directory: sandbox.storage)
        await UsageIngestor(store: store, registry: sandbox.registry, log: log).ingest()
        let history = UsageHistory(store: store, estimator: try CostEstimator.bundled(), calendar: utcCalendar)

        let series = try await history.usage(
            since: try utc("2026-11-04T00:00:00Z"), until: try utc("2026-11-07T00:00:00Z"), bucket: .day,
            provider: "claude")
        #expect(
            series.buckets.map(\.start) == [
                try utc("2026-11-04T00:00:00Z"), try utc("2026-11-05T00:00:00Z"), try utc("2026-11-06T00:00:00Z"),
            ])
        #expect(series.buckets.map(\.totals.records) == [0, 2, 2])
        #expect(
            series.buckets[1].totals.tokens == TokenCounts(input: 30, output: 250, cacheCreation: 100, cacheRead: 3000))
        #expect(Set(series.buckets[2].byModel.keys) == ["claude-haiku-4-5-20251001", "claude-fable-5-1"])

        // Another provider has nothing.
        let other = try await history.usage(
            since: try utc("2026-11-04T00:00:00Z"), until: try utc("2026-11-07T00:00:00Z"), bucket: .day,
            provider: "codex")
        #expect(other.total == .zero)
    }

    @Test func todayIsHourlyFromLocalMidnight() async throws {
        let sandbox = try Sandbox()
        let store = try UsageStore(directory: sandbox.storage)
        await UsageIngestor(store: store, registry: sandbox.registry, log: log).ingest()
        let history = UsageHistory(store: store, estimator: try CostEstimator.bundled(), calendar: utcCalendar)
        let today = try await history.today(now: try utc("2026-11-06T18:30:00Z"))
        #expect(today.bucket == .hour && today.buckets.count == 24)
        #expect(today.total.records == 2)
        #expect(today.buckets[15].totals.records == 1)  // m4 at 15:00
    }

    @Test func costMath() async throws {
        let sandbox = try Sandbox()
        let store = try UsageStore(directory: sandbox.storage)
        await UsageIngestor(store: store, registry: sandbox.registry, log: log).ingest()
        let series = try await totals(store)
        // m1 1740e-6 + m2 2240e-6 + m3 1500e-6 + m4 201000e-6 (USD).
        #expect(abs(series.total.estimatedCost - 0.20648) < 1e-9)
        #expect(abs((series.byModel["claude-fable-5-1"]?.estimatedCost ?? 0) - 0.201) < 1e-9)
        #expect(series.total.isFullyPriced)
    }

    @Test func unknownModelsHaveNoCostAndAreCounted() async throws {
        let sandbox = try Sandbox()
        let store = try UsageStore(directory: sandbox.storage)
        let record = UsageRecord(
            at: try utc("2026-11-05T12:00:00Z"), model: "claude-mystery-9", project: "/p", sessionID: "s",
            messageID: "m", requestID: nil, inputTokens: 1_000_000, outputTokens: 0, cacheCreationTokens: 0,
            cacheReadTokens: 0)
        try await store.commit(
            provider: "claude", path: "/x.jsonl", state: IngestFileState(offset: 1, size: 1, mtime: 1),
            records: [record])
        let series = try await totals(store)
        #expect(series.total.estimatedCost == 0)
        #expect(series.total.unpricedRecords == 1 && !series.total.isFullyPriced)
        #expect(series.total.tokens.input == 1_000_000)
    }
}

@Suite struct PriceTableTests {
    @Test func bundledTableLoads() throws {
        let estimator = try CostEstimator.bundled()
        #expect(estimator.version == 2)
        #expect(estimator.table.schema == PriceTable.currentSchema)
        for id in [
            "claude-opus-4", "claude-sonnet-4", "claude-opus-4-5", "claude-sonnet-4-5", "claude-haiku-4-5",
            "claude-opus-4-8", "claude-opus-5", "claude-opus-5-5", "claude-sonnet-5", "claude-sonnet-5-5",
            "claude-fable-5-1",
        ] {
            #expect(estimator.prices(for: "claude")[id] != nil, "no price for \(id)")
        }
        #expect(
            estimator.price(for: "claude-opus-5-5", provider: "claude")
                == ModelPrice(input: 4, output: 20, cacheWrite: 5, cacheRead: 0.2))
    }

    @Test func everyFixtureModelHasAPrice() async throws {
        let sandbox = try Sandbox()
        let estimator = try CostEstimator.bundled()
        var models: Set<String> = []
        for file in try await sandbox.reader.logFiles() {
            for record in try await sandbox.reader.readUsage(from: file, offset: 0).records {
                models.insert(record.model)
            }
        }
        #expect(models.count == 4)
        for model in models { #expect(estimator.price(for: model, provider: "claude") != nil, "no price for \(model)") }
    }

    @Test func dateSuffixedIdsMatchTheLongestPrefix() throws {
        let estimator = try CostEstimator.bundled()
        let claude = estimator.prices(for: "claude")
        #expect(estimator.price(for: "claude-haiku-4-5-20251001", provider: "claude") == claude["claude-haiku-4-5"])
        #expect(estimator.price(for: "claude-opus-4-20250514", provider: "claude") == claude["claude-opus-4"])
        #expect(estimator.price(for: "claude-opus-4-8", provider: "claude") == claude["claude-opus-4-8"])
        #expect(estimator.price(for: "claude-opus", provider: "claude") == nil)
        #expect(estimator.cost(of: TokenCounts(input: 1), model: "gpt-x", provider: "claude") == nil)
    }
}
