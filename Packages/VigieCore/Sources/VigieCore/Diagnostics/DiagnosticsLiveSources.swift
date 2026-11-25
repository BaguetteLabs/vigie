import AppKit
import Darwin
import Foundation
import ModuleKit
import Security
import Wire

/// The production ``DiagnosticsSources`` (Story 17.4): in-process state only.
extension DiagnosticsCollector {
    /// - Parameters:
    ///   - secretStore: answers `<set>` / `<unset>` and gives the values for the exact-match scrub; nil prints
    ///     `<unknown>` and scrubs by shape only.
    ///   - alertCenter: the Notifier, for open and resolved `setup.problem` alerts; nil lists none.
    public static func live(
        configStore: ConfigStore,
        registry: ModuleRegistry,
        secretStore: KeychainSecretStore?,
        alertCenter: @escaping @MainActor @Sendable () -> AlertCenter?,
        syncOn: @escaping @MainActor @Sendable () -> Bool,
        iCloudAvailable: @escaping @MainActor @Sendable () -> Bool,
        bundle: Bundle = .main
    ) -> DiagnosticsCollector {
        let environment = configStore.environment
        let secretState: @Sendable (String, String) async -> Bool? = { owner, key in
            guard let secretStore else { return nil }
            return try? await secretStore.exists(owner: owner, key: key)
        }
        let secretValue: @Sendable (String, String) async -> String? = { owner, key in
            guard let secretStore else { return nil }
            return try? await secretStore.get(owner: owner, key: key)
        }
        let sources = DiagnosticsSources(
            app: { app(environment: environment, bundle: bundle) },
            system: { system() },
            displays: {
                displays(
                    DisplayInfo.current(), scales: screenScales(), selection: DisplaySelection(configStore: configStore)
                )
            },
            modules: { modules(registry: registry, configStore: configStore) },
            contributions: { await contributions(registry: registry) },
            setupProblems: { setupProblems(alertCenter()) },
            config: {
                await config(
                    configStore: configStore, syncOn: syncOn(), iCloudAvailable: iCloudAvailable(),
                    secretIsSet: secretState)
            },
            logs: OSLogLinesProvider(subsystems: logSubsystems(environment)),
            secretValues: SecretValues {
                await secretValues(configStore: configStore, registry: registry, read: secretValue)
            },
            homeDirectory: environment.homeDirectoryURL)
        return DiagnosticsCollector(sources: sources)
    }

    /// The bundle id (Vigie or Vigie Dev), the release id and the bare `vigie` some loggers use.
    nonisolated static func logSubsystems(_ environment: AppEnvironment) -> [String] {
        Array(Set([environment.logSubsystem, AppEnvironment.releaseBundleID, "vigie"])).sorted()
    }

    // MARK: App

    static func app(environment: AppEnvironment, bundle: Bundle) -> DiagnosticsInputs.App {
        let info = bundle.infoDictionary ?? [:]
        return DiagnosticsInputs.App(
            name: environment.displayName,
            version: info["CFBundleShortVersionString"] as? String ?? "unknown",
            build: info["CFBundleVersion"] as? String ?? "unknown",
            bundleID: bundle.bundleIdentifier ?? environment.bundleID,
            flavor: environment.flavor == .dev ? "dev" : "release",
            signing: signing(),
            installPath: environment.abbreviatingHome(bundle.bundleURL))
    }

    /// The running code's signature: `ad-hoc`, `Developer ID (<team id>)`, `<certificate kind> (<team id>)`,
    /// `unsigned` or `unknown`. Reads this process's own code object only.
    nonisolated static func signing() -> String {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return "unknown" }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode else {
            return "unknown"
        }
        var info: CFDictionary?
        guard
            SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
                == errSecSuccess,
            let dictionary = info as? [String: Any]
        else { return "unknown" }
        let flags = (dictionary[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        if flags & SecCodeSignatureFlags.adhoc.rawValue != 0 { return "ad-hoc" }
        guard let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate],
            let leaf = certificates.first
        else { return dictionary[kSecCodeInfoIdentifier as String] == nil ? "unsigned" : "unknown" }
        let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String ?? "?"
        // The summary is `<kind>: <holder name> (<team>)`; only the kind is kept.
        let summary = SecCertificateCopySubjectSummary(leaf) as String? ?? ""
        let kind = summary.split(separator: ":").first.map(String.init) ?? "signed"
        return "\(kind.hasPrefix("Developer ID") ? "Developer ID" : kind) (\(team))"
    }

