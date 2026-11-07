import Darwin
import Foundation
import Wire

/// Why `CLIInstaller.install()` could not create or repair the link.
public enum CLIInstallFailure: Error, Equatable, Sendable {
    /// The app bundle has no CLI at the expected place (a build without the helper).
    case bundledCLIMissing(URL)
    /// The app runs from a translocated (quarantined, read-only) location; linking there would break on the next launch.
    case appTranslocated(URL)
    /// The bin folder could not be created or is not a folder.
    case binDirectoryUnavailable(URL)
    /// `symlink` or `rename` failed with this `errno`.
    case linkFailed(errno: Int32)
}

/// What `CLIInstaller.install()` did.
public enum CLIInstallResult: Equatable, Sendable {
    /// The link did not exist and was created.
    case installed
    /// A link to an older location of the bundled CLI (the app moved) was replaced; `from` is the old target.
    case repaired(from: URL)
    /// The link already points at the bundled CLI.
    case alreadyCurrent
    case failed(CLIInstallFailure)
    /// Something that is not a Vigie link occupies the path (`existing`); it was left alone.
    case skippedConflict(existing: URL)
}

/// What `CLIInstaller.diagnose()` found, for Settings › General.
public enum CLIInstallStatus: Equatable, Sendable {
    /// The link points at the bundled CLI.
    case current(link: URL)
    /// No link yet.
    case missing(link: URL)
    /// A Vigie link points at another (older) location.
    case stale(link: URL, target: URL)
    /// A file or foreign link occupies the path.
    case conflict(existing: URL)
    /// The app bundle has no CLI to link to.
    case bundledCLIMissing(URL)
}

/// Shown in Settings › General when the bin folder is not on the login shell's PATH.
public struct CLIPathHint: Equatable, Sendable {
    /// The folder that holds the link.
    public let binDirectory: URL
    /// A line to add to the shell profile (POSIX shells).
    public let exportLine: String
}

/// Keeps `~/.local/bin/<cliName>` a symlink to the CLI bundled in the running app (AD-22, FR8).
///
/// Runs at every launch after the instance lock. A link that points at another
/// `Contents/Helpers/<cliName>` (the app moved, or an older copy) is repaired atomically; anything
/// else at that path (a regular file, a foreign link) is never overwritten. The dev and release
/// flavors use different names (`AppEnvironment.cliName`), so they never touch each other's link.
public struct CLIInstaller: Sendable {
    /// The bin folder, relative to the home folder.
    public static let binDirectoryRelativePath = ".local/bin"
    /// Where the build puts the CLI inside the app bundle.
    public static let helpersRelativePath = "Contents/Helpers"

    public let environment: AppEnvironment
    public let bundledCLIURL: URL
    public let homeDirectory: URL

    public init(
        environment: AppEnvironment,
        bundledCLIURL: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.environment = environment
        self.bundledCLIURL = bundledCLIURL
        self.homeDirectory = homeDirectory
    }

