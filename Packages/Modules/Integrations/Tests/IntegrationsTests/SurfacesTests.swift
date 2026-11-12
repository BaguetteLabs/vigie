import Foundation
import ModuleKit
import SwiftUI
import Testing
import VigieUI

@testable import Integrations

/// A script file with the surface keys of the front matter.
func surfaceScript(
    id: String, name: String = "Site", widget: String = "status", surfaces: String = "[home, side, page]",
    priority: Int? = nil, code: String = "print(1)"
) -> Data {
    var lines = [
        "---", "id: \(id)", "name: \(name)", "icon: globe", "interval: 1m", "runtime: python3", "widget: \(widget)",
        "surfaces: \(surfaces)",
    ]
    if let priority { lines.append("priority: \(priority)") }
    lines += ["---", "", "Docs.", "", "```python", code, "```", ""]
    return Data(lines.joined(separator: "\n").utf8)
}

func frontMatter(
    _ widget: ScriptWidgetType = .status, surfaces: [ScriptSurface] = [.home, .side, .page], priority: Int? = nil
) -> ScriptFrontMatter {
    ScriptFrontMatter(
        id: "site.status", name: "vigie.app", interval: .seconds(60), runtime: "python3", widget: widget,
        surfaces: surfaces, priority: priority)
}

func output(
    _ type: ScriptWidgetType = .status, value: String? = "200 · 142 ms", label: String? = "vigie.app",
    detail: String? = "up", level: ScriptLevel? = .ok, state: ModuleState = .ambient, action: ScriptAction? = nil
) -> ScriptOutput {
    ScriptOutput(
        state: state, widget: ScriptWidget(type: type, value: value, label: label, detail: detail, level: level),
        action: action)
}

func goodRecord(_ output: ScriptOutput, at date: Date) -> ScriptRunRecord {
    ScriptRunRecord(startedAt: date, duration: .milliseconds(100), outcome: .succeeded(output), stderrExcerpt: "")
}

