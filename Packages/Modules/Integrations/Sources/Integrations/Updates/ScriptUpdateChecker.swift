import CryptoKit
import Foundation
import ModuleKit
import VigieUI

/// A newer version of an installed script, fetched and verified, waiting for the user's decision (Story 12.10).
/// The confirmed file keeps running until Confirm replaces it.
public struct ScriptUpdateCandidate: Equatable, Sendable {
    /// `modules/<file>`, the key of the script's records.
    public let relativePath: String
    /// The installed file the diff starts from; Confirm replaces it only while its bytes still hash the same.
    public let installed: ScriptModuleDefinition
    /// The new bytes, parsed as they will be read once they replace the file (same URL).
    public let definition: ScriptModuleDefinition
    public let data: Data
    /// The fetched signature file, nil when unsigned.
    public let signature: Data?
    /// Where the new version was downloaded from, after redirects.
    public let fileURL: URL
    /// The signature URL that answered, nil when unsigned.
    public let signatureURL: URL?
    public let verification: ScriptConfirmationContent.Verification

    public var contentHash: String { definition.contentHash }
}

/// The update under review in the Script Confirmation (Story 12.10): from the badge, from Settings › Scripts, or
/// from a same-id `vigie://install` link.
public struct ScriptUpdateReview: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let candidate: ScriptUpdateCandidate
}

/// Why Confirm could not apply an update. The installed file is unchanged in every case.
public enum ScriptUpdateError: Error, Equatable, Sendable {
    case noFolder
    /// The installed file changed on disk since the update was found (the diff no longer applies).
    case changedOnDisk
    /// Writing the file or recording the confirmation failed (the old bytes were put back).
    case writeFailed(String)

    /// The line Settings › Scripts shows.
    public var message: String {
        switch self {
        case .noFolder: IntegrationsText.string("script.install.failed.noFolder")
        case .changedOnDisk: IntegrationsText.string("script.update.failed.changed")
        case .writeFailed(let detail): IntegrationsText.format("script.update.failed.write", detail)
        }
    }
}

/// Story 12.10: re-fetches a script's recorded source over HTTPS with its signature (AD-16 amended 2026-11-06:
/// script update fetches are user-enabled), compares the bytes with the installed file and verifies a changed
/// version as a link install would (AD-18, SPEC §9.4). Network and parsing run off the main actor.
public struct ScriptUpdateChecker: Sendable {
    /// A script's source is fetched at most once per this interval (SPEC §9.5: at most once a day).
    public static let checkInterval: TimeInterval = 24 * 60 * 60
    /// How often the module looks for scripts whose last check is a day old.
    public static let tickInterval: Duration = .seconds(15 * 60)

    let downloader: any ScriptDownloading
    let trustedKeys: [Data]

    public init(
        downloader: any ScriptDownloading = URLSessionScriptDownloader(), trustedKeys: [Data] = TrustedScriptKeys.all
    ) {
        self.downloader = downloader
        self.trustedKeys = trustedKeys
    }

    public enum Outcome: Equatable, Sendable {
        /// The source serves exactly the installed bytes.
        case unchanged
        case changed(ScriptUpdateCandidate)
        /// Nothing usable was fetched (network, status, not HTTPS, too large, a file that does not parse); the
        /// reason for the log.
        case failed(String)
    }

    /// Fetches `source` (and `signatureURL`, else `<source>.sig`) for the installed `definition`.
    public func check(_ installed: ScriptModuleDefinition, source: URL, signatureURL: URL?) async -> Outcome {
        guard source.scheme?.lowercased() == "https" else { return .failed("source is not https") }
        let file: ScriptDownload
        do {
            file = try await downloader.download(source, maxBytes: ScriptInstaller.maxFileBytes)
        } catch {
            return .failed(String(describing: error))
        }
        guard file.url.scheme?.lowercased() == "https" else { return .failed("redirected away from https") }
        guard (200..<300).contains(file.statusCode) else { return .failed("HTTP \(file.statusCode)") }
        if ScriptModuleDefinition.sha256(file.data) == installed.contentHash { return .unchanged }

        let folderName = installed.url.deletingLastPathComponent().lastPathComponent
        let enabled = installed.enabled
        let definition = ScriptModuleDefinition(
            url: installed.url, folderName: folderName, data: file.data, enabled: { _ in enabled })
        if let message = definition.errorMessage { return .failed("invalid update: \(message)") }
        let (signature, signatureFound) = await ScriptInstaller.fetchSignature(
            downloader, explicit: signatureURL, fileURL: file.url)
        let verification = ScriptInstaller.verification(
            file: file.data, signature: signature, downloadURL: file.url, definition: definition,
            trustedKeys: trustedKeys)
        return .changed(
            ScriptUpdateCandidate(
                relativePath: installed.relativePath, installed: installed, definition: definition, data: file.data,
                signature: signature, fileURL: file.url, signatureURL: signatureFound, verification: verification))
    }

