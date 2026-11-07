import Foundation
import ModuleKit
import Testing
import Wire

@testable import VigieCore

@Suite("ActivityStore")
struct ActivityStoreTests {
    let root = makeTempDirectory()
    var env: AppEnvironment { makeEnvironment(root) }
    let t0 = Date(timeIntervalSince1970: 1_800_000_000.123)  // 2027-01-15 UTC

    func entry(_ at: Date, kind: String = "k", outcome: ActivityOutcome = .posted) -> ActivityEntry {
        .alert(module: "agents", kind: kind, severity: .warn, dedupeKey: "d", outcome: outcome, at: at)
    }

    func lines(_ store: ActivityStore, _ day: String) throws -> [String] {
        let url = store.directory.appendingPathComponent("\(day).jsonl")
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    @Test func appendWritesOneLinePerEntryWithMode0600() async throws {
        let store = ActivityStore(environment: env)
        await store.append(entry(t0))
        await store.append(entry(t0.addingTimeInterval(1)))
        let l = try lines(store, "2027-01-15")
        #expect(l.count == 2)
        let file = store.directory.appendingPathComponent("2027-01-15.jsonl").path
        let attrs = try FileManager.default.attributesOfItem(atPath: file)
        #expect((attrs[.posixPermissions] as? Int) == 0o600)
        let dir = try FileManager.default.attributesOfItem(atPath: store.directory.path)
        #expect((dir[.posixPermissions] as? Int) == 0o700)
        #expect(l[0].contains("2027-01-15T"))
    }

    @Test func roundTripKeepsFractionalSeconds() async throws {
        let store = ActivityStore(environment: env)
        let e = ActivityEntry(
            at: t0, module: "agents", category: .focus, kind: "focus", severity: .info, dedupeKey: "x",
            outcome: .focusFailed(reason: "no:tab"), adapter: "ghostty", detail: ["a": "b"])
        await store.append(e)
        let back = await store.entries(on: t0)
        #expect(back == [e])
        #expect(try lines(store, "2027-01-15")[0].contains(".123Z"))
    }

    @Test func dayBoundaryIsUTC() async throws {
        let store = ActivityStore(environment: env)
        let late = Date(timeIntervalSince1970: 1_800_057_599.5)  // 2027-01-15T23:59:59.5Z
        await store.append(entry(late))
        await store.append(entry(late.addingTimeInterval(1)))
        #expect(try lines(store, "2027-01-15").count == 1)
        #expect(try lines(store, "2027-01-16").count == 1)
    }

    @Test func corruptLineIsSkippedAndCounted() async throws {
        let store = ActivityStore(environment: env)
        await store.append(entry(t0))
        let url = store.directory.appendingPathComponent("2027-01-15.jsonl")
        let h = try FileHandle(forWritingTo: url)
        try h.seekToEnd()
        try h.write(contentsOf: Data("{not json\n".utf8))
        try h.close()
        await store.append(entry(t0.addingTimeInterval(1)))
        #expect(await store.entries(on: t0).count == 2)
        #expect(await store.skippedLines == 1)
    }

    @Test func sinceIsNewestFirstAndLimited() async {
        let store = ActivityStore(environment: env)
        for i in 0..<5 { await store.append(entry(t0.addingTimeInterval(Double(i) * 86_400), kind: "k\(i)")) }
        let all = await store.entries(since: t0.addingTimeInterval(-1))
        #expect(all.map(\.kind) == ["k4", "k3", "k2", "k1", "k0"])
        let two = await store.entries(since: t0.addingTimeInterval(-1), limit: 2)
        #expect(two.map(\.kind) == ["k4", "k3"])
    }

    @Test func summaryCounts() async {
        let store = ActivityStore(environment: env)
        await store.append(entry(t0, kind: "done"))
        await store.append(entry(t0, kind: "done"))
        await store.append(entry(t0, kind: "blocked"))
        await store.append(entry(t0, outcome: .suppressed(reason: "mute")))
        await store.append(entry(t0, outcome: .shown))
        await store.append(entry(t0, outcome: .repeated))
        await store.append(.focus(module: "agents", adapter: "a", outcome: .focusExact, at: t0))
        await store.append(.focus(module: "agents", adapter: "a", outcome: .focusAppOnly, at: t0))
        await store.append(.focus(module: "agents", adapter: "a", outcome: .focusFailed(reason: "x"), at: t0))
        let s = await store.summary(for: t0)
        #expect(s.alertsByKind == ["done": 2, "blocked": 1])
        #expect(s.suppressedByReason == ["mute": 1])
        #expect(s.peeks == 1 && s.reminders == 1)
        #expect(s.focusExact == 1 && s.focusAppOnly == 1 && s.focusFailed == 1)
    }

    @Test func pruneRemovesOldFilesOnly() async throws {
        let store = ActivityStore(environment: env, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        for n in ["2026-12-01.jsonl", "2026-12-14.jsonl", "2026-12-20.jsonl", "2027-01-14.jsonl", "notes.txt"] {
            try Data("{}\n".utf8).write(to: store.directory.appendingPathComponent(n))
        }
        #expect(await store.prune() == 2)  // cutoff 2026-12-16
        let left = try FileManager.default.contentsOfDirectory(atPath: store.directory.path).sorted()
        #expect(left == ["2026-12-20.jsonl", "2027-01-14.jsonl", "notes.txt"])
    }

    @Test func redactionDropsSecretsAndTruncates() {
        let e = ActivityEntry(
            category: .module, kind: "k", outcome: .posted,
            detail: [
                "api_token": "s", "Secret": "s", "pwd_password": "s", "APIKey": "s",
                "note": String(repeating: "x", count: 500),
            ]
        ).redacted()
        #expect(e.detail.keys.sorted() == ["note"])
        #expect(e.detail["note"]?.count == 200)
    }

    @Test func coreActivityLogStampsModule() async {
        let store = ActivityStore(environment: env)
        CoreActivityLog(moduleID: "notes", store: store)
            .record(
                ActivityEntry(
                    at: t0, module: "agents", category: .module, kind: "k", outcome: .custom("x"),
                    detail: ["token": "s"]))
        #expect(await eventually { await store.entries(on: self.t0).count == 1 })
        let e = await store.entries(on: t0)[0]
        #expect(e.module == "notes" && e.detail.isEmpty)
    }

    @Test func concurrentAppendsNeverInterleave() async throws {
        let store = ActivityStore(environment: env)
        let t0 = self.t0
        await withTaskGroup(of: Void.self) { g in
            for w in 0..<4 {
                g.addTask {
                    for i in 0..<50 {
                        await store.append(
                            ActivityEntry(
                                at: t0, category: .module, kind: "w\(w)-\(i)", outcome: .posted,
                                detail: ["p": String(repeating: "y", count: 150)]))
                    }
                }
            }
        }
        #expect(await store.entries(on: t0).count == 200)
        #expect(await store.skippedLines == 0)
    }

    @Test func storeLivesUnderApplicationSupport() async {
        let store = ActivityStore(environment: env)
        #expect(store.directory.path.hasPrefix(env.applicationSupportURL.path))
        #expect(store.directory.lastPathComponent == "activity")
    }
}
