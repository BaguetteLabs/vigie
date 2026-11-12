import AgentKit
import CryptoKit
import Foundation
import ModuleKit

/// The signed price table on disk and on the release host (Story 6.5, AD-16): one plain HTTPS GET of
/// `prices.json` and one of `prices.json.sig` from the fixed ``PriceTableLocation``, nothing else sent. A table is
/// stored in `agents.usage`'s storage folder only when its detached Ed25519 signature verifies with the embedded
/// Sparkle public key and its `version` is above the newest one known. All file and network I/O runs on this
/// actor, off the main actor.
actor PriceTableUpdater {
    static let tableName = "prices.json"
    static let signatureName = "prices.json.sig"
    static let lastCheckName = "prices-check.json"

    /// The table the estimator uses, and where it comes from.
    struct Loaded: Hashable, Sendable {
        let table: PriceTable
        let source: PriceTableSource
    }

    /// What one check did.
    enum Outcome: Hashable, Sendable {
        /// A newer table was verified and stored.
        case updated(version: Int)
        /// The published table is the one already in use.
        case upToDate
        /// The host could not be reached or did not serve both files (offline, no release yet).
        case unavailable
        /// The signature does not verify with the embedded key.
        case badSignature
        /// A signed table older than the one in use (a rollback).
        case downgrade(version: Int)
        /// Signed but unreadable here (another schema).
        case unreadable
    }

    let directory: URL
    let bundled: PriceTable
    let http: any HTTPClient
    let now: @Sendable () -> Date

    init(directory: URL, bundled: PriceTable, http: any HTTPClient, now: @escaping @Sendable () -> Date) {
        self.directory = directory
        self.bundled = bundled
        self.http = http
        self.now = now
    }

    var tableURL: URL { directory.appendingPathComponent(Self.tableName) }
    var signatureURL: URL { directory.appendingPathComponent(Self.signatureName) }
    var lastCheckURL: URL { directory.appendingPathComponent(Self.lastCheckName) }

    // MARK: Disk

    /// The newest table on disk: the stored one (signature checked again with `publicKey`) when its version is
    /// above the bundled one, its missing provider sections taken from the bundled table; else the bundled one.
    func load(publicKey: Data?) -> Loaded {
        guard let publicKey, let stored = storedTable(publicKey: publicKey), stored.version > bundled.version else {
            return Loaded(table: bundled, source: .bundled)
        }
        return Loaded(table: stored.merged(fallback: bundled), source: .updated)
    }

    private func storedTable(publicKey: Data) -> PriceTable? {
        guard let data = try? Data(contentsOf: tableURL), let signature = try? Data(contentsOf: signatureURL),
            Self.verify(data, signature: signature, publicKey: publicKey)
        else { return nil }
        return try? PriceTable.decode(data)
    }

    /// When the last check that reached the host ran (persisted, so a relaunch does not check early).
    func lastChecked() -> Date? {
        guard let data = try? Data(contentsOf: lastCheckURL) else { return nil }
        return (try? JSONDecoder().decode(LastCheck.self, from: data))?.at
    }

    private func recordCheck() {
        if let data = try? JSONEncoder().encode(LastCheck(at: now())) {
            try? data.write(to: lastCheckURL, options: .atomic)
        }
    }

    struct LastCheck: Codable {
        let at: Date
    }

    // MARK: Network

    /// Fetches and verifies the published table. `current` is the version in use (stored or bundled).
    func check(_ location: PriceTableLocation, current: Int) async -> Outcome {
        guard let data = await fetch(location.tableURL), let signature = await fetch(location.signatureURL) else {
            return .unavailable
        }
        recordCheck()
        guard Self.verify(data, signature: signature, publicKey: location.publicKey) else { return .badSignature }
        guard let table = try? PriceTable.decode(data) else { return .unreadable }
        if table.version == current { return .upToDate }
        guard table.version > current else { return .downgrade(version: table.version) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: tableURL, options: .atomic)
            try signature.write(to: signatureURL, options: .atomic)
        } catch {
            return .unavailable
        }
        return .updated(version: table.version)
    }

    /// One GET: no cookies, no cache, no other header than URLSession's own.
    private func fetch(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpShouldHandleCookies = false
        guard let (data, response) = try? await http.data(for: request), response.statusCode == 200 else {
            return nil
        }
        return data
    }

    // MARK: Signature

    /// `signature` is the base64 Ed25519 signature of `data` (Sparkle's `sign_update` output, one line).
    static func verify(_ data: Data, signature: Data, publicKey: Data) -> Bool {
        let text = String(decoding: signature, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Data(base64Encoded: text), raw.count == 64,
            let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        else { return false }
        return key.isValidSignature(raw, for: data)
    }
}