    /// Rebuilds a stored candidate against the installed file, verifying its signature again (PRD FR-42: every
    /// update is verified). Nil when the stored bytes are not the pending hash or no longer parse.
    func candidate(
        installed: ScriptModuleDefinition, pending: ScriptPendingUpdate, data: Data, signature: Data?
    ) -> ScriptUpdateCandidate? {
        guard ScriptModuleDefinition.sha256(data) == pending.sha256 else { return nil }
        let folderName = installed.url.deletingLastPathComponent().lastPathComponent
        let enabled = installed.enabled
        let definition = ScriptModuleDefinition(
            url: installed.url, folderName: folderName, data: data, enabled: { _ in enabled })
        guard definition.errorMessage == nil else { return nil }
        let verification = ScriptInstaller.verification(
            file: data, signature: signature, downloadURL: pending.fileURL, definition: definition,
            trustedKeys: trustedKeys)
        return ScriptUpdateCandidate(
            relativePath: installed.relativePath, installed: installed, definition: definition, data: data,
            signature: signature, fileURL: pending.fileURL, signatureURL: pending.signatureURL,
            verification: verification)
    }
}

/// A candidate stored in the module's storage (Story 12.10), in `script-updates.json` under its relative path.
public struct ScriptPendingUpdate: Codable, Equatable, Sendable {
    /// SHA-256 of the candidate bytes (`updates/<file>.md`).
    public var sha256: String
    public var fileURL: URL
    public var signatureURL: URL?
    public var foundAt: Date
}

/// `script-updates.json` (schema 1) in the module's storage: each source's last check and the pending candidates,
/// by relative path. Candidate bytes live beside it in `updates/<file>.md` and `updates/<file>.md.sig`.
struct ScriptUpdateState: Codable, Equatable, Sendable {
    static let name = "script-updates"
    static let schema = 1

    var lastChecked: [String: Date] = [:]
    var pending: [String: ScriptPendingUpdate] = [:]
}

/// The candidate bytes on disk (`<module storage>/updates/`) and the atomic replacement of a script file. All
/// work runs detached, off the main actor.
enum ScriptUpdateFiles {
    static func directory(_ storage: URL) -> URL { storage.appendingPathComponent("updates", isDirectory: true) }

    static func store(_ candidate: ScriptUpdateCandidate, in storage: URL) async throws {
        let directory = directory(storage)
        let name = candidate.installed.fileName
        try await Task.detached {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try candidate.data.write(to: directory.appendingPathComponent(name), options: .atomic)
            let sig = directory.appendingPathComponent(name + ".sig")
            if let signature = candidate.signature {
                try signature.write(to: sig, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: sig)
            }
        }.value
    }

    static func read(_ fileName: String, in storage: URL) async -> (data: Data?, signature: Data?) {
        let directory = directory(storage)
        return await Task.detached {
            (
                try? Data(contentsOf: directory.appendingPathComponent(fileName)),
                try? Data(contentsOf: directory.appendingPathComponent(fileName + ".sig"))
            )
        }.value
    }

    static func remove(_ fileName: String, in storage: URL) async {
        let directory = directory(storage)
        await Task.detached {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName + ".sig"))
        }.value
    }

    /// Replaces `target` with `data` atomically (written to `temporaryDirectory` on the same volume, then
    /// `rename(2)` over the file), only while the file's bytes still hash to `expecting`. Returns the bytes it
    /// replaced. On any failure the file is untouched.
    static func replace(_ target: URL, with data: Data, expecting: String, temporaryDirectory: URL)
        async throws(ScriptUpdateError) -> Data
    {
        let result: Result<Data, ScriptUpdateError> = await Task.detached {
            guard let old = try? Data(contentsOf: target) else { return .failure(.changedOnDisk) }
            guard ScriptModuleDefinition.sha256(old) == expecting else { return .failure(.changedOnDisk) }
            let directory = temporaryDirectory.appendingPathComponent(
                "vigie-update-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let temporary = directory.appendingPathComponent(target.lastPathComponent)
                try data.write(to: temporary, options: [.withoutOverwriting])
                if let attributes = try? FileManager.default.attributesOfItem(atPath: target.path),
                    let permissions = attributes[.posixPermissions]
                {
                    try? FileManager.default.setAttributes(
                        [.posixPermissions: permissions], ofItemAtPath: temporary.path)
                }
                guard rename(temporary.path, target.path) == 0 else {
                    return .failure(.writeFailed(String(cString: strerror(errno))))
                }
                return .success(old)
            } catch {
                return .failure(.writeFailed(error.localizedDescription))
            }
        }.value
        return try result.get()
    }
}
