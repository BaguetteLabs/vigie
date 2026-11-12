import Foundation
import ModuleKit
import Observation
import os

/// The one runner of script code blocks (AD-18, SPEC §9.2, Story 12.4).
///
/// Every eligible script (``isEligible``: Story 12.3 supplies "confirmed on this Mac and enabled") runs once
/// when it becomes eligible, then every `interval` after the start of its previous run, and on ``refresh(id:)``.
/// Runs of one script never overlap: a Refresh during a run is dropped (the run in progress delivers fresh
/// output) and the next run is scheduled only once a run ends. A new ``ScriptModuleDefinition/contentHash``
/// cancels the run in progress and the schedule and starts again from `WAITING · FIRST RUN`; a script that
/// disappears or stops being eligible is stopped and its state dropped.
///
/// Each run resolves `runtime` through `context.executables`, writes the code block to a 0600 file in the
/// module's scratch folder (`<module storage>/runs/`), and starts `<runtime> <file>` through
/// ``ScriptProcessLaunching`` with ``ScriptEnvironment``, the modules folder as working directory, stdin on
/// `/dev/null`, in its own process group, with a timeout of `min(interval, 30s)`. Process work and file I/O
/// happen off the main actor; state is published here.
@MainActor @Observable
public final class ScriptRunner {
    /// Runs kept per script for the runs card (Story 12.7).
    public nonisolated static let recordLimit = 20
    /// The timeout is `min(interval, timeoutCap)`.
    public nonisolated static let timeoutCap: Duration = .seconds(30)
    /// Runs of one script start at least this far apart, whatever its `interval`.
    public nonisolated static let minimumInterval: Duration = .seconds(1)
    /// Bytes of stderr kept per run (the end of it).
    public nonisolated static let stderrLimit = 4096
    /// Replaces a secret's value wherever stderr repeats it.
    nonisolated static let secretMask = "••••"

    /// Run state per eligible script, keyed by ``ScriptModuleDefinition/id`` (the file name).
    public private(set) var states: [String: ScriptRunState] = [:]

    /// Everything the runner uses from the outside, injected so tests use fakes.
    struct Dependencies: Sendable {
        var executables: any ExecutableResolver
        var secrets: any SecretStore
        var scheduler: any Scheduler
        var launcher: any ScriptProcessLaunching
        /// The module's own scratch folder for code files and captured output; nil disables running.
        var scratchDirectory: URL?
        /// The modules folder (the script's working directory).
        var workingDirectory: URL?
        /// `[modules."<id>"] <key>` as configured, nil when absent (then the front-matter default applies).
        var configuredValue: @MainActor @Sendable (ModuleID, String) -> (any SettingValue)?
        var home: String
        var language: String?
        var now: @Sendable () -> Date
        /// The module log; stderr and failures go here, never secrets or the environment.
        var log: @Sendable (String) -> Void
    }

    private struct Entry {
        var definition: ScriptModuleDefinition
        let generation: Int
        var runTask: Task<Void, Never>?
        var nextRun: RegistrationToken?
    }

    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private let isEligible: @MainActor (ScriptModuleDefinition) -> Bool
    @ObservationIgnored private var entries: [String: Entry] = [:]
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var stopped = false

    init(dependencies: Dependencies, isEligible: @escaping @MainActor (ScriptModuleDefinition) -> Bool) {
        self.dependencies = dependencies
        self.isEligible = isEligible
    }

    /// The runner of the integrations module, on its context's services.
    convenience init(context: any ModuleContext, isEligible: @escaping @MainActor (ScriptModuleDefinition) -> Bool) {
        let log = context.log
        let environment = ProcessInfo.processInfo.environment
        self.init(
            dependencies: Dependencies(
                executables: context.executables, secrets: context.secrets, scheduler: context.scheduler,
                launcher: ScriptProcessLauncher(),
                scratchDirectory: context.storage.directory.appendingPathComponent("runs", isDirectory: true),
                workingDirectory: context.scriptFolder.url,
                // `[modules."<script id>"] <key>` read at each run (Story 12.6), so a change applies at the next run.
                configuredValue: { [settings = context.scriptFolder.settings] id, key in settings.value(id, key: key) },
                home: environment["HOME"] ?? NSHomeDirectory(), language: environment["LANG"], now: { Date() },
                log: { message in log.notice("\(message, privacy: .private)") }),
            isEligible: isEligible)
    }

