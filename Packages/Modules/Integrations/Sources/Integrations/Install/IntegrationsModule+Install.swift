import Foundation
import ModuleKit
import VigieUI

/// A link install in progress (Story 12.9): what the Script Confirmation shows in Settings › Scripts.
public struct ScriptInstallReview: Identifiable, Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case downloading
        /// Nothing to confirm; nothing was written.
        case failed(ScriptInstallError)
        case ready(ScriptInstallCandidate)
    }

    public let id: UUID
    public let request: ScriptInstallRequest
    public internal(set) var phase: Phase

    public var candidate: ScriptInstallCandidate? {
        if case .ready(let candidate) = phase { return candidate }
        return nil
    }
}

/// Story 12.9: install scripts from `vigie://install` links (AD-18 "Install from link", SPEC §9.4, Flow 7).
///
/// The host delivers each link through `context.scriptFolder.installRequests()` (queued while the app launches).
/// The module opens Settings on its pane with the link's intent (`context.host.openOwnSettings`), where
/// Settings › Scripts presents the Script Confirmation for ``installReview``: downloading, then the whole file with
/// its source, author and verification state, or why there is nothing to confirm. Confirm moves the reviewed bytes
/// into the scripts folder (never over a file), records their hash as confirmed on this Mac and the source in
/// `local.toml`, then rescans so the script starts. Decline and Close leave nothing behind.
extension IntegrationsModule {
    func startInstalls(_ context: any ModuleContext) {
        let requests = context.scriptFolder.installRequests()
        installTask = Task { [weak self] in
            for await request in requests {
                guard !Task.isCancelled else { return }
                self?.beginInstall(request)
            }
        }
    }

    func stopInstalls() async {
        installTask?.cancel()
        installTask = nil
        prepareTask?.cancel()
        prepareTask = nil
        if let candidate = installReview?.candidate { await installer.discard(candidate) }
        installReview = nil
    }

    /// Starts reviewing `request`, replacing a review still open (its temporary file is removed).
    public func beginInstall(_ request: ScriptInstallRequest) {
        let previous = installReview?.candidate
        prepareTask?.cancel()
        let review = ScriptInstallReview(id: UUID(), request: request, phase: .downloading)
        installReview = review
        context?.log.info("install link: downloading from \(request.fileURL.host() ?? "-", privacy: .private)")
        context?.host.openOwnSettings(focus: request.intent)

        let installer = installer
        let folder = context?.scriptFolder.url
        var existing: [ModuleID: String] = [:]
        for script in scripts { if let id = script.moduleID { existing[id] = script.fileName } }
        let snapshot = existing
        prepareTask = Task { [weak self] in
            if let previous { await installer.discard(previous) }
            let phase: ScriptInstallReview.Phase
            if let folder {
                do throws(ScriptInstallError) {
                    phase = .ready(try await installer.prepare(request, folder: folder, existing: snapshot))
                } catch {
                    phase = .failed(error)
                }
            } else {
                phase = .failed(.noFolder)
            }
            guard let self, self.installReview?.id == review.id, !Task.isCancelled else {
                if case .ready(let candidate) = phase { await installer.discard(candidate) }
                return
            }
            self.installReview?.phase = phase
        }
    }

    /// What the Script Confirmation shows for `review`.
    public func installContent(for review: ScriptInstallReview) -> ScriptConfirmationContent {
        let source = review.request.fileURL.absoluteString
        switch review.phase {
        case .downloading:
            return .unavailable(sourceURL: source, availability: .downloading)
        case .failed(let error):
            return .unavailable(sourceURL: source, availability: .failed(title: error.title, detail: error.detail))
        case .ready(let candidate):
            var content = ScriptConfirmationContent(candidate.definition)
            content.sourceURL = candidate.fileURL.absoluteString
            content.author = candidate.definition.frontMatter?.author
            content.verification = candidate.verification
            return content
        }
    }

    /// Confirm, from a user action only: moves the reviewed bytes into the folder, records their hash as confirmed
    /// and the source on this Mac, then rescans (the script starts). On a failure nothing stays in the folder.
    /// Returns the installed file.
    @discardableResult
    public func confirmInstall() async throws -> URL {
        guard let review = installReview, let candidate = review.candidate else { throw ScriptInstallError.noFolder }
        guard let folder = context?.scriptFolder.url else { throw ScriptInstallError.noFolder }
        let target: URL
        do throws(ScriptInstallError) {
            target = try await installer.commit(candidate, into: folder)
        } catch {
            await installer.discard(candidate)
            if installReview?.id == review.id { installReview?.phase = .failed(error) }
            throw error
        }
        let relativePath = folder.lastPathComponent + "/" + target.lastPathComponent
        do {
            try await confirmations.confirm(relativePath, sha256: candidate.contentHash)
            try await confirmations.recordSource(
                relativePath,
                ScriptSourceRecord(url: candidate.fileURL, signatureURL: candidate.signatureURL, installedAt: Date()))
        } catch {
            try? FileManager.default.removeItem(at: target)
            let failure = ScriptInstallError.writeFailed(String(describing: error))
            if installReview?.id == review.id { installReview?.phase = .failed(failure) }
            throw failure
        }
        if installReview?.id == review.id { installReview = nil }
        context?.log.info("install link: confirmed as \(relativePath, privacy: .public)")
        await rescan()
        return target
    }

    /// Decline or Close: nothing is recorded (there is no file in the folder), the temporary file is removed.
    public func cancelInstall() async {
        prepareTask?.cancel()
        prepareTask = nil
        let candidate = installReview?.candidate
        installReview = nil
        if let candidate { await installer.discard(candidate) }
    }
}
