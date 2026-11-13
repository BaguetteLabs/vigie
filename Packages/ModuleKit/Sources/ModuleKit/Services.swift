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

    /// Whether a secret is stored under `key`, without reading its value (Story 7.3). Default: `read != nil`.
    func contains(_ key: String) async throws -> Bool

    /// Reads a credential another app stored on this Mac (AD-9 as amended 2026-11-06 and 2026-11-12) into process
    /// memory: the caller may hold it for the session, never writes it to disk, renews or deletes it. Throws
    /// ``SecretStoreError/consentRequired`` while the user has not allowed it on this Mac (``hasConsent(for:)``),
    /// `.notFound` when the item does not exist. macOS may show its own Keychain prompt on the first read.
    /// Default: throws `.unavailable`.
    func readExternal(_ descriptor: ExternalCredentialDescriptor) async throws -> String
    /// Whether the user allowed ``readExternal(_:)`` for `descriptor` on this Mac. Default: false.
    func hasConsent(for descriptor: ExternalCredentialDescriptor) async -> Bool
    /// Records the user's consent (per Mac, in `local.toml`, never synced). Call only from a user action.
    /// Default: throws `.unavailable`.
    func grantConsent(for descriptor: ExternalCredentialDescriptor) async throws
    /// Removes the consent at once; later reads throw `.consentRequired`. Default: throws `.unavailable`.
    func revokeConsent(for descriptor: ExternalCredentialDescriptor) async throws
}

extension SecretStore {
    public func contains(_ key: String) async throws -> Bool { try await read(key) != nil }
    public func readExternal(_ descriptor: ExternalCredentialDescriptor) async throws -> String {
        throw SecretStoreError.unavailable(status: SecretStoreError.unimplementedStatus)
    }
    public func hasConsent(for descriptor: ExternalCredentialDescriptor) async -> Bool { false }
    public func grantConsent(for descriptor: ExternalCredentialDescriptor) async throws {
        throw SecretStoreError.unavailable(status: SecretStoreError.unimplementedStatus)
    }
    public func revokeConsent(for descriptor: ExternalCredentialDescriptor) async throws {
        throw SecretStoreError.unavailable(status: SecretStoreError.unimplementedStatus)
    }
}

/// A credential owned by another app that an adapter asks to read (AD-9 amended, Story 7.3), e.g. Claude Code's
/// stored login. Declared by the adapter; its names are shown in the consent text.
public struct ExternalCredentialDescriptor: Hashable, Sendable {
    /// Stable id, `<adapter id>.<name>` (e.g. `claude.claude_code_login`); the consent is recorded under it.
    public let id: String
    /// The owning app as the user knows it, e.g. "Claude Code".
    public let displayName: String
    /// Keychain service (`kSecAttrService`) of the login-keychain generic password.
    public let service: String
    /// Keychain account (`kSecAttrAccount`); nil matches the first item of `service`.
    public let accountHint: String?
    /// What the credential is used for, shown under the consent button.
    public let explanation: LocalizedStringResource

    public init(
        id: String, displayName: String, service: String, accountHint: String? = nil,
        explanation: LocalizedStringResource
    ) {
        self.id = id
        self.displayName = displayName
        self.service = service
        self.accountHint = accountHint
        self.explanation = explanation
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.service == rhs.service && lhs.accountHint == rhs.accountHint
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(service)
        hasher.combine(accountHint)
    }
}

/// A user's consent to ``SecretStore/readExternal(_:)`` for one descriptor, on this Mac. Read and written only
/// by VigieCore, in `local.toml` under `[consents."<descriptor id>"] granted_at` (never synced).
public struct ExternalConsent: Hashable, Sendable {
    public let descriptorID: String
    public let grantedAt: Date

    public init(descriptorID: String, grantedAt: Date) {
        self.descriptorID = descriptorID
        self.grantedAt = grantedAt
    }
}

/// Why a `SecretStore` call failed (Story 7.2). `status` is the Keychain `OSStatus`. Never carries the value.
public enum SecretStoreError: Error, Equatable, Sendable {
    /// Secrets cannot be used in this build (not signed with the keychain entitlement, `errSecMissingEntitlement`).
    case unavailable(status: Int32)
    /// No secret is stored under this key.
    case notFound
    /// Any other Keychain failure.
    case failed(status: Int32)
    /// ``SecretStore/readExternal(_:)`` without the user's consent on this Mac (Story 7.3).
    case consentRequired

