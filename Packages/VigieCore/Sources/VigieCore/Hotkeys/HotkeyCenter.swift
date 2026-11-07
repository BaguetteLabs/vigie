import Foundation
import ModuleKit
import Observation

/// Who registered a hotkey; the prefix of its full name (Conventions: Hotkeys).
public enum HotkeyOwner: Hashable, Sendable {
    /// VigieCore's own shortcuts (`core.expand`).
    case core
    case module(ModuleID)

    public var prefix: String {
        switch self {
        case .core: "core"
        case .module(let id): id.rawValue
        }
    }
}

/// A hotkey that could not be bound. Surfaced as a setup-problem alert in Story 3.4.
public struct HotkeyProblem: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Its key combination is already used by an earlier registration, which keeps it.
        case conflict
        /// The configured string does not parse (or is Option-only); the default stays in effect.
        case invalid
    }

    public let kind: Kind
    /// Full name of the hotkey that is not bound (conflict) or whose config is invalid.
    public let name: String
    /// For `.conflict`: the full name that holds the combination.
    public let conflictingWith: String?
    /// For `.invalid`: the rejected config value.
    public let value: String?

    public init(kind: Kind, name: String, conflictingWith: String? = nil, value: String? = nil) {
        self.kind = kind
        self.name = name
        self.conflictingWith = conflictingWith
        self.value = value
    }
}

/// Owns every global shortcut Vigie registers (AD-13, AD-19, FR111).
///
/// - Names are namespaced `<owner>.<name>` (`core.expand`, `agents.sessions.focus`); a full name can be
///   registered once at a time.
/// - The effective shortcut is the config override (`applyConfig`) if any, else the registration's default.
/// - **Conflicts:** when two registrations resolve to the same combination, the earlier registration keeps it;
///   the later is left unbound and a `.conflict` problem is recorded. Unregistering the earlier one does
///   **not** bind the later one at once; that happens on the next `applyConfig` (config reload), which
///   re-runs conflict detection over all registrations in registration order.
/// - Every key-up mints a fresh `UserIntent` (source `.hotkey(fullName)`) and passes it to the handler.
@MainActor @Observable
public final class HotkeyCenter {
    /// Current problems: config values that did not parse, then conflicts. Observed by the alert in Story 3.4.
    public var problems: [HotkeyProblem] { invalidProblems + conflictProblems }

    private var invalidProblems: [HotkeyProblem] = []
    private var conflictProblems: [HotkeyProblem] = []
    /// Full name -> shortcut actually bound now.
    public private(set) var bound: [String: HotkeySpec] = [:]

    private struct Entry {
        let id: UUID
        let fullName: String
        let defaultSpec: HotkeySpec?
        let handler: @MainActor (UserIntent) -> Void
    }

    @ObservationIgnored private let binding: any HotkeyBinding
    /// In registration order.
    @ObservationIgnored private var entries: [Entry] = []
    /// Full name -> configured shortcut; a nil value means "configured off".
    @ObservationIgnored private var overrides: [String: HotkeySpec?] = [:]

    public init(binding: any HotkeyBinding) {
        self.binding = binding
    }

    /// Creates a center bound to the real KeyboardShortcuts backend.
    public convenience init() {
        self.init(binding: KeyboardShortcutsBinding())
    }

    /// Full names registered now, in registration order.
    public var registeredNames: [String] { entries.map(\.fullName) }

    /// The shortcut `fullName` would use (override, else default), bound or not.
    public func effectiveShortcut(for fullName: String) -> HotkeySpec? {
        guard let entry = entries.first(where: { $0.fullName == fullName }) else { return nil }
        return resolved(entry)
    }

