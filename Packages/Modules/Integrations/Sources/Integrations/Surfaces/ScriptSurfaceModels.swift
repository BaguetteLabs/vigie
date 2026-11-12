import Foundation
import ModuleKit
import VigieUI

/// What a script's surfaces render (Story 12.5): its front matter, its state on this Mac and its run state.
public struct ScriptSurfaceSnapshot: Equatable, Sendable {
    public var frontMatter: ScriptFrontMatter
    public var local: ScriptLocalState
    /// Nil while the runner does not run the script (not confirmed, disabled, or stopped).
    public var run: ScriptRunState?

    public init(frontMatter: ScriptFrontMatter, local: ScriptLocalState, run: ScriptRunState?) {
        self.frontMatter = frontMatter
        self.local = local
        self.run = run
    }
}

/// Builds the VigieUI view models of a script's surfaces and its arbitration state from a snapshot. Pure, so
/// every mapping is testable without views (AD-18: the templates live in VigieUI, the mapping here).
public enum ScriptSurfaces {
    /// Left-wing priority of a script whose front matter sets none (lower is shown first; the built-ins use
    /// 1–3, so scripts follow them by default, as in SPEC §11's `priority = 5` example).
    public static let defaultPriority = 5

    /// The script's left-wing priority: front matter `priority`, else ``defaultPriority``.
    public static func priority(_ frontMatter: ScriptFrontMatter) -> Int {
        frontMatter.priority ?? defaultPriority
    }

    // MARK: Arbitration state (SPEC §5.1, §9.3)

    /// - Awaiting confirmation: `ambient` (the surfaces show `NOT CONFIRMED`); declined: `hidden`.
    /// - Not run yet: `ambient` (`WAITING · FIRST RUN`).
    /// - Latest run good: the output's `state` (default `ambient`; `hidden` takes the script off the lane).
    /// - Latest run failed: the last good output's `state`, at least `ambient`, so the failure badge shows.
    public static func state(_ snapshot: ScriptSurfaceSnapshot) -> ModuleState {
        switch snapshot.local {
        case .declined: return .hidden
        case .awaitingConfirmation: return .ambient
        case .confirmed: break
        }
        switch snapshot.run?.phase {
        case nil, .waitingFirstRun: return .ambient
        case .ok(let output, _): return output.state
        case .errored(_, let output, _): return max(output?.state ?? .ambient, .ambient)
        }
    }

    // MARK: Widget content

    /// `ok` → OK, `warn` → WARN, `error` → DOWN (SPEC §9.3).
    public static func level(_ level: ScriptLevel) -> StatusLevel {
        switch level {
        case .ok: .ok
        case .warn: .warn
        case .error: .down
        }
    }

    /// The template content of an output's widget. A status widget's `label` is its target (header and side
    /// slot), its `detail` the qualifier after the level (`OK · UP`), its `value` the value line.
    public static func content(_ widget: ScriptWidget) -> ScriptWidgetContent {
        switch widget.type {
        case .status:
            return .status(level: level(widget.level ?? .ok), qualifier: widget.detail, value: widget.value)
        case .number:
            let value = widget.value ?? ""
            return .number(
                value: value, label: widget.label, detail: widget.detail, bar: ScriptNumberBar(value: Double(value)),
                level: widget.level.map(level))
        case .text:
            return .text(label: widget.label, value: widget.value ?? "", level: widget.level.map(level))
        }
    }

    /// The target in the header and side slot: a status widget's `label`.
    static func target(_ widget: ScriptWidget) -> String? {
        widget.type == .status ? widget.label : nil
    }

    static func action(_ action: ScriptAction?) -> ScriptWidgetAction? {
        switch action {
        case .open: .open
        case .run: .run
        case .copy: .copy
        case nil: nil
        }
    }

    /// `EVERY 1M` from the interval.
    public static func cadence(_ frontMatter: ScriptFrontMatter) -> String {
        IntegrationsText.format("script.card.cadence", ScriptDuration.format(frontMatter.interval).uppercased())
    }