    /// `errSecUnimplemented`: the store does not offer the call.
    public static let unimplementedStatus: Int32 = -4
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
///
/// Privacy mode (AD-24, Story 21.2): `title` and `body` are always ``Sensitive``. While Privacy mode is active
/// the peek shows them as dots and the macOS notification carries only the kind label; the kicker (from the
/// kind) and `category` are core copy and stay. There is no way to post a non-sensitive title or body.
public struct NotifierEvent: Hashable, Sendable {
    /// One of the kinds declared in the manifest's `alertKinds`.
    public let kind: String
    public let severity: AlertSeverity
    @Sensitive public var title: String
    @Sensitive public var body: String?
    public let action: AlertAction?
    public let dedupeKey: String?
    /// Numeric facts the Notifier's rule conditions compare against (A54), e.g. `working_duration` in seconds.
    public let metrics: [String: Double]
    /// Short uppercase category the peek shows in the kicker (`SETUP · <CATEGORY>`); used by `setup.problem`.
    public let category: String?
    /// Performed after the Notifier cancels the reminder when the user takes the peek's second button (`⌥⌘⌫`):
    /// the break peek's Skip (`time.break_reminder`, Story 20.4), or the calendar reminder's Dismiss, which tells
    /// the module to resolve the alert (`calendar.reminder`, Story 13.4). Without it Dismiss routes nothing.
    public let secondaryAction: AlertAction?
    /// The break peek's third action, Snooze (`⌥⌘Z`), performed after the Notifier cancels the reminder (Story
    /// 20.4). Only `time.break_reminder` peeks draw it (DESIGN: the one three-action peek).
    public let tertiaryAction: AlertAction?
    /// Replaces the kind's kicker (the Pomodoro source of a break, `POMODORO · LONG BREAK`, Story 20.5).
    /// Not sensitive: like the kind label it is core-style state copy.
    public let kicker: String?
    /// Delivered without peek and sound whatever the rule says (`breaks.style = "quiet"`, Story 20.4). The alert
    /// is still active (reminders, `after_focus` and the module's state see it) but never peeks or plays.
    public let quiet: Bool
    /// Replaces the kind's primary action label, already localized by the module: the calendar reminder's
    /// `Join call` when the event has a video link (Story 13.4). Not sensitive: it is action copy.
    public let primaryLabel: String?

    public init(
        kind: String,
        severity: AlertSeverity,
        title: String,
        body: String? = nil,
        action: AlertAction? = nil,
        dedupeKey: String? = nil,
        metrics: [String: Double] = [:],
        category: String? = nil,
        secondaryAction: AlertAction? = nil,
        tertiaryAction: AlertAction? = nil,
        kicker: String? = nil,
        quiet: Bool = false,
        primaryLabel: String? = nil
    ) {
        self.primaryLabel = primaryLabel
        self.secondaryAction = secondaryAction
        self.tertiaryAction = tertiaryAction
        self.kicker = kicker
        self.quiet = quiet
        self.category = category
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
    /// Opens the Settings window on this module's pane and brings it forward; acts only with a `UserIntent`
    /// (AD-13), e.g. the one of a `vigie://install` link (Story 12.9). Default: does nothing.
    @MainActor func openOwnSettings(focus: UserIntent?)
    /// Shows this module's floating panel and makes it key (Story 15.3, AD-13: the only window a module may
    /// request). Refused (returns false) without a live `UserIntent`. Replaces any floating panel already shown.
    /// Default: refuses.
    @MainActor @discardableResult func presentFloatingPanel(_ request: FloatingPanelRequest, focus: UserIntent?)
        -> Bool
    /// Closes this module's floating panel, if it is shown (its `onClose` runs). Default: does nothing.
    @MainActor func dismissFloatingPanel()
}

extension HostControl {
    @MainActor public func openOwnSettings(focus: UserIntent?) {}

    @MainActor @discardableResult public func presentFloatingPanel(
        _ request: FloatingPanelRequest, focus: UserIntent?
    ) -> Bool { false }

    @MainActor public func dismissFloatingPanel() {}
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
    /// The login-shell `PATH` entries `resolve` searches, in order (captured once per launch). The script runner
    /// passes them as the child's `PATH` (AD-18, Story 12.4). Default: none (the caller falls back).
    var searchPath: [String] { get async }
}

extension ExecutableResolver {
    public var searchPath: [String] {
        get async { [] }
    }
}

// MARK: - Privacy (implemented in Story 21.2)

/// `context.privacy` (AD-24): the one Privacy mode state, read-only. Modules never detect sharing themselves and
/// never redact on their own: they mark fields ``Sensitive`` and the host and VigieUI do the rest. Read it only
/// for behavior that is not rendering (none in v0.2).
public protocol PrivacyService: Sendable {
    /// True while Privacy mode is on (detected sharing or the user's force-on).
    var isActive: Bool { get }
    /// Yields the new state on each change. Each access returns a new stream; stop iterating to end it.
    var changes: AsyncStream<Bool> { get }
}

// MARK: - Away (implemented in Story 20.3)

/// Whether the user is at the Mac (SPEC §7.7, glossary "Away"): Present while input happened within
/// `[modules.time.breaks] away_after` (default 90 s) and the screen can be seen; Away otherwise, at once on
/// screen lock, screensaver, display sleep, a session switch or system sleep.
public enum Presence: Hashable, Sendable {
    case present
    /// `since`: the last input for an input-idle Away, or the moment the screen became unavailable.
    case away(since: Date)

