import ModuleKit
import SwiftUI
import VigieUI

/// Which cards Home shows (Story 11.1, FR90): the ids of `[home] cards`, in that order, that a provider offers
/// right now. Pure, so ordering and filtering are testable without views.
enum HomeCardSelection {
    /// `order` ∩ `offered`, in `order`; duplicates keep their first place. `missing` lists ids no provider
    /// offers now (unknown, disabled or stopped), in order.
    static func resolve<Card>(order: [String], offered: [String: Card]) -> (cards: [Card], missing: [String]) {
        var seen: Set<String> = []
        var cards: [Card] = []
        var missing: [String] = []
        for id in order where seen.insert(id).inserted {
            if let card = offered[id] {
                cards.append(card)
            } else {
                missing.append(id)
            }
        }
        return (cards, missing)
    }
}

/// The Home tab (Story 11.1; FR87, FR89, FR90, A34): always first, not a module, not in `[general] tab_order`.
extension NotchHost {
    /// Home's cards: the providers named by `[home] cards`, in that order, that offer a `homeCard()` now.
    /// Reading it tracks `[home] cards` (ConfigStore's revision) and module starts and stops, so the open
    /// Home updates live. Ids that offer no card are skipped and logged once each.
    public var homeCards: [HomeCardModel] {
        _ = registry.statuses  // module starts and stops
        var offered: [String: HomeCardModel] = [:]
        for module in registry.runningModules {
            guard let view = module.homeCard() else { continue }
            let manifest = module.manifest
            offered[manifest.id.rawValue] = HomeCardModel(
                id: manifest.id.rawValue, title: String(localized: manifest.name),
                opensTab: module.expandedView() != nil, content: view)
        }
        for card in additionalHomeCards() where offered[card.id] == nil {
            offered[card.id] = card
        }
        let (cards, missing) = HomeCardSelection.resolve(order: homeCardOrder(), offered: offered)
        for id in missing where loggedMissingHomeCards.insert(id).inserted {
            logger.info("home: no card from \(id, privacy: .public); skipped")
        }
        return cards
    }

    /// The Home tab body: the grid, or the empty state leading to Settings › Home.
    func homeContent() -> AnyView {
        var openSettingsAction: (@MainActor () -> Void)?
        if openSettingsPane != nil || openSettings != nil {
            openSettingsAction = { [weak self] in self?.openHomeSettings() }
        }
        return AnyView(
            HomeTabView(
                cards: homeCards,
                onOpen: { [weak self] id in self?.openHomeCard(id) },
                onOpenSettings: openSettingsAction))
    }

    /// A click on a Home card opens its provider's tab (A34).
    public func openHomeCard(_ id: String) {
        guard expandedTabs.contains(where: { $0.id == id && $0.id != ExpandedTab.homeID }) else {
            logger.info("home: \(id, privacy: .public) has no tab")
            return
        }
        selectedTabID = id
    }

    /// `Open settings` on the empty Home: Settings › Home.
    func openHomeSettings() {
        if let openSettingsPane {
            openSettingsPane(SettingsPaneCatalog.homePaneID)
        } else {
            openSettings?()
        }
    }
}