/// Story 12.5: dynamic script modules, their surfaces, state, lane priority and actions.
@MainActor @Suite struct SurfacesTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Registration

    final class Folder {
        let root: URL
        let modules: URL
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "integrations-surfaces-\(UUID().uuidString)", isDirectory: true)
            modules = root.appendingPathComponent("modules", isDirectory: true)
            try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        }
        func write(_ name: String, _ data: Data) throws { try data.write(to: modules.appendingPathComponent(name)) }
        func remove(_ name: String) throws {
            try FileManager.default.removeItem(at: modules.appendingPathComponent(name))
        }
        deinit { try? FileManager.default.removeItem(at: root) }
    }

    @Test func registersParsedScriptsAndUnregistersOnRemovalErrorAndDecline() async throws {
        let folder = try Folder()
        try folder.write("a.md", surfaceScript(id: "a.script"))
        try folder.write("b.md", Data("---\nid: b.script\n---\nno code\n".utf8))
        try folder.write("c.md", surfaceScript(id: "c.script", widget: "number"))
        let context = FakeModuleContext(scriptFolder: FakeScriptFolder(url: folder.modules))
        let host = context.fakeHost
        let module = IntegrationsModule()
        try await module.start(context: context)

        // Awaiting confirmation is registered (NOT CONFIRMED); the errored file is not.
        #expect(host.registeredIDs == ["a.script", "c.script"])
        let a = try #require(module.scriptModules["a.md"])
        #expect(a.manifest.id == "a.script")
        #expect(String(localized: a.manifest.name) == "Site")
        #expect(a.manifest.icon == "globe")
        #expect(a.snapshot.local == .awaitingConfirmation)
        #expect(a.state == .ambient)
        #expect(module.runner?.states.isEmpty == true, "registered, never run before a confirmation")

        // Confirming keeps the same registration.
        try await module.confirm(module.scripts[0])
        #expect(host.registrations == 2)
        #expect(module.scriptModules["a.md"] === a)

        // Decline unregisters.
        try await module.decline(try #require(module.scripts.first { $0.id == "c.md" }))
        #expect(host.registeredIDs == ["a.script"])

        // A parse error unregisters; fixing it registers again.
        try folder.write("a.md", Data("---\nid: a.script\nname: Site\n---\nbroken\n".utf8))
        await module.rescan()
        #expect(host.registeredIDs.isEmpty)
        try folder.write("a.md", surfaceScript(id: "a.script"))
        await module.rescan()
        #expect(host.registeredIDs == ["a.script"])

        // A front-matter change re-registers (new manifest); a code change keeps the module.
        let before = try #require(module.scriptModules["a.md"])
        try folder.write("a.md", surfaceScript(id: "a.script", code: "print(2)"))
        await module.rescan()
        #expect(module.scriptModules["a.md"] === before)
        #expect(before.definition.code == "print(2)")
        try folder.write("a.md", surfaceScript(id: "a.script", name: "Site 2"))
        await module.rescan()
        let renamed = try #require(module.scriptModules["a.md"])
        #expect(renamed !== before)
        #expect(String(localized: renamed.manifest.name) == "Site 2")
        #expect(host.registeredIDs == ["a.script"])

        // Removal unregisters.
        try folder.remove("a.md")
        await module.rescan()
        #expect(host.registeredIDs.isEmpty)
        #expect(module.scriptModules.isEmpty)

        try folder.write("d.md", surfaceScript(id: "d.script"))
        await module.rescan()
        #expect(host.registeredIDs == ["d.script"])
        await module.stop()
        #expect(host.registeredIDs.isEmpty, "stop cancels every registration")
    }

    @Test func registrationDoesNotDependOnEnabledAndSurvivesAHostRefusal() async throws {
        let folder = try Folder()
        try folder.write("a.md", surfaceScript(id: "a.script"))
        let context = FakeModuleContext(
            scriptFolder: FakeScriptFolder(url: folder.modules, enabled: ["a.script": false]))
        context.fakeHost.registrationError = ModuleServiceError.notAvailable
        let module = IntegrationsModule()
        try await module.start(context: context)
        #expect(module.scriptModules.isEmpty)
        context.fakeHost.registrationError = nil
        await module.rescan()
        #expect(context.fakeHost.registeredIDs == ["a.script"], "disabled scripts are registered too")
        await module.stop()
    }

    // MARK: State

    @Test func stateFollowsConfirmationAndTheRun() {
        let fm = frontMatter()
        func state(_ local: ScriptLocalState, _ run: ScriptRunState?) -> ModuleState {
            ScriptSurfaces.state(ScriptSurfaceSnapshot(frontMatter: fm, local: local, run: run))
        }
        #expect(state(.declined, nil) == .hidden)
        #expect(state(.awaitingConfirmation, nil) == .ambient)
        #expect(state(.confirmed, nil) == .ambient)
        #expect(state(.confirmed, ScriptRunState()) == .ambient)
        #expect(state(.confirmed, ScriptRunState(phase: .ok(output(state: .alert), at: Self.t0))) == .alert)
        #expect(state(.confirmed, ScriptRunState(phase: .ok(output(state: .hidden), at: Self.t0))) == .hidden)
        let failed = ScriptRunState(phase: .errored(.failed(exitCode: 3), lastGoodOutput: nil, at: Self.t0))
        #expect(state(.confirmed, failed) == .ambient)
        let failedAfterActive = ScriptRunState(
            phase: .errored(.timedOut(seconds: 30), lastGoodOutput: output(state: .active), at: Self.t0))
        #expect(state(.confirmed, failedAfterActive) == .active)
        let failedAfterHidden = ScriptRunState(
            phase: .errored(.timedOut(seconds: 30), lastGoodOutput: output(state: .hidden), at: Self.t0))
        #expect(state(.confirmed, failedAfterHidden) == .ambient, "a failure stays visible")
    }

    // MARK: Card

    @Test func cardShowsTheStateOfTheScript() {
        let fm = frontMatter()
        func card(_ local: ScriptLocalState, _ run: ScriptRunState?) -> ScriptCardModel {
            ScriptSurfaces.card(ScriptSurfaceSnapshot(frontMatter: fm, local: local, run: run))
        }
        #expect(card(.awaitingConfirmation, nil).body == .notConfirmed)
        #expect(card(.awaitingConfirmation, nil).cadence == "EVERY 1M")
        #expect(card(.awaitingConfirmation, nil).name == "vigie.app")
        #expect(card(.confirmed, ScriptRunState()).body == .state("WAITING · FIRST RUN"))

        let ok = card(.confirmed, ScriptRunState(phase: .ok(output(action: .open("https://vigie.app")), at: Self.t0)))
        #expect(ok.target == "vigie.app")
        #expect(ok.body == .output(.status(level: .ok, qualifier: "up", value: "200 · 142 ms")))
        #expect(ok.meta == .checked(Self.t0))
        #expect(ok.action == .open)
        #expect(!ok.warningBadge)

        let number = card(
            .confirmed,
            ScriptRunState(
                phase: .ok(output(.number, value: "3", label: "open", detail: "2 awaiting", level: .warn), at: Self.t0))
        )
        #expect(number.target == nil)
        #expect(
            number.body
                == .output(
                    .number(
                        value: "3", label: "open", detail: "2 awaiting", bar: ScriptNumberBar(value: 3), level: .warn)))
        #expect(number.meta == .updated(Self.t0))

        let text = card(
            .confirmed,
            ScriptRunState(phase: .ok(output(.text, value: "Fri 14:00", label: nil, level: nil), at: Self.t0)))
        #expect(text.body == .output(.text(label: nil, value: "Fri 14:00", level: nil)))
        #expect(text.meta == .updated(Self.t0))
    }

    @Test func downSinceIsTheStartOfTheDownStreak() {
        let down = output(level: .error)
        let up = output(level: .ok)
        let failure = ScriptRunRecord(
            startedAt: Self.t0.addingTimeInterval(150), duration: .zero, outcome: .failed(exitCode: 1),
            stderrExcerpt: "")
        let records = [
            goodRecord(down, at: Self.t0.addingTimeInterval(180)), failure,
            goodRecord(down, at: Self.t0.addingTimeInterval(120)), goodRecord(down, at: Self.t0.addingTimeInterval(60)),
            goodRecord(up, at: Self.t0),
        ]
        #expect(ScriptSurfaces.downSince(records) == Self.t0.addingTimeInterval(60))
        let model = ScriptSurfaces.card(
            ScriptSurfaceSnapshot(
                frontMatter: frontMatter(), local: .confirmed,
                run: ScriptRunState(phase: .ok(down, at: Self.t0.addingTimeInterval(181)), records: records)))
        #expect(model.meta == .downSince(Self.t0.addingTimeInterval(60)))
    }

    @Test func anErroredScriptKeepsItsLastGoodOutputWithTheWarnBadge() {
        let fm = frontMatter()
        let withOutput = ScriptSurfaces.card(
            ScriptSurfaceSnapshot(
                frontMatter: fm, local: .confirmed,
                run: ScriptRunState(phase: .errored(.timedOut(seconds: 30), lastGoodOutput: output(), at: Self.t0))))
        #expect(withOutput.body == .output(.status(level: .ok, qualifier: "up", value: "200 · 142 ms")))
        #expect(withOutput.warningBadge)
        #expect(withOutput.meta == .label("TIMED OUT · 30S"))

        let without = ScriptSurfaces.card(
            ScriptSurfaceSnapshot(
                frontMatter: fm, local: .confirmed,
                run: ScriptRunState(phase: .errored(.failed(exitCode: 3), lastGoodOutput: nil, at: Self.t0))))
        #expect(without.body == .state("EXIT 3"))
        #expect(without.warningBadge)
    }

    // MARK: Side slot

    @Test func sideItemIsLevelOverTargetOrValueOverLabel() {
        func item(_ fm: ScriptFrontMatter, _ local: ScriptLocalState, _ run: ScriptRunState?) -> ScriptSideItemModel {
            ScriptSurfaces.sideItem(ScriptSurfaceSnapshot(frontMatter: fm, local: local, run: run))
        }
        let status = item(frontMatter(), .confirmed, ScriptRunState(phase: .ok(output(), at: Self.t0)))
        #expect(status.content == .level(.ok, target: "vigie.app"))
        #expect(status.accessibilityLabel == "vigie.app, OK")
        let down = item(frontMatter(), .confirmed, ScriptRunState(phase: .ok(output(level: .error), at: Self.t0)))
        #expect(down.accessibilityLabel == "vigie.app, DOWN")
        let number = item(
            frontMatter(.number), .confirmed,
            ScriptRunState(phase: .ok(output(.number, value: "3", label: "open", level: nil), at: Self.t0)))
        #expect(number.content == .value("3", label: "open", valueIsText: false))
        let text = item(
            frontMatter(.text), .confirmed,
            ScriptRunState(phase: .ok(output(.text, value: "release/0.3", label: nil, level: nil), at: Self.t0)))
        #expect(text.content == .value("release/0.3", label: "TEXT", valueIsText: true))
        #expect(item(frontMatter(), .awaitingConfirmation, nil).content == .state("NOT CONFIRMED"))
        #expect(item(frontMatter(), .confirmed, ScriptRunState()).content == .state("WAITING · FIRST RUN"))
        #expect(
            item(
                frontMatter(), .confirmed,
                ScriptRunState(phase: .errored(.failed(exitCode: 2), lastGoodOutput: nil, at: Self.t0))
            ).content == .state("EXIT 2"))
    }

    // MARK: Surfaces and priority

    static func module(
        _ fm: ScriptFrontMatter, local: ScriptLocalState = .confirmed, run: ScriptRunState? = nil,
        performed: Box<[(ScriptAction, String)]> = Box([]), reviewed: Box<[String]> = Box([])
    ) -> ScriptModule {
        let definition = runnerDefinition(surfaceScript(id: fm.id.rawValue), name: "site.md")
        return ScriptModule(
            definition: definition, frontMatter: fm,
            source: ScriptModuleSource(
                localState: { _ in local }, runState: { _ in run },
                perform: { performed.value.append(($0, $1)) }, review: { reviewed.value.append($0.id) }))
    }

    final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    @Test func surfacesFollowTheFrontMatter() {
        let all = Self.module(frontMatter(priority: 2))
        #expect(all.homeCard() != nil)
        #expect(all.expandedView() != nil, "page: a tab named after the script")
        let items = all.leftWingItems()
        #expect(items.map(\.id) == [ScriptModule.sideItemID])
        #expect(items.first?.priority == 2, "front matter priority")
        #expect(items.first?.state == nil, "ranked by the module's state")
        #expect(items.first?.compactView(.short) != nil)

        let homeOnly = Self.module(frontMatter(surfaces: [.home]))
        #expect(homeOnly.leftWingItems().isEmpty)
        #expect(homeOnly.expandedView() == nil)
        #expect(Self.module(frontMatter(surfaces: [.side])).homeCard() == nil)
        #expect(
            Self.module(frontMatter(surfaces: [.side])).leftWingItems().first?.priority
                == ScriptSurfaces.defaultPriority)
    }

    @Test func pagePlaceholderStringsResolve() {
        for key in ["script.page.placeholder.label", "script.page.placeholder.sentence", "script.card.cadence"] {
            #expect(IntegrationsText.string(key) != key)
        }
    }

    // MARK: Actions

    @Test func activateRunsTheOutputActionOnlyWhenConfirmed() {
        let performed = Box<[(ScriptAction, String)]>([])
        let run = ScriptRunState(phase: .ok(output(action: .copy("hello")), at: Self.t0))
        Self.module(frontMatter(), run: run, performed: performed).activate()
        #expect(performed.value.map(\.0) == [.copy("hello")])
        #expect(performed.value.map(\.1) == ["site.md"])

        Self.module(frontMatter(), local: .awaitingConfirmation, run: run, performed: performed).activate()
        Self.module(frontMatter(), run: ScriptRunState(), performed: performed).activate()
        #expect(performed.value.count == 1)

        // An errored script still acts on its last good output.
        let errored = ScriptRunState(
            phase: .errored(.failed(exitCode: 1), lastGoodOutput: output(action: .open("https://a.b")), at: Self.t0))
        Self.module(frontMatter(), run: errored, performed: performed).activate()
        #expect(performed.value.last?.0 == .open("https://a.b"))

        let reviewed = Box<[String]>([])
        Self.module(frontMatter(), local: .awaitingConfirmation, reviewed: reviewed).review()
        #expect(reviewed.value == ["site.md"])
    }

    @Test func openAndCopyGoThroughTheHostFacilities() async throws {
        let context = FakeModuleContext()
        let module = IntegrationsModule()
        try await module.start(context: context)
        var opened: [URL] = []
        module.surfaces.openURL = { opened.append($0) }
        module.perform(.open("https://github.com/me/project/pulls"), scriptID: "x.md")
        #expect(opened == [URL(string: "https://github.com/me/project/pulls")!])
        module.perform(.copy("release/0.3"), scriptID: "x.md")
        #expect(context.fakeClipboard.copied == ["release/0.3"])
        await module.stop()
    }

    @Test func runActionsUseTheRunnerRulesAndAreRecorded() async throws {
        let h = RunnerHarness(
            resolver: FakeResolver([
                "python3": URL(fileURLWithPath: "/opt/homebrew/bin/python3"),
                "gh": URL(fileURLWithPath: "/opt/homebrew/bin/gh"),
            ]))
        defer { h.cleanUp() }
        let definition = runnerDefinition(runnerScript(interval: "5m"))
        h.runner.update([definition])
        await h.runner.waitForIdle()
        let phase = h.state()?.phase

        h.launcher.enqueue(launchResult(.exited(4), stdout: Data("not json".utf8)))
        h.runner.run(argv: ["gh", "pr", "list"], for: "test.md")
        await h.runner.waitForIdle()
        let launch = try #require(h.launcher.launches.last)
        #expect(launch.request.executable.path == "/opt/homebrew/bin/gh")
        #expect(launch.request.arguments == ["pr", "list"])
        #expect(launch.request.workingDirectory?.path == "/runner-tests/modules")
        #expect(launch.request.timeout == .seconds(30))
        #expect(launch.request.environment["HOME"] == "/Users/tester")
        let record = try #require(h.state()?.records.first)
        #expect(record.action == ["gh", "pr", "list"])
        #expect(record.outcome == .actionExited(4))
        #expect(ScriptRunLabel.outcome(record.outcome) == "EXIT 4")
        #expect(h.state()?.phase == phase, "the widget keeps its output")

        // Unknown executable: recorded, nothing launched.
        let count = h.launcher.count
        h.runner.run(argv: ["nope"], for: "test.md")
        await h.runner.waitForIdle()
        #expect(h.launcher.count == count)
        #expect(h.state()?.records.first?.outcome == .runtimeNotFound("nope"))

        // A script that does not run (not eligible) never runs actions.
        h.runner.run(argv: ["gh"], for: "other.md")
        await h.runner.waitForIdle()
        #expect(h.launcher.count == count)
        await h.runner.stop()
    }
}
