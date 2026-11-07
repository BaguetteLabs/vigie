import AgentKit
import Foundation
import ModuleKit
import Observation
import os

/// Settings › Agents: connect and disconnect each agent adapter's integration (Story 4.7, FR41, FR82, AD-22).
///
/// Connect asks the adapter for its install plan (`integrationPlan`), previews it through
/// `IntegrationInstaller` and waits for the user to confirm the diff. A stale preview (the target changed since
/// the plan was read) or an apply refused with `targetChanged` re-plans through the adapter and shows the new diff
/// instead. On success the adapter id is added to `adapters` (`[modules."agents.sessions"]`); Disconnect runs the
/// removal plan the same way and removes it. The module never writes agent config itself.
@MainActor @Observable
public final class AgentIntegrationsModel {
    /// Where an adapter's integration stands, from its two plans.
    public enum Status: Equatable, Sendable {
        /// Not checked yet.
        case unknown
        /// Nothing left to install, managed entries present.
        case connected
        /// No managed entry yet.
        case notConnected
        /// Some managed entries, some missing.
        case partial
        /// The adapter has no integration to install (both plans empty, nothing managed).
        case none
    }

    public enum Phase: Equatable, Sendable {
        case idle
        /// Planning, previewing or applying.
        case working
        /// The diff awaits Apply or Cancel. `changed`: the target changed since the first plan and this is the
        /// re-planned diff.
        case confirming(IntegrationPreview, changed: Bool)
        /// The last apply succeeded.
        case applied(IntegrationAction, IntegrationResult)
        case failed(String)
    }

    public struct Row: Identifiable, Equatable, Sendable {
        public let id: AgentID
        public let name: String
        public var support: AdapterSupport?
        public var status: Status = .unknown
        public var phase: Phase = .idle

        public var canConnect: Bool { status == .notConnected || status == .partial }
        public var canDisconnect: Bool { status == .connected || status == .partial }
    }

    /// How many times a stale preview is re-planned before giving up.
    nonisolated static let maxReplans = 3

    public private(set) var rows: [Row]

    @ObservationIgnored let adapters: AgentAdapters
    @ObservationIgnored let contexts: [AgentID: any AdapterContext]
    @ObservationIgnored let installer: any IntegrationInstaller
    @ObservationIgnored let settings: any ModuleSettings
    @ObservationIgnored let homeDirectory: URL
    @ObservationIgnored let log: Logger

    init(
        adapters: AgentAdapters, contexts: [AgentID: any AdapterContext], installer: any IntegrationInstaller,
        settings: any ModuleSettings, homeDirectory: URL, log: Logger
    ) {
        self.adapters = adapters
        self.contexts = contexts
        self.installer = installer
        self.settings = settings
        self.homeDirectory = homeDirectory
        self.log = log
        rows = adapters.adapters.map { Row(id: $0.id, name: String(localized: $0.name)) }
    }

    var inputs: IntegrationInputs {
        IntegrationInputs(cliPath: installer.cliPath, homeDirectory: homeDirectory, projectDirectory: nil)
    }

    /// Detects each adapter's version and status. Rows awaiting confirmation keep their phase.
    public func refresh() async {
        for adapter in adapters.adapters {
            let context = context(for: adapter)
            let version = await adapter.detectVersion(context: context)
            update(adapter.id) { $0.support = adapter.support(for: version) }
            await refreshStatus(adapter)
        }
    }

    public func connect(_ id: AgentID) async { await plan(id, action: .install, changed: false) }

    public func disconnect(_ id: AgentID) async { await plan(id, action: .remove, changed: false) }

    /// Applies the diff awaiting confirmation.
    public func confirm(_ id: AgentID) async {
        guard let row = row(id), case .confirming(let preview, _) = row.phase,
            let adapter = adapters.adapter(for: id)
        else { return }
        update(id) { $0.phase = .working }
        do {
            let result = try await installer.apply(preview)
            await updateAdapterList(id, enabled: preview.action == .install)
            update(id) { $0.phase = .applied(preview.action, result) }
            await refreshStatus(adapter)
        } catch IntegrationError.targetChanged, IntegrationError.stalePreview {
            await plan(id, action: preview.action, changed: true)
        } catch {
            log.error(
                "integration \(id.rawValue, privacy: .public) not applied: \(String(describing: error), privacy: .public)"
            )
            update(id) {
                $0.phase = .failed(
                    IntegrationText.format("agentsSessions.integration.error.apply", Self.describe(error)))
            }
        }
    }

    /// Drops the pending diff; nothing is written.
    public func cancel(_ id: AgentID) {
        update(id) { $0.phase = .idle }
    }

    // MARK: - Flow

    private func plan(_ id: AgentID, action: IntegrationAction, changed: Bool) async {
        guard let adapter = adapters.adapter(for: id) else { return }
        update(id) { $0.phase = .working }
        let context = context(for: adapter)
        var changed = changed
        do {
            for _ in 0..<Self.maxReplans {
                let diffs =
                    switch action {
                    case .install: try await adapter.integrationPlan(context: context, inputs: inputs)
                    case .remove: try await adapter.removalPlan(context: context, inputs: inputs)
                    }
                guard !diffs.isEmpty else {
                    // Already in the requested state: keep `adapters` in step with it.
                    await updateAdapterList(id, enabled: action == .install)
                    update(id) { $0.phase = .idle }
                    await refreshStatus(adapter)
                    return
                }
                let preview = try await installer.preview(diffs, adapterID: id.rawValue, action: action)
                if !preview.stale {
                    update(id) { $0.phase = .confirming(preview, changed: changed) }
                    return
                }
                changed = true
            }
            update(id) { $0.phase = .failed(IntegrationText.string("agentsSessions.integration.error.unstable")) }
        } catch {
            log.error(
                "integration \(id.rawValue, privacy: .public) not planned: \(String(describing: error), privacy: .public)"
            )
            update(id) {
                $0.phase = .failed(
                    IntegrationText.format("agentsSessions.integration.error.plan", Self.describe(error)))
            }
        }
    }

