import ModuleKit
import VigieUI

/// Tab order of the expanded view (SPEC §10, §11 `[general] tab_order`, A12, A74).
enum ExpandedTabOrder {
    /// `tabs` (in registry order) rearranged by `order`: listed ids first, in that order; tabs not listed follow
    /// in registry order. Ids in `order` with no tab (disabled or unknown modules) are ignored.
    static func ordered(_ tabs: [ExpandedTab], by order: [String]) -> [ExpandedTab] {
        var remaining = tabs
        var result: [ExpandedTab] = []
        for id in order {
            guard let index = remaining.firstIndex(where: { $0.id == id }) else { continue }
            result.append(remaining.remove(at: index))
        }
        return result + remaining
    }

    /// The tab of a running module with an `expandedView()`, or nil. A module in `alert` needs attention.
    @MainActor
    static func tab(for module: any NotchModule) -> ExpandedTab? {
        guard module.expandedView() != nil else { return nil }
        let manifest = module.manifest
        return ExpandedTab(
            id: manifest.id.rawValue, title: String(localized: manifest.name), icon: manifest.icon,
            needsAttention: module.state == .alert)
    }
}
