import Darwin
import Foundation
import Wire

/// What ``ConfigStore/relocate(to:)`` did (Story 16.1).
public enum ConfigRelocationOutcome: Sendable, Equatable {
    /// `config.toml`, `themes/` and `modules/` were moved into the new folder; values are unchanged.
    case moved
    /// The new folder already had a `config.toml`: Vigie now uses it and left the previous folder untouched.
    case adopted
}

/// A checked relocation, before anything is touched: what ``ConfigStore/relocate(to:)`` would do.
public struct ConfigRelocationPlan: Sendable, Equatable {
    /// The folder to use (standardized).
    public let target: URL
    /// The folder in effect now.
    public let current: URL
    /// The new folder already holds a `config.toml` (adopt it) rather than receiving the current files (move).
    public let adopts: Bool
    /// The target is the default folder (the record in `local.toml` is removed rather than written).
    public let isDefault: Bool
}

/// Why a relocation was refused or failed. Nothing changed on disk or in the store when one is thrown.
public enum ConfigRelocationError: Error, Sendable, Equatable, LocalizedError {
    /// The folder is the one in effect.
    case sameFolder
    /// The folder is inside the current config folder.
    case insideCurrentFolder
    /// The current config folder is inside the chosen folder.
    case containsCurrentFolder
    /// The folder is `AppEnvironment.applicationSupportURL` (or inside it): it holds machine-specific data only.
    case applicationSupport
    /// The path exists and is a file.
    case notAFolder
    /// Vigie cannot write there.
    case notWritable
    /// The folder has no `config.toml` but already holds `themes` or `modules` (named): moving would merge them.
    case conflict(String)
    /// Copying the files failed; the copies were removed and the current folder is untouched.
    case moveFailed(String)
    /// The location could not be recorded in `local.toml`; nothing was moved.
    case recordFailed(String)

    public var errorDescription: String? {
        switch self {
        case .sameFolder: SettingsText.string("settings.configFolder.error.sameFolder")
        case .insideCurrentFolder: SettingsText.string("settings.configFolder.error.insideCurrent")
        case .containsCurrentFolder: SettingsText.string("settings.configFolder.error.containsCurrent")
        case .applicationSupport: SettingsText.string("settings.configFolder.error.applicationSupport")
        case .notAFolder: SettingsText.string("settings.configFolder.error.notAFolder")
        case .notWritable: SettingsText.string("settings.configFolder.error.notWritable")
        case .conflict(let name): SettingsText.format("settings.configFolder.error.conflict", name)
        case .moveFailed(let reason): SettingsText.format("settings.configFolder.error.moveFailed", reason)
        case .recordFailed(let reason): SettingsText.format("settings.configFolder.error.recordFailed", reason)
        }
    }
}

/// The file steps of a move, injectable so tests can fail one midway.
struct ConfigRelocationFileSystem: Sendable {
    var copy: @Sendable (_ from: URL, _ to: URL) throws -> Void
    var remove: @Sendable (URL) throws -> Void

    static let standard = ConfigRelocationFileSystem(
        copy: { try FileManager.default.copyItem(at: $0, to: $1) },
        remove: { try FileManager.default.removeItem(at: $0) })
}

extension ConfigStore {
    /// `[config] folder` in `local.toml` (AD-12, SPEC §11.1): the recorded config folder location, read by
    /// `AppEnvironment` at launch. Written only by ``relocate(to:)``.
    public nonisolated static let folderRecordPath = CoreSettings.path(
        AppEnvironment.configFolderRecordTable, AppEnvironment.configFolderRecordKey)

    /// Whether the folder in effect is the default one.
    public var isUsingDefaultFolder: Bool {
        configFolderURL.standardizedFileURL.path == environment.defaultConfigFolderURL.standardizedFileURL.path
    }

    /// Checks a relocation to `newFolder` without touching anything (Settings shows adopt vs move before
    /// confirming). Throws the refusal ``relocate(to:)`` would throw.
    public func planRelocation(to newFolder: URL) throws(ConfigRelocationError) -> ConfigRelocationPlan {
        try Self.plan(
            target: newFolder, current: configFolderURL, applicationSupport: environment.applicationSupportURL,
            defaultFolder: environment.defaultConfigFolderURL)
    }

