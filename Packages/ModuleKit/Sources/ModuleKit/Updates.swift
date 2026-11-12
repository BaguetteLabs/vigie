import Foundation

/// Where the signed price table is published (Story 6.5, AD-16): one fixed HTTPS location built from the release
/// repository, and the embedded Sparkle EdDSA public key that verifies it.
public struct PriceTableLocation: Hashable, Sendable {
    /// `https://github.com/<release repo>/releases/latest/download/prices.json`.
    public let tableURL: URL
    /// The detached signature next to it (`prices.json.sig`: the base64 Ed25519 signature of the table's bytes).
    public let signatureURL: URL
    /// The raw 32-byte Ed25519 public key (`SUPublicEDKey`, decoded).
    public let publicKey: Data

    public init(tableURL: URL, signatureURL: URL, publicKey: Data) {
        self.tableURL = tableURL
        self.signatureURL = signatureURL
        self.publicKey = publicKey
    }
}

/// The app-level `[updates]` keys a module may read (Story 6.5, AD-8): read-only, current at each read. Only
/// `agents.usage` uses it, for the price table.
public protocol UpdatesService: Sendable {
    /// `[updates] prices`: fetch the signed price table. Off = no request at all.
    var pricesEnabled: Bool { get }
    /// `[updates] check_interval`, never under one hour.
    var checkInterval: Duration { get }
    /// The price table's location and key; nil when this build has none (placeholder release repository, no
    /// public key): then nothing is ever fetched.
    var priceTable: PriceTableLocation? { get }
}

/// No updates in this context: prices off, no location.
public struct NoUpdatesService: UpdatesService {
    public init() {}
    public var pricesEnabled: Bool { false }
    public var checkInterval: Duration { .seconds(24 * 3600) }
    public var priceTable: PriceTableLocation? { nil }
}
