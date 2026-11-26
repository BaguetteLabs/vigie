import Foundation
import VigieUI

/// Feeds `[appearance] theme` from `ConfigStore` into ``ThemeController`` (Story 18.1): applied at start and on
/// every change, so the whole app re-skins live (AD-8). An unknown id resolves to the default theme and the
/// controller reports the problem.
@MainActor
public final class AppearanceConfigBridge {
    static let themePath = CoreSettings.path("appearance", "theme")

    private let store: ConfigStore
    private let themes: ThemeController
    private var changesTask: Task<Void, Never>?

    public init(store: ConfigStore, themes: ThemeController) {
        self.store = store
        self.themes = themes
    }

    public func start() {
        guard changesTask == nil else { return }
        let changes = store.changes  // subscribe before the first apply so no change is missed
        apply()
        changesTask = Task { [weak self] in
            for await keys in changes {
                guard let self else { return }
                if keys.contains(Self.themePath) { self.apply() }
            }
        }
    }

    public func stop() {
        changesTask?.cancel()
        changesTask = nil
    }

    private func apply() {
        let id = store.value(Self.themePath, as: String.self) ?? ThemeLibrary.defaultVariantID
        if themes.variantID != id { themes.variantID = id }
    }
}