    /// Makes `newFolder` the config folder (Story 16.1, AD-12: only ConfigStore relocates).
    ///
    /// - If `newFolder` already has a `config.toml`, it is **adopted**: Vigie reads it from now on and leaves the
    ///   previous folder untouched; observers hear about every key whose resolved value changed.
    /// - Else `config.toml`, `themes/` and `modules/` are **moved** there (created when missing): copied, verified,
    ///   then the originals removed. A failed copy removes the partial copies and leaves everything as it was.
    ///   Values do not change, so observers stay silent.
    ///
    /// Either way the location is recorded in `local.toml` (`[config] folder`, home abbreviated to `~`; removed
    /// when `newFolder` is the default), the watchers follow the new folder, and ``location`` tells the services
    /// derived from it (the script folder rescans). Runs after every queued reload or write.
    @discardableResult
    public func relocate(to newFolder: URL) async throws(ConfigRelocationError) -> ConfigRelocationOutcome {
        let result: Result<ConfigRelocationOutcome, ConfigRelocationError> = await serialized {
            do throws(ConfigRelocationError) {
                return .success(try await self.performRelocation(to: newFolder))
            } catch {
                return .failure(error)
            }
        }
        switch result {
        case .success(let outcome): return outcome
        case .failure(let error):
            logger.error("Config folder not changed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    private func performRelocation(to newFolder: URL) async throws(ConfigRelocationError) -> ConfigRelocationOutcome {
        let plan = try planRelocation(to: newFolder)
        let fileSystem = relocationFileSystem
        let names = AppEnvironment.configFolderItemNames

        var copied: [URL] = []
        var createdTarget = false
        if !plan.adopts {
            let step = await Task.detached {
                Self.copyItems(names, from: plan.current, to: plan.target, fileSystem: fileSystem)
            }.value
            copied = step.copied
            createdTarget = step.createdTarget
            if let failure = step.failure {
                await Self.discard(copied, createdTarget ? plan.target : nil)
                throw .moveFailed(failure)
            }
        }

        // Record before switching: if the record cannot be written, nothing moved.
        let record: TOMLScalar? = plan.isDefault ? nil : .string(environment.abbreviatingHome(plan.target))
        do throws(ConfigError) {
            let written = try await writer.write(Self.folderRecordPath, value: record, to: localURL)
            localFile = FileState(data: written.data, document: written.document, problem: nil)
        } catch {
            await Self.discard(copied, createdTarget ? plan.target : nil)
            throw .recordFailed(String(describing: error))
        }

        let previous = plan.current
        location.set(plan.target)
        configFolderURL = plan.target
        if isStarted {
            let configURL = configURL
            let localURL = localURL
            let defaultText = Self.defaultConfigText
            let created = await Task.detached {
                Self.createMissingFiles(configURL: configURL, localURL: localURL, defaultText: defaultText)
            }.value
            for message in created { logger.info("\(message, privacy: .public)") }
            armWatches()
        }
        recompute()
        await performReload()

        if !plan.adopts {
            let leftovers = await Task.detached {
                names.compactMap { name -> String? in
                    let original = previous.appendingPathComponent(name)
                    guard Self.itemExists(original) else { return nil }
                    do {
                        try fileSystem.remove(original)
                        return nil
                    } catch {
                        return "\(name): \(error.localizedDescription)"
                    }
                }
            }.value
            for leftover in leftovers {
                logger.error("Moved config folder but could not remove the original \(leftover, privacy: .public)")
            }
        }
        let outcome: ConfigRelocationOutcome = plan.adopts ? .adopted : .moved
        logger.info(
            "Config folder is now \(self.environment.abbreviatingHome(plan.target), privacy: .public) (\(String(describing: outcome), privacy: .public))"
        )
        return outcome
    }

    // MARK: - Steps (off the main actor)

    nonisolated static func plan(
        target: URL, current: URL, applicationSupport: URL, defaultFolder: URL
    ) throws(ConfigRelocationError) -> ConfigRelocationPlan {
        let fm = FileManager.default
        let target = target.standardizedFileURL
        let resolvedTarget = target.resolvingSymlinksInPath().path
        let resolvedCurrent = current.standardizedFileURL.resolvingSymlinksInPath().path
        let resolvedSupport = applicationSupport.standardizedFileURL.resolvingSymlinksInPath().path

        if resolvedTarget == resolvedCurrent { throw .sameFolder }
        if resolvedTarget.hasPrefix(resolvedCurrent + "/") { throw .insideCurrentFolder }
        if resolvedCurrent.hasPrefix(resolvedTarget + "/") || resolvedTarget == "/" { throw .containsCurrentFolder }
        if resolvedTarget == resolvedSupport || resolvedTarget.hasPrefix(resolvedSupport + "/") {
            throw .applicationSupport
        }
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: target.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw .notAFolder }
            guard Darwin.access(target.path, W_OK) == 0 else { throw .notWritable }
        } else {
            // The nearest existing ancestor must be a writable folder (the target is created there).
            var ancestor = target.deletingLastPathComponent()
            while !fm.fileExists(atPath: ancestor.path, isDirectory: &isDirectory), ancestor.path != "/" {
                ancestor = ancestor.deletingLastPathComponent()
            }
            guard isDirectory.boolValue else { throw .notAFolder }
            guard Darwin.access(ancestor.path, W_OK) == 0 else { throw .notWritable }
        }

        let adopts = fm.fileExists(atPath: target.appendingPathComponent(AppEnvironment.configFileName).path)
        if !adopts {
            for name in AppEnvironment.configFolderItemNames
            where itemExists(current.appendingPathComponent(name)) && itemExists(target.appendingPathComponent(name)) {
                throw .conflict(name)
            }
        }
        let isDefault =
            resolvedTarget == defaultFolder.standardizedFileURL.resolvingSymlinksInPath().path
            || target.path == defaultFolder.standardizedFileURL.path
        return ConfigRelocationPlan(target: target, current: current, adopts: adopts, isDefault: isDefault)
    }

