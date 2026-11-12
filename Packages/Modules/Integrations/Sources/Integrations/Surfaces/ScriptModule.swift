import Foundation
import ModuleKit
import Observation
import SwiftUI
import VigieUI

/// What a ``ScriptModule`` reads from and asks of the integrations module that registered it.
struct ScriptModuleSource {
    /// The script's state on this Mac (``IntegrationsModule/localState(for:)``).
    var localState: @MainActor (ScriptModuleDefinition) -> ScriptLocalState
    /// The runner's state of the script, by file name; nil while it does not run.
    var runState: @MainActor (String) -> ScriptRunState?
    /// Performs an output's action for the script (by file name).
    var perform: @MainActor (ScriptAction, String) -> Void
    /// `NOT CONFIRMED` was clicked: open the Script Confirmation on the file.
    var review: @MainActor (ScriptModuleDefinition) -> Void
    /// `REVEAL`: show the file in Finder (Story 12.11).
    var reveal: @MainActor (ScriptModuleDefinition) -> Void = { _ in }
    /// `OPEN SOURCE`: open the file in the default editor for its type (Story 12.11).
    var openSource: @MainActor (ScriptModuleDefinition) -> Void = { _ in }
}

/// One script as its own module (SPEC §7.4, AD-18, Story 12.5): registered by ``IntegrationsModule`` through
/// `context.host.registerDynamicModule` for every parsed script that is not declined on this Mac (awaiting
/// confirmation included: its surfaces show `NOT CONFIRMED`; it never runs until confirmed). Its manifest comes
/// from the front matter (id, name, icon); its surfaces from `surfaces`: `home` → the Home card, `side` → one
/// left-wing item with the script's `priority`, `page` → a tab named after the script holding the script page
/// (Story 12.11). It has no context of its own: the integrations module runs it and owns its registration.
@MainActor @Observable
public final class ScriptModule: NotchModule {
    /// The id of its one left-wing item.
    public nonisolated static let sideItemID = "script"

    public let manifest: ModuleManifest
    /// The file of the script (``ScriptModuleDefinition/id``), the key of its runs and confirmation.
    public let scriptID: String
    public let frontMatter: ScriptFrontMatter
    /// The parsed file as of the last scan (same front matter; code and documentation may change).
    public private(set) var definition: ScriptModuleDefinition
    @ObservationIgnored let source: ScriptModuleSource

    /// `definition` must have parsed (`frontMatter` set).
    init(definition: ScriptModuleDefinition, frontMatter: ScriptFrontMatter, source: ScriptModuleSource) {
        self.definition = definition
        self.frontMatter = frontMatter
        self.source = source
        scriptID = definition.id
        manifest = ModuleManifest(
            id: frontMatter.id, name: LocalizedStringResource(stringLiteral: frontMatter.name),
            icon: frontMatter.icon)
    }

    /// A new scan of the same file with the same front matter.
    func update(_ definition: ScriptModuleDefinition) {
        if definition != self.definition { self.definition = definition }
    }

    /// What the surfaces render now. Reading it tracks the confirmation records and the run state.
    public var snapshot: ScriptSurfaceSnapshot {
        ScriptSurfaceSnapshot(
            frontMatter: frontMatter, local: source.localState(definition), run: source.runState(scriptID))
    }

    /// Arbitration state (``ScriptSurfaces/state(_:)``), derived from observed state.
    public var state: ModuleState { ScriptSurfaces.state(snapshot) }

    public var surfaces: [ScriptSurface] { frontMatter.surfaces }

    /// The left-wing priority (front matter, else ``ScriptSurfaces/defaultPriority``).
    public var priority: Int { ScriptSurfaces.priority(frontMatter) }

    // MARK: Surfaces

    public func homeCard() -> AnyView? {
        guard surfaces.contains(.home) else { return nil }
        return AnyView(ScriptHomeCard(module: self))
    }

    public func leftWingItems() -> [LeftWingItem] {
        guard surfaces.contains(.side) else { return [] }
        let model = ScriptSurfaces.sideItem(snapshot)
        return [
            LeftWingItem(id: Self.sideItemID, priority: priority) { _ in AnyView(ScriptSideItem(model: model)) }
        ]
    }

    public func expandedView() -> AnyView? {
        guard surfaces.contains(.page) else { return nil }
        return AnyView(ScriptPageTab(module: self))
    }

    public func start(context: any ModuleContext) async throws {}
    public func stop() async {}

    // MARK: Actions

    /// A click on the widget: the latest good output's action, only for a script confirmed on this Mac.
    public func activate() {
        let snapshot = snapshot
        guard snapshot.local == .confirmed, let action = snapshot.run?.lastGoodOutput?.action else { return }
        source.perform(action, scriptID)
    }

    /// A click on `NOT CONFIRMED`.
    public func review() {
        source.review(definition)
    }

    /// The script page's model now (Story 12.11). Reading it tracks the definition, the confirmation records
    /// and the run state, so the tab re-renders as runs complete.
    public var pageModel: ScriptPageModel {
        ScriptSurfaces.page(snapshot, definition: definition)
    }

    /// `REVEAL` on the page: the file in Finder.
    public func reveal() {
        source.reveal(definition)
    }

    /// `OPEN SOURCE` on the page: the file in its default editor.
    public func openSource() {
        source.openSource(definition)
    }
}

/// The Home card of a script module, re-rendered when its snapshot changes.
struct ScriptHomeCard: View {
    let module: ScriptModule

    var body: some View {
        let model = ScriptSurfaces.card(module.snapshot)
        ScriptCard(
            model: model, onActivate: model.action == nil ? nil : { module.activate() },
            onReview: { module.review() })
    }
}

/// The tab of a script with `page` (Story 12.11): the script page, re-rendered when its model changes.
struct ScriptPageTab: View {
    let module: ScriptModule

    var body: some View {
        ScriptPage(
            model: module.pageModel,
            actions: ScriptPageActions(
                activate: { module.activate() }, review: { module.review() }, reveal: { module.reveal() },
                openSource: { module.openSource() }))
    }
}
