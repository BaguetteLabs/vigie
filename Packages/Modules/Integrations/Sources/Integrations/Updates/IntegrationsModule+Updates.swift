import Foundation
import ModuleKit
import VigieUI

/// `Check for updates` state in Settings › Scripts (Story 12.10).
public struct ScriptUpdateCheckStatus: Equatable, Sendable {
    public var isRunning = false
    /// Scripts fetched by the last check that ended, and how many updates were then waiting.
    public var lastChecked: Int?
    public var lastAvailable: Int?

    public init() {}
}

/// Story 12.10: script update checks (SPEC §9.5, AD-18, AD-16 amended, PRD FR-43, UX-DR87, UX-DR106).
///
/// Cadence: every ``ScriptUpdateChecker/tickInterval`` (and once at start) the module looks at each script with a
/// source and fetches the ones not checked for ``ScriptUpdateChecker/checkInterval`` (a day). The last check per
/// relative path is kept in `context.storage` (`script-updates.json`), so a relaunch does not fetch early; a
/// failed fetch counts as a check. `Check for updates` in Settings › Scripts fetches every source at once. With
/// `update_checks = false` nothing is fetched, ever.
///
/// Source: `[scripts.sources."modules/<file>"]` in `local.toml` (Story 12.9); on a Mac that received the file by
/// sync and has no record, the front matter `source` when it is `https`.
///
/// A changed file is verified like a link install and stored as a candidate (`updates/<file>.md` + `.sig` beside
/// `script-updates.json`), which shows `UPDATE AVAILABLE`; the confirmed version keeps running. A candidate whose
/// hash the user declined (`[scripts.declined_updates]` in `local.toml`) is never offered again.
extension IntegrationsModule {
    func startUpdates(_ context: any ModuleContext) async {
        if let state = try? await context.storage.readJSON(
            ScriptUpdateState.name, as: ScriptUpdateState.self, schema: ScriptUpdateState.schema)
        {
            updateState = state
        }
        pendingUpdates = updateState.pending
        updateJob = context.scheduler.every(ScriptUpdateChecker.tickInterval) { [weak self] in
            await self?.updateTick()
        }
        let toggles = context.settings.observe(Self.updateChecksKey)
        updateTasks = [
            Task { [weak self] in await self?.updateTick() },
            Task { [weak self] in
                for await _ in toggles {
                    guard !Task.isCancelled else { return }
                    await self?.updateTick()
                }
            },
        ]
    }

    func stopUpdates() {
        updateJob?.cancel()
        updateJob = nil
        for task in updateTasks { task.cancel() }
        updateTasks = []
        updateReview = nil
    }

    /// `[modules.integrations] update_checks`, default on.
    public var updateChecksEnabled: Bool {
        context?.settings.value(Self.updateChecksKey, as: Bool.self) ?? true
    }

    /// Where `definition` is checked from: its source record, else an `https` front matter `source`.
    func updateSource(_ definition: ScriptModuleDefinition) -> (url: URL, signature: URL?)? {
        if let record = confirmations.source(for: definition.relativePath) {
            return (record.url, record.signatureURL)
        }
        if let source = definition.frontMatter?.source, source.scheme?.lowercased() == "https" {
            return (source, nil)
        }
        return nil
    }

    /// The scheduled check: only scripts whose last check is a day old, only while `update_checks` is on.
    func updateTick() async {
        defer { completedUpdateTicks += 1 }
        guard context != nil, updateChecksEnabled, !updateCheck.isRunning else { return }
        let now = now()
        let due = scripts.filter { script in
            guard updateSource(script) != nil else { return false }
            guard let last = updateState.lastChecked[script.relativePath] else { return true }
            return now.timeIntervalSince(last) >= ScriptUpdateChecker.checkInterval
        }
        guard !due.isEmpty else { return }
        await runUpdateChecks(due)
    }

    /// Settings › Scripts `Check for updates`: every script with a source now, whatever its last check.
    public func checkForUpdatesNow() async {
        guard context != nil, updateChecksEnabled, !updateCheck.isRunning else { return }
        await runUpdateChecks(scripts.filter { updateSource($0) != nil })
    }

