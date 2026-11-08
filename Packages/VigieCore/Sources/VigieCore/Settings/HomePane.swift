import ModuleKit
import Observation
import SwiftUI

/// A provider of a Home card as Settings › Home lists it: a module with a `homeCard()`, or (Epic 12) a script
/// with the `home` surface. `id` is what `[home] cards` stores.
public struct HomeProviderDescriptor: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Settings › Home (Story 11.1, FR90, UX-DR97): every provider that offers a Home card, each with a checkbox,
/// dragged into order. Ticked rows come first in `[home] cards` order; unticked rows sit below in provider
/// order. Every change writes `[home] cards` (synced) through `ConfigStore`, and Home follows live.
@MainActor @Observable
public final class HomePaneModel {
    /// One row of the list.
    public struct Row: Identifiable, Hashable, Sendable {
        public let id: String
        public let name: String
        public let isOn: Bool
    }

    public static let cardsPath = CoreSettings.path("home", "cards")

    @ObservationIgnored public let configStore: ConfigStore
    @ObservationIgnored let providers: @MainActor () -> [HomeProviderDescriptor]
    /// Inline error of the last refused write.
    public private(set) var error: String?

    /// - Parameter providers: the providers offering a card now, in registry order (modules, then scripts).
    public init(configStore: ConfigStore, providers: @escaping @MainActor () -> [HomeProviderDescriptor]) {
        self.configStore = configStore
        self.providers = providers
    }

    /// `[home] cards` as written.
    public var cards: [String] { configStore.value(Self.cardsPath, as: [String].self) ?? [] }

    /// Ticked rows in `[home] cards` order, then unticked rows in provider order. Ids in `[home] cards` with no
    /// provider now are not listed.
    public var rows: [Row] {
        let available = providers()
        let byID = Dictionary(available.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ticked = HomeCardSelection.resolve(order: cards, offered: byID).cards
        let tickedIDs = Set(ticked.map(\.id))
        return ticked.map { Row(id: $0.id, name: $0.name, isOn: true) }
            + available.filter { !tickedIDs.contains($0.id) }.map { Row(id: $0.id, name: $0.name, isOn: false) }
    }

    /// Ticks or unticks a row. A ticked row joins the end of the Home order.
    public func setOn(_ id: String, _ on: Bool) async {
        var list = rows
        guard let index = list.firstIndex(where: { $0.id == id }), list[index].isOn != on else { return }
        let row = list.remove(at: index)
        let updated = Row(id: row.id, name: row.name, isOn: on)
        let lastTicked = list.lastIndex(where: \.isOn).map { $0 + 1 } ?? 0
        list.insert(updated, at: on ? lastTicked : min(index, list.count))
        await write(list)
    }

    /// Drag to reorder (`ForEach.onMove`): the Home order becomes the ticked rows in list order.
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) async {
        var list = rows
        list.move(fromOffsets: source, toOffset: destination)
        await write(list)
    }

    /// Moves a row one place up or down (VoiceOver and keyboard alternative to dragging).
    public func move(_ id: String, by offset: Int) async {
        let list = rows
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard list.indices.contains(target) else { return }
        await move(fromOffsets: IndexSet(integer: index), toOffset: offset > 0 ? target + 1 : target)
    }

    /// Writes the ticked rows in order. Ids in `[home] cards` whose provider is not available now (a disabled
    /// module, a script not loaded) are kept after them, so ticking in this list never forgets them.
    private func write(_ list: [Row]) async {
        let listed = Set(list.map(\.id))
        let kept = cards.filter { !listed.contains($0) }
        var ids = list.filter(\.isOn).map(\.id)
        for id in kept where !ids.contains(id) { ids.append(id) }
        guard ids != cards else { return }
        do throws(ConfigError) {
            try await configStore.set(Self.cardsPath, to: .strings(ids))
            error = nil
        } catch {
            self.error = SettingWriteError(error).errorDescription
        }
    }
}

/// The Home card list inside the Settings `Form`: checkbox, name and drag handle per row.
struct HomePaneContent: View {
    let model: HomePaneModel

    var body: some View {
        let rows = model.rows
        Section {
            if rows.isEmpty {
                Text(SettingsText.resource("settings.home.empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    HomeProviderRow(model: model, row: row)
                }
                .onMove { source, destination in
                    Task { await model.move(fromOffsets: source, toOffset: destination) }
                }
            }
        } header: {
            Text(SettingsText.resource("settings.home.cards"))
        } footer: {
            VStack(alignment: .leading) {
                Text(SettingsText.resource("settings.home.footer"))
                if let error = model.error {
                    Text(verbatim: error).foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct HomeProviderRow: View {
    let model: HomePaneModel
    let row: HomePaneModel.Row

    var body: some View {
        HStack {
            Toggle(isOn: Binding(get: { row.isOn }, set: { on in Task { await model.setOn(row.id, on) } })) {
                Text(verbatim: row.name)
            }
            .toggleStyle(.checkbox)
            Spacer()
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .help(Text(SettingsText.resource("settings.home.drag")))
                .accessibilityHidden(true)
        }
        .accessibilityAction(named: Text(SettingsText.resource("settings.home.moveUp"))) {
            Task { await model.move(row.id, by: -1) }
        }
        .accessibilityAction(named: Text(SettingsText.resource("settings.home.moveDown"))) {
            Task { await model.move(row.id, by: 1) }
        }
    }
}
