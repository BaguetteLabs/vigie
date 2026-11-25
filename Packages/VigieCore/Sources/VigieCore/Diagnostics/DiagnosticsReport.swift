import Foundation
import ModuleKit

/// The Copy diagnostics text (Story 17.4, AD-16): a pure rendering of ``DiagnosticsInputs`` as plain text with
/// `== SECTION ==` headers, in this order: App, System, Displays, Modules, Agents, Setup problems, Config, Logs,
/// then the footer. The text is English on purpose (it is read by whoever handles the bug report, not shown in the
/// UI) and goes through ``DiagnosticsRedactor`` before it leaves the process.
public enum DiagnosticsReport {
    public static let sections = [
        "APP", "SYSTEM", "DISPLAYS", "MODULES", "AGENTS", "SETUP PROBLEMS", "CONFIG", "LOGS",
    ]
    public static let maxLogLines = 200
    public static let maxResolvedProblems = 20
    /// How far back the Logs section reads.
    public static let logWindow: Duration = .seconds(15 * 60)

    public static func render(_ inputs: DiagnosticsInputs) -> String {
        var out: [String] = []
        func section(_ name: String, _ lines: [String]) {
            out.append("== \(name) ==")
            out.append(contentsOf: lines)
            out.append("")
        }
        section("APP", app(inputs.app))
        section("SYSTEM", system(inputs.system))
        section("DISPLAYS", displays(inputs.displays))
        section("MODULES", modules(inputs.modules) + inputs.moduleLines)
        section("AGENTS", inputs.agentLines.isEmpty ? ["(agents.sessions not running)"] : inputs.agentLines)
        section("SETUP PROBLEMS", problems(inputs.setupProblems, resolved: inputs.resolvedProblems))
        section("CONFIG", config(inputs.config))
        section("LOGS", logs(inputs.logs))
        out.append(footer(inputs.generatedAt))
        return out.joined(separator: "\n") + "\n"
    }

    static func footer(_ date: Date) -> String {
        "Generated \(timestamp(date)) · Vigie diagnostics contain no secrets; review before sharing."
    }

    static func timestamp(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    static func app(_ app: DiagnosticsInputs.App) -> [String] {
        [
            "name: \(app.name)",
            "version: \(app.version) (\(app.build))",
            "bundle id: \(app.bundleID)",
            "flavor: \(app.flavor)",
            "signing: \(app.signing)",
            "install path: \(app.installPath)",
        ]
    }

    static func system(_ system: DiagnosticsInputs.System) -> [String] {
        [
            "macOS: \(system.osVersion)",
            "model: \(system.model)",
            "chip: \(system.chip)",
            "architecture: \(system.architecture)",
            "locale: \(system.locale)",
            "reduce motion: \(system.reduceMotion)",
            "reduce transparency: \(system.reduceTransparency)",
            "increase contrast: \(system.increaseContrast)",
        ]
    }

    static func displays(_ displays: [DiagnosticsInputs.Display]) -> [String] {
        ["count: \(displays.count)"]
            + displays.enumerated().map { index, display in
                var line =
                    "display \(index + 1): \(kindText(display))  \(display.width)x\(display.height) pt  @\(scaleText(display.scale))x"
                if display.isMain { line += "  main" }
                if display.isDrawn { line += "  vigie" }
                return line
            }
    }

    /// `physical notch (built-in)`, `virtual notch (built-in without notch)`, `virtual notch (external)`.
    static func kindText(_ display: DiagnosticsInputs.Display) -> String {
        switch display.kind {
        case .physical: return "physical notch (built-in)"
        case .island: return "dynamic island, virtual notch (\(display.isBuiltIn ? "built-in" : "external"))"
        case .plain: return "virtual notch (\(display.isBuiltIn ? "built-in without notch" : "external"))"
        }
    }

    static func scaleText(_ scale: Double) -> String {
        scale == scale.rounded() ? String(Int(scale)) : String(scale)
    }

    static func modules(_ modules: [DiagnosticsInputs.Module]) -> [String] {
        modules.map { module in
            if module.isScript {
                return "\(module.id)  script  status=\(module.status)"
            }
            var line = "\(module.id)  enabled=\(module.enabled)  status=\(module.status)"
            if let state = module.state { line += "  state=\(stateText(state))" }
            if !module.alertKinds.isEmpty { line += "  alerts=\(module.alertKinds.joined(separator: ","))" }
            return line
        }
    }

    static func stateText(_ state: ModuleState) -> String {
        switch state {
        case .hidden: "hidden"
        case .ambient: "ambient"
        case .active: "active"
        case .alert: "alert"
        }
    }

    static func problems(
        _ current: [DiagnosticsInputs.SetupProblem], resolved: [DiagnosticsInputs.ResolvedProblem]
    ) -> [String] {
        var lines = ["current: \(current.count)"]
        lines += current.map { problem in
            let category = problem.category.map { " [\($0)]" } ?? ""
            return "  \(timestamp(problem.since))  \(problem.module)\(category)  \(problem.title)"
        }
        let recent = resolved.suffix(maxResolvedProblems)
        lines.append("resolved this launch (last \(maxResolvedProblems)): \(recent.count)")
        lines += recent.map { "  \(timestamp($0.at))  \($0.module)" }
        return lines
    }

    static func config(_ config: DiagnosticsInputs.Config) -> [String] {
        [
            "folder: \(config.folder)",
            "sync: \(config.syncOn ? "on" : "off")",
            "iCloud Drive available: \(config.iCloudAvailable)",
            "problems: \(config.problems)",
        ] + config.lines.map { "\($0.key) = \($0.value)\($0.isLocal ? "  (local)" : "")" }
    }

    static func logs(_ logs: DiagnosticsInputs.Logs) -> [String] {
        var lines: [String] = []
        if let failure = logs.failure { lines.append("unavailable: \(failure)") }
        let recent = logs.lines.suffix(maxLogLines)
        lines.append("last \(recent.count) lines (max \(maxLogLines), last 15 minutes):")
        lines += recent
        return lines
    }
}
