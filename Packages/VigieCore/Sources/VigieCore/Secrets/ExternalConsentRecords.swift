import Foundation
import ModuleKit

/// Where ``KeychainSecretStore`` keeps the user's consents to read another app's credential (Story 7.3, AD-9
/// amended): per Mac, never synced, revocable.
public protocol ExternalConsentRecords: Sendable {
    func consent(for descriptorID: String) async -> ExternalConsent?
    func grant(_ descriptorID: String, at date: Date) async throws
    func revoke(_ descriptorID: String) async throws
}

/// The production records: `[consents."<descriptor id>"] granted_at = "<ISO-8601>"` in `local.toml`, through
/// ``ConfigStore`` (the only writer of config files, AD-8). Never written to `config.toml`.
public struct ConfigConsentRecords: ExternalConsentRecords {
    let store: ConfigStore

    public init(store: ConfigStore) {
        self.store = store
    }

    public func consent(for descriptorID: String) async -> ExternalConsent? {
        await MainActor.run {
            store.registerConsent(descriptorID)
            guard let text = store.value(CoreSettings.consentPath(descriptorID), as: String.self), !text.isEmpty,
                let date = Self.parse(text)
            else { return nil }
            return ExternalConsent(descriptorID: descriptorID, grantedAt: date)
        }
    }

    public func grant(_ descriptorID: String, at date: Date) async throws {
        let path = CoreSettings.consentPath(descriptorID)
        await MainActor.run { store.registerConsent(descriptorID) }
        try await store.set(path, to: .string(Self.format(date)))
    }

    public func revoke(_ descriptorID: String) async throws {
        let path = CoreSettings.consentPath(descriptorID)
        await MainActor.run { store.registerConsent(descriptorID) }
        try await store.remove(path)
    }

    static func format(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    static func parse(_ text: String) -> Date? {
        try? Date(text, strategy: .iso8601)
    }
}

/// In-memory records (tests, and a store built without a ConfigStore).
public actor MemoryConsentRecords: ExternalConsentRecords {
    private var granted: [String: Date] = [:]

    public init() {}

    public func consent(for descriptorID: String) -> ExternalConsent? {
        granted[descriptorID].map { ExternalConsent(descriptorID: descriptorID, grantedAt: $0) }
    }

    public func grant(_ descriptorID: String, at date: Date) {
        granted[descriptorID] = date
    }

    public func revoke(_ descriptorID: String) {
        granted[descriptorID] = nil
    }
}
