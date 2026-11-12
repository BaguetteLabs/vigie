import CryptoKit
import Foundation
import VigieUI

/// The Ed25519 public keys of the Script repository's CI that this Vigie trusts (AD-18, SPEC §9.4,
/// `docs/script-signing.md`). Raw 32-byte keys, base64. Rotated only by an app update: a new key is added here and
/// shipped before the repository's CI starts signing with it, and the old one is removed only after that.
public enum TrustedScriptKeys {
    // TODO(A84): add the Script repository's signing key once the repository exists (Story 12.8, org name A49).
    // Until then no signature verifies and every link install shows the stronger warning.
    public static let base64: [String] = []

    /// The keys of ``base64`` that decode to 32 bytes.
    public static var all: [Data] { base64.compactMap(ScriptSignature.publicKey) }
}

/// Detached Ed25519 signatures over a script file's exact bytes (Story 12.9).
public enum ScriptSignature {
    public static let signatureLength = 64
    public static let publicKeyLength = 32

    /// A raw 32-byte public key from base64 text, or nil.
    public static func publicKey(_ base64: String) -> Data? {
        guard let data = Data(base64Encoded: base64.trimmingCharacters(in: .whitespacesAndNewlines)),
            data.count == publicKeyLength
        else { return nil }
        return data
    }

    /// The 64-byte signature in a `.sig` file: raw bytes, or base64 text (what the repository's CI publishes),
    /// surrounding whitespace allowed. Nil for anything else.
    public static func decode(_ file: Data) -> Data? {
        if file.count == signatureLength { return file }
        guard let text = String(data: file, encoding: .utf8),
            let data = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
            data.count == signatureLength
        else { return nil }
        return data
    }

    /// `.verified` when one trusted key verifies `signature` over `file`; `.unsigned` without a signature;
    /// `.badSignature` otherwise (unreadable signature, tampered bytes, or a key this Vigie does not trust: Ed25519
    /// cannot tell those apart).
    public static func verify(file: Data, signature: Data?, trustedKeys: [Data])
        -> ScriptConfirmationContent.Verification
    {
        guard let signature else { return .unsigned }
        guard let raw = decode(signature) else { return .badSignature }
        for keyData in trustedKeys {
            guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else { continue }
            if key.isValidSignature(raw, for: file) { return .verified }
        }
        return .badSignature
    }
}
