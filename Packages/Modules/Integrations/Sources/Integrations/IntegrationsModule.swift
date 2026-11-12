import Foundation
import ModuleKit
import Observation

/// `integrations` (SPEC §7.4): the runtime of script modules (SPEC §9, AD-18).
///
/// Story 12.2: discovers every `*.md` file of `<config folder>/modules/` (`context.scriptFolder`) at start and on
/// each change of the folder, parses it into a ``ScriptModuleDefinition`` and raises one `setup.problem` alert per
/// errored file. Confirmation (12.3), the runner (12.4) and the dynamic modules each confirmed script registers
/// (12.5) build on ``scripts``. Until then the module renders nothing and its state stays `hidden` (setup problems
/// do not change a module's state, as for the other modules).
@MainActor @Observable
public final class IntegrationsModule: NotchModule {
    /// The core setup-problem kind (AD-13). Declared in the manifest: AlertCenter drops undeclared kinds.
    public nonisolated static let setupProblemKind = "setup.problem"
    /// Settings pane of the module: Settings › Scripts (Story 12.6).
    public nonisolated static let settingsPane = "integrations"
    /// `[modules.integrations] update_checks` (SPEC §11, Story 12.10): check link-installed scripts for updates at
    /// most once a day. Off: no network request for script updates at all.
    public nonisolated static let updateChecksKey = "update_checks"

    public nonisolated static let staticManifest = ModuleManifest(
        id: "integrations",
        name: IntegrationsText.resource("integrations.module.name"),
        icon: "puzzlepiece.extension",
        settings: [
            SettingDescriptor(
                key: updateChecksKey, label: IntegrationsText.resource("integrations.setting.updateChecks"),
                kind: .bool(default: true), help: IntegrationsText.resource("integrations.setting.updateChecks.help"))
        ],
        alertKinds: [setupProblemKind]
    )

    public let manifest = IntegrationsModule.staticManifest
    public private(set) var state: ModuleState = .hidden
    /// Every script file of the folder, usable or errored, sorted by file name.
    public internal(set) var scripts: [ScriptModuleDefinition] = []
    /// Each script's state on this Mac by file name (Story 12.3), recomputed on every scan and record change.
    public internal(set) var localStates: [String: ScriptLocalState] = [:]
    /// The file under review in the Script Confirmation (Story 12.3), nil when none is open.
    public internal(set) var reviewing: ScriptModuleDefinition?
    /// The `vigie://install` link under review (Story 12.9), nil when none is open.
    public internal(set) var installReview: ScriptInstallReview?
    /// Downloads, verifies and installs link scripts (Story 12.9). Tests inject a fake downloader and keys.
    @ObservationIgnored public var installer = ScriptInstaller()
    @ObservationIgnored var installTask: Task<Void, Never>?
    @ObservationIgnored var prepareTask: Task<Void, Never>?

    /// Update candidates waiting for review by relative path (Story 12.10); drives `UPDATE AVAILABLE`.
    public internal(set) var pendingUpdates: [String: ScriptPendingUpdate] = [:]
    /// The update under review in the Script Confirmation (Story 12.10), nil when none is open.
    public internal(set) var updateReview: ScriptUpdateReview?
    /// The state of `Check for updates` in Settings › Scripts.
    public internal(set) var updateCheck = ScriptUpdateCheckStatus()
    /// Fetches and verifies script updates (Story 12.10). Tests inject a fake downloader and keys.
    @ObservationIgnored public var updateChecker = ScriptUpdateChecker()
    /// The clock of the update cadence (tests move it).
    @ObservationIgnored public var now: @Sendable () -> Date = { Date() }
    @ObservationIgnored var updateState = ScriptUpdateState()
    @ObservationIgnored var updateJob: RegistrationToken?
    @ObservationIgnored var updateTasks: [Task<Void, Never>] = []
    /// Scheduled update ticks finished so far (a test seam).
    @ObservationIgnored var completedUpdateTicks = 0

    /// Runs the eligible scripts (Story 12.4); nil while stopped. Its `states` are the scripts' run states.
    public private(set) var runner: ScriptRunner?
    /// Whether a script may run on this Mac: parsed, enabled and confirmed here (``isEligible(_:)``, Story 12.3).
    /// Tests may override it; ``updateRunner()`` is called after every scan and record change.
    @ObservationIgnored public var isScriptEligible: (@MainActor (ScriptModuleDefinition) -> Bool)?