    /// `<bundle>/Contents/Helpers/<cliName>`, or `nil` when the bundle has no such file.
    public static func bundledCLIURL(in bundle: Bundle, cliName: String) -> URL? {
        let url = bundle.bundleURL.appendingPathComponent(helpersRelativePath, isDirectory: true)
            .appendingPathComponent(cliName)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// `~/.local/bin`.
    public var binDirectory: URL {
        homeDirectory.appendingPathComponent(Self.binDirectoryRelativePath, isDirectory: true)
    }

    /// `~/.local/bin/<cliName>`; hooks always call this absolute path (AD-22).
    public var linkURL: URL {
        binDirectory.appendingPathComponent(environment.cliName)
    }

    /// Ensures the link; never overwrites anything that is not a Vigie link or a dangling link (a link whose
    /// target no longer exists replaces nothing usable).
    public func install() async -> CLIInstallResult {
        let source = bundledCLIURL.standardizedFileURL
        guard fileManager.isExecutableFile(atPath: source.path) else {
            return .failed(.bundledCLIMissing(source))
        }
        guard !source.path.contains("/AppTranslocation/") else { return .failed(.appTranslocated(source)) }
        guard ensureBinDirectory() else { return .failed(.binDirectoryUnavailable(binDirectory)) }

        switch inspectLink() {
        case .missing:
            guard symlink(source.path, linkURL.path) == 0 else { return .failed(.linkFailed(errno: errno)) }
            return .installed
        case .link(let target) where target == source:
            return .alreadyCurrent
        case .link(let target) where isVigieHelper(target) || isDangling(target):
            if let failure = replaceLink(pointingTo: source) { return .failed(failure) }
            return .repaired(from: target)
        case .link, .other:
            return .skippedConflict(existing: linkURL)
        }
    }

    /// Reports the link's state without changing anything.
    public func diagnose() async -> CLIInstallStatus {
        let source = bundledCLIURL.standardizedFileURL
        guard fileManager.isExecutableFile(atPath: source.path) else { return .bundledCLIMissing(source) }
        switch inspectLink() {
        case .missing: return .missing(link: linkURL)
        case .link(let target) where target == source: return .current(link: linkURL)
        case .link(let target) where isVigieHelper(target) || isDangling(target):
            return .stale(link: linkURL, target: target)
        case .link, .other: return .conflict(existing: linkURL)
        }
    }

    /// A hint when `~/.local/bin` is not among the login shell's PATH entries; `nil` when it is,
    /// or when the PATH is unknown (no false alarm).
    public func pathHint(loginShellPath: String?) -> CLIPathHint? {
        guard let loginShellPath else { return nil }
        let wanted = binDirectory.standardizedFileURL.path
        let home = homeDirectory.standardizedFileURL.path
        for entry in loginShellPath.split(separator: ":", omittingEmptySubsequences: true) {
            var path = String(entry)
            for prefix in ["~/", "$HOME/", "${HOME}/"] where path.hasPrefix(prefix) {
                path = home + "/" + path.dropFirst(prefix.count)
            }
            if URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path == wanted { return nil }
        }
        return CLIPathHint(
            binDirectory: binDirectory,
            exportLine: "export PATH=\"$HOME/\(Self.binDirectoryRelativePath):$PATH\"")
    }

    // MARK: - Private

    /// `FileManager` is not `Sendable`; `.default` is documented as thread-safe.
    private var fileManager: FileManager { .default }

    private enum LinkState {
        case missing
        case link(target: URL)
        case other
    }

    private func inspectLink() -> LinkState {
        var info = stat()
        guard lstat(linkURL.path, &info) == 0 else { return errno == ENOENT ? .missing : .other }
        guard info.st_mode & S_IFMT == S_IFLNK,
            let destination = try? fileManager.destinationOfSymbolicLink(atPath: linkURL.path)
        else { return .other }
        let target =
            destination.hasPrefix("/")
            ? URL(fileURLWithPath: destination) : binDirectory.appendingPathComponent(destination)
        return .link(target: target.standardizedFileURL)
    }

    /// `…/Contents/Helpers/<cliName>`: a CLI from some copy of this flavor of Vigie.
    private func isVigieHelper(_ target: URL) -> Bool {
        target.lastPathComponent == environment.cliName
            && target.deletingLastPathComponent().path.hasSuffix("/" + Self.helpersRelativePath)
    }

    /// Nothing exists at `target` (not even another link).
    private func isDangling(_ target: URL) -> Bool {
        var info = stat()
        return lstat(target.path, &info) != 0 && errno == ENOENT
    }

    private func ensureBinDirectory() -> Bool {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: binDirectory.path, isDirectory: &isDirectory) {
            return isDirectory.boolValue
        }
        do {
            try fileManager.createDirectory(
                at: binDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
            return true
        } catch {
            return false
        }
    }

    /// `symlink` to a temporary name in the same folder, then `rename` over the link (atomic).
    private func replaceLink(pointingTo source: URL) -> CLIInstallFailure? {
        let temporary = binDirectory.appendingPathComponent(".\(environment.cliName).\(UUID().uuidString).tmp")
        guard symlink(source.path, temporary.path) == 0 else { return .linkFailed(errno: errno) }
        guard rename(temporary.path, linkURL.path) == 0 else {
            let code = errno
            unlink(temporary.path)
            return .linkFailed(errno: code)
        }
        return nil
    }
}
