import Foundation
import ModuleKit

/// Copy diagnostics (Story 17.4): each script file's id, parse status, enabled flag and confirmation state on this
/// Mac. Never its code, documentation, output, setting values or source URL. Its `secret` setting values are
/// handed to the host only for the exact-match scrub (``diagnosticsSecretValues()``).
extension IntegrationsModule: DiagnosticsContributing {
    public func diagnostics() async -> [ModuleDiagnostics] {
        [
            ModuleDiagnostics(
                section: .modules, lines: scripts.map { Self.diagnosticsLine($0, state: localStates[$0.id]) })
        ]
    }

    public func diagnosticsSecretValues() async -> [String] {
        guard let secrets else { return [] }
        var values: [String] = []
        for script in scripts {
            guard let frontMatter = script.frontMatter else { continue }
            for setting in frontMatter.settings where setting.kind == .secret {
                let key = ScriptEnvironment.secretKey(scriptID: frontMatter.id, settingKey: setting.key)
                if let value = try? await secrets.read(key), !value.isEmpty { values.append(value) }
            }
        }
        return values
    }

    /// `script github.prs  status=ok  enabled=true  confirmation=confirmed`.
    nonisolated static func diagnosticsLine(_ script: ScriptModuleDefinition, state: ScriptLocalState?) -> String {
        let id = script.moduleID?.rawValue ?? "<unparsed>"
        let status = script.status == .ok ? "ok" : "errored"
        let confirmation = state?.rawValue ?? "unknown"
        return "script \(id)  status=\(status)  enabled=\(script.enabled)  confirmation=\(confirmation)"
    }
}