    // MARK: System

    static func system() -> DiagnosticsInputs.System {
        let workspace = NSWorkspace.shared
        return DiagnosticsInputs.System(
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            model: sysctlString("hw.model") ?? "unknown",
            chip: sysctlString("machdep.cpu.brand_string") ?? "unknown",
            architecture: architecture(),
            locale: Locale.current.identifier,
            reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast)
    }

    nonisolated static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    nonisolated static func architecture() -> String {
        #if arch(arm64)
            return "arm64"
        #else
            var translated: Int32 = 0
            var size = MemoryLayout<Int32>.size
            let rosetta = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 && translated == 1
            return rosetta ? "x86_64 (Rosetta)" : "x86_64"
        #endif
    }

    // MARK: Displays

    static func screenScales() -> [CGDirectDisplayID: Double] {
        Dictionary(
            NSScreen.screens.map { ($0.displayID, Double($0.backingScaleFactor)) }, uniquingKeysWith: { a, _ in a })
    }

    /// Pure: each display's kind, size and scale, and whether Vigie draws on it.
    nonisolated static func displays(
        _ displays: [DisplayInfo], scales: [CGDirectDisplayID: Double], selection: DisplaySelection
    ) -> [DiagnosticsInputs.Display] {
        let drawn = Set(DisplaySelector.select(displays, selection: selection).map(\.id))
        return displays.map { display in
            DiagnosticsInputs.Display(
                kind: display.kind, isBuiltIn: display.isBuiltIn, isMain: display.isMain,
                width: Int(display.frame.width.rounded()), height: Int(display.frame.height.rounded()),
                scale: scales[display.id] ?? 1, isDrawn: drawn.contains(display.id))
        }
    }

    // MARK: Modules

    static func modules(registry: ModuleRegistry, configStore: ConfigStore) -> [DiagnosticsInputs.Module] {
        let builtIns = registry.descriptors.map { descriptor -> DiagnosticsInputs.Module in
            let manifest = descriptor.manifest
            let status = registry.status(of: manifest.id)
            return DiagnosticsInputs.Module(
                id: manifest.id.rawValue,
                enabled: configStore.isModuleEnabled(manifest.id) ?? manifest.defaultEnabled,
                status: statusText(status), state: registry.module(manifest.id)?.state,
                alertKinds: manifest.alertKinds, isScript: false)
        }
        let scripts = registry.dynamicModuleIDs.map { id in
            DiagnosticsInputs.Module(
                id: id.rawValue, enabled: true, status: statusText(registry.status(of: id)), state: nil,
                alertKinds: [], isScript: true)
        }
        return builtIns + scripts
    }

    nonisolated static func statusText(_ status: ModuleStatus) -> String {
        switch status {
        case .disabled: "disabled"
        case .running: "running"
        case .stopped: "stopped"
        case .errored(let message): "errored: \(message)"
        case .needsPermission(let permission): "needs permission: \(permission)"
        }
    }

    static func contributions(registry: ModuleRegistry) async -> [ModuleDiagnostics] {
        var result: [ModuleDiagnostics] = []
        for module in registry.runningModules {
            guard let contributor = module as? any DiagnosticsContributing else { continue }
            result += await contributor.diagnostics()
        }
        return result
    }

    // MARK: Setup problems

    static func setupProblems(_ alertCenter: AlertCenter?) -> (
        current: [DiagnosticsInputs.SetupProblem], resolved: [DiagnosticsInputs.ResolvedProblem]
    ) {
        guard let alertCenter else { return ([], []) }
        let kind = SetupProblemReporter.alertKind
        let current = alertCenter.active.filter { $0.kind == kind }.map { alert in
            DiagnosticsInputs.SetupProblem(
                since: alert.postedAt, module: alert.module.rawValue, category: alert.event.category,
                title: alert.event.title)
        }
        let resolved = alertCenter.history.filter { $0.kind == kind && $0.outcome == .resolved }.map {
            DiagnosticsInputs.ResolvedProblem(at: $0.at, module: $0.module.rawValue)
        }
        return (current, Array(resolved.suffix(DiagnosticsReport.maxResolvedProblems)))
    }