    // MARK: Home card

    /// The Home card (UX-DR86): `NOT CONFIRMED` while awaiting confirmation; `WAITING · FIRST RUN` before the
    /// first run; the output with `CHECKED <n> MIN AGO` (`DOWN SINCE <time>` at DOWN) or `UPDATED <n> MIN AGO`;
    /// after a failure the last good output with the WARN badge and the failure (`EXIT 3`) on the meta line.
    public static func card(_ snapshot: ScriptSurfaceSnapshot) -> ScriptCardModel {
        let frontMatter = snapshot.frontMatter
        var model = ScriptCardModel(
            name: frontMatter.name, cadence: cadence(frontMatter), body: .state(ScriptRunLabel.waitingFirstRun))
        guard snapshot.local == .confirmed else {
            model.body = .notConfirmed
            return model
        }
        guard let run = snapshot.run else { return model }
        switch run.phase {
        case .waitingFirstRun:
            break
        case .ok(let output, let at):
            apply(output, at: at, records: run.records, to: &model)
        case .errored(let reason, let output, let at):
            let failure = ScriptRunLabel.outcome(reason)
            if let output {
                apply(output, at: at, records: run.records, to: &model)
                model.meta = .label(failure)
            } else {
                model.body = .state(failure)
                model.meta = nil
            }
            model.warningBadge = true
        }
        return model
    }

    private static func apply(
        _ output: ScriptOutput, at: Date, records: [ScriptRunRecord], to model: inout ScriptCardModel
    ) {
        let widget = output.widget
        model.target = target(widget)
        model.body = .output(content(widget))
        model.action = action(output.action)
        switch widget.type {
        case .status where widget.level == .error:
            model.meta = .downSince(downSince(records) ?? at)
        case .status:
            model.meta = .checked(at)
        case .number, .text:
            model.meta = .updated(at)
        }
    }

    /// When the latest good output went DOWN: the start of the oldest good run in the newest unbroken streak of
    /// `error`-level outputs (failed runs in between do not break it).
    static func downSince(_ records: [ScriptRunRecord]) -> Date? {
        var since: Date?
        for record in records where record.action == nil {
            guard case .succeeded(let output) = record.outcome else { continue }
            guard output.widget.level == .error else { break }
            since = record.startedAt
        }
        return since
    }

    // MARK: Side slot

    /// The left-wing item (DESIGN "Side-slot item", A22): status = level over target (the script's name when
    /// the output has no label); number = value over label; text = value over label (`TEXT` without one);
    /// `NOT CONFIRMED`, `WAITING · FIRST RUN` or the failure under the name before any good output.
    public static func sideItem(_ snapshot: ScriptSurfaceSnapshot) -> ScriptSideItemModel {
        let name = snapshot.frontMatter.name
        guard snapshot.local == .confirmed else {
            return ScriptSideItemModel(name: name, content: .state(ScriptStateLabel.notConfirmedText))
        }
        guard let run = snapshot.run, let output = run.lastGoodOutput else {
            let text = snapshot.run.flatMap(ScriptRunLabel.state) ?? ScriptRunLabel.waitingFirstRun
            return ScriptSideItemModel(name: name, content: .state(text))
        }
        let widget = output.widget
        switch widget.type {
        case .status:
            let level = level(widget.level ?? .ok)
            return ScriptSideItemModel(name: name, content: .level(level, target: widget.label ?? name), level: level)
        case .number:
            return ScriptSideItemModel(
                name: name, content: .value(widget.value ?? "", label: widget.label ?? name, valueIsText: false),
                level: widget.level.map(level))
        case .text:
            return ScriptSideItemModel(
                name: name,
                content: .value(
                    widget.value ?? "", label: widget.label ?? ScriptTextWidget.defaultLabel, valueIsText: true),
                level: widget.level.map(level))
        }
    }
}
