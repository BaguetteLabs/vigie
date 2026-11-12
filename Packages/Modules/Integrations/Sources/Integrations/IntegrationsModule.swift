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
    /// Settings pane of the module (Settings › Scripts arrives with Story 12.6).
    public nonisolated static let settingsPane = "integrations"

    public nonisolated static let staticManifest = ModuleManifest(
        id: "integrations",
        name: IntegrationsText.resource("integrations.module.name"),
        icon: "puzzlepiece.extension",
        alertKinds: [setupProblemKind]
    )

    public let manifest = IntegrationsModule.staticManifest
    public private(set) var state: ModuleState = .hidden
    /// Every script file of the folder, usable or errored, sorted by file name.
    public private(set) var scripts: [ScriptModuleDefinition] = []

    @ObservationIgnored private var context: (any ModuleContext)?
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    /// Last bytes read per file, kept while an iCloud file is pending (AD-12: last good value stays).
    @ObservationIgnored private var lastData: [URL: Data] = [:]
    /// Open setup problems by dedupe key, with the body they were posted with.
    @ObservationIgnored private var problems: [String: (body: String, handle: AlertHandle)] = [:]
    @ObservationIgnored private var scanGeneration = 0
    /// Scans applied so far (a test seam).
    @ObservationIgnored private(set) var completedScans = 0

    public init() {}

    public func start(context: any ModuleContext) async throws {
        self.context = context
        guard context.scriptFolder.url != nil else { return }
        // Subscribe before the first scan so a change made during it is not lost.
        let changes = context.scriptFolder.changes()
        await rescan()
        watchTask = Task { [weak self] in
            for await _ in changes {
                guard !Task.isCancelled else { return }
                await self?.rescan()
            }
        }
    }

    public func stop() async {
        watchTask?.cancel()
        watchTask = nil
        for problem in problems.values { problem.handle.resolve() }
        problems = [:]
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
        reconcileProblems(context.notifier)
        completedScans += 1
    }

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