    // MARK: Config

    /// The keys present in `config.toml` / `local.toml` with their values, except: `secret` settings print
    /// `<set>` / `<unset>` (never the value, which is not in a file anyway), paths print `<path>`, lists
    /// print their length. Every declared `secret` setting is listed, present or not.
    static func config(
        configStore: ConfigStore, syncOn: Bool, iCloudAvailable: Bool,
        secretIsSet: @Sendable (String, String) async -> Bool?
    ) async -> DiagnosticsInputs.Config {
        var lines: [DiagnosticsInputs.ConfigLine] = []
        let entries = configStore.schema.entries.values.sorted { $0.path.description < $1.path.description }
        for entry in entries {
            let key = entry.path.description
            if case .secret = entry.descriptor.kind {
                let state: String
                if let owner = secretOwner(entry) {
                    switch await secretIsSet(owner, entry.descriptor.key) {
                    case true?: state = "<set>"
                    case false?: state = "<unset>"
                    case nil: state = "<unknown>"
                    }
                } else {
                    state = "<unknown>"
                }
                lines.append(.init(key: key, value: state, isLocal: true))
                continue
            }
            let isLocal = configStore.rawValue(at: entry.path, in: .local) != nil
            guard isLocal || configStore.rawValue(at: entry.path, in: .synced) != nil else { continue }
            lines.append(
                .init(
                    key: key, value: valueText(entry.descriptor.kind, configStore.resolvedValue(entry.path)),
                    isLocal: isLocal))
        }
        return DiagnosticsInputs.Config(
            folder: configStore.environment.abbreviatingHome(configStore.configFolderURL), syncOn: syncOn,
            iCloudAvailable: iCloudAvailable, problems: configStore.problems.count, lines: lines)
    }

    /// The `SecretStore` owner of a `secret` setting: the module id, or `adapter.<id>` for an adapter's setting
    /// (`modules."<module>".adapter.<id>.<key>`).
    nonisolated static func secretOwner(_ entry: ConfigSchemaEntry) -> String? {
        let segments = entry.path.segments
        if segments.count > 4, segments[0] == "modules", segments[2] == CoreSettings.adapterTableSegment {
            return KeychainSecretStore.adapterOwner(segments[3])
        }
        return entry.moduleID?.rawValue
    }

    nonisolated static func valueText(_ kind: SettingKind, _ value: ConfigResolvedValue?) -> String {
        switch kind {
        case .path: return "<path>"
        case .secret: return "<set>"
        default: break
        }
        switch value {
        case .bool(let value)?: return String(value)
        case .int(let value)?: return String(value)
        case .double(let value)?: return String(value)
        case .string(let value)?: return "\"\(value)\""
        case .duration(let value)?: return "\(value.components.seconds)s"
        case .strings(let values)?: return "<list of \(values.count)>"
        case .none?, nil: return "<none>"
        }
    }

    // MARK: Secret values (exact-match scrub)

    /// The Keychain values of every declared `secret` setting, plus what running modules hand over
    /// (``DiagnosticsContributing/diagnosticsSecretValues()``: script `secret` settings). Used only by the
    /// redactor.
    static func secretValues(
        configStore: ConfigStore, registry: ModuleRegistry, read: @Sendable (String, String) async -> String?
    ) async -> [String] {
        var values: [String] = []
        for entry in configStore.schema.entries.values {
            guard case .secret = entry.descriptor.kind, let owner = secretOwner(entry) else { continue }
            if let value = await read(owner, entry.descriptor.key) { values.append(value) }
        }
        for module in registry.runningModules {
            guard let contributor = module as? any DiagnosticsContributing else { continue }
            values += await contributor.diagnosticsSecretValues()
        }
        return values
    }
}