    public var isAway: Bool {
        if case .away = self { return true }
        return false
    }
}

/// `context.away` (AD-25, Story 20.3): the one Present / Away signal. Modules never read input idle time or
/// lock, screensaver or display-sleep notifications themselves (`Scripts/check-module-away.sh`).
///
/// The host watches the user only while at least one `changes` stream is open (PRD FR-4): nothing is polled or
/// observed otherwise, and `presence` then reads `.present`. It never uses the camera and asks no permission.
public protocol AwayService: Sendable {
    var presence: Presence { get }
    /// Yields each transition. Each access returns a new stream (one subscriber); stop iterating to end it.
    var changes: AsyncStream<Presence> { get }
}

// MARK: - Activity log (implemented in Story 3.8)

public enum ActivityCategory: String, Codable, Hashable, Sendable {
    case alert, peek, reminder, focus, module
    /// Present / Away transitions (A80, Story 20.3): kinds `away.present` and `away.away`.
    case presence
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

// MARK: - Alert actions (Story 3.3)

/// Adopted by a module whose alerts carry `.module(id:actionID:payload:)` actions (AD-13). The Notifier delivers
/// the action back to the posting module when the user takes it: the peek's primary action (`⌥⌘↵` or a click)
/// or a click on the macOS notification, and the break peek's Skip and Snooze (`secondaryAction`,
/// `tertiaryAction`). `intent` is present when the action came from a user gesture, so the
/// module may pass it to focus-taking host calls; it is nil otherwise. Modules without alert actions need not
/// adopt it.
@MainActor
public protocol AlertActionHandler: AnyObject {
    func handleAlertAction(_ actionID: String, payload: Data, intent: UserIntent?)
}

// MARK: - Integration installer (implemented in Story 4.7)

/// Whether an integration edit connects or disconnects an agent.
public enum IntegrationAction: String, Hashable, Sendable, Codable {
    case install
    case remove
}

/// One file of an ``IntegrationPreview``: the adapter's diff and a unified diff of it for display.
public struct IntegrationFileChange: Hashable, Sendable {
    public let diff: ConfigDiff
    /// A unified diff (`---` / `+++` headers, `@@` hunks, three lines of context) of `diff.oldText` → `diff.newText`.
    public let unifiedDiff: String
    /// True when the target's current bytes no longer hash to `diff.baseHash` (or it appeared or vanished).
    public let stale: Bool

    public init(diff: ConfigDiff, unifiedDiff: String, stale: Bool) {
        self.diff = diff
        self.unifiedDiff = unifiedDiff
        self.stale = stale
    }
}

/// What the user confirms before ``IntegrationInstaller/apply(_:)`` (AD-22).
public struct IntegrationPreview: Hashable, Sendable {
    /// Adapter id (`claude`): the `local.toml` record is kept under `[integrations.<id>]`.
    public let adapterID: String
    public let action: IntegrationAction
    public let files: [IntegrationFileChange]

    public init(adapterID: String, action: IntegrationAction, files: [IntegrationFileChange]) {
        self.adapterID = adapterID
        self.action = action
        self.files = files
    }

    public var diffs: [ConfigDiff] { files.map(\.diff) }
    /// A target changed since the adapter planned: re-plan through the adapter and preview again.
    public var stale: Bool { files.contains(where: \.stale) }
}

/// What ``IntegrationInstaller/apply(_:)`` wrote.
public struct IntegrationResult: Hashable, Sendable {
    public let appliedPaths: [URL]
    /// `<target>.vigie-backup-<yyyyMMdd-HHmmss>`, one per target that existed before.
    public let backupPaths: [URL]

    public init(appliedPaths: [URL], backupPaths: [URL]) {
        self.appliedPaths = appliedPaths
        self.backupPaths = backupPaths
    }
}

public enum IntegrationError: Error, Equatable, Sendable {
    /// A target changed after the preview (its hash no longer matches the diff's base). Nothing was written;
    /// re-plan through the adapter and show the new diff.
    case targetChanged(paths: [URL])
    /// The preview is stale; preview a fresh plan instead.
    case stalePreview
    /// Reading a target failed (other than "does not exist").
    case readFailed(path: URL, reason: String)
    /// Writing the backup or the target failed; the target is untouched (atomic rename).
    case writeFailed(path: URL, reason: String)
}

/// The only writer of agent config files (AD-22). Adapters plan ``ConfigDiff``s; the installer shows them,
/// re-reads each target and checks its hash against the diff's base, writes a timestamped backup next to the
/// target, applies the change atomically (temp file + rename) and records the result in `local.toml`.
public protocol IntegrationInstaller: Sendable {
    /// Absolute path of `~/.local/bin/<cli name>`: the `cliPath` of `IntegrationInputs` (hooks always call it).
    var cliPath: String { get }
    /// Re-reads each target and builds the unified diffs. A preview whose `stale` is true must be re-planned.
    func preview(_ diffs: [ConfigDiff], adapterID: String, action: IntegrationAction) async throws
        -> IntegrationPreview
    /// Re-checks every hash (throws ``IntegrationError/targetChanged(paths:)`` and writes nothing on a
    /// mismatch), then backs up and writes each target and records the result.
    func apply(_ preview: IntegrationPreview) async throws -> IntegrationResult
}
