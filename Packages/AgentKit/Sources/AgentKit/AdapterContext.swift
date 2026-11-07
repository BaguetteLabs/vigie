import Foundation
import os

/// Read-only view of one adapter's settings, at the SPEC §11 path
/// `[modules."agents.sessions".adapters.<id>]` (AD-23). Edited only on Settings › Agents, never by the adapter.
public protocol ReadOnlySettings: Sendable {
    /// The resolved value of `key` (config, else the declared default), or nil if unset or of another type.
    func value<T: SettingValue>(_ key: String, as type: T.Type) -> T?
}

/// The only network path for adapters (AD-19), so tests can fake it and the app can add policy in one place.
public protocol HTTPClient: Sendable {
    /// Performs `request`. Throws on transport errors; a non-HTTP response is a transport error too.
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The complete service API an adapter may use (AD-19). Declared here, built by App assembly from VigieCore
/// services (AD-4). Adapters never call Security, `Process` with a bare executable name, or `URLSession`
/// directly.
public protocol AdapterContext: Sendable {
    var settings: any ReadOnlySettings { get }
    var secrets: any SecretStore { get }
    /// The same resolver instance as `ModuleContext.executables`.
    var executables: any ExecutableResolver { get }
    var http: any HTTPClient { get }
    /// `os.Logger`, subsystem = bundle id, category = adapter id. Never log secrets.
    var log: Logger { get }
}

/// The concrete `AdapterContext` App assembly builds for each adapter.
public struct AdapterContextBox: AdapterContext {
    public let settings: any ReadOnlySettings
    public let secrets: any SecretStore
    public let executables: any ExecutableResolver
    public let http: any HTTPClient
    public let log: Logger

    public init(
        settings: any ReadOnlySettings,
        secrets: any SecretStore,
        executables: any ExecutableResolver,
        http: any HTTPClient,
        log: Logger
    ) {
        self.settings = settings
        self.secrets = secrets
        self.executables = executables
        self.http = http
        self.log = log
    }
}

/// `ReadOnlySettings` that returns each descriptor's declared default. Used until ConfigStore serves adapter
/// settings (Stories 2.3 / 2.13).
public struct DefaultsReadOnlySettings: ReadOnlySettings {
    public let descriptors: [SettingDescriptor]

    public init(descriptors: [SettingDescriptor]) {
        self.descriptors = descriptors
    }

    public func value<T: SettingValue>(_ key: String, as type: T.Type) -> T? {
        descriptors.first { $0.key == key }?.defaultValue as? T
    }
}

/// `HTTPClient` backed by an ephemeral `URLSession` (no cookies or cache on disk).
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}
