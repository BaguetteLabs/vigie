import Foundation
import ModuleKit
import VigieUI

/// Why a link install stopped before anything could be confirmed (Story 12.9). Nothing is written in any case.
public enum ScriptInstallError: Error, Equatable, Sendable {
    /// The link's `url` is not `https` (AD-18: any other scheme is refused).
    case notHTTPS(scheme: String)
    /// The server redirected to a URL that is not `https`.
    case insecureRedirect
    /// The file is larger than ``ScriptInstaller/maxFileBytes``.
    case tooLarge(limit: Int)
    /// The server answered with a non-2xx status.
    case httpStatus(Int)
    /// A transport failure.
    case network(String)
    /// The file is not a valid script (front matter, code block, schema), with the parse message.
    case invalidFile(String)
    /// A same-id link whose file is byte-identical to the installed one (Story 12.10): nothing to update.
    case alreadyInstalled(fileName: String)
    /// The host has no scripts folder.
    case noFolder
    /// Writing the file or its records failed.
    case writeFailed(String)

    /// The download did not succeed (UX-DR100: "the file could not be downloaded").
    public var isDownloadFailure: Bool {
        switch self {
        case .notHTTPS, .insecureRedirect, .tooLarge, .httpStatus, .network: true
        case .invalidFile, .alreadyInstalled, .noFolder, .writeFailed: false
        }
    }

    /// The sheet's headline.
    public var title: String {
        switch self {
        case .notHTTPS, .insecureRedirect, .tooLarge, .httpStatus, .network:
            IntegrationsText.string("script.install.failed.download")
        case .invalidFile: IntegrationsText.string("script.install.failed.invalid")
        case .alreadyInstalled: IntegrationsText.string("script.install.failed.alreadyInstalled")
        case .noFolder: IntegrationsText.string("script.install.failed.noFolder")
        case .writeFailed: IntegrationsText.string("script.install.failed.write")
        }
    }

    /// The sentence under the headline.
    public var detail: String? {
        switch self {
        case .notHTTPS(let scheme): IntegrationsText.format("script.install.detail.notHTTPS", scheme)
        case .insecureRedirect: IntegrationsText.string("script.install.detail.insecureRedirect")
        case .tooLarge(let limit): IntegrationsText.format("script.install.detail.tooLarge", limit / 1024)
        case .httpStatus(let code): IntegrationsText.format("script.install.detail.httpStatus", code)
        case .network(let message), .invalidFile(let message), .writeFailed(let message): message
        case .alreadyInstalled(let fileName):
            IntegrationsText.format("script.install.detail.alreadyInstalled", fileName)
        case .noFolder: nil
        }
    }
}

/// A downloaded, parsed and verified script waiting for the user's decision. Its bytes sit in a temporary file
/// outside the scripts folder (on the same volume, so the move on Confirm is a rename).
public struct ScriptInstallCandidate: Equatable, Sendable {
    /// The exact bytes the user reviews; their hash is what Confirm records.
    public let data: Data
    /// Where the file was downloaded from, after redirects.
    public let fileURL: URL
    /// The signature URL whose file was found, nil when unsigned.
    public let signatureURL: URL?
    public let verification: ScriptConfirmationContent.Verification
    /// The file as it will be read once in the folder (its `url` is the planned target).
    public let definition: ScriptModuleDefinition
    /// The temporary file holding ``data``.
    public let temporaryFile: URL
    /// The file of the scripts folder that already declares the script's id (Story 12.10): the link continues as
    /// an update of that file. Nil for a new script.
    public var replacing: String? = nil
    /// The fetched signature file's bytes, nil when unsigned (kept for an update's re-verification).
    public var signature: Data? = nil

    public var contentHash: String { definition.contentHash }
}