    /// `Check for updates` is offered: update checks on, a script with a source, no check running.
    public var canCheckForUpdates: Bool {
        updateChecksEnabled && !updateCheck.isRunning && scripts.contains { updateSource($0) != nil }
    }

    private func runUpdateChecks(_ targets: [ScriptModuleDefinition]) async {
        guard let context else { return }
        updateCheck.isRunning = true
        defer { updateCheck.isRunning = false }
        let checker = updateChecker
        for installed in targets {
            guard self.context != nil, updateChecksEnabled, let source = updateSource(installed) else { break }
            let outcome = await checker.check(installed, source: source.url, signatureURL: source.signature)
            guard self.context != nil else { return }
            // The file changed during the fetch: the next check compares the new bytes.
            guard let current = scripts.first(where: { $0.relativePath == installed.relativePath }),
                current.contentHash == installed.contentHash
            else { continue }
            await apply(outcome, for: installed, storage: context.storage)
            updateState.lastChecked[installed.relativePath] = now()
        }
        await saveUpdateState()
        updateCheck.lastChecked = targets.count
        updateCheck.lastAvailable = scripts.filter(updateAvailable(for:)).count
    }

    private func apply(
        _ outcome: ScriptUpdateChecker.Outcome, for installed: ScriptModuleDefinition, storage: any ModuleStorage
    ) async {
        let path = installed.relativePath
        switch outcome {
        case .unchanged:
            await dropPendingUpdate(path, fileName: installed.fileName)
        case .failed(let reason):
            context?.log.info("script update check \(path, privacy: .public): \(reason, privacy: .private)")
        case .changed(let candidate):
            if candidate.contentHash == confirmations.declinedUpdate(for: path) {
                await dropPendingUpdate(path, fileName: installed.fileName)
                return
            }
            if let id = candidate.definition.moduleID,
                scripts.contains(where: { $0.moduleID == id && $0.relativePath != path })
            {
                context?.log.info("script update check \(path, privacy: .public): id used by another file")
                return
            }
            if updateState.pending[path]?.sha256 == candidate.contentHash { return }
            do {
                try await ScriptUpdateFiles.store(candidate, in: storage.directory)
            } catch {
                context?.log.error("script update \(path, privacy: .public) not stored: \(String(describing: error))")
                return
            }
            let pending = ScriptPendingUpdate(
                sha256: candidate.contentHash, fileURL: candidate.fileURL, signatureURL: candidate.signatureURL,
                foundAt: now())
            updateState.pending[path] = pending
            pendingUpdates[path] = pending
            context?.log.info("script update available for \(path, privacy: .public)")
        }
    }

    func dropPendingUpdate(_ relativePath: String, fileName: String) async {
        guard updateState.pending[relativePath] != nil || pendingUpdates[relativePath] != nil else { return }
        updateState.pending[relativePath] = nil
        pendingUpdates[relativePath] = nil
        if let storage = context?.storage { await ScriptUpdateFiles.remove(fileName, in: storage.directory) }
    }

    func saveUpdateState() async {
        guard let storage = context?.storage else { return }
        do {
            try await storage.writeJSON(updateState, name: ScriptUpdateState.name, schema: ScriptUpdateState.schema)
        } catch {
            context?.log.error("script update state not saved: \(String(describing: error), privacy: .public)")
        }
    }

    /// `UPDATE AVAILABLE`: a stored candidate other than the file's current bytes and not declined on this Mac.
    public func updateAvailable(for definition: ScriptModuleDefinition) -> Bool {
        guard let pending = pendingUpdates[definition.relativePath] else { return false }
        return pending.sha256 != definition.contentHash
            && pending.sha256 != confirmations.declinedUpdate(for: definition.relativePath)
    }

    // MARK: - Review

