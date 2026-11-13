import Darwin
import Foundation
import Wire

/// What ``ConfigStore/relocateUserFolder(_:)`` did (Story 16.2).
public enum UserFolderRelocationOutcome: Sendable, Equatable {
    /// The folder's contents were moved into the target.
    case moved
    /// The target already had contents: it is used from now on and the previous folder is left untouched.
    case adopted
    /// The previous folder did not exist (nothing to move): only the setting changed.
    case recorded
}

/// A checked move of a module's user folder (a `.local` `path` setting such as `[modules.notes] folder`), before
/// anything is touched.
public struct UserFolderRelocationPlan: Sendable, Equatable {
    /// The `.local` path setting that names the folder.
    public let setting: ConfigKeyPath
    /// The folder in use now (standardized).
    public let current: URL
    /// The folder to use (standardized).
    public let target: URL
    /// The target already has contents: adopt it rather than move into it.
    public let adopts: Bool
    /// The value to write for ``setting`` (home abbreviated to `~`), or nil to remove it (its default applies).
    public let record: String?
}

/// Why a user folder move was refused or failed. Nothing changed on disk or in the store when one is thrown.
public enum UserFolderRelocationError: Error, Sendable, Equatable, LocalizedError {
    case sameFolder
    case insideCurrentFolder
    case containsCurrentFolder
    case notAFolder
    case notWritable
    /// `n` items of the folder are still downloading from iCloud (downloads were started); try again later.
    case downloadsPending(Int)
    /// Copying failed; the copies were removed and the folder is untouched.
    case moveFailed(String)
    /// The setting could not be written; nothing was moved.
    case recordFailed(String)

    public var errorDescription: String? {
        switch self {
        case .sameFolder: SettingsText.string("settings.userFolder.error.sameFolder")
        case .insideCurrentFolder: SettingsText.string("settings.userFolder.error.insideCurrent")
        case .containsCurrentFolder: SettingsText.string("settings.userFolder.error.containsCurrent")
        case .notAFolder: SettingsText.string("settings.userFolder.error.notAFolder")
        case .notWritable: SettingsText.string("settings.userFolder.error.notWritable")
        case .downloadsPending(let count): SettingsText.format("settings.userFolder.error.downloadsPending", count)
        case .moveFailed(let reason): SettingsText.format("settings.userFolder.error.moveFailed", reason)
        case .recordFailed(let reason): SettingsText.format("settings.userFolder.error.recordFailed", reason)
        }
    }
}

extension ConfigStore {
    /// Items a folder move ignores (Finder metadata), both when moving and when deciding whether a folder is empty.
    nonisolated static let ignoredFolderItems: Set<String> = [".DS_Store"]

