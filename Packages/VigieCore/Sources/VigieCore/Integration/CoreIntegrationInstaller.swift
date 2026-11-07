import CryptoKit
import Foundation
import ModuleKit
import Wire
import os

/// The one writer of agent config files (AD-22, FR82, NFR16).
///
/// `preview` re-reads each target and marks a file stale when its SHA-256 no longer matches the diff's
/// `baseHash` (nil ⇔ absent), so the caller re-plans through the adapter and shows the new diff. `apply`
/// re-checks every hash first (nothing is written on a mismatch), then per target: writes
/// `<target>.vigie-backup-<yyyyMMdd-HHmmss>` next to it (skipped when the file did not exist), writes the new
/// text to a temp file in the same folder with the original permissions (0600 for a new file) and renames it
/// over the target. A symlinked target is followed: the link stays, its destination is edited. The result is
/// recorded in `local.toml` under `[integrations."<adapter id>"]` and in the activity log.
public actor CoreIntegrationInstaller: IntegrationInstaller {
    public nonisolated let cliPath: String
    private let configStore: ConfigStore?
    private let activity: (any ActivityLog)?
    private let log: Logger
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - environment: gives the CLI name; the CLI path is `<home>/.local/bin/<cliName>` (`CLIInstaller.linkURL`).
    ///   - configStore: records the result in `local.toml`; nil records nothing (tests, no config).
    ///   - activity: the module's activity log (`.module` entries `integration.install` / `integration.remove`).
    public init(
        environment: AppEnvironment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        configStore: ConfigStore?,
        activity: (any ActivityLog)?,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        cliPath =
            homeDirectory.appendingPathComponent(CLIInstaller.binDirectoryRelativePath, isDirectory: true)
            .appendingPathComponent(environment.cliName).path
        self.configStore = configStore
        self.activity = activity
        self.log = Logger(subsystem: environment.logSubsystem, category: "integrations")
        self.now = now
    }

    // MARK: - Preview

    public func preview(_ diffs: [ConfigDiff], adapterID: String, action: IntegrationAction) async throws
        -> IntegrationPreview
    {
        var files: [IntegrationFileChange] = []
        for diff in diffs {
            let current = try Self.read(diff.path)
            let stale = Self.hash(current) != diff.baseHash
            let label = (diff.path.path as NSString).abbreviatingWithTildeInPath
            let unified = UnifiedDiff.render(
                old: diff.oldText, new: diff.newText, label: label, oldExists: diff.baseHash != nil)
            files.append(IntegrationFileChange(diff: diff, unifiedDiff: unified, stale: stale))
        }
        return IntegrationPreview(adapterID: adapterID, action: action, files: files)
    }

    // MARK: - Apply

    public func apply(_ preview: IntegrationPreview) async throws -> IntegrationResult {
        guard !preview.stale else { throw IntegrationError.stalePreview }
        // Re-check every target before touching any (AD-22: never clobber a concurrent edit).
        var current: [URL: Data?] = [:]
        var changed: [URL] = []
        for diff in preview.diffs {
            let data = try Self.read(diff.path)
            if Self.hash(data) != diff.baseHash { changed.append(diff.path) }
            current[diff.path] = data
        }
        guard changed.isEmpty else {
            log.notice("integration \(preview.adapterID, privacy: .public): target changed, re-plan")
            throw IntegrationError.targetChanged(paths: changed)
        }

        let stamp = Self.stamp(now())
        var applied: [URL] = []
        var backups: [URL] = []
        for diff in preview.diffs {
            let target = diff.path.resolvingSymlinksInPath()
            let old = current[diff.path] ?? nil
            var mode: Int = 0o600
            if let old {
                let attributes = try? FileManager.default.attributesOfItem(atPath: target.path)
                mode = (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? mode
                let backup = Self.backupURL(for: target, stamp: stamp)
                try Self.writeAtomically(old, to: backup, mode: mode)
                backups.append(backup)
            } else {
                do {
                    try FileManager.default.createDirectory(
                        at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                } catch {
                    throw IntegrationError.writeFailed(path: target, reason: error.localizedDescription)
                }
            }
            try Self.writeAtomically(Data(diff.newText.utf8), to: target, mode: mode)
            applied.append(diff.path)
        }
        let result = IntegrationResult(appliedPaths: applied, backupPaths: backups)
        log.info(
            "integration \(preview.adapterID, privacy: .public) \(preview.action.rawValue, privacy: .public): \(applied.count, privacy: .public) file(s)"
        )
        await record(preview, result: result)
        return result
    }

    // MARK: - Record

    private func record(_ preview: IntegrationPreview, result: IntegrationResult) async {
        let id = preview.adapterID
        activity?.record(
            ActivityEntry(
                at: now(), category: .module, kind: "integration.\(preview.action.rawValue)",
                outcome: .custom("applied"), adapter: id,
                detail: [
                    "target": result.appliedPaths.map(\.path).joined(separator: ", "),
                    "backup": result.backupPaths.map(\.path).joined(separator: ", "),
                ]))
        guard let configStore else { return }
        await configStore.registerIntegration(id)
        do {
            switch preview.action {
            case .install:
                try await configStore.set(
                    CoreSettings.integrationPath(id, "installed_at"), to: .string(WireDate.string(from: now())))
                try await configStore.set(
                    CoreSettings.integrationPath(id, "target"), to: .string(result.appliedPaths.first?.path ?? ""))
                if let backup = result.backupPaths.first {
                    try await configStore.set(CoreSettings.integrationPath(id, "backup"), to: .string(backup.path))
                } else {
                    try await configStore.remove(CoreSettings.integrationPath(id, "backup"))
                }
                try await configStore.set(CoreSettings.integrationPath(id, "cli_path"), to: .string(cliPath))
            case .remove:
                for key in CoreSettings.integrationKeys {
                    try await configStore.remove(CoreSettings.integrationPath(id, key))
                }
            }
        } catch {
            // The agent config is already written; the record is informational.
            log.error(
                "integration \(id, privacy: .public): local.toml record not written: \(String(describing: error), privacy: .public)"
            )
        }
    }

    // MARK: - Files

    /// The file's bytes, nil when it does not exist.
    static func read(_ url: URL) throws(IntegrationError) -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw .readFailed(path: url, reason: error.localizedDescription)
        }
    }

    /// SHA-256, lowercase hex; nil for an absent file (the `ConfigDiff.baseHash` convention).
    static func hash(_ data: Data?) -> String? {
        data.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
    }

    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    /// `<target>.vigie-backup-<stamp>`, with `-2`, `-3`… when that name is taken.
    static func backupURL(for target: URL, stamp: String) -> URL {
        let base = target.path + ".vigie-backup-" + stamp
        var candidate = base
        var index = 2
        while FileManager.default.fileExists(atPath: candidate) {
            candidate = "\(base)-\(index)"
            index += 1
        }
        return URL(fileURLWithPath: candidate)
    }

    /// Writes `data` to a temp file next to `url` with `mode`, flushes it, then renames it over `url`.
    static func writeAtomically(_ data: Data, to url: URL, mode: Int) throws(IntegrationError) {
        let folder = url.deletingLastPathComponent()
        let temp = folder.appendingPathComponent(".\(url.lastPathComponent).vigie-tmp-\(UUID().uuidString)")
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL, mode_t(mode))
        guard fd >= 0 else { throw .writeFailed(path: url, reason: String(cString: strerror(errno))) }
        var failure: String?
        let written = data.withUnsafeBytes { buffer -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            var offset = 0
            while offset < buffer.count {
                let count = write(fd, base + offset, buffer.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    return -1
                }
                offset += count
            }
            return offset
        }
        if written != data.count { failure = String(cString: strerror(errno)) }
        // `open` applies the umask; set the exact mode.
        if failure == nil, fchmod(fd, mode_t(mode)) != 0 { failure = String(cString: strerror(errno)) }
        if failure == nil, fsync(fd) != 0 { failure = String(cString: strerror(errno)) }
        close(fd)
        if failure == nil, rename(temp.path, url.path) != 0 { failure = String(cString: strerror(errno)) }
        if let failure {
            unlink(temp.path)
            throw .writeFailed(path: url, reason: failure)
        }
    }
}
