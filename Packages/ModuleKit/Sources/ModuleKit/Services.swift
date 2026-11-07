import Foundation

// MARK: - Settings (implemented in Story 2.3 / 2.13)

/// Typed access to the module's own settings, routed by each descriptor's scope (AD-8).
public protocol ModuleSettings: Sendable {
    /// The resolved value of `key` (config, else the declared default), or nil if unset or of another type.
    func value<T: SettingValue>(_ key: String, as type: T.Type) -> T?
    /// Writes through ConfigStore (Story 2.13); nil removes the key.
    func set<T: SettingValue>(_ value: T?, for key: String) async throws
    /// Yields each time the resolved value of `key` changes.
    func observe(_ key: String) -> AsyncStream<Void>
}

// MARK: - Storage (implemented in Story 2.2)

/// The module's private data folder `<AppEnvironment.applicationSupportURL>/modules/<module id>/` (AD-11).
///
/// JSON state files carry a top-level `"schema"` (Conventions: JSON state files). Writes are atomic and
/// coalesced to at most one disk write per 250 ms per file; an unreadable file is renamed `.corrupt` and
/// reads as nil.
public protocol ModuleStorage: Sendable {
    var directory: URL { get }

    /// Reads `<name>.json`. Returns nil when the file is missing or unreadable (then set aside as `.corrupt`).
    /// A file written with an older schema is passed to `migrate(fromSchema, valueJSON)`; without a
    /// migration it is decoded as `T` directly. Throws `ModuleStorageError.newerSchema` for a newer file.
    func readJSON<T: Decodable & Sendable>(
        _ name: String,
        as type: T.Type,
        schema: Int,
        migrate: (@Sendable (_ fromSchema: Int, _ value: Data) throws -> T)?
    ) async throws -> T?

    /// Encodes now (throws on encoding failure), writes later: atomically, coalesced per file.
    func writeJSON<T: Encodable & Sendable>(_ value: T, name: String, schema: Int) async throws

    /// Writes every pending value now. Called by the Registry after `stop()`.
    func flush() async

    /// The folder a `path` setting points at (notes folder, AD-11). Implemented in Story 2.3+.
    func userFolder(setting key: String) -> URL?
}

extension ModuleStorage {
    public func readJSON<T: Decodable & Sendable>(_ name: String, as type: T.Type, schema: Int) async throws -> T? {
        try await readJSON(name, as: type, schema: schema, migrate: nil)
    }
}

public enum ModuleStorageError: Error, Equatable, Sendable {
    /// The file was written by a newer Vigie; it is left untouched.
    case newerSchema(found: Int, supported: Int)
    /// The name is not a plain file name.
    case invalidName(String)
}

// MARK: - Secrets (implemented in Story 7.2)

/// Keychain access for the module's `secret` settings (AD-9).
public protocol SecretStore: Sendable {
    func read(_ key: String) async throws -> String?
    /// nil deletes the secret.
    func write(_ value: String?, for key: String) async throws
}

// MARK: - Scheduler (implemented in Story 2.2)

public protocol Scheduler: Sendable {
    /// Runs `body` every `interval` (first run after one interval), never overlapping itself.
    func every(_ interval: Duration, _ body: @escaping @Sendable () async -> Void) -> RegistrationToken
    /// Runs `body` once at `date` (immediately if it is in the past).
    func at(_ date: Date, _ body: @escaping @Sendable () async -> Void) -> RegistrationToken
}

// MARK: - Hotkeys (implemented in Story 2.9)

public protocol HotkeyRegistry: Sendable {
    /// Registers `<module id>.<name>` with an optional default shortcut (e.g. `opt+cmd+n`). The handler gets
    /// a `UserIntent`. Throws when the name is taken (the earlier registration wins, AD-13).
    func register(
        name: String,
        default shortcut: String?,
        handler: @escaping @MainActor @Sendable (UserIntent) -> Void
    ) throws -> RegistrationToken
}

// MARK: - Notifier (implemented in Story 3.1)

public enum AlertSeverity: Int, Comparable, Hashable, Sendable, Codable {
    case info
    case warn
    case critical

    public static func < (lhs: AlertSeverity, rhs: AlertSeverity) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What clicking an alert does (AD-13).
public enum AlertAction: Hashable, Sendable {
    /// Routed back to the posting module.
    case module(id: ModuleID, actionID: String, payload: Data)
    case openSettings(pane: String)
    case openURL(URL)
}

/// An alert a module posts. The posting module's id is added by its context.
public struct NotifierEvent: Hashable, Sendable {
    /// One of the kinds declared in the manifest's `alertKinds`.
    public let kind: String
    public let severity: AlertSeverity
    public let title: String
    public let body: String?
    public let action: AlertAction?
    public let dedupeKey: String?
    /// Numeric facts the Notifier's rule conditions compare against (A54), e.g. `working_duration` in seconds.
    public let metrics: [String: Double]

