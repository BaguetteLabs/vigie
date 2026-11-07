import Foundation
import ModuleKit
import Observation
import os

/// Turns config and hotkey problems into `setup.problem` alerts (Story 3.4, FR16, FR99, AD-8, AD-13).
///
/// One alert per distinct problem: config problems dedupe on file path + key path (file-level problems on the
/// path alone), hotkey conflicts on the sorted pair of hotkey names. The alert is resolved when the problem
/// leaves the latest set. Never touches module state.
@MainActor
public final class SetupProblemReporter {
    public nonisolated static let alertKind = "setup.problem"

    /// Manifest of the core-owned notifier: the App passes it to `AlertCenter.makeNotifier(for:)`.
    public nonisolated static let manifest = ModuleManifest(
        id: "core",
        name: LocalizedStringResource("vigiecore.setup.category.config", bundle: .atURL(Bundle.module.bundleURL)),
        icon: "gearshape",
        alertKinds: [alertKind]
    )

    private let configStore: ConfigStore
    private let hotkeys: HotkeyCenter
    private let notifier: any Notifier
    private let log: Logger
    private var handles: [String: AlertHandle] = [:]
    private var observing = false

    public init(
        configStore: ConfigStore, hotkeys: HotkeyCenter, notifier: any Notifier,
        log: Logger = Logger(subsystem: "fr.baguettelabs.vigie", category: "setup-problems")
    ) {
        self.configStore = configStore
        self.hotkeys = hotkeys
        self.notifier = notifier
        self.log = log
    }

    /// Reconciles now, then re-reconciles whenever the config or hotkey problems change.
    public func start() {
        guard !observing else { return }
        observing = true
        refresh()
        track()
    }

    /// Stops observing. Active alerts stay until their problems clear.
    public func stop() { observing = false }

    /// Posts alerts for new problems and resolves those that went away. Idempotent.
    public func refresh() {
        var current: [String: NotifierEvent] = [:]
        for problem in configStore.problems { current[Self.dedupeKey(problem)] = Self.event(for: problem) }
        for problem in hotkeys.problems {
            guard let event = Self.event(for: problem) else { continue }
            current[event.dedupeKey ?? ""] = event
        }
        for (key, handle) in handles where current[key] == nil {
            handle.resolve()
            handles[key] = nil
        }
        for (key, event) in current.sorted(by: { $0.key < $1.key }) where handles[key] == nil {
            handles[key] = notifier.post(event)
            log.info("Setup problem alert posted")
        }
    }

    private func track() {
        guard observing else { return }
        withObservationTracking {
            _ = configStore.problems
            _ = hotkeys.problems
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.observing else { return }
                self.refresh()
                self.track()
            }
        }
    }

    // MARK: Mapping

    static func dedupeKey(_ problem: ConfigProblem) -> String {
        if case .invalidFile = problem.kind { return problem.path.path }
        return "\(problem.path.path):\(problem.key ?? "")"
    }

    /// `modules."<id>".x` → `<id>`, `closed.x` → `closed`, else `general`.
    static func pane(forKey key: String?) -> String {
        guard let key else { return "general" }
        if key.hasPrefix("modules.\"") {
            let rest = key.dropFirst("modules.\"".count)
            if let end = rest.firstIndex(of: "\""), end != rest.startIndex { return String(rest[..<end]) }
        } else if key.hasPrefix("modules.") {
            let parts = key.dropFirst("modules.".count).split(separator: ".")
            if parts.count > 1 { return parts.dropLast().joined(separator: ".") }
        }
        if key == "closed" || key.hasPrefix("closed.") { return "closed" }
        return "general"
    }

    static func event(for problem: ConfigProblem) -> NotifierEvent {
        let file = problem.path.lastPathComponent
        let subject = problem.key ?? file
        let title: String
        let body: String
        switch problem.kind {
        case .invalidFile:
            title = format("vigiecore.setup.title.invalidFile", file)
            body = format("vigiecore.setup.body.invalidFile", file)
        case .invalidValue:
            title = format("vigiecore.setup.title.invalidValue", subject)
            body = format("vigiecore.setup.body.invalidValue")
        case .wrongFile:
            title = format("vigiecore.setup.title.wrongFile", subject)
            body = format("vigiecore.setup.body.wrongFile")
        case .unknownKey:
            title = format("vigiecore.setup.title.unknownKey", subject)
            body = format("vigiecore.setup.body.unknownKey")
        }
        let pane: String
        if case .invalidFile = problem.kind { pane = "general" } else { pane = Self.pane(forKey: problem.key) }
        return NotifierEvent(
            kind: alertKind, severity: .warn, title: title, body: body, action: .openSettings(pane: pane),
            dedupeKey: dedupeKey(problem), category: format("vigiecore.setup.category.config"))
    }

    static func event(for problem: HotkeyProblem) -> NotifierEvent? {
        let category = format("vigiecore.setup.category.hotkey")
        switch problem.kind {
        case .conflict:
            guard let holder = problem.conflictingWith else { return nil }
            let key = "hotkey:" + [problem.name, holder].sorted().joined(separator: "|")
            return NotifierEvent(
                kind: alertKind, severity: .warn,
                title: format("vigiecore.setup.title.hotkeyConflict", holder, problem.name),
                body: format("vigiecore.setup.body.hotkeyConflict", holder, problem.name),
                action: .openSettings(pane: "general"), dedupeKey: key, category: category)
        case .invalid:
            return NotifierEvent(
                kind: alertKind, severity: .warn,
                title: format("vigiecore.setup.title.hotkeyInvalid", problem.name),
                body: format("vigiecore.setup.body.hotkeyInvalid"),
                action: .openSettings(pane: "general"), dedupeKey: "hotkey-invalid:" + problem.name,
                category: category)
        }
    }

    private static func format(_ key: String.LocalizationValue, _ args: String...) -> String {
        String(format: String(localized: key, bundle: .module), arguments: args)
    }
}
