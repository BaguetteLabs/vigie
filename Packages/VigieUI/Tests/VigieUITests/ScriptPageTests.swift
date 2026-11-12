import AppKit
import Foundation
import ModuleKit
import SwiftUI
import Testing

@testable import VigieUI

/// Story 12.11: the script page (DESIGN "Script page", UX-DR86, UX-DR87; AD-24).
@MainActor @Suite struct ScriptPageTests {
    static let theme = Fixtures.library.resolve(themeID: ThemeLibrary.defaultVariantID, look: .dark).theme
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let utc = TimeZone(identifier: "UTC")!
    static func seed(_ n: Int) -> String { PrivacyTests.seed(n) }

    static let runs = ScriptRunsCardModel(
        runtime: "bash", interval: .seconds(60), timeout: .seconds(30), fileName: "site-status.md",
        folder: "~/Vigie/modules/",
        runs: [
            ScriptRunRow(
                startedAt: now.addingTimeInterval(-60), duration: .seconds(30), result: .timedOut(seconds: 30)),
            ScriptRunRow(
                startedAt: now.addingTimeInterval(-120), duration: .milliseconds(1_200), result: .exit(3),
                exitCode: 3),
            ScriptRunRow(
                startedAt: now.addingTimeInterval(-180), duration: .milliseconds(400), result: .ok, exitCode: 0),
        ],
        nextRunAt: now.addingTimeInterval(38))

    static func page(
        _ body: ScriptCardModel.Body = .output(.status(level: .ok, qualifier: "up", value: "200 · 142 ms")),
        target: String? = "vigie.app", meta: ScriptCardMeta? = .checked(now.addingTimeInterval(-120)),
        warning: Bool = false, action: ScriptWidgetAction? = .open, documentation: String = "# Site\n\nChecks it."
    ) -> ScriptPageModel {
        ScriptPageModel(
            hero: ScriptCardModel(
                name: "vigie.app", target: target, cadence: "EVERY 1M", body: body, meta: meta,
                warningBadge: warning, action: action),
            kind: .status, documentation: documentation, runs: runs)
    }

    // MARK: Labels

    @Test func headingsAndRunsCardLabels() {
        let page = Self.page()
        #expect(page.aboutHeading == "ABOUT · FROM site-status.md")
        #expect(page.aboutMeta == "FROM site-status.md")
        #expect(page.heroMeta == "STATUS WIDGET · EVERY 1M")
        let runs = page.runs
        #expect(runs.runs.map(\.result.label) == ["TIMED OUT · 30S", "EXIT 3", "OK"])
        #expect(runs.runs.map(\.durationText) == ["30 s", "1.2 s", "0.4 s"])
        #expect(runs.runs[1].timeText(timeZone: Self.utc) == "07:58:00")
        #expect(runs.runs[2].accessibilityLabel(timeZone: Self.utc) == "07:57:00, 0.4 s, OK")
        #expect(runs.lastRunDetail == "TIMED OUT · 30S · 30 s")
        var exited = runs
        exited.runs = Array(runs.runs.dropFirst(2))
        #expect(exited.lastRunDetail == "exit 0 · 0.4 s")
        #expect(runs.timeoutText == "30 s")
        #expect(runs.nextRunText(timeZone: Self.utc) == "08:00:38")
        #expect(runs.nextRunDetail(now: Self.now) == "in 38 s · every 1 m")
        #expect(runs.nextRunDetail(now: Self.now.addingTimeInterval(37.2)) == "in 1 s · every 1 m", "rounded up")
        #expect(runs.nextRunDetail(now: Self.now.addingTimeInterval(90)) == "in 0 s · every 1 m")
        var running = runs
        running.isRunning = true
        #expect(running.nextRunText() == "RUNNING")
        #expect(running.nextRunDetail(now: Self.now) == "every 1 m")
        var idle = runs
        idle.nextRunAt = nil
        idle.runs = []
        #expect(idle.nextRunText() == "NOT SCHEDULED")
        #expect(idle.lastRun == nil)
        #expect(idle.lastRunDetail == nil)
    }

