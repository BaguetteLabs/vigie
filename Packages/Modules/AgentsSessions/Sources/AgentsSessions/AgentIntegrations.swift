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
///
/// Accounts (Story 7.11): the plans cover every Account's config location, the default first, in one confirmation
/// that lists each file's diff. A location whose folder does not exist is skipped and raised as a
/// `SETUP · AGENT` problem naming the path (sensitive). Adding an Account while the adapter is connected plans the
/// install for that location alone; removing one plans the removal from that location alone (both confirmed like
/// Connect, and neither changes `adapters`).
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

    /// What a plan covers: every Account's location (Connect, Install, Disconnect) or one Account's (Account
    /// added or removed, Story 7.11).
    public enum Scope: Equatable, Sendable {
        case all
        case account(AgentAccount)
    }

    /// One Account's location as the status line shows it (Story 7.11).
    public enum LocationState: Equatable, Sendable {
        case unknown
        /// Every hook present.
        case installed
        /// No managed hook.
        case missing
        /// Some hooks present, some missing (or edited away).
        case modified
        /// The location's folder does not exist (setup problem).
        case folderMissing
    }

    public struct Location: Identifiable, Equatable, Sendable {
        public let account: AgentAccount
        public var state: LocationState
        public var id: AccountID { account.id }
    }

    public struct Row: Identifiable, Equatable, Sendable {
        public let id: AgentID
        public let name: String
        public var support: AdapterSupport?
        public var status: Status = .unknown
        public var phase: Phase = .idle
        /// What the pending or last plan covers.
        public var scope: Scope = .all
        /// Each Account's location, the default first.
        public var locations: [Location] = []

        public var canConnect: Bool { status == .notConnected || status == .partial }
        public var canDisconnect: Bool { status == .connected || status == .partial }
        /// Some location is installed, another lacks hooks: the button reads Install (it repairs every one).
        public var isRepair: Bool { status == .partial }
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
    @ObservationIgnored let notifier: (any Notifier)?
    /// The Accounts each adapter had at the last check, to tell an added or removed one (Story 7.11).
    @ObservationIgnored private var knownAccounts: [AgentID: [AgentAccount]] = [:]
    /// Account plans waiting for the current confirmation to end.
    @ObservationIgnored private var queued: [AgentID: [(IntegrationAction, AgentAccount)]] = [:]
    /// Open missing-folder setup problems by dedupe key.
    @ObservationIgnored private var locationAlerts: [String: AlertHandle] = [:]
    @ObservationIgnored private var observers: [Task<Void, Never>] = []

    init(
        adapters: AgentAdapters, contexts: [AgentID: any AdapterContext], installer: any IntegrationInstaller,
        settings: any ModuleSettings, homeDirectory: URL, log: Logger, notifier: (any Notifier)? = nil
    ) {
        self.adapters = adapters
        self.contexts = contexts
        self.installer = installer
        self.settings = settings
        self.homeDirectory = homeDirectory
        self.log = log
        self.notifier = notifier
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

    /// Connect, or Install when some location lacks hooks: every Account's location.
    public func connect(_ id: AgentID) async { await plan(id, action: .install, scope: .all, changed: false) }

    /// Every Account's location.
    public func disconnect(_ id: AgentID) async { await plan(id, action: .remove, scope: .all, changed: false) }

    /// Applies the diff awaiting confirmation.
    public func confirm(_ id: AgentID) async {
        guard let row = row(id), case .confirming(let preview, _) = row.phase,
            let adapter = adapters.adapter(for: id)
        else { return }
        let scope = row.scope
        update(id) { $0.phase = .working }
        do {
            let result = try await installer.apply(preview)
            if scope == .all { await updateAdapterList(id, enabled: preview.action == .install) }
            update(id) { $0.phase = .applied(preview.action, result) }
            await refreshStatus(adapter)
            await runQueued(id)
        } catch IntegrationError.targetChanged, IntegrationError.stalePreview {
            await plan(id, action: preview.action, scope: scope, changed: true)
        } catch {
            log.error(
                "integration \(id.rawValue, privacy: .public) not applied: \(String(describing: error), privacy: .public)"
            )
            update(id) {
                $0.phase = .failed(
                    IntegrationText.format("agentsSessions.integration.error.apply", Self.describe(error)))
            }
            await runQueued(id)
        }
    }

    /// Drops the pending diff; nothing is written.
    public func cancel(_ id: AgentID) {
        update(id) { $0.phase = .idle }
        guard queued[id]?.isEmpty == false else { return }
        Task { await runQueued(id) }
    }

    // MARK: - Accounts (Story 7.11)

    /// Watches each adapter's `accounts` list (`adapterSettings`: the adapters' writable settings, the same
    /// `ConfigStore` table `agents.usage` edits); each change runs ``accountsChanged(_:)``.
    func observeAccounts(_ adapterSettings: [AgentID: any ModuleSettings]) {
        for adapter in adapters.adapters where adapter.defaultAccountLocation != nil {
            guard let store = adapterSettings[adapter.id] else { continue }
            let id = adapter.id
            // The baseline the first change is compared with (no file is read here).
            if knownAccounts[id] == nil { knownAccounts[id] = accounts(of: adapter) }
            let changes = store.observe(AgentAccounts.listKey)
            observers.append(
                Task { [weak self] in
                    for await _ in changes { await self?.accountsChanged(id) }
                })
        }
    }

    /// An Account was added or removed: removal from a removed Account's location (whatever the connection), install
    /// into an added one's while the adapter is connected (in `adapters`). One confirmation at a time; the others
    /// wait for it.
    func accountsChanged(_ id: AgentID) async {
        guard let adapter = adapters.adapter(for: id) else { return }
        let current = accounts(of: adapter)
        guard let known = knownAccounts[id] else {
            await refreshStatus(adapter)
            return
        }
        func same(_ a: AgentAccount, _ b: AgentAccount) -> Bool { a.id == b.id && a.location == b.location }
        let removed = known.filter { old in !old.isDefault && !current.contains { same($0, old) } }
        let added = current.filter { new in !new.isDefault && !known.contains { same($0, new) } }
        let connected = (settings.value("adapters", as: [String].self) ?? []).contains(id.rawValue)
        var plans = removed.map { (IntegrationAction.remove, $0) }
        if connected { plans += added.map { (IntegrationAction.install, $0) } }
        knownAccounts[id] = current
        queued[id, default: []] += plans
        if !isBusy(id) { await runQueued(id) }
        if queued[id]?.isEmpty != false, !isBusy(id) { await refreshStatus(adapter) }
    }

    func stopObserving() {
        for task in observers { task.cancel() }
        observers.removeAll()
        let open = locationAlerts.values
        locationAlerts.removeAll()
        for handle in open { handle.resolve() }
    }

    private func runQueued(_ id: AgentID) async {
        while var pending = queued[id], !pending.isEmpty, !isBusy(id) {
            let (action, account) = pending.removeFirst()
            queued[id] = pending
            await plan(id, action: action, scope: .account(account), changed: false)
        }
    }

    private func isBusy(_ id: AgentID) -> Bool {
        switch row(id)?.phase {
        case .working, .confirming: true
        default: false
        }
    }

    private func accounts(of adapter: any AgentAdapter) -> [AgentAccount] {
        adapter.accounts(settings: context(for: adapter).settings)
    }

    // MARK: - Flow

    private func plan(_ id: AgentID, action: IntegrationAction, scope: Scope, changed: Bool) async {
        guard let adapter = adapters.adapter(for: id) else { return }
        update(id) {
            $0.phase = .working
            $0.scope = scope
        }
        let context = context(for: adapter)
        var changed = changed
        do {
            for _ in 0..<Self.maxReplans {
                let diffs = try await diffs(adapter, context: context, action: action, scope: scope)
                guard !diffs.isEmpty else {
                    // Already in the requested state: keep `adapters` in step with it.
                    if scope == .all { await updateAdapterList(id, enabled: action == .install) }
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
        } catch let missing as MissingAccountLocation {
            update(id) {
                $0.phase = .failed(IntegrationText.format("agentsSessions.integration.location.error", missing.path))
            }
            await refreshStatus(adapter)
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

    /// The scope's diffs, the default location first. With `.all`, a location whose folder is missing is left out
    /// (``refreshStatus(_:)`` reports it); with one Account, it throws ``MissingAccountLocation``.
    private func diffs(
        _ adapter: any AgentAdapter, context: any AdapterContext, action: IntegrationAction, scope: Scope
    ) async throws -> [ConfigDiff] {
        let targets: [AgentAccount]
        switch scope {
        case .all: targets = accounts(of: adapter)
        case .account(let account): targets = [account]
        }
        var result: [ConfigDiff] = []
        for account in targets {
            do {
                let plan =
                    switch action {
                    case .install: try await adapter.integrationPlan(context: context, inputs: inputs, account: account)
                    case .remove: try await adapter.removalPlan(context: context, inputs: inputs, account: account)
                    }
                // Two Accounts never share a location (Settings refuses it); still, never write a file twice.
                result += plan.filter { diff in !result.contains { $0.path == diff.path } }
            } catch let missing as MissingAccountLocation where scope == .all {
                log.notice(
                    "integration \(adapter.id.rawValue, privacy: .public): Account \(missing.account.rawValue, privacy: .public) folder missing"
                )
            }
        }
        return result
    }

    private func refreshStatus(_ adapter: any AgentAdapter) async {
        let context = context(for: adapter)
        let accounts = accounts(of: adapter)
        // ``accountsChanged(_:)`` alone moves the snapshot on, so a refresh never hides an added or removed Account.
        if knownAccounts[adapter.id] == nil { knownAccounts[adapter.id] = accounts }
        var locations: [Location] = []
        var installEmpty = true
        var removeEmpty = true
        do {
            for account in accounts {
                do {
                    let install = try await adapter.integrationPlan(context: context, inputs: inputs, account: account)
                    let remove = try await adapter.removalPlan(context: context, inputs: inputs, account: account)
                    installEmpty = installEmpty && install.isEmpty
                    removeEmpty = removeEmpty && remove.isEmpty
                    let state = Self.locationState(installEmpty: install.isEmpty, removeEmpty: remove.isEmpty)
                    locations.append(Location(account: account, state: state))
                } catch is MissingAccountLocation {
                    locations.append(Location(account: account, state: .folderMissing))
                }
            }
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
        let status = Self.status(installEmpty: installEmpty, removeEmpty: removeEmpty)
        update(adapter.id) {
            $0.status = status
            $0.locations = locations
        }
        updateLocationAlerts(adapter, missing: locations.filter { $0.state == .folderMissing }.map(\.account))
    }

    nonisolated static func status(installEmpty: Bool, removeEmpty: Bool) -> Status {
        switch (installEmpty, removeEmpty) {
        case (true, false): .connected
        case (false, true): .notConnected
        case (false, false): .partial
        case (true, true): .none
        }
    }

    nonisolated static func locationState(installEmpty: Bool, removeEmpty: Bool) -> LocationState {
        switch (installEmpty, removeEmpty) {
        case (true, false): .installed
        case (false, true): .missing
        case (false, false): .modified
        case (true, true): .unknown
        }
    }

    // MARK: - Setup problems (Story 7.11)

    nonisolated static func locationDedupeKey(_ adapter: AgentID, _ account: AccountID) -> String {
        "location:\(adapter.rawValue):\(account.rawValue)"
    }

    private func updateLocationAlerts(_ adapter: any AgentAdapter, missing: [AgentAccount]) {
        let prefix = "location:\(adapter.id.rawValue):"
        let wanted = Set(missing.map { Self.locationDedupeKey(adapter.id, $0.id) })
        for key in locationAlerts.keys where key.hasPrefix(prefix) && !wanted.contains(key) {
            locationAlerts.removeValue(forKey: key)?.resolve()
        }
        guard let notifier else { return }
        for account in missing {
            let key = Self.locationDedupeKey(adapter.id, account.id)
            guard locationAlerts[key] == nil else { continue }
            locationAlerts[key] = notifier.post(Self.missingLocationEvent(adapter, account: account))
            log.notice(
                "integration \(adapter.id.rawValue, privacy: .public): Account \(account.id.rawValue, privacy: .public) folder missing"
            )
        }
    }

    /// `Claude Code · Work: config folder not found`, the path in the body. Title and body are sensitive
    /// (`NotifierEvent`: Privacy mode masks them).
    nonisolated static func missingLocationEvent(_ adapter: any AgentAdapter, account: AgentAccount) -> NotifierEvent {
        NotifierEvent(
            kind: AgentsSessionsModule.setupProblemKind,
            severity: .warn,
            title: IntegrationText.format(
                "agentsSessions.integration.location.problem.title", String(localized: adapter.name),
                IntegrationText.accountLabel(account)),
            body: IntegrationText.format(
                "agentsSessions.integration.location.problem.body", account.location?.path ?? ""),
            action: .openSettings(pane: AgentsSessionsModule.settingsPane),
            dedupeKey: locationDedupeKey(adapter.id, account.id),
            category: IntegrationText.string("agentsSessions.support.category"))
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

    /// Tests and previews: sets a row's location lines directly.
    func showForTesting(_ id: AgentID, locations: [Location]) {
        update(id) { $0.locations = locations }
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
struct NoAdapterSecrets: SecretStore {
    func read(_ key: String) async throws -> String? { nil }
    func write(_ value: String?, for key: String) async throws {}
}

struct NoAdapterExecutables: ExecutableResolver {
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

    /// The Account's label, `Default` for an unnamed default Account.
    static func accountLabel(_ account: AgentAccount) -> String {
        account.label.isEmpty
            ? (account.isDefault ? string("agentsSessions.integration.location.default") : account.id.rawValue)
            : account.label
    }

    /// `Work · ~/.claude-work: installed` (Story 7.11).
    static func location(_ location: AgentIntegrationsModel.Location, home: URL) -> String {
        let path = location.account.location.map { location in
            (location.normalizedPath(home: home) as NSString).abbreviatingWithTildeInPath
        }
        let state =
            switch location.state {
            case .unknown: string("agentsSessions.integration.location.unknown")
            case .installed: string("agentsSessions.integration.location.installed")
            case .missing: string("agentsSessions.integration.location.missing")
            case .modified: string("agentsSessions.integration.location.modified")
            case .folderMissing: string("agentsSessions.integration.location.folderMissing")
            }
        return format("agentsSessions.integration.location.line", accountLabel(location.account), path ?? "", state)
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