    @ObservationIgnored var context: (any ModuleContext)?
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    /// Last bytes read per file, kept while an iCloud file is pending (AD-12: last good value stays).
    @ObservationIgnored private var lastData: [URL: Data] = [:]
    /// Open setup problems by dedupe key, with the body they were posted with.
    @ObservationIgnored private var problems: [String: (body: String, handle: AlertHandle)] = [:]
    @ObservationIgnored private var scanGeneration = 0
    /// `context.scriptFolder.confirmations` while started (Story 12.3).
    @ObservationIgnored var confirmations: any ScriptConfirmationStore = NoScriptConfirmations()
    @ObservationIgnored var confirmationTask: Task<Void, Never>?
    /// `context.scriptFolder.settings` and `context.secrets` while started (Story 12.6, Settings › Scripts).
    @ObservationIgnored var scriptSettings: any ScriptSettingsStore = NoScriptSettings()
    @ObservationIgnored var secrets: (any SecretStore)?
    @ObservationIgnored var settingsTask: Task<Void, Never>?
    /// The settings each script id has registered with the host (Story 12.6).
    @ObservationIgnored var registeredSettings: [ModuleID: [ScriptSetting]] = [:]
    /// Scans applied so far (a test seam).
    @ObservationIgnored private(set) var completedScans = 0
    /// The script modules registered with the host and the widget-action seams (Story 12.5).
    @ObservationIgnored var surfaces = ScriptSurfaceRegistry()

    public init() {}

    public func start(context: any ModuleContext) async throws {
        self.context = context
        startConfirmations(context)
        startSettings(context)
        guard context.scriptFolder.url != nil else {
            startInstalls(context)
            return
        }
        // Subscribe before the first scan so a change made during it is not lost.
        let changes = context.scriptFolder.changes()
        runner = ScriptRunner(context: context) { [weak self] definition in
            guard let self else { return false }
            return isScriptEligible?(definition) ?? isEligible(definition)
        }
        await rescan()
        // After the first scan, so a link received while launching sees the folder's ids.
        startInstalls(context)
        await startUpdates(context)
        watchTask = Task { [weak self] in
            for await _ in changes {
                guard !Task.isCancelled else { return }
                await self?.rescan()
            }
        }
    }

    public func stop() async {
        await stopInstalls()
        stopUpdates()
        watchTask?.cancel()
        watchTask = nil
        await runner?.stop()
        runner = nil
        unregisterScriptModules()
        for problem in problems.values { problem.handle.resolve() }
        problems = [:]
        stopConfirmations()
        stopSettings()
        context = nil
    }

    /// The dedupe key of a file's setup problem.
    nonisolated static func problemKey(fileName: String) -> String { "script:" + fileName }

    /// Reads the folder, rebuilds ``scripts`` and reconciles the setup problems. A scan overtaken by a newer one
    /// is dropped.
    func rescan() async {
        guard let context, let folder = context.scriptFolder.url else { return }
        scanGeneration += 1
        let generation = scanGeneration
        let reads = await ScriptFolderReader.read(folder)
        guard generation == scanGeneration, self.context != nil else { return }

        var files: [(url: URL, data: Data)] = []
        var nextData: [URL: Data] = [:]
        for (url, read) in reads {
            switch read {
            case .data(let data): nextData[url] = data
            case .pending: if let data = lastData[url] { nextData[url] = data }
            case .unavailable: break
            }
        }
        for (url, data) in nextData { files.append((url, data)) }
        lastData = nextData

        let service = context.scriptFolder
        let next = ScriptCatalog.build(
            files: files, folderName: folder.lastPathComponent, builtIns: service.builtInModuleIDs,
            enabled: { service.isEnabled($0) })
        if next != scripts { scripts = next }
        registerScriptSettings()
        refreshLocalStates()
        reconcileProblems(context.notifier)
        updateRunner()
        completedScans += 1
    }

    /// Matches the runs to ``scripts`` and ``isScriptEligible`` (after each scan; Story 12.3 calls it after a
    /// confirmation or a decline).
    public func updateRunner() {
        runner?.update(scripts)
        reconcileScriptModules()
    }

    /// The host's Refresh for one script (SPEC §9.2), by ``ScriptModuleDefinition/id`` (its file name): runs it
    /// now unless it is running.
    public func refresh(scriptID: String) { runner?.refresh(id: scriptID) }

    /// Refresh for every eligible script.
    public func refreshAll() { runner?.refreshAll() }

    private func reconcileProblems(_ notifier: any Notifier) {
        var open: Set<String> = []
        for script in scripts {
            guard let error = script.status.error else { continue }
            let key = Self.problemKey(fileName: script.fileName)
            open.insert(key)
            let event = Self.problemEvent(script, error: error)
            if problems[key]?.body == event.body { continue }
            problems[key]?.handle.resolve()
            problems[key] = (event.body ?? "", notifier.post(event))
        }
        for key in problems.keys where !open.contains(key) {
            problems.removeValue(forKey: key)?.handle.resolve()
        }
    }

    /// `Script github.md can’t be loaded`, the file's path and the problem in the body. Title and body are
    /// sensitive (`NotifierEvent`: Privacy mode masks them).
    nonisolated static func problemEvent(_ script: ScriptModuleDefinition, error: ScriptParseError) -> NotifierEvent {
        NotifierEvent(
            kind: setupProblemKind,
            severity: .warn,
            title: IntegrationsText.format("script.problem.title", script.fileName),
            body: IntegrationsText.format("script.problem.body", script.url.path, error.message),
            action: .openSettings(pane: settingsPane),
            dedupeKey: problemKey(fileName: script.fileName),
            category: IntegrationsText.string("script.problem.category"))
    }
}