/// Link installs (Story 12.9, AD-18): fetch over HTTPS only, cap the size, fetch the detached signature, parse and
/// validate, verify against ``TrustedScriptKeys``, then on Confirm move the file into the scripts folder without
/// overwriting anything. All file and network work runs off the main actor.
public struct ScriptInstaller: Sendable {
    /// Script files are small; anything larger is refused before it is read in full.
    public static let maxFileBytes = 256 * 1024
    /// A `.sig` is 64 bytes raw or 88 bytes of base64.
    public static let maxSignatureBytes = 1024

    let downloader: any ScriptDownloading
    let trustedKeys: [Data]
    /// A directory for the temporary file, on the scripts folder's volume. Tests pass their own.
    let temporaryDirectory: @Sendable (URL) throws -> URL

    public init(
        downloader: any ScriptDownloading = URLSessionScriptDownloader(),
        trustedKeys: [Data] = TrustedScriptKeys.all,
        temporaryDirectory: (@Sendable (URL) throws -> URL)? = nil
    ) {
        self.downloader = downloader
        self.trustedKeys = trustedKeys
        self.temporaryDirectory = temporaryDirectory ?? Self.replacementDirectory
    }

    /// `NSItemReplacementDirectory` for the folder's volume (the folder itself may not exist yet).
    static func replacementDirectory(for folder: URL) throws -> URL {
        var anchor = folder
        while !FileManager.default.fileExists(atPath: anchor.path), anchor.pathComponents.count > 1 {
            anchor.deleteLastPathComponent()
        }
        return try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: anchor, create: true)
    }

    // MARK: - Prepare

    /// Downloads, parses and verifies `request`'s file. Nothing is written to the scripts folder.
    /// - Parameters:
    ///   - folder: `<config folder>/modules/`.
    ///   - existing: the folder's current files by script id: a link whose id one of them declares continues as
    ///     an update of that file (``ScriptInstallCandidate/replacing``, Story 12.10).
    public func prepare(_ request: ScriptInstallRequest, folder: URL, existing: [ModuleID: String])
        async throws(ScriptInstallError) -> ScriptInstallCandidate
    {
        let fileURL = request.fileURL
        guard fileURL.scheme?.lowercased() == "https" else {
            throw .notHTTPS(scheme: fileURL.scheme ?? "")
        }
        let file = try await fetch(fileURL, maxBytes: Self.maxFileBytes)
        guard file.url.scheme?.lowercased() == "https" else { throw .insecureRedirect }
        guard (200..<300).contains(file.statusCode) else { throw .httpStatus(file.statusCode) }

        let name = Self.fileName(from: file.url)
        let target = folder.appendingPathComponent(name, isDirectory: false)
        let definition = ScriptModuleDefinition(
            url: target, folderName: folder.lastPathComponent, data: file.data, enabled: { _ in nil })
        if let message = definition.errorMessage { throw .invalidFile(message) }
        let replacing = definition.moduleID.flatMap { existing[$0] }

        let (signature, signatureURL) = await Self.fetchSignature(
            downloader, explicit: request.signatureURL, fileURL: file.url)
        let verification = Self.verification(
            file: file.data, signature: signature, downloadURL: file.url, definition: definition,
            trustedKeys: trustedKeys)

        let temporaryFile: URL
        do {
            let directory = try temporaryDirectory(folder).appendingPathComponent(
                "vigie-install-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            temporaryFile = directory.appendingPathComponent(name, isDirectory: false)
            try file.data.write(to: temporaryFile, options: [.withoutOverwriting])
        } catch {
            throw .writeFailed(error.localizedDescription)
        }
        return ScriptInstallCandidate(
            data: file.data, fileURL: file.url, signatureURL: signatureURL, verification: verification,
            definition: definition, temporaryFile: temporaryFile, replacing: replacing, signature: signature)
    }

    /// The verification state of `file` (AD-18, SPEC §9.4): `.verified` only when a trusted key verifies the
    /// signature AND the front matter's `source`, if any, is on the download's host (else `.otherSite`).
    static func verification(
        file: Data, signature: Data?, downloadURL: URL, definition: ScriptModuleDefinition, trustedKeys: [Data]
    ) -> ScriptConfirmationContent.Verification {
        let verification = ScriptSignature.verify(file: file, signature: signature, trustedKeys: trustedKeys)
        if verification == .verified, let source = definition.frontMatter?.source,
            source.host()?.lowercased() != downloadURL.host()?.lowercased()
        {
            return .otherSite
        }
        return verification
    }

    private func fetch(_ url: URL, maxBytes: Int) async throws(ScriptInstallError) -> ScriptDownload {
        do {
            return try await downloader.download(url, maxBytes: maxBytes)
        } catch ScriptDownloadError.insecureRedirect {
            throw .insecureRedirect
        } catch ScriptDownloadError.tooLarge(let limit) {
            throw .tooLarge(limit: limit)
        } catch ScriptDownloadError.network(let message) {
            throw .network(message)
        } catch {
            throw .network(error.localizedDescription)
        }
    }

    /// `explicit` (the link's `sig`, or the recorded one), else `<file URL>.sig`. Any failure (404, other status,
    /// not HTTPS, network, too large) counts as unsigned: the stronger warning shows and the file is still
    /// reviewable.
    static func fetchSignature(_ downloader: any ScriptDownloading, explicit: URL?, fileURL: URL) async -> (
        Data?, URL?
    ) {
        guard let url = explicit ?? Self.defaultSignatureURL(for: fileURL),
            url.scheme?.lowercased() == "https",
            let response = try? await downloader.download(url, maxBytes: Self.maxSignatureBytes),
            response.url.scheme?.lowercased() == "https",
            (200..<300).contains(response.statusCode)
        else { return (nil, nil) }
        return (response.data, url)
    }

    /// `<url>.sig`: the path gains `.sig`, query and fragment are kept.
    static func defaultSignatureURL(for fileURL: URL) -> URL? {
        guard var components = URLComponents(url: fileURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path += ".sig"
        return components.url
    }

    /// The URL's last path component, reduced to `[A-Za-z0-9._-]`, without leading dots, ending in `.md`
    /// (`script.md` when nothing is left).
    static func fileName(from url: URL) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        var name = String(
            url.lastPathComponent.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        while name.hasPrefix(".") || name.hasPrefix("-") { name.removeFirst() }
        if name.lowercased().hasSuffix(".md") { name = String(name.dropLast(3)) }
        name = String(name.prefix(80))
        if name.isEmpty || name == "/" { name = "script" }
        return name + ".md"
    }

    // MARK: - Commit and discard

    /// Moves the candidate into `folder` under its name, or `<name>-2.md`, `<name>-3.md`… when taken: never over an
    /// existing file. Returns the final URL. The temporary directory is removed.
    public func commit(_ candidate: ScriptInstallCandidate, into folder: URL) async throws(ScriptInstallError) -> URL {
        let result: Result<URL, ScriptInstallError> = await Task.detached {
            do {
                let fileManager = FileManager.default
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                let name = candidate.definition.fileName
                let stem = String(name.dropLast(3))
                for attempt in 1...100 {
                    let target = folder.appendingPathComponent(
                        attempt == 1 ? name : "\(stem)-\(attempt).md", isDirectory: false)
                    if fileManager.fileExists(atPath: target.path) { continue }
                    do {
                        try fileManager.moveItem(at: candidate.temporaryFile, to: target)
                    } catch let error as CocoaError where error.code == .fileWriteFileExists {
                        continue
                    }
                    try? fileManager.removeItem(at: candidate.temporaryFile.deletingLastPathComponent())
                    return .success(target)
                }
                return .failure(.writeFailed(name))
            } catch {
                return .failure(.writeFailed(error.localizedDescription))
            }
        }.value
        return try result.get()
    }

    /// Removes the candidate's temporary file and directory (Decline, Close, a failure, a newer link).
    public func discard(_ candidate: ScriptInstallCandidate) async {
        let directory = candidate.temporaryFile.deletingLastPathComponent()
        await Task.detached { try? FileManager.default.removeItem(at: directory) }.value
    }
}
