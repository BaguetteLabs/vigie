import Foundation
import ModuleKit
import Observation

/// `integrations` (SPEC §7.4): the runtime of script modules (SPEC §9, AD-18).
///
/// Story 12.1 ships only the skeleton and the script schema types (`Schema/`, checked against
/// `schemas/script-module.schema.json`). Discovery and parsing (12.2), confirmation (12.3), the runner (12.4) and
/// the dynamic modules each confirmed script registers (12.5) build on it. Until then the module renders nothing
/// and its state stays `hidden`.
@MainActor @Observable
public final class IntegrationsModule: NotchModule {
    public nonisolated static let staticManifest = ModuleManifest(
        id: "integrations",
        name: IntegrationsText.resource("integrations.module.name"),
        icon: "puzzlepiece.extension"
    )

    public let manifest = IntegrationsModule.staticManifest
    public private(set) var state: ModuleState = .hidden

    public init() {}

    public func start(context: any ModuleContext) async throws {}

    public func stop() async {}
}
