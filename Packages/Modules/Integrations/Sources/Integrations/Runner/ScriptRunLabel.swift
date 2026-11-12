import Foundation

/// The mono labels of a script's run state (UX-DR87), from the String Catalog. Story 12.5 (widget meta line) and
/// the runs card reuse them; nothing is rendered here.
public enum ScriptRunLabel {
    /// `WAITING · FIRST RUN`: a confirmed script that has not finished a run yet.
    public static var waitingFirstRun: String { IntegrationsText.string("script.run.waiting_first_run") }

    /// `EXIT 0`, `EXIT 3`, `TIMED OUT · 30S`, `INVALID OUTPUT`, `RUNTIME NOT FOUND`, `LAUNCH FAILED`.
    public static func outcome(_ outcome: ScriptRunOutcome) -> String {
        switch outcome {
        case .succeeded: IntegrationsText.format("script.run.exit", 0)
        case .timedOut(let seconds): IntegrationsText.format("script.run.timed_out", seconds)
        case .failed(let code), .actionExited(let code): IntegrationsText.format("script.run.exit", Int(code))
        case .invalidOutput: IntegrationsText.string("script.run.invalid_output")
        case .runtimeNotFound: IntegrationsText.string("script.run.runtime_not_found")
        case .launchFailed: IntegrationsText.string("script.run.launch_failed")
        }
    }

    /// The label of a state: `WAITING · FIRST RUN`, the failure of an errored script, nil when the latest run
    /// succeeded (the widget shows its output).
    public static func state(_ state: ScriptRunState) -> String? {
        switch state.phase {
        case .waitingFirstRun: waitingFirstRun
        case .ok: nil
        case .errored(let reason, _, _): outcome(reason)
        }
    }
}
