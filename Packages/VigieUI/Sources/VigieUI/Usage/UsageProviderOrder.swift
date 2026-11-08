import Foundation

/// Provider order arithmetic shared by the Usage tab's drag and the module's Settings list (Story 7.9).
public enum UsageProviderOrder {
    /// `ids` with the elements at `source` moved before `destination` (`ForEach.onMove` semantics).
    public static func moved(_ ids: [String], fromOffsets source: IndexSet, toOffset destination: Int) -> [String] {
        var list = ids
        list.move(fromOffsets: source, toOffset: destination)
        return list
    }

    /// `ids` with `id` moved one place by `offset` (-1 up, 1 down); unchanged at the bounds or if absent.
    public static func moving(_ id: String, by offset: Int, in ids: [String]) -> [String] {
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return ids }
        return moved(
            ids, fromOffsets: IndexSet(integer: index), toOffset: offset > 0 ? index + offset + 1 : index + offset)
    }

    /// `ids` with `id` dropped on `target`: it takes the target's place (after it when moving down).
    public static func moving(_ id: String, onto target: String, in ids: [String]) -> [String] {
        guard id != target, let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target) else { return ids }
        return moved(ids, fromOffsets: IndexSet(integer: from), toOffset: from < to ? to + 1 : to)
    }

    /// The full list to write: `shown` in its new order, then every other known provider in its current
    /// order, then ids already in `existing` that are unknown now (a provider not installed), so nothing is lost.
    public static func merged(shown: [String], current: [String], existing: [String]) -> [String] {
        var result: [String] = []
        for id in shown + current + existing where !result.contains(id) { result.append(id) }
        return result
    }
}