    /// Opens the update review on `definition`'s pending candidate (the badge, `Review update…`). A candidate
    /// whose stored bytes are gone or no longer match is dropped.
    public func openUpdate(for definition: ScriptModuleDefinition) async {
        guard let storage = context?.storage, updateAvailable(for: definition),
            let pending = pendingUpdates[definition.relativePath]
        else { return }
        let stored = await ScriptUpdateFiles.read(definition.fileName, in: storage.directory)
        guard let data = stored.data,
            let candidate = updateChecker.candidate(
                installed: definition, pending: pending, data: data, signature: stored.signature)
        else {
            await dropPendingUpdate(definition.relativePath, fileName: definition.fileName)
            await saveUpdateState()
            return
        }
        updateReview = ScriptUpdateReview(id: UUID(), candidate: candidate)
    }

    /// What the Script Confirmation shows for an update: the new version's file, source, author and verification,
    /// and the diff from the installed file.
    public func updateContent(for candidate: ScriptUpdateCandidate) -> ScriptConfirmationContent {
        var content = ScriptConfirmationContent(candidate.definition)
        content.sourceURL = candidate.fileURL.absoluteString
        content.author = candidate.definition.frontMatter?.author
        content.verification = candidate.verification
        content.update = ScriptConfirmationContent.Update(
            diff: ScriptLineDiff.lines(old: candidate.installed.source ?? "", new: candidate.definition.source ?? ""),
            oldVersion: candidate.installed.frontMatter?.version, newVersion: candidate.definition.frontMatter?.version)
        return content
    }

    /// Confirm, from a user action only.
    public func confirmUpdate() async throws(ScriptUpdateError) {
        guard let review = updateReview else { return }
        try await applyUpdate(review.candidate)
        if updateReview?.id == review.id { updateReview = nil }
    }

    /// Decline, from a user action only: the old version keeps running and this exact content is never offered
    /// again (its hash goes to `[scripts.declined_updates]` in `local.toml`).
    public func declineUpdate() async throws {
        guard let review = updateReview else { return }
        try await recordDeclinedUpdate(review.candidate)
        if updateReview?.id == review.id { updateReview = nil }
    }

    /// Close: nothing changes, the candidate stays pending and the badge stays.
    public func closeUpdate() {
        updateReview = nil
    }

    func recordDeclinedUpdate(_ candidate: ScriptUpdateCandidate) async throws {
        try await confirmations.declineUpdate(candidate.relativePath, sha256: candidate.contentHash)
        if updateState.pending[candidate.relativePath]?.sha256 == candidate.contentHash {
            await dropPendingUpdate(candidate.relativePath, fileName: candidate.installed.fileName)
            await saveUpdateState()
        }
    }

    /// Replaces the installed file atomically with the candidate's bytes (only while the file is still the one
    /// reviewed), confirms the new hash on this Mac, refreshes the source record, then rescans so the new version
    /// runs. When the confirmation cannot be recorded the old bytes are put back.
    func applyUpdate(_ candidate: ScriptUpdateCandidate) async throws(ScriptUpdateError) {
        guard let folder = context?.scriptFolder.url else { throw .noFolder }
        let temporary: URL
        do {
            temporary = try installer.temporaryDirectory(folder)
        } catch {
            throw .writeFailed(error.localizedDescription)
        }
        let target = candidate.installed.url
        let old = try await ScriptUpdateFiles.replace(
            target, with: candidate.data, expecting: candidate.installed.contentHash, temporaryDirectory: temporary)
        do {
            try await confirmations.confirm(candidate.relativePath, sha256: candidate.contentHash)
        } catch {
            _ = try? await ScriptUpdateFiles.replace(
                target, with: old, expecting: candidate.contentHash, temporaryDirectory: temporary)
            throw .writeFailed(String(describing: error))
        }
        do {
            try await confirmations.recordSource(
                candidate.relativePath,
                ScriptSourceRecord(url: candidate.fileURL, signatureURL: candidate.signatureURL, installedAt: now()))
        } catch {
            context?.log.error("script update: source not recorded: \(String(describing: error), privacy: .public)")
        }
        updateState.lastChecked[candidate.relativePath] = now()
        updateState.pending[candidate.relativePath] = nil
        pendingUpdates[candidate.relativePath] = nil
        if let storage = context?.storage {
            await ScriptUpdateFiles.remove(candidate.installed.fileName, in: storage.directory)
        }
        await saveUpdateState()
        context?.log.info("script update confirmed for \(candidate.relativePath, privacy: .public)")
        await rescan()
    }
}