    @Test func durationFormats() {
        #expect(ScriptPageFormat.duration(.milliseconds(400)) == "0.4 s")
        #expect(ScriptPageFormat.duration(.milliseconds(2_340)) == "2.3 s")
        #expect(ScriptPageFormat.duration(.seconds(2)) == "2 s")
        #expect(ScriptPageFormat.duration(.seconds(12)) == "12 s")
        #expect(ScriptPageFormat.duration(.seconds(60)) == "1 m")
        #expect(ScriptPageFormat.duration(.seconds(65)) == "1 m 5 s")
        #expect(ScriptPageFormat.duration(.seconds(3_600)) == "1 h")
        #expect(ScriptPageFormat.duration(.seconds(5_400)) == "1 h 30 m")
        #expect(ScriptPageFormat.duration(.zero) == "0 s")
    }

    @Test func runResultLabels() {
        #expect(ScriptRunResult.ok.label == "OK")
        #expect(ScriptRunResult.exit(3).label == "EXIT 3")
        #expect(ScriptRunResult.timedOut(seconds: 30).label == "TIMED OUT · 30S")
        #expect(ScriptRunResult.failure("INVALID OUTPUT").label == "INVALID OUTPUT")
        #expect(!ScriptRunResult.ok.isFailure)
        #expect(ScriptRunResult.exit(3).isFailure)
        #expect(ScriptWidgetKind.allCases.map(\.label) == ["STATUS WIDGET", "NUMBER WIDGET", "TEXT WIDGET"])
    }

    @Test func catalogKeysResolve() {
        let keys = [
            "script.page.kind.status", "script.page.kind.number", "script.page.kind.text", "script.page.run.ok",
            "script.page.run.exit", "script.page.run.timedOut", "script.page.lastRun.exit",
            "script.page.nextRun.running", "script.page.nextRun.none", "script.page.nextRun.in", "script.page.every",
            "script.page.never", "script.page.duration.decimalSeconds", "script.page.duration.seconds",
            "script.page.duration.minutes", "script.page.duration.minutesSeconds", "script.page.duration.hours",
            "script.page.duration.hoursMinutes", "script.page.about", "script.page.about.from",
            "script.page.about.empty", "script.page.runs", "script.page.runs.empty", "script.page.lastRun",
            "script.page.nextRun", "script.page.timeout", "script.page.source", "script.page.reveal",
            "script.page.reveal.hint", "script.page.openSource", "script.page.openSource.hint",
            "script.page.a11y.checked", "script.page.a11y.updated", "script.page.a11y.about", "script.page.a11y.runs",
        ]
        for key in keys {
            #expect(L10n.string(key) != key, "\(key) does not resolve")
        }
    }

    // MARK: Hero states

    @Test func heroStates() {
        #expect(Self.page(.notConfirmed, meta: nil).heroIsActionable, "NOT CONFIRMED opens the confirmation")
        #expect(!Self.page(.state("WAITING · FIRST RUN"), meta: nil).heroIsActionable)
        #expect(Self.page().heroIsActionable, "an output with an action")
        #expect(!Self.page(action: nil).heroIsActionable)
    }