    public init(
        kind: String,
        severity: AlertSeverity,
        title: String,
        body: String? = nil,
        action: AlertAction? = nil,
        dedupeKey: String? = nil,
        metrics: [String: Double] = [:]
    ) {
        self.kind = kind
        self.severity = severity
        self.title = title
        self.body = body
        self.action = action
        self.dedupeKey = dedupeKey
        self.metrics = metrics
    }
}

/// Returned by `Notifier.post`; `resolve()` when the condition ends cancels reminders and retracts the peek.
public struct AlertHandle: Hashable, Sendable {
    public let id: UUID
    private let onResolve: @Sendable () -> Void

    public init(id: UUID = UUID(), resolve: @escaping @Sendable () -> Void) {
        self.id = id
        self.onResolve = resolve
    }

    public func resolve() { onResolve() }

    public static func == (lhs: AlertHandle, rhs: AlertHandle) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public protocol Notifier: Sendable {
    @discardableResult
    func post(_ event: NotifierEvent) -> AlertHandle
}

// MARK: - Events (implemented in Story 2.2; fed by the Event Server in Story 4.1)

/// One message on the event bus.
public struct EventMessage: Hashable, Sendable {
    /// Lowercase dotted, e.g. `agent.hook`.
    public let topic: String
    public let payload: Data
    /// When the sender produced it (envelope `sent_at`, AD-7).
    public let sentAt: Date
    public let receivedAt: Date
    /// True when it came from the spool replay (AD-6).
    public let replayed: Bool

    public init(topic: String, payload: Data, sentAt: Date, receivedAt: Date = Date(), replayed: Bool = false) {
        self.topic = topic
        self.payload = payload
        self.sentAt = sentAt
        self.receivedAt = receivedAt
        self.replayed = replayed
    }
}

public protocol EventBus: Sendable {
    /// Messages whose topic equals `topicPrefix` or lies under it (`agent` and `agent.` both match `agent.hook`,
    /// not `agents.x`); an empty prefix matches everything. The stream ends when the module stops.
    func subscribe(topicPrefix: String) -> AsyncStream<EventMessage>
}

// MARK: - Host (implemented in Stories 2.5, 2.10, 3.2, AD-18 dynamic modules)

public protocol HostControl: Sendable {
    /// Asks the host to show this module's closed-notch content briefly. Alerts go through `Notifier`.
    @MainActor func requestPeek()
    /// Expands the notch; takes focus only with a `UserIntent` (AD-13).
    @MainActor func expand(focus: UserIntent?)
    /// Expands the notch on this module's tab.
    @MainActor func openOwnTab(focus: UserIntent?)
    /// Registers a dynamic (script) module; the token unregisters it (AD-18).
    @MainActor func registerDynamicModule(_ module: any NotchModule) throws -> RegistrationToken
}

// MARK: - Permissions (implemented in Story 2.12)

public enum PermissionStatus: Hashable, Sendable {
    case notDetermined
    case granted
    case denied
    /// Automation only: the target app is not running, so macOS cannot say.
    case targetNotRunning
}

public protocol PermissionsService: Sendable {
    func status(of permission: Permission) async -> PermissionStatus
    func request(_ permission: Permission) async -> PermissionStatus
}

// MARK: - Power (implemented in Story 4.12)

public enum SleepWakeEvent: Hashable, Sendable {
    case willSleep
    case didWake
}

public protocol PowerService: Sendable {
    /// Keeps the Mac from idle-sleeping until the token is cancelled (or the module stops).
    func preventIdleSleep(reason: String) -> RegistrationToken
    var sleepWake: AsyncStream<SleepWakeEvent> { get }
}

// MARK: - Clipboard (implemented in Story 9.9)

public protocol ClipboardService: Sendable {
    /// Copies plain text; clears it after `clearAfter` if the clipboard still holds it.
    func copy(_ text: String, clearAfter: Duration?)
}

// MARK: - Executables (implemented in Story 4.4)

public protocol ExecutableResolver: Sendable {
    /// Absolute URL of `name` from the login-shell PATH or a `local.toml` override; nil if not found.
    func resolve(_ name: String) async -> URL?
}

// MARK: - Privacy (implemented in Story 21.2)

public protocol PrivacyService: Sendable {
    var isActive: Bool { get }
    var changes: AsyncStream<Bool> { get }
}

// MARK: - Away (implemented in Story 20.3)

public enum Presence: Hashable, Sendable {
    case present
    case away(since: Date)
}

public protocol AwayService: Sendable {
    var presence: Presence { get }
    var changes: AsyncStream<Presence> { get }
}

// MARK: - Activity log (implemented in Story 3.8)

public enum ActivityCategory: String, Codable, Hashable, Sendable {
    case alert, peek, reminder, focus, module
}

/// What happened. Encoded as one string: `posted`, `suppressed:<reason>`, `focusFailed:<reason>`, `custom:<text>`.
public enum ActivityOutcome: Hashable, Sendable, Codable {
    case posted
    /// `reason`: mute, quietHours, cooldown, dnd, undeclaredKind, minSeverity, condition.
    case suppressed(reason: String)
    case shown
    case repeated
    case dismissed
    case resolved
    case focusExact
    case focusAppOnly
    case focusFailed(reason: String)
    case custom(String)

