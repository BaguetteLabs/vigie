import Foundation
import ModuleKit
import VigieUI

/// A script file's state on this Mac (AD-18, SPEC §9.2, Story 12.3), from its confirmation record and the hash of
/// its current bytes.
public enum ScriptLocalState: String, Equatable, Hashable, Sendable {
    /// New or changed file: no record matches its current bytes. It does not run (`NOT CONFIRMED`, UX-DR87).
    case awaitingConfirmation
    /// The user confirmed these exact bytes on this Mac: it may run once enabled.
    case confirmed
    /// The user declined these exact bytes on this Mac: disabled here only, until the file changes.
    case declined

    /// - A decline of the current bytes wins over a confirmation of them (a hand edit holding both is read the
    ///   safe way).
    /// - A record of other bytes counts for nothing: any byte change returns the file to awaiting confirmation,
    ///   whether it had been confirmed or declined, so the new content is reviewed again.
    public init(record: ScriptConfirmationRecord, contentHash: String) {
        let hash = contentHash.lowercased()
        if record.declinedSHA256?.lowercased() == hash {
            self = .declined
        } else if record.confirmedSHA256?.lowercased() == hash {
            self = .confirmed
        } else {
            self = .awaitingConfirmation
        }
    }
}

extension ScriptConfirmationContent {
    /// The review of `definition`: its documentation, front matter, code and whole text as read at the last scan.
    init(_ definition: ScriptModuleDefinition) {
        self.init(
            fileName: definition.fileName, path: definition.url.path, documentation: definition.documentation,
            frontMatter: definition.frontMatterText, code: definition.code, language: definition.language,
            fileText: definition.source, problem: definition.errorMessage)
    }
}
