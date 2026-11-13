import CryptoKit
import Foundation
import ModuleKit

/// Why a note file could not be opened. Never carries note text.
public enum NoteFileError: Error, Hashable, Sendable {
    /// No valid header line (``NoteFileHeader``).
    case noHeader
    /// A header `format` this Vigie does not know (written by a newer Vigie).
    case unsupportedFormat(Int)
    /// Encrypted with a key this Vigie does not hold.
    case unknownKey(keyID: String)
    /// The ciphertext does not open with the key (tampered, truncated, header changed) or the payload is not a
    /// format 1 payload.
    case corrupt
}

/// Note file format 1 (Story 15.2, AD-10; byte layout in `docs/notes-file-format.md`).
///
/// ```
/// {"format":1,"key_id":"<16 hex>"}\n          plaintext header line (NoteFileHeader)
/// <ChaChaPoly sealed box, combined>            12-byte nonce ‖ ciphertext ‖ 16-byte tag
/// ```
///
/// The ciphertext is ChaCha20-Poly1305 (CryptoKit) over the JSON payload ``Payload``, with the header line bytes
/// (line feed included) as authenticated additional data: a file whose header was changed or swapped does not
/// open. The nonce is random for every write.
public enum NoteFile {
    /// The encrypted JSON payload.
    struct Payload: Codable, Sendable {
        var id: UUID
        var title: String
        var body: String
        var created: Date
        var modified: Date
        var format: Int
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(isoStyle))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = (try? isoStyle.parse(text)) ?? (try? Date.ISO8601FormatStyle().parse(text)) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "not ISO 8601")
            }
            return date
        }
        return decoder
    }()

    /// ISO 8601 in UTC with milliseconds (`2026-11-13T09:41:00.123Z`); plain ISO 8601 is read too.
    static let isoStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    /// The bytes of `note` sealed with `key`.
    public static func seal(_ note: Note, key: SyncedKey) throws -> Data {
        let header = NoteFileHeader(keyID: key.keyID).encoded()
        let payload = Payload(
            id: note.id, title: note.title, body: note.body, created: note.created, modified: note.modified,
            format: NoteFileHeader.currentFormat)
        let plaintext = try encoder.encode(payload)
        let box = try ChaChaPoly.seal(plaintext, using: key.symmetricKey, authenticating: header)
        var data = header
        data.append(box.combined)
        return data
    }

    /// The note in `data`, opened with `key`.
    public static func open(_ data: Data, key: SyncedKey) throws(NoteFileError) -> Note {
        guard let header = NoteFileHeader.parse(data), let newline = data.firstIndex(of: 0x0A) else {
            throw .noHeader
        }
        guard header.format == NoteFileHeader.currentFormat else { throw .unsupportedFormat(header.format) }
        guard header.keyID == key.keyID else { throw .unknownKey(keyID: header.keyID) }
        let headerBytes = data[data.startIndex...newline]
        let sealed = data[data.index(after: newline)...]
        let payload: Payload
        do {
            let box = try ChaChaPoly.SealedBox(combined: sealed)
            let plaintext = try ChaChaPoly.open(box, using: key.symmetricKey, authenticating: headerBytes)
            payload = try decoder.decode(Payload.self, from: plaintext)
        } catch {
            throw .corrupt
        }
        guard payload.format == NoteFileHeader.currentFormat else { throw .corrupt }
        return Note(
            id: payload.id, title: payload.title, body: payload.body, created: payload.created,
            modified: payload.modified)
    }
}