    public var encoded: String {
        switch self {
        case .posted: "posted"
        case .suppressed(let r): "suppressed:\(r)"
        case .shown: "shown"
        case .repeated: "repeated"
        case .dismissed: "dismissed"
        case .resolved: "resolved"
        case .focusExact: "focusExact"
        case .focusAppOnly: "focusAppOnly"
        case .focusFailed(let r): "focusFailed:\(r)"
        case .custom(let t): "custom:\(t)"
        }
    }

    public init(encoded: String) {
        let parts = encoded.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let tail = parts.count > 1 ? String(parts[1]) : ""
        switch parts[0] {
        case "posted": self = .posted
        case "suppressed": self = .suppressed(reason: tail)
        case "shown": self = .shown
        case "repeated": self = .repeated
        case "dismissed": self = .dismissed
        case "resolved": self = .resolved
        case "focusExact": self = .focusExact
        case "focusAppOnly": self = .focusAppOnly
        case "focusFailed": self = .focusFailed(reason: tail)
        case "custom": self = .custom(tail)
        default: self = .custom(encoded)
        }
    }

    public init(from decoder: any Decoder) throws {
        self.init(encoded: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(encoded)
    }
}

/// An outcome entry (AD-26), one JSON line. Never put secrets, note content or raw script output in it;
/// `detail` is small, and `redacted()` drops keys that look secret and truncates values to 200 characters.
public struct ActivityEntry: Hashable, Sendable, Codable {
    public var at: Date
    /// nil for core components.
    public var module: ModuleID?
    public var category: ActivityCategory
    /// Alert kind or focus action.
    public var kind: String
    public var severity: AlertSeverity?
    public var dedupeKey: String?
    public var outcome: ActivityOutcome
    /// Terminal adapter id (focus entries).
    public var adapter: String?
    public var detail: [String: String]

    public init(
        at: Date = Date(), module: ModuleID? = nil, category: ActivityCategory, kind: String,
        severity: AlertSeverity? = nil, dedupeKey: String? = nil, outcome: ActivityOutcome,
        adapter: String? = nil, detail: [String: String] = [:]
    ) {
        self.at = at
        self.module = module
        self.category = category
        self.kind = kind
        self.severity = severity
        self.dedupeKey = dedupeKey
        self.outcome = outcome
        self.adapter = adapter
        self.detail = detail
    }

    public static func alert(
        module: ModuleID?, kind: String, severity: AlertSeverity?, dedupeKey: String? = nil,
        outcome: ActivityOutcome, at: Date = Date()
    ) -> ActivityEntry {
        ActivityEntry(
            at: at, module: module, category: .alert, kind: kind, severity: severity, dedupeKey: dedupeKey,
            outcome: outcome)
    }

    public static func focus(
        module: ModuleID?, adapter: String?, outcome: ActivityOutcome, kind: String = "focus", at: Date = Date()
    ) -> ActivityEntry {
        ActivityEntry(at: at, module: module, category: .focus, kind: kind, outcome: outcome, adapter: adapter)
    }

    /// Drops `detail` keys containing token, secret, password or key (case-insensitive); truncates values to 200.
    public func redacted() -> ActivityEntry {
        var copy = self
        copy.detail = detail.reduce(into: [:]) { out, pair in
            let k = pair.key.lowercased()
            guard !["token", "secret", "password", "key"].contains(where: k.contains) else { return }
            out[pair.key] = String(pair.value.prefix(200))
        }
        return copy
    }
}

public protocol ActivityLog: Sendable {
    /// Records an entry; the module id is added by the context.
    func record(_ entry: ActivityEntry)
}