    /// The timeout of a script with this interval: `min(interval, 30s)`.
    nonisolated static func timeout(for interval: Duration) -> Duration { min(interval, timeoutCap) }

    /// The timeout in whole seconds, rounded up, as `TIMED OUT · <n>S` shows it.
    nonisolated static func timeoutSeconds(_ timeout: Duration) -> Int {
        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        return max(1, Int(seconds.rounded(.up)))
    }

    /// Only a file that parsed, with front matter and one code block, can run.
    nonisolated static func isRunnable(_ definition: ScriptModuleDefinition) -> Bool {
        definition.status == .ok && definition.frontMatter != nil && definition.code != nil
    }

    // MARK: - Reconciling

    /// Matches the runs to the folder's current scripts (after every scan, and when eligibility changes).
    public func update(_ scripts: [ScriptModuleDefinition]) {
        guard !stopped else { return }
        var current: Set<String> = []
        for definition in scripts where Self.isRunnable(definition) && isEligible(definition) {
            current.insert(definition.id)
            if let entry = entries[definition.id] {
                if entry.definition.contentHash == definition.contentHash {
                    entries[definition.id]?.definition = definition
                    continue
                }
                discard(definition.id)
            }
            generation += 1
            entries[definition.id] = Entry(definition: definition, generation: generation)
            states[definition.id] = ScriptRunState()
            startRun(definition.id)
        }
        for id in Array(entries.keys) where !current.contains(id) {
            discard(id)
            states[id] = nil
        }
    }

    /// Runs the script now, unless it is already running.
    public func refresh(id: String) { startRun(id) }

    /// Runs every eligible script now (the ones already running are left alone).
    public func refreshAll() {
        for id in entries.keys.sorted() { startRun(id) }
    }

    /// Ends every run (process groups killed) and schedule, and waits for the runs to finish.
    public func stop() async {
        stopped = true
        let tasks = entries.values.compactMap(\.runTask)
        for id in Array(entries.keys) { discard(id) }
        states = [:]
        for task in tasks { await task.value }
    }

    /// Waits until no run is in progress (a test seam).
    func waitForIdle() async {
        while let task = entries.values.compactMap(\.runTask).first { await task.value }
    }

