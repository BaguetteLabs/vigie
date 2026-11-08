import ModuleKit

/// `context.dropZones` (Stories 9.7, 9.10): the running modules' zones as the drop display collects them, and
/// their handlers run through ``DropDisplayController/perform(zoneID:payload:)`` so every path gets the same
/// progress and readout routing as a real drop. Bound to the Notch Host late, through a ``NotchHostLink``;
/// unbound it lists nothing and runs nothing.
public struct CoreDropZoneDirectory: DropZoneDirectory {
    public let link: NotchHostLink

    public init(link: NotchHostLink) {
        self.link = link
    }

    @MainActor public func zones() -> [DropZoneSummary] {
        link.host?.dropZoneSummaries() ?? []
    }

    @MainActor public func perform(zoneID: String, payload: DropPayload) async -> DropResult {
        guard let host = link.host else { return .rejected }
        return await host.dropDisplay.perform(zoneID: zoneID, payload: payload)
    }
}

extension NotchHost {
    /// Every running module's zones with their owner, first declaration of an id wins, in `order`.
    public func dropZoneSummaries() -> [DropZoneSummary] {
        var seen: Set<String> = []
        var summaries: [DropZoneSummary] = []
        for module in registry.runningModules {
            for zone in module.dropZones where seen.insert(zone.id).inserted {
                summaries.append(DropZoneSummary(zone, moduleID: module.manifest.id))
            }
        }
        return summaries.sorted { $0.order < $1.order }
    }
}
