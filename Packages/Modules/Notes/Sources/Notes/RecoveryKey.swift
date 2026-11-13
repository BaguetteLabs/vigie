import CryptoKit
import Foundation
import ModuleKit

/// The user-exportable recovery key (Story 15.1, AD-9; format in `docs/notes-recovery-key.md`).
///
/// 35 bytes: a version byte (`0x01`), the 32 key bytes, then the first 2 bytes of SHA-256(version + key) as a
/// checksum. Encoded in Crockford base32 (5 bits per character, most significant bit first): exactly 56
/// uppercase characters, written as 8 groups of 7 joined by `-`.
///
/// Parsing accepts lowercase, spaces and missing or extra dashes, and reads `O` as `0` and `I`/`L` as `1`
/// (Crockford). A typo fails the checksum.
public enum RecoveryKey {
    public static let version: UInt8 = 1
    public static let checksumByteCount = 2
    public static let groupCount = 8
    public static let groupLength = 7
    /// 35 bytes × 8 bits / 5 bits.
    public static let characterCount = groupCount * groupLength

    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ".utf8)

    public enum ParseError: Error, Hashable, Sendable {
        /// Not 56 base32 characters once spaces and dashes are removed.
        case invalidLength
        /// A character outside Crockford base32 (`U`, punctuation...).
        case invalidCharacter
        /// The checksum does not match: a typo.
        case checksumMismatch
        /// A format version this Vigie does not know.
        case unsupportedVersion
    }

    /// `XXXXXXX-XXXXXXX-…` (8 groups of 7).
    public static func encode(_ key: SyncedKey) -> String {
        var bytes = Data([version])
        bytes.append(key.data)
        bytes.append(checksum(bytes))
        let characters = base32(bytes)
        return stride(from: 0, to: characters.count, by: groupLength)
            .map { String(decoding: characters[$0..<min($0 + groupLength, characters.count)], as: UTF8.self) }
            .joined(separator: "-")
    }

    /// The key a recovery key holds.
    public static func parse(_ text: String) throws(ParseError) -> SyncedKey {
        var values: [UInt8] = []
        for scalar in text.uppercased().unicodeScalars {
            if scalar == "-" || CharacterSet.whitespacesAndNewlines.contains(scalar) { continue }
            guard scalar.isASCII else { throw .invalidCharacter }
            var byte = UInt8(scalar.value)
            switch byte {
            case UInt8(ascii: "O"): byte = UInt8(ascii: "0")
            case UInt8(ascii: "I"), UInt8(ascii: "L"): byte = UInt8(ascii: "1")
            default: break
            }
            guard let index = alphabet.firstIndex(of: byte) else { throw .invalidCharacter }
            values.append(UInt8(index))
        }
        guard values.count == characterCount else { throw .invalidLength }
        let bytes = unbase32(values)
        let body = bytes.prefix(1 + SyncedKey.byteCount)
        guard checksum(Data(body)) == bytes.suffix(checksumByteCount) else { throw .checksumMismatch }
        guard bytes.first == version, let key = SyncedKey(data: Data(body.dropFirst())) else {
            throw .unsupportedVersion
        }
        return key
    }

    static func checksum(_ body: Data) -> Data {
        Data(SHA256.hash(data: body).prefix(checksumByteCount))
    }

    static func base32(_ bytes: Data) -> [UInt8] {
        var output: [UInt8] = []
        var buffer = 0
        var bits = 0
        for byte in bytes {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                output.append(alphabet[(buffer >> (bits - 5)) & 0x1F])
                bits -= 5
            }
        }
        if bits > 0 { output.append(alphabet[(buffer << (5 - bits)) & 0x1F]) }
        return output
    }

    static func unbase32(_ values: [UInt8]) -> Data {
        var output = Data()
        var buffer = 0
        var bits = 0
        for value in values {
            buffer = ((buffer << 5) | Int(value)) & 0xFFFF
            bits += 5
            if bits >= 8 {
                output.append(UInt8((buffer >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        return output
    }
}
