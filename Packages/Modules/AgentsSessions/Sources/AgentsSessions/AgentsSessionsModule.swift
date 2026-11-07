import AgentKit
import Foundation
import ModuleKit
import Observation
import SwiftUI
import VigieUI
import Wire
import os

/// `agents.sessions` (SPEC §7.1): tracks every running CLI agent session.
///
/// App assembly builds the adapter lists once and passes the same instances here and to `agents.usage`
/// (AD-4); this module never discovers adapters itself, so adding an agent needs no change here (NFR23).
///
/// Event path (AD-5, AD-7): `agent.hook` messages are decoded (`HookPayload`) and normalized by the matching
/// adapter off the main actor, then applied in arrival order to the `SessionStore` on the main actor. Replayed
/// messages go through the same path, so statuses converge. Status and membership changes are persisted to
/// `sessions.json` off the main actor; heartbeats are not.
@MainActor @Observable
public final class AgentsSessionsModule: NotchModule {
    nonisolated static let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)

    /// `sessions.json`, schema 1.
    nonisolated static let storageName = "sessions"
    nonisolated static let storageSchema = 1
    /// SPEC §11 default for `done_to_idle`.
    nonisolated static let defaultDoneToIdle: Duration = .seconds(15 * 60)
    /// How often done sessions are checked against `done_to_idle`.
    nonisolated static let expiryInterval: Duration = .seconds(30)

    public nonisolated static let staticManifest = ModuleManifest(
        id: "agents.sessions",
        name: LocalizedStringResource("agentsSessions.module.name", bundle: bundle),
        icon: "terminal",
        settings: [
            SettingDescriptor(
                key: "done_to_idle",
                label: LocalizedStringResource("agentsSessions.setting.doneToIdle", bundle: bundle),
                kind: .duration(default: defaultDoneToIdle),
                scope: .synced,
                help: LocalizedStringResource("agentsSessions.setting.doneToIdle.help", bundle: bundle)),
            SettingDescriptor(
                key: "terminal",
                label: LocalizedStringResource("agentsSessions.setting.terminal", bundle: bundle),
                kind: .string(default: "terminal"),
                scope: .local),
            SettingDescriptor(
                key: "adapters",
                label: LocalizedStringResource("agentsSessions.setting.adapters", bundle: bundle),
                kind: .list(of: .string, default: ["claude"]),
                scope: .synced),
        ],
        defaultEnabled: true
    )

    public let manifest = AgentsSessionsModule.staticManifest
    public private(set) var state: ModuleState = .hidden

    public let adapters: AgentAdapters
    public let terminals: TerminalAdapters
    /// Per-adapter contexts built by App assembly (AD-19), for adapter calls that need services.
    public let adapterContexts: [AgentID: any AdapterContext]

    /// The session table. Only its reducer writes statuses (AD-5).
    public let store = SessionStore()
    /// Urgency-sorted sessions (FR34).
    public var sessions: [Session] { store.sessions }

    @ObservationIgnored var eventTask: Task<Void, Never>?
    @ObservationIgnored private var expiryToken: RegistrationToken?
    @ObservationIgnored private var persister: SessionPersister?
    @ObservationIgnored private var log: Logger?

    public init(
        adapters: AgentAdapters,
        terminals: TerminalAdapters,
        contexts: [AgentID: any AdapterContext] = [:]
    ) {
        self.adapters = adapters
        self.terminals = terminals
        self.adapterContexts = contexts
    }

    public func start(context: any ModuleContext) async throws {
        let log = context.log
        self.log = log
        let persister = SessionPersister(storage: context.storage, log: log)
        self.persister = persister

        let saved: [Session]?
        do {
            saved = try await context.storage.readJSON(
                Self.storageName, as: [Session].self, schema: Self.storageSchema)
        } catch {
            log.error("sessions.json not loaded: \(String(describing: error), privacy: .public)")
            saved = nil
        }
        store.load(saved ?? [])
        if let save = expireDone(settings: context.settings) {
            await persister.write(save.sessions, generation: save.generation)
        }
        syncState()

        // Subscribe before returning (AD-6 launch order: modules subscribe before the spool replay).
        let stream = context.events.subscribe(topicPrefix: "agent.")
        let pipeline = HookPipeline(adapters: adapters, log: log)
        eventTask = Task.detached { [weak self] in
            for await message in stream {
                let events = pipeline.normalize(message)
                guard !events.isEmpty else { continue }
                let save = await self?.apply(events)
                if let save { await persister.write(save.sessions, generation: save.generation) }
            }
        }

        let settings = context.settings
        expiryToken = context.scheduler.every(Self.expiryInterval) { [weak self] in
            guard let save = await self?.expireDone(settings: settings) else { return }
            await persister.write(save.sessions, generation: save.generation)
        }
    }

    public func stop() async {
        eventTask?.cancel()
        eventTask = nil
        expiryToken?.cancel()
        expiryToken = nil
        // Heartbeat metadata (last action, last event time) is saved once on the way out.
        await persister?.write(store.snapshot, generation: store.generation, force: true)
    }

    // TODO(4.9): one status glyph per session, in urgency order.
    public func leftWingItems() -> [LeftWingItem] { [] }

    // TODO(4.10): the Agents tab list replaces this placeholder.
    public func expandedView() -> AnyView? {
        AnyView(EmptyStateBlock(VigieCopy.noActiveSessions))
    }

    /// Applies normalized events in order; returns the table to persist when status or membership changed.
    func apply(_ events: [AgentEvent]) -> (sessions: [Session], generation: Int)? {
        var persist = false
        for event in events where store.apply(event).persists {
            persist = true
        }
        syncState()
        return persist ? (store.snapshot, store.generation) : nil
    }

    /// Runs the `done_to_idle` check now; returns the table to persist when a session moved.
    @discardableResult
    func expireDone(settings: any ModuleSettings, now: Date = Date()) -> (sessions: [Session], generation: Int)? {
        let delay = settings.value("done_to_idle", as: Duration.self) ?? Self.defaultDoneToIdle
        let expired = store.expireDone(now: now, doneToIdle: delay)
        syncState()
        return expired.isEmpty ? nil : (store.snapshot, store.generation)
    }

    private func syncState() {
        if state != store.state { state = store.state }
    }
}