    /// True for a file, folder or symlink (even a dangling one).
    nonisolated static func itemExists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    struct CopyStep: Sendable {
        var copied: [URL] = []
        var createdTarget = false
        var failure: String?
    }

    /// Copies each existing item into `target` (created when missing) and verifies the copies.
    nonisolated static func copyItems(
        _ names: [String], from current: URL, to target: URL, fileSystem: ConfigRelocationFileSystem
    ) -> CopyStep {
        var step = CopyStep()
        let fm = FileManager.default
        if !fm.fileExists(atPath: target.path) {
            do {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                step.createdTarget = true
            } catch {
                step.failure = error.localizedDescription
                return step
            }
        }
        for name in names {
            let source = current.appendingPathComponent(name)
            guard itemExists(source) else { continue }
            let destination = target.appendingPathComponent(name)
            do {
                try fileSystem.copy(source, destination)
                step.copied.append(destination)
            } catch {
                if itemExists(destination) { step.copied.append(destination) }
                step.failure = "\(name): \(error.localizedDescription)"
                return step
            }
            guard sameContent(source, destination) else {
                step.failure = "\(name): the copy differs from the original"
                return step
            }
        }
        return step
    }

    /// Whether two items hold the same tree: same names, same file bytes, same symlink destinations.
    nonisolated static func sameContent(_ a: URL, _ b: URL) -> Bool {
        let fm = FileManager.default
        if let link = try? fm.destinationOfSymbolicLink(atPath: a.path) {
            return (try? fm.destinationOfSymbolicLink(atPath: b.path)) == link
        }
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: a.path, isDirectory: &isDirectory) else { return !itemExists(b) }
        if !isDirectory.boolValue {
            guard let left = fm.contents(atPath: a.path), let right = fm.contents(atPath: b.path) else { return false }
            return left == right
        }
        guard let left = try? fm.contentsOfDirectory(atPath: a.path).sorted(),
            let right = try? fm.contentsOfDirectory(atPath: b.path).sorted(), left == right
        else { return false }
        return left.allSatisfy { sameContent(a.appendingPathComponent($0), b.appendingPathComponent($0)) }
    }

    /// Rollback of a failed move: removes the copies, and the target folder when the move created it.
    nonisolated static func discard(_ copies: [URL], _ createdFolder: URL?) async {
        await Task.detached {
            for copy in copies { try? FileManager.default.removeItem(at: copy) }
            if let createdFolder,
                (try? FileManager.default.contentsOfDirectory(atPath: createdFolder.path))?
                    .isEmpty == true
            {
                try? FileManager.default.removeItem(at: createdFolder)
            }
        }.value
    }
}