    private func refreshStatus(_ adapter: any AgentAdapter) async {
        let context = context(for: adapter)
        let status: Status
        do {
            let install = try await adapter.integrationPlan(context: context, inputs: inputs)
            let remove = try await adapter.removalPlan(context: context, inputs: inputs)
            status = Self.status(installEmpty: install.isEmpty, removeEmpty: remove.isEmpty)
        } catch {
            log.error(
                "integration \(adapter.id.rawValue, privacy: .public) status: \(String(describing: error), privacy: .public)"
            )
            update(adapter.id) {
                $0.status = .unknown
                if case .confirming = $0.phase { return }
                $0.phase = .failed(
                    IntegrationText.format("agentsSessions.integration.error.plan", Self.describe(error)))
            }
            return
        }
        update(adapter.id) { $0.status = status }
    }

    nonisolated static func status(installEmpty: Bool, removeEmpty: Bool) -> Status {
        switch (installEmpty, removeEmpty) {
        case (true, false): .connected
        case (false, true): .notConnected
        case (false, false): .partial
        case (true, true): .none
        }
    }

    /// Adds or removes `id` in `adapters` (FR41), keeping the order of the others.
    private func updateAdapterList(_ id: AgentID, enabled: Bool) async {
        let current = settings.value("adapters", as: [String].self) ?? []
        var next = current.filter { $0 != id.rawValue }
        if enabled { next = current.contains(id.rawValue) ? current : current + [id.rawValue] }
        guard next != current else { return }
        do {
            try await settings.set(next, for: "adapters")
        } catch {
            log.error("adapters not updated: \(String(describing: error), privacy: .public)")
        }
    }

    private func context(for adapter: any AgentAdapter) -> any AdapterContext {
        contexts[adapter.id]
            ?? AdapterContextBox(
                settings: DefaultsReadOnlySettings(descriptors: adapter.settings), secrets: NoAdapterSecrets(),
                executables: NoAdapterExecutables(), http: URLSessionHTTPClient(), log: log)
    }

    func row(_ id: AgentID) -> Row? { rows.first { $0.id == id } }

    /// Tests and previews: puts a row in `phase` directly.
    func showForTesting(_ id: AgentID, _ phase: Phase) {
        update(id) { $0.phase = phase }
    }

    private func update(_ id: AgentID, _ change: (inout Row) -> Void) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        var row = rows[index]
        change(&row)
        if row != rows[index] { rows[index] = row }
    }

    nonisolated static func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}

/// Used only when App assembly gave an adapter no context (tests, previews).
private struct NoAdapterSecrets: SecretStore {
    func read(_ key: String) async throws -> String? { nil }
    func write(_ value: String?, for key: String) async throws {}
}

private struct NoAdapterExecutables: ExecutableResolver {
    func resolve(_ name: String) async -> URL? { nil }
}

/// Catalog lookups for the integration block.
enum IntegrationText {
    static func string(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }

    static func format(_ key: String, _ arguments: any CVarArg...) -> String {
        let locale = Locale(identifier: Bundle.module.preferredLocalizations.first ?? "en")
        return String(format: string(key), locale: locale, arguments: arguments)
    }

    /// `Claude Code 2.1.319 · supported`, the 4.6 warning for an assumed or unsupported version, or
    /// `Not installed`.
    static func support(_ support: AdapterSupport?) -> String {
        switch support {
        case nil: string("agentsSessions.integration.version.checking")
        case .supported(let version): format("agentsSessions.integration.version.supported", version.display)
        case .assumed(let version): format("agentsSessions.integration.version.assumed", version.display)
        case .unsupported(let version): format("agentsSessions.integration.version.unsupported", version.display)
        case .notInstalled: string("agentsSessions.integration.version.notInstalled")
        }
    }

    static func status(_ status: AgentIntegrationsModel.Status) -> String {
        switch status {
        case .unknown: string("agentsSessions.integration.status.unknown")
        case .connected: string("agentsSessions.integration.status.connected")
        case .notConnected: string("agentsSessions.integration.status.notConnected")
        case .partial: string("agentsSessions.integration.status.partial")
        case .none: string("agentsSessions.integration.status.none")
        }
    }

    static func applied(_ action: IntegrationAction, _ result: IntegrationResult) -> String {
        let done = string(
            action == .install
                ? "agentsSessions.integration.applied.install" : "agentsSessions.integration.applied.remove")
        guard let backup = result.backupPaths.first else { return done }
        let path = (backup.path as NSString).abbreviatingWithTildeInPath
        return done + " " + format("agentsSessions.integration.applied.backup", path)
    }
}

extension AgentVersion {
    /// The semver when parsed, else the raw text.
    var display: String { semver?.description ?? raw }
}
