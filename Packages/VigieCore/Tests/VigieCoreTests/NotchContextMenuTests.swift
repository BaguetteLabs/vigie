import AppKit
import Testing

@testable import VigieCore

@MainActor
@Suite struct NotchContextMenuTests {
    @Test func buildsLocalizedItems() {
        let menu = NotchContextMenu()
        #expect(menu.menu.items.count == 2)
        #expect(!menu.settingsItem.title.isEmpty && menu.settingsItem.title != "menu.settings")
        #expect(!menu.quitItem.title.isEmpty && menu.quitItem.title != "menu.quit")
        #expect(menu.settingsItem.keyEquivalent == ",")
        #expect(menu.quitItem.keyEquivalent == "q")
        #expect(menu.settingsItem.isEnabled)
        #expect(menu.quitItem.isEnabled)
    }

    @Test func quitItemInvokesInjectedClosure() throws {
        var quits = 0
        let menu = NotchContextMenu(quit: { quits += 1 })
        let item = menu.quitItem
        let target = try #require(item.target as? NSObject)
        _ = target.perform(try #require(item.action))
        #expect(quits == 1)
    }

    @Test func settingsActionInvokesInjectedClosure() {
        var opens = 0
        let menu = NotchContextMenu(openSettings: { opens += 1 })
        menu.performOpenSettings()
        #expect(opens == 1)
    }
}