    /// Registers `<owner>.<name>`. Throws `HotkeyError.duplicateName` when that full name is already
    /// registered and `.invalidName` for an empty name or one with whitespace. A combination conflict does not
    /// throw: the registration is kept unbound and a `.conflict` problem is recorded.
    public func register(
        owner: HotkeyOwner,
        name: String,
        default defaultSpec: HotkeySpec?,
        handler: @escaping @MainActor (UserIntent) -> Void
    ) throws -> RegistrationToken {
        guard !name.isEmpty, name.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw HotkeyError.invalidName(name)
        }
        let fullName = "\(owner.prefix).\(name)"
        guard !entries.contains(where: { $0.fullName == fullName }) else {
            throw HotkeyError.duplicateName(fullName)
        }
        let entry = Entry(id: UUID(), fullName: fullName, defaultSpec: defaultSpec, handler: handler)
        entries.append(entry)
        bindIfFree(entry)

        let id = entry.id
        return RegistrationToken(id: id) { [weak self] in
            Self.onMain { self?.unregister(id: id) }
        }
    }

    /// Applies the configured shortcuts, keyed by full name (`core.expand` = `[general] expand_hotkey`, module
    /// `hotkey` keys mapped by the caller). Replaces the previous overrides. An empty string or `none` turns the
    /// hotkey off; an invalid value records an `.invalid` problem and leaves the default in effect. Overrides for
    /// names not registered yet apply when they register. Re-runs conflict detection over all registrations.
    public func applyConfig(_ values: [String: String]) {
        var newOverrides: [String: HotkeySpec?] = [:]
        var invalid: [HotkeyProblem] = []
        for (fullName, value) in values.sorted(by: { $0.key < $1.key }) {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.lowercased() == "none" {
                newOverrides[fullName] = .some(nil)
                continue
            }
            do {
                newOverrides[fullName] = try HotkeySpec(parsing: trimmed)
            } catch {
                invalid.append(HotkeyProblem(kind: .invalid, name: fullName, value: value))
            }
        }
        overrides = newOverrides
        invalidProblems = invalid
        rebindAll()
    }

    // MARK: - Internals

    private func resolved(_ entry: Entry) -> HotkeySpec? {
        if let override = overrides[entry.fullName] { return override }
        return entry.defaultSpec
    }

    /// Binds `entry` unless an earlier registration already holds its combination.
    private func bindIfFree(_ entry: Entry) {
        guard let spec = resolved(entry) else { return }
        if let holder = bound.first(where: { $0.value == spec && $0.key != entry.fullName })?.key {
            conflictProblems.append(HotkeyProblem(kind: .conflict, name: entry.fullName, conflictingWith: holder))
            return
        }
        bind(entry, spec)
    }

    private func bind(_ entry: Entry, _ spec: HotkeySpec) {
        let id = entry.id
        let fullName = entry.fullName
        binding.bind(name: fullName, shortcut: spec) { [weak self] in
            self?.fire(id: id, fullName: fullName)
        }
        bound[fullName] = spec
    }

    /// Recomputes every binding in registration order (earlier wins), touching only those that change.
    private func rebindAll() {
        var desired: [String: HotkeySpec] = [:]
        var holders: [HotkeySpec: String] = [:]
        var conflicts: [HotkeyProblem] = []
        for entry in entries {
            guard let spec = resolved(entry) else { continue }
            if let holder = holders[spec] {
                conflicts.append(HotkeyProblem(kind: .conflict, name: entry.fullName, conflictingWith: holder))
            } else {
                holders[spec] = entry.fullName
                desired[entry.fullName] = spec
            }
        }
        for (name, spec) in bound where desired[name] != spec {
            binding.unbind(name: name)
            bound[name] = nil
        }
        for entry in entries {
            if let spec = desired[entry.fullName], bound[entry.fullName] != spec { bind(entry, spec) }
        }
        conflictProblems = conflicts
    }

    private func unregister(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let fullName = entries.remove(at: index).fullName
        if bound.removeValue(forKey: fullName) != nil { binding.unbind(name: fullName) }
        conflictProblems.removeAll { $0.name == fullName }
    }

    private func fire(id: UUID, fullName: String) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        entry.handler(UserIntentMinter.mint(source: .hotkey(fullName)))
    }

    /// Runs `body` on the main actor: inline when already there (the usual case: modules stop on the main
    /// actor), else on a main-actor task.
    nonisolated static func onMain(_ body: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { body() }
        } else {
            Task { @MainActor in body() }
        }
    }
}