    private func discard(_ id: String) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        entry.nextRun?.cancel()
        entry.runTask?.cancel()
    }

    // MARK: - Running

    private func startRun(_ id: String) {
        guard !stopped, var entry = entries[id], entry.runTask == nil else { return }
        entry.nextRun?.cancel()
        entry.nextRun = nil
        let definition = entry.definition
        let generation = entry.generation
        entry.runTask = Task { [weak self] in
            guard let record = await self?.perform(definition) else { return }
            self?.finish(id, generation: generation, record: record)
        }
        entries[id] = entry
        states[id]?.isRunning = true
        states[id]?.nextRunAt = nil
    }

    private func finish(_ id: String, generation: Int, record: ScriptRunRecord) {
        // A run cancelled by a file change, a removal or stop() leaves no trace.
        guard !stopped, var entry = entries[id], entry.generation == generation else { return }
        entry.runTask = nil

        var state = states[id] ?? ScriptRunState()
        state.records.insert(record, at: 0)
        if state.records.count > Self.recordLimit { state.records.removeLast(state.records.count - Self.recordLimit) }
        let endedAt = dependencies.now()
        if case .succeeded(let output) = record.outcome {
            state.phase = .ok(output, at: endedAt)
        } else {
            state.phase = .errored(record.outcome, lastGoodOutput: state.lastGoodOutput, at: endedAt)
        }
        state.isRunning = false

        // Every `interval` from the start of this run; a failure waits for the next interval too (no retry storm).
        let interval = max(entry.definition.frontMatter?.interval ?? Self.minimumInterval, Self.minimumInterval)
        let next = max(record.startedAt.addingTimeInterval(Self.seconds(interval)), endedAt)
        entry.nextRun = dependencies.scheduler.at(next) { [weak self] in
            await self?.scheduledRun(id, generation: generation)
        }
        state.nextRunAt = next
        entries[id] = entry
        states[id] = state
    }

    private func scheduledRun(_ id: String, generation: Int) {
        guard entries[id]?.generation == generation else { return }
        entries[id]?.nextRun = nil
        startRun(id)
    }

    /// One run, start to record. Returns even when cancelled (the caller then drops the record).
    private func perform(_ definition: ScriptModuleDefinition) async -> ScriptRunRecord {
        let startedAt = dependencies.now()
        guard let frontMatter = definition.frontMatter, let code = definition.code else {
            return ScriptRunRecord(
                startedAt: startedAt, duration: .zero, outcome: .launchFailed("not runnable"), stderrExcerpt: "")
        }
        let name = frontMatter.id.rawValue
        let timeout = Self.timeout(for: frontMatter.interval)

        guard let runtime = await dependencies.executables.resolve(frontMatter.runtime) else {
            dependencies.log("script \(name): runtime \(frontMatter.runtime) not found")
            return ScriptRunRecord(
                startedAt: startedAt, duration: .zero, outcome: .runtimeNotFound(frontMatter.runtime),
                stderrExcerpt: "")
        }
        let searchPath = await dependencies.executables.searchPath
        let secrets = await readSecrets(frontMatter)
        let configured = dependencies.configuredValue
        let environment = ScriptEnvironment.build(
            settings: frontMatter.settings, configured: { configured(frontMatter.id, $0) }, secrets: secrets,
            searchPath: searchPath, runtime: runtime, home: dependencies.home, language: dependencies.language)

        guard let scratch = dependencies.scratchDirectory else {
            return ScriptRunRecord(
                startedAt: startedAt, duration: .zero, outcome: .launchFailed("no scratch folder"), stderrExcerpt: "")
        }
        let launched = await Self.execute(
            code: code, fileExtension: ScriptEnvironment.fileExtension(language: definition.language),
            request: ScriptLaunchRequest(
                executable: runtime, arguments: [], environment: environment,
                workingDirectory: dependencies.workingDirectory, timeout: timeout, scratchDirectory: scratch),
            launcher: dependencies.launcher)

        let record: ScriptRunRecord
        switch launched {
        case .failure(let error):
            dependencies.log("script \(name): launch failed: \(error.description)")
            record = ScriptRunRecord(
                startedAt: startedAt, duration: .zero, outcome: .launchFailed(error.description), stderrExcerpt: "")
        case .success(let result):
            let stderr = Self.excerpt(result.stderr, masking: Array(secrets.values))
            let outcome = Self.outcome(result, timeout: timeout, widget: frontMatter.widget)
            if !stderr.isEmpty { dependencies.log("script \(name) stderr:\n\(stderr)") }
            if !outcome.isSuccess {
                var line = "script \(name): run failed, \(ScriptRunLabel.outcome(outcome))"
                if case .invalidOutput(let message) = outcome { line += ": " + message }
                dependencies.log(line)
            }
            record = ScriptRunRecord(
                startedAt: startedAt, duration: result.duration, outcome: outcome, stderrExcerpt: stderr)
        }
        return record
    }

    /// Each `secret` setting's value from SecretStore, read now; never logged.
    private func readSecrets(_ frontMatter: ScriptFrontMatter) async -> [String: String] {
        var values: [String: String] = [:]
        for setting in frontMatter.settings {
            guard case .secret = setting.kind else { continue }
            let key = ScriptEnvironment.secretKey(scriptID: frontMatter.id, settingKey: setting.key)
            do {
                if let value = try await dependencies.secrets.read(key), !value.isEmpty { values[setting.key] = value }
            } catch {
                dependencies.log("script \(frontMatter.id.rawValue): secret \(setting.key) unreadable: \(error)")
            }
        }
        return values
    }

    /// Writes the code to a 0600 file in the scratch folder, launches `<runtime> <file>`, removes the file.
    /// Off the main actor.
    @concurrent
    nonisolated static func execute(
        code: String, fileExtension: String?, request: ScriptLaunchRequest, launcher: any ScriptProcessLaunching
    ) async -> Result<ScriptLaunchResult, ScriptLaunchError> {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: request.scratchDirectory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        } catch {
            return .failure(ScriptLaunchError(description: "scratch folder: \(error.localizedDescription)"))
        }
        var name = UUID().uuidString
        if let fileExtension { name += "." + fileExtension }
        let file = request.scratchDirectory.appendingPathComponent(name, isDirectory: false)
        guard
            fileManager.createFile(
                atPath: file.path, contents: Data(code.utf8), attributes: [.posixPermissions: 0o600])
        else {
            return .failure(ScriptLaunchError(description: "could not write the code file"))
        }
        defer { try? fileManager.removeItem(at: file) }
        var request = request
        request.arguments = [file.path]
        do {
            return .success(try await launcher.launch(request))
        } catch let error as ScriptLaunchError {
            return .failure(error)
        } catch {
            return .failure(ScriptLaunchError(description: String(describing: error)))
        }
    }

    /// Classifies a finished process (SPEC §9.2-9.3).
    nonisolated static func outcome(_ result: ScriptLaunchResult, timeout: Duration, widget: ScriptWidgetType)
        -> ScriptRunOutcome
    {
        switch result.termination {
        case .timedOut:
            return .timedOut(seconds: timeoutSeconds(timeout))
        case .signaled(let signal):
            return .failed(exitCode: 128 + signal)
        case .exited(let code) where code != 0:
            return .failed(exitCode: code)
        case .exited:
            return decode(result, widget: widget)
        }
    }

    nonisolated static func decode(_ result: ScriptLaunchResult, widget: ScriptWidgetType) -> ScriptRunOutcome {
        if result.stdoutTruncated {
            return .invalidOutput(
                IntegrationsText.format("script.run.output_too_large", ScriptProcessLauncher.stdoutLimit / 1024))
        }
        let trimmed = String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalidOutput(IntegrationsText.string("script.run.output_empty")) }
        let output: ScriptOutput
        do {
            output = try ScriptOutput.decode(json: Data(trimmed.utf8))
        } catch let error as ScriptSchemaError {
            return .invalidOutput(error.message)
        } catch let DecodingError.dataCorrupted(context) {
            if let error = context.underlyingError as? ScriptSchemaError { return .invalidOutput(error.message) }
            return .invalidOutput(IntegrationsText.string("script.run.output_not_json"))
        } catch {
            return .invalidOutput(IntegrationsText.string("script.run.output_not_json"))
        }
        guard output.widget.type == widget else {
            return .invalidOutput(
                IntegrationsText.format(
                    "script.run.widget_mismatch", output.widget.type.rawValue, widget.rawValue))
        }
        return .succeeded(output)
    }

    /// stderr as text, the last ``stderrLimit`` bytes, every secret value masked, trimmed.
    nonisolated static func excerpt(_ data: Data, masking secrets: [String]) -> String {
        var text = String(decoding: data.suffix(stderrLimit), as: UTF8.self)
        for secret in secrets where !secret.isEmpty {
            text = text.replacingOccurrences(of: secret, with: secretMask)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func seconds(_ duration: Duration) -> TimeInterval {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