/// Decodes `agent.hook` payloads and normalizes them with the matching adapter. Runs off the main actor;
/// logs an unknown agent once per id.
final class HookPipeline: Sendable {
    static let hookTopic = "agent.hook"

    private let adapters: AgentAdapters
    private let log: Logger
    private let reported = OSAllocatedUnfairLock(initialState: Set<String>())

    init(adapters: AgentAdapters, log: Logger) {
        self.adapters = adapters
        self.log = log
    }

    func normalize(_ message: EventMessage) -> [AgentEvent] {
        // TODO(generic path, AD-5): `agent.generic` from `vigie agent` / `vigie run`.
        guard message.topic == Self.hookTopic else { return [] }
        let payload: HookPayload
        do {
            payload = try JSONDecoder().decode(HookPayload.self, from: message.payload)
        } catch {
            log.error("agent.hook payload not decoded: \(String(describing: error), privacy: .public)")
            return []
        }
        guard let id = AgentID(payload.agent), let adapter = adapters.adapter(for: id) else {
            let first = reported.withLock { $0.insert(payload.agent).inserted }
            if first {
                log.notice("agent.hook from unknown agent \(payload.agent, privacy: .public): ignored")
            }
            return []
        }
        return adapter.normalize(payload, sentAt: message.sentAt)
    }
}

/// Writes `sessions.json` through `ModuleStorage` off the main actor, dropping snapshots older than the last one
/// written (two writers: the event loop and the expiry job).
actor SessionPersister {
    private let storage: any ModuleStorage
    private let log: Logger
    private var written = -1

    init(storage: any ModuleStorage, log: Logger) {
        self.storage = storage
        self.log = log
    }

    func write(_ sessions: [Session], generation: Int, force: Bool = false) async {
        guard force || generation > written else { return }
        written = max(written, generation)
        do {
            try await storage.writeJSON(
                sessions, name: AgentsSessionsModule.storageName, schema: AgentsSessionsModule.storageSchema)
        } catch {
            log.error("sessions.json not written: \(String(describing: error), privacy: .public)")
        }
    }
}