    @Test func heroLabelCarriesNameLevelValuesAndCheckedTime() {
        let label = Self.page().heroAccessibilityLabel(now: Self.now)
        #expect(label == "vigie.app, OK, up, 200, 142 ms, checked 2 minutes ago")
        let warned = Self.page(warning: true, documentation: "").heroAccessibilityLabel(now: Self.now)
        #expect(warned == "vigie.app, OK, up, 200, 142 ms, WARN, checked 2 minutes ago")
        #expect(
            Self.page(.notConfirmed, meta: nil).heroAccessibilityLabel(now: Self.now) == "vigie.app, NOT CONFIRMED")
        #expect(
            Self.page(.state("WAITING · FIRST RUN"), meta: nil).heroAccessibilityLabel(now: Self.now)
                == "vigie.app, WAITING · FIRST RUN")
        let number = Self.page(
            .output(.number(value: "3", label: "open", detail: nil, bar: ScriptNumberBar(value: 3), level: nil)),
            target: nil, meta: .updated(Self.now.addingTimeInterval(-240)))
        #expect(number.heroAccessibilityLabel(now: Self.now) == "vigie.app, 3, open, updated 4 minutes ago")
    }

    // MARK: Theme

    @Test func gridComesFromTheTheme() {
        #expect(ScriptPageMetrics.grid(Self.theme) == ScriptPageMetrics.Grid(runsWidth: 212, heroHeight: 118))
        var custom = Self.theme
        custom.components["script-page"] = ["columns": "1fr 240px", "rows": "100px 1fr"]
        #expect(ScriptPageMetrics.grid(custom) == ScriptPageMetrics.Grid(runsWidth: 240, heroHeight: 100))
        #expect(ScriptPageMetrics.fixed("1fr") == nil)
    }

    // MARK: Rendering, privacy and keyboard

    static func strings(_ model: ScriptPageModel, privacy: Bool) -> [String] {
        PrivacyTests.accessibilityStrings(
            ScriptPage(model: model, now: now).privacyActive(privacy).environment(\.timeZone, utc),
            size: CGSize(width: 700, height: 420))
    }

    @Test func pageRendersInBothPrivacyStatesAndLooks() {
        let models = [
            Self.page(), Self.page(.notConfirmed, meta: nil), Self.page(.state("WAITING · FIRST RUN"), meta: nil),
            Self.page(warning: true), Self.page(documentation: ""),
        ]
        for privacy in [false, true] {
            for look in [Look.dark, .light] {
                let theme = Fixtures.library.resolve(themeID: ThemeLibrary.defaultVariantID, look: look).theme
                for model in models {
                    let view = ScriptPage(model: model, now: Self.now).privacyActive(privacy).vigieTheme(theme)
                        .frame(width: 700, height: 420)
                    #expect(ImageRenderer(content: view).cgImage != nil)
                }
            }
        }
    }

    @Test func privacyHidesScriptTextButKeepsRunsAndFile() {
        let model = Self.page(
            .output(.status(level: .down, qualifier: Self.seed(1), value: Self.seed(2))), target: Self.seed(3),
            documentation: "# \(Self.seed(4))\n\n\(Self.seed(5))")
        let redacted = model.redacted()
        #expect(redacted.documentation == PrivacyMask.text)
        #expect(redacted.hero.name == "vigie.app")
        #expect(redacted.runs == model.runs, "times, durations, exit codes, runtime and file stay")
        PrivacyTests.expectNoSeed([
            PrivacyTests.dumped(redacted), redacted.heroAccessibilityLabel(now: Self.now),
        ])
        let strings = Self.strings(model, privacy: true)
        PrivacyTests.expectNoSeed(strings)
        #expect(strings.contains { $0.hasPrefix("vigie.app, \(PrivacyMask.text), DOWN") }, "name and level stay")
        #expect(strings.contains("07:57:00, 0.4 s, OK"))
        #expect(strings.contains("About, from site-status.md"))
        // Without Privacy mode the script text reads.
        #expect(Self.strings(model, privacy: false).contains { $0.contains(Self.seed(2)) })
    }

    @Test func keyboardStopsComeInTabOrder() {
        #expect(ScriptPageFocus.order == [.hero, .about, .runs, .reveal, .openSource])
        let ids = Set(ScriptPageFocus.allCases.map(\.accessibilityID))
        let found = Self.strings(Self.page(), privacy: false).filter { ids.contains($0) }
        var seen: [String] = []
        for id in found where !seen.contains(id) { seen.append(id) }
        #expect(seen == ScriptPageFocus.order.map(\.accessibilityID), "laid out hero → About → runs → chips")
    }
}
