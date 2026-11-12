import Foundation
import ModuleKit
import VigieUI

/// One script in Settings › Scripts (Story 12.6, UX-DR74): name, file, state, last run, and which actions apply.
public struct ScriptPaneRow: Identifiable, Equatable, Sendable {
    /// What the row's state label says, most urgent first (a file that can't load wins over everything).
    public enum State: Equatable, Sendable {
        /// The file did not parse (or broke an id rule); the message names the problem.
        case cantLoad(String)
        /// Declined on this Mac.
        case declined
        /// New or changed bytes not confirmed on this Mac (`NOT CONFIRMED`, UX-DR87).
        case awaitingConfirmation
        /// Disabled on this Mac (`[scripts.enabled]`, AD-8).
        case disabled
        /// A run is in progress.
        case running
        /// Confirmed and enabled, no run finished yet (`WAITING · FIRST RUN`).
        case waitingFirstRun
        /// The latest run succeeded.
        case ok
        /// The latest run failed; the 12.4 label (`EXIT 2`, `TIMED OUT · 30S`, …).
        case errored(String)
        /// Eligible but not handed to a runner (the module is stopped or has no folder).
        case confirmed

        /// The mono label (catalog strings; the run labels are Story 12.4's).
        public var label: String {
            switch self {
            case .cantLoad: IntegrationsText.string("script.settings.state.errored")
            case .declined: IntegrationsText.string("script.settings.state.declined")
            case .awaitingConfirmation: ScriptStateLabel.notConfirmedText
            case .disabled: IntegrationsText.string("script.settings.state.disabled")
            case .running: IntegrationsText.string("script.settings.state.running")
            case .waitingFirstRun: ScriptRunLabel.waitingFirstRun
            case .ok: IntegrationsText.string("script.settings.state.ok")
            case .errored(let label): label
            case .confirmed: IntegrationsText.string("script.settings.state.confirmed")
            }
        }
    }

    /// The file name (``ScriptModuleDefinition/id``).
    public let id: String
    /// The front matter's `name`, else the file name.
    public let name: String
    /// `modules/<file>`.
    public let file: String
    public let state: State
    /// Start of the latest finished run on this launch, nil when none.
    public let lastRun: Date?
    /// Refresh runs it now: only an eligible script with a run state that is not running.
    public let canRefresh: Bool
    /// Enabled on this Mac.
    public let isEnabled: Bool
    /// The parse problem of a file that can't load, for its help text.
    public let problem: String?

    init(
        script: ScriptModuleDefinition, localState: ScriptLocalState, isEligible: Bool, runState: ScriptRunState?
    ) {
        id = script.id
        name = script.frontMatter?.name ?? script.fileName
        file = script.relativePath
        isEnabled = script.enabled
        problem = script.errorMessage
        lastRun = runState?.records.first?.startedAt
        canRefresh = isEligible && runState != nil && runState?.isRunning == false
        state = Self.state(
            script: script, localState: localState, isEligible: isEligible, runState: runState)
    }

    static func state(
        script: ScriptModuleDefinition, localState: ScriptLocalState, isEligible: Bool, runState: ScriptRunState?
    ) -> State {
        if let message = script.errorMessage { return .cantLoad(message) }
        switch localState {
        case .declined: return .declined
        case .awaitingConfirmation: return .awaitingConfirmation
        case .confirmed: break
        }
        if !script.enabled { return .disabled }
        guard isEligible, let runState else { return .confirmed }
        if runState.isRunning { return .running }
        switch runState.phase {
        case .waitingFirstRun: return .waitingFirstRun
        case .ok: return .ok
        case .errored(let reason, _, _): return .errored(ScriptRunLabel.outcome(reason))
        }
    }

    /// `Last run 5 minutes ago`, or `Not run yet`, relative to `now` in the catalog's language.
    public func lastRunText(now: Date = Date()) -> String {
        guard let lastRun else { return IntegrationsText.string("script.settings.lastRun.never") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = IntegrationsText.catalogLocale
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .numeric
        return IntegrationsText.format(
            "script.settings.lastRun", formatter.localizedString(for: lastRun, relativeTo: max(now, lastRun)))
    }
}

/// The community Script repository (SPEC §9.6, A84: `vigie-scripts`, public, under the same GitHub owner as the
/// releases host). The owner is still the `OWNER` placeholder (A49, as in `App/Config/Updates.xcconfig`): until
/// it is set the Settings link is shown disabled rather than pointing at a guessed account.
public enum ScriptRepository {
    public static let owner = "OWNER"
    public static let name = "vigie-scripts"
    public static let placeholderOwner = "OWNER"

    /// `https://github.com/<owner>/vigie-scripts`, nil while the owner is the placeholder.
    public static var url: URL? {
        guard owner != placeholderOwner else { return nil }
        return URL(string: "https://github.com/\(owner)/\(name)")
    }
}
