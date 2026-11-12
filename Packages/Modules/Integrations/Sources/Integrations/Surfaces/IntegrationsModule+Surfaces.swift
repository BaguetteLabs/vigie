import AppKit
import Foundation
import ModuleKit

/// The dynamic modules the integrations module registered (Story 12.5), and its widget-action seams.
struct ScriptSurfaceRegistry {
    struct Entry {
        let module: ScriptModule
        let token: RegistrationToken
    }

    /// Registered script modules by file name.
    var entries: [String: Entry] = [:]
    /// Opens an `open` action's URL (tests record it).
    var openURL: @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// `REVEAL` on the script page: shows the file in Finder (Story 12.11; tests record it).
    var revealInFinder: @MainActor (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    /// `OPEN SOURCE` on the script page: opens the file with the default app for its type (tests record it).
    var openFile: @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }
}

/// Story 12.5: one dynamic module per script (AD-18, SPEC §7.4).
///
/// After every scan and every confirmation change (both end in ``updateRunner()``), every script that parsed
/// and is not declined on this Mac is registered through `context.host.registerDynamicModule`; a removed,
/// errored or declined file is unregistered (its token cancelled), and a front-matter change re-registers it
/// (its manifest and surfaces come from the front matter). Registration does not depend on `enabled`.
extension IntegrationsModule {
    /// The registered script modules, by file name (a test seam and Settings' lookup).
    public var scriptModules: [String: ScriptModule] { surfaces.entries.mapValues(\.module) }

    /// Whether `definition` has a module of its own: parsed, with front matter, not declined on this Mac.
    func wantsModule(_ definition: ScriptModuleDefinition) -> Bool {
        definition.status == .ok && definition.frontMatter != nil && localState(for: definition) != .declined
    }

    func reconcileScriptModules() {
        guard let context else { return }
        var wanted: [String: ScriptModuleDefinition] = [:]
        for script in scripts where wantsModule(script) { wanted[script.id] = script }

        for (id, entry) in surfaces.entries where wanted[id]?.frontMatter != entry.module.frontMatter {
            entry.token.cancel()
            surfaces.entries[id] = nil
        }
        for script in scripts {
            guard let definition = wanted[script.id], let frontMatter = definition.frontMatter else { continue }
            if let entry = surfaces.entries[script.id] {
                entry.module.update(definition)
                continue
            }
            let module = ScriptModule(definition: definition, frontMatter: frontMatter, source: scriptModuleSource())
            do {
                let token = try context.host.registerDynamicModule(module)
                surfaces.entries[script.id] = ScriptSurfaceRegistry.Entry(module: module, token: token)
            } catch {
                context.log.error(
                    "script \(script.fileName, privacy: .private): module not registered: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    /// Cancels every registration (the module stops).
    func unregisterScriptModules() {
        for entry in surfaces.entries.values { entry.token.cancel() }
        surfaces.entries = [:]
    }

    private func scriptModuleSource() -> ScriptModuleSource {
        ScriptModuleSource(
            localState: { [weak self] definition in self?.localState(for: definition) ?? .awaitingConfirmation },
            runState: { [weak self] id in self?.runner?.states[id] },
            perform: { [weak self] action, id in self?.perform(action, scriptID: id) },
            review: { [weak self] definition in self?.openConfirmation(for: definition) },
            reveal: { [weak self] definition in self?.surfaces.revealInFinder(definition.url) },
            openSource: { [weak self] definition in self?.surfaces.openFile(definition.url) },
            updateAvailable: { [weak self] definition in self?.updateAvailable(for: definition) ?? false },
            reviewUpdate: { [weak self] definition in
                Task { await self?.openUpdate(for: definition) }
            })
    }

    /// A widget click (Story 12.5): `open` opens the URL, `run` runs argv through the runner (same rules as the
    /// script's runs), `copy` copies through `context.clipboard`.
    public func perform(_ action: ScriptAction, scriptID: String) {
        switch action {
        case .open:
            guard let url = action.url else { return }
            surfaces.openURL(url)
        case .run(let argv):
            runner?.run(argv: argv, for: scriptID)
        case .copy(let text):
            context?.clipboard.copy(text, clearAfter: nil)
        }
    }
}