    /// Checks a move of the folder named by `setting` from `current` to `target` (Story 16.2). Throws the refusal
    /// ``relocateUserFolder(_:)`` would throw. `record` is the value written for `setting` (nil removes it).
    public func planUserFolderRelocation(
        setting: ConfigKeyPath, from current: URL, to target: URL, record: String?
    ) throws(UserFolderRelocationError) -> UserFolderRelocationPlan {
        let fm = FileManager.default
        let current = current.standardizedFileURL
        let target = target.standardizedFileURL
        let resolvedTarget = target.resolvingSymlinksInPath().path
        let resolvedCurrent = current.resolvingSymlinksInPath().path
        if resolvedTarget == resolvedCurrent { throw .sameFolder }
        if resolvedTarget.hasPrefix(resolvedCurrent + "/") { throw .insideCurrentFolder }
        if resolvedCurrent.hasPrefix(resolvedTarget + "/") || resolvedTarget == "/" { throw .containsCurrentFolder }
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: target.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw .notAFolder }
            guard Darwin.access(target.path, W_OK) == 0 else { throw .notWritable }
        } else {
            var ancestor = target.deletingLastPathComponent()
            while !fm.fileExists(atPath: ancestor.path, isDirectory: &isDirectory), ancestor.path != "/" {
                ancestor = ancestor.deletingLastPathComponent()
            }
            guard isDirectory.boolValue else { throw .notAFolder }
            guard Darwin.access(ancestor.path, W_OK) == 0 else { throw .notWritable }
        }
        return UserFolderRelocationPlan(
            setting: setting, current: current, target: target, adopts: !Self.folderItems(target).isEmpty,
            record: record)
    }

    /// Makes `plan.target` the folder of `plan.setting` (Story 16.2: the notes folder moving into or out of iCloud
    /// Drive). Copy, verify, record, then remove the originals, like ``relocate(to:)``:
    ///
    /// - The target has contents: it is **adopted** (only the setting changes; the previous folder is untouched).
    /// - Else each item of the current folder is copied into the target (created when missing) and verified; a
    ///   failed copy removes the copies. Items still downloading from iCloud refuse the move (their download is
    ///   started). Then the setting is written through ``set(_:to:)`` / ``remove(_:)`` so the module hears about
    ///   it, and the originals are removed (the emptied folder stays).
    @discardableResult
    public func relocateUserFolder(_ plan: UserFolderRelocationPlan) async throws(UserFolderRelocationError)
        -> UserFolderRelocationOutcome
    {
        let fileSystem = relocationFileSystem
        let current = plan.current
        let target = plan.target
        let sourceExists = FileManager.default.fileExists(atPath: current.path)
        let moves = !plan.adopts && sourceExists
        var copied: [URL] = []
        var createdTarget = false
        if moves {
            let pending = await pendingDownloads(in: current)
            if pending > 0 { throw .downloadsPending(pending) }
            let names = Self.folderItems(current)
            let step = await Task.detached {
                Self.copyItems(names, from: current, to: target, fileSystem: fileSystem)
            }.value
            copied = step.copied
            createdTarget = step.createdTarget
            if let failure = step.failure {
                await Self.discard(copied, createdTarget ? target : nil)
                logger.error("User folder not moved: \(failure, privacy: .public)")
                throw .moveFailed(failure)
            }
        }

        do throws(ConfigError) {
            if let record = plan.record {
                try await set(plan.setting, to: .string(record))
            } else {
                try await remove(plan.setting)
            }
        } catch {
            await Self.discard(copied, createdTarget ? target : nil)
            throw .recordFailed(String(describing: error))
        }

        if moves {
            let names = copied.map(\.lastPathComponent)
            let leftovers = await Task.detached {
                names.compactMap { name -> String? in
                    do {
                        try fileSystem.remove(current.appendingPathComponent(name))
                        return nil
                    } catch {
                        return "\(name): \(error.localizedDescription)"
                    }
                }
            }.value
            for leftover in leftovers {
                logger.error("Moved a user folder but could not remove the original \(leftover, privacy: .public)")
            }
        }
        let outcome: UserFolderRelocationOutcome = plan.adopts ? .adopted : (moves ? .moved : .recorded)
        logger.info(
            "\(plan.setting.description, privacy: .public) is now \(self.environment.abbreviatingHome(target), privacy: .public) (\(String(describing: outcome), privacy: .public))"
        )
        return outcome
    }

    /// Counts the items under `folder` that are not downloaded from iCloud yet and starts their download
    /// (Story 16.2: a folder is moved out of iCloud Drive only once it is entirely local).
    public func pendingDownloads(in folder: URL) async -> Int {
        let status = fileReader.status
        return await Task.detached { Self.startPendingDownloads(in: folder, status: status) }.value
    }

    nonisolated static func startPendingDownloads(in folder: URL, status: any UbiquitousItemStatusProviding) -> Int {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else {
            return 0
        }
        var count = 0
        while let url = walker.nextObject() as? URL {
            var name = url.lastPathComponent
            // Old-style placeholder `.<name>.icloud` stands for `<name>`.
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                name = String(name.dropFirst().dropLast(".icloud".count))
            }
            let item = url.deletingLastPathComponent().appendingPathComponent(name)
            if status.status(of: item) == .notDownloaded {
                status.startDownloading(item)
                count += 1
            }
        }
        return count
    }

    /// The item names of `folder` a move carries (none when it is missing), sorted.
    nonisolated static func folderItems(_ folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { !ignoredFolderItems.contains($0) }.sorted()
    }
}
