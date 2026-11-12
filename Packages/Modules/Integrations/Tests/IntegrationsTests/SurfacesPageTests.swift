import Foundation
import ModuleKit
import Observation
import SwiftUI
import Testing
import VigieUI

@testable import Integrations

/// Story 12.11: the script page's model from a definition and run state, its live updates, and its actions.
@MainActor @Suite struct SurfacesPageTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    static func definition(name: String = "site-status.md") -> ScriptModuleDefinition {
        runnerDefinition(surfaceScript(id: "site.status"), name: name)
    }

    static func record(_ outcome: ScriptRunOutcome, at offset: TimeInterval, ms: Int = 400) -> ScriptRunRecord {
        ScriptRunRecord(
            startedAt: t0.addingTimeInterval(offset), duration: .milliseconds(ms), outcome: outcome, stderrExcerpt: "")
    }

    /// Newest first: timed out, exit 3, ok, and a widget `run` action (not a run of the script).
    static let records = [
        record(.timedOut(seconds: 30), at: 180, ms: 30_000),
        ScriptRunRecord(
            startedAt: t0.addingTimeInterval(150), duration: .milliseconds(80), outcome: .actionExited(0),
            stderrExcerpt: "", action: ["open", "x"]),
        record(.failed(exitCode: 3), at: 120, ms: 1_200),
        record(.succeeded(output()), at: 60),
    ]

    static func page(_ local: ScriptLocalState, _ run: ScriptRunState?) -> ScriptPageModel {
        ScriptSurfaces.page(
            ScriptSurfaceSnapshot(frontMatter: frontMatter(), local: local, run: run), definition: definition())
    }

    @Test func pageModelComesFromTheDefinitionAndTheRunState() {
        let run = ScriptRunState(
            phase: .errored(.timedOut(seconds: 30), lastGoodOutput: output(), at: Self.t0.addingTimeInterval(180)),
            records: Self.records, nextRunAt: Self.t0.addingTimeInterval(240))
        let page = Self.page(.confirmed, run)
        #expect(page.aboutHeading == "ABOUT · FROM site-status.md")
        #expect(page.documentation == "Docs.")
        #expect(page.kind == .status)
        #expect(page.heroMeta == "STATUS WIDGET · EVERY 1M")
        #expect(page.runs.runtime == "python3")
        #expect(page.runs.interval == .seconds(60))
        #expect(page.runs.timeout == .seconds(30), "min(interval, 30 s)")
        #expect(page.runs.fileName == "site-status.md")
        #expect(page.runs.folder == "/runner-tests/modules/")
        #expect(page.runs.nextRunAt == Self.t0.addingTimeInterval(240))
        #expect(page.runs.runs.map(\.result.label) == ["TIMED OUT · 30S", "EXIT 3", "OK"], "actions left out")
        #expect(page.runs.runs.map(\.exitCode) == [nil, 3, 0])
        #expect(page.runs.lastRunDetail == "TIMED OUT · 30S · 30 s")

        // A failure keeps the last good output with the WARN badge.
        #expect(page.hero.body == .output(.status(level: .ok, qualifier: "up", value: "200 · 142 ms")))
        #expect(page.hero.warningBadge)

        let five = ScriptFrontMatter(
            id: "a.b", name: "A", interval: .seconds(10), runtime: "bash", widget: .number, surfaces: [.page])
        let short = ScriptSurfaces.page(
            ScriptSurfaceSnapshot(frontMatter: five, local: .confirmed, run: nil), definition: Self.definition())
        #expect(short.runs.timeout == .seconds(10))
        #expect(short.kind == .number)
        #expect(short.runs.runtime == "bash")
    }

    @Test func heroStatesFollowConfirmationAndRuns() {
        #expect(Self.page(.awaitingConfirmation, nil).hero.body == .notConfirmed)
        #expect(Self.page(.awaitingConfirmation, nil).heroIsActionable)
        #expect(Self.page(.confirmed, ScriptRunState()).hero.body == .state("WAITING · FIRST RUN"))
        let failed = Self.page(
            .confirmed, ScriptRunState(phase: .errored(.failed(exitCode: 3), lastGoodOutput: nil, at: Self.t0)))
        #expect(failed.hero.body == .state("EXIT 3"))
        // Not confirmed: no runs shown even if a stale state exists.
        let stale = Self.page(.awaitingConfirmation, ScriptRunState(records: Self.records))
        #expect(stale.runs.runs.isEmpty)
    }

    @Test func otherFailuresReadTheirRunnerLabel() {
        let rows = [ScriptRunOutcome.invalidOutput("x"), .runtimeNotFound("python3"), .launchFailed("e")].map {
            ScriptSurfaces.runRow(Self.record($0, at: 0)).result.label
        }
        #expect(rows == ["INVALID OUTPUT", "RUNTIME NOT FOUND", "LAUNCH FAILED"])
    }

    @Observable final class Runs {
        var state: ScriptRunState?
        init(_ state: ScriptRunState?) { self.state = state }
    }

    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var raised = false
        var value: Bool { lock.withLock { raised } }
        func set() { lock.withLock { raised = true } }
    }

    @Test func pageUpdatesWhenARunCompletes() async {
        let runs = Runs(ScriptRunState(nextRunAt: Self.t0))
        let module = ScriptModule(
            definition: Self.definition(), frontMatter: frontMatter(),
            source: ScriptModuleSource(
                localState: { _ in .confirmed }, runState: { _ in runs.state }, perform: { _, _ in },
                review: { _ in }))
        #expect(module.pageModel.hero.body == .state("WAITING · FIRST RUN"))
        let changed = Flag()
        withObservationTracking {
            _ = module.pageModel
        } onChange: {
            changed.set()
        }
        runs.state = ScriptRunState(
            phase: .ok(output(), at: Self.t0), records: [Self.record(.succeeded(output()), at: 0)],
            nextRunAt: Self.t0.addingTimeInterval(60))
        #expect(changed.value, "reading the page model tracks the run state")
        #expect(module.pageModel.runs.runs.count == 1)
        #expect(module.pageModel.hero.body == .output(.status(level: .ok, qualifier: "up", value: "200 · 142 ms")))
        #expect(module.expandedView() != nil)
    }

    @Test func revealOpenSourceAndReviewGoThroughTheSeams() async throws {
        let folder = try SurfacesTests.Folder()
        try folder.write("site-status.md", surfaceScript(id: "site.status"))
        let context = FakeModuleContext(scriptFolder: FakeScriptFolder(url: folder.modules))
        let module = IntegrationsModule()
        try await module.start(context: context)
        var revealed: [URL] = []
        var opened: [URL] = []
        module.surfaces.revealInFinder = { revealed.append($0) }
        module.surfaces.openFile = { opened.append($0) }
        let script = try #require(module.scriptModules["site-status.md"])
        let file = folder.modules.appendingPathComponent("site-status.md")

        script.reveal()
        script.openSource()
        #expect(revealed.map(\.standardizedFileURL) == [file.standardizedFileURL])
        #expect(opened.map(\.standardizedFileURL) == [file.standardizedFileURL])

        // NOT CONFIRMED on the hero opens the Script Confirmation on the file.
        #expect(script.pageModel.hero.body == .notConfirmed)
        script.review()
        #expect(module.reviewing?.id == "site-status.md")
        await module.stop()
    }
}
