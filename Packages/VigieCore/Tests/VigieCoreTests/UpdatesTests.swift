import AppKit
import Foundation
import ModuleKit
import Testing

@testable import VigieCore

/// Records what the bridge, Settings and the context menu ask of the updater (Story 6.3).
@MainActor
final class FakeUpdater: UpdaterControlling {
    var unavailableReason: UpdaterUnavailableReason?
    var canCheckForUpdates = true
    var applied: [UpdateSettings] = []
    var checks = 0
    var onAutoInstallChangedByUser: (@MainActor (Bool) -> Void)?

    init(unavailableReason: UpdaterUnavailableReason? = nil) {
        self.unavailableReason = unavailableReason
        if unavailableReason != nil { canCheckForUpdates = false }
    }

    func apply(_ settings: UpdateSettings) { applied.append(settings) }
    func checkForUpdates() { checks += 1 }
}

@MainActor @Suite struct UpdatesTests {
    let fixture = ConfigFixture()

    func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    }

    // MARK: - Keys and defaults

    @Test func updatesKeysAreSyncedWithTheSpecDefaults() {
        let schema = ConfigSchema()
        let check = schema.entries[UpdateSettings.autoCheckPath]
        let interval = schema.entries[UpdateSettings.checkIntervalPath]
        let install = schema.entries[UpdateSettings.autoInstallPath]
        #expect(check?.descriptor.kind == .bool(default: true))
        #expect(interval?.descriptor.kind == .duration(default: .seconds(24 * 3600)))
        #expect(install?.descriptor.kind == .bool(default: false))
        #expect([check, interval, install].allSatisfy { $0?.descriptor.scope == .synced })
        #expect(
            UpdateSettings.defaults
                == UpdateSettings(autoCheck: true, checkInterval: .seconds(86400), autoInstall: false))
    }

    @Test func readsTheConfigAndFallsBackToDefaults() async throws {
        let (empty, _) = try await fixture.makeStore()
        #expect(UpdateSettings.read(from: empty) == .defaults)
        empty.stop()
        let other = ConfigFixture()
        let (store, _) = try await other.makeStore(
            config: "[updates]\nauto_check = false\ncheck_interval = \"6h\"\nauto_install = true\n")
        #expect(
            UpdateSettings.read(from: store)
                == UpdateSettings(autoCheck: false, checkInterval: .seconds(6 * 3600), autoInstall: true))
        store.stop()
    }

    // MARK: - Plan (what the Sparkle updater is told)

    @Test func defaultPlanChecksEvery24HoursAndAsksBeforeInstalling() {
        let plan = UpdaterPlan(.defaults, alreadyStarted: false)
        #expect(plan.automaticallyChecks && plan.allowsBackgroundChecks && plan.startsUpdater)
        #expect(plan.intervalSeconds == 86400)
        #expect(!plan.automaticallyDownloads)  // asks first (PRD FR-61)
    }

    @Test func autoInstallDownloadsAutomaticallyOnlyWithChecksOn() {
        let on = UpdaterPlan(
            UpdateSettings(autoCheck: true, checkInterval: .seconds(86400), autoInstall: true), alreadyStarted: false)
        #expect(on.automaticallyDownloads)
        let off = UpdaterPlan(
            UpdateSettings(autoCheck: false, checkInterval: .seconds(86400), autoInstall: true), alreadyStarted: false)
        #expect(!off.automaticallyDownloads)
    }

    @Test func autoCheckOffNeverStartsTheUpdaterNorAllowsBackgroundChecks() {
        let settings = UpdateSettings(autoCheck: false, checkInterval: .seconds(86400), autoInstall: false)
        let plan = UpdaterPlan(settings, alreadyStarted: false)
        #expect(!plan.startsUpdater && !plan.automaticallyChecks && !plan.allowsBackgroundChecks)
        // Turned off after start: scheduling stops and the delegate refuses background checks.
        let later = UpdaterPlan(settings, alreadyStarted: true)
        #expect(!later.startsUpdater && !later.automaticallyChecks && !later.allowsBackgroundChecks)
        // Only an explicit "Check for Updates…" starts it, and still schedules nothing.
        let manual = UpdaterPlan(settings, alreadyStarted: false, userRequestedCheck: true)
        #expect(manual.startsUpdater && !manual.automaticallyChecks && !manual.allowsBackgroundChecks)
    }

    @Test func intervalUnderAnHourIsRaisedToSparklesMinimum() {
        let plan = UpdaterPlan(
            UpdateSettings(autoCheck: true, checkInterval: .seconds(60), autoInstall: false), alreadyStarted: true)
        #expect(plan.intervalSeconds == 3600)
        #expect(!plan.startsUpdater)
        let long = UpdaterPlan(
            UpdateSettings(autoCheck: true, checkInterval: .seconds(7 * 86400), autoInstall: false),
            alreadyStarted: true)
        #expect(long.intervalSeconds == 7 * 86400)
    }

    // MARK: - Info.plist configuration

    static let key = Data(repeating: 7, count: 32).base64EncodedString()
    static let feed = "https://github.com/BaguetteLabs/vigie-releases/releases/latest/download/appcast.xml"

    @Test func configuredBuildIsAvailable() {
        #expect(UpdaterConfiguration.check(infoDictionary: ["SUPublicEDKey": Self.key, "SUFeedURL": Self.feed]) == nil)
    }

    @Test func emptyOrMalformedPublicKeyDisablesTheUpdater() {
        for key in ["", "   ", "not base64!", Data(repeating: 1, count: 31).base64EncodedString()] {
            #expect(
                UpdaterConfiguration.check(infoDictionary: ["SUPublicEDKey": key, "SUFeedURL": Self.feed])
                    == .missingPublicKey)
        }
        #expect(UpdaterConfiguration.check(infoDictionary: ["SUFeedURL": Self.feed]) == .missingPublicKey)
    }

    @Test func placeholderOrInsecureFeedDisablesTheUpdater() {
        for feed in [
            "https://github.com/OWNER/vigie-releases/releases/latest/download/appcast.xml",
            "https://github.com//releases/latest/download/appcast.xml",
            "http://github.com/BaguetteLabs/vigie-releases/releases/latest/download/appcast.xml",
            "",
        ] {
            #expect(
                UpdaterConfiguration.check(infoDictionary: ["SUPublicEDKey": Self.key, "SUFeedURL": feed])
                    == .missingFeed, "\(feed)")
        }
    }

    // MARK: - Bridge (live reload)

    @Test func bridgeAppliesAtStartAndOnEveryChange() async throws {
        let (store, _) = try await fixture.makeStore()
        let updater = FakeUpdater()
        let bridge = UpdatesConfigBridge(store: store, updater: updater, logger: testLogger)
        bridge.start()
        #expect(updater.applied == [.defaults])

        try await store.set(UpdateSettings.autoInstallPath, to: .bool(true))
        try await wait { updater.applied.count == 2 }
        #expect(updater.applied.last?.autoInstall == true)

        try await store.set(UpdateSettings.autoCheckPath, to: .bool(false))
        try await wait { updater.applied.count == 3 }
        #expect(updater.applied.last?.autoCheck == false)

        // Unrelated keys do not reach the updater.
        try await store.set(CoreSettings.path("closed", "peek"), to: .bool(false))
        try await Task.sleep(for: .milliseconds(50))
        #expect(updater.applied.count == 3)
        bridge.stop()
        store.stop()
    }

    @Test func bridgeFollowsAnOutsideEditOfConfigToml() async throws {
        let (store, watcher) = try await fixture.makeStore()
        let updater = FakeUpdater()
        let bridge = UpdatesConfigBridge(store: store, updater: updater, logger: testLogger)
        bridge.start()
        try fixture.writeConfig("[updates]\ncheck_interval = \"12h\"\n")
        watcher.fire()
        try await wait { updater.applied.count == 2 }
        #expect(updater.applied.last?.checkInterval == .seconds(12 * 3600))
        bridge.stop()
        store.stop()
    }

    @Test func sparklesAutoInstallCheckboxIsWrittenToConfig() async throws {
        let (store, _) = try await fixture.makeStore()
        let updater = FakeUpdater()
        let bridge = UpdatesConfigBridge(store: store, updater: updater, logger: testLogger)
        bridge.start()
        updater.onAutoInstallChangedByUser?(true)
        try await wait { store.value(UpdateSettings.autoInstallPath, as: Bool.self) == true }
        #expect(store.value(UpdateSettings.autoInstallPath, as: Bool.self) == true)
        let text = try String(contentsOf: fixture.configURL, encoding: .utf8)
        #expect(text.contains("auto_install = true"))
        bridge.stop()
        #expect(updater.onAutoInstallChangedByUser == nil)
        store.stop()
    }

    @Test func unavailableUpdaterIsNeverDriven() async throws {
        let (store, _) = try await fixture.makeStore()
        let updater = FakeUpdater(unavailableReason: .missingPublicKey)
        let bridge = UpdatesConfigBridge(store: store, updater: updater, logger: testLogger)
        bridge.start()
        try await store.set(UpdateSettings.autoCheckPath, to: .bool(false))
        try await Task.sleep(for: .milliseconds(50))
        #expect(updater.applied.isEmpty && updater.onAutoInstallChangedByUser == nil)
        bridge.stop()
        store.stop()
    }

    // MARK: - Settings › Updates and the context menu

    @Test func updatesPaneHasTheThreeRowsAndTheCheckAction() async throws {
        let h = try await SettingsHarness()
        let pane = try #require(h.controller.pane("updates"))
        guard case .core(let sections) = pane.content else {
            Issue.record("not a core pane")
            return
        }
        #expect(
            sections.flatMap(\.keys) == [
                UpdateSettings.autoCheckPath, UpdateSettings.checkIntervalPath, UpdateSettings.autoInstallPath,
            ])
        #expect(sections.flatMap(\.keys).allSatisfy { h.controller.rowModel(for: $0) != nil })

        // No updater yet: disabled, with the explanatory line.
        #expect(!h.controller.canCheckForUpdates)
        #expect(h.controller.updatesUnavailableText != nil)
        #expect(SettingsText.string("settings.updates.checkNow") == "Check for Updates…")

        let updater = FakeUpdater()
        h.controller.updater = updater
        #expect(h.controller.canCheckForUpdates && h.controller.updatesUnavailableText == nil)
        h.controller.checkForUpdates()
        #expect(updater.checks == 1)
        updater.canCheckForUpdates = false  // a check is running
        h.controller.checkForUpdates()
        #expect(updater.checks == 1)

        h.controller.updater = FakeUpdater(unavailableReason: .missingFeed)
        #expect(!h.controller.canCheckForUpdates && h.controller.updatesUnavailableText != nil)
        await h.tearDown()
    }

    @Test func contextMenuOffersCheckForUpdatesWithAnUpdater() throws {
        #expect(
            !NotchContextMenu().menu.items.contains { $0.action == #selector(NotchContextMenu.performCheckForUpdates) })

        let updater = FakeUpdater()
        let menu = NotchContextMenu(updater: updater)
        #expect(
            menu.menu.items.map(\.title) == [
                menu.settingsItem.title, menu.checkForUpdatesItem.title, menu.quitItem.title,
            ])
        #expect(menu.checkForUpdatesItem.title == "Check for Updates…")
        #expect(menu.checkForUpdatesItem.isEnabled)
        let target = try #require(menu.checkForUpdatesItem.target as? NSObject)
        _ = target.perform(try #require(menu.checkForUpdatesItem.action))
        #expect(updater.checks == 1)

        updater.canCheckForUpdates = false
        menu.menuNeedsUpdate(menu.menu)
        #expect(!menu.checkForUpdatesItem.isEnabled)
        menu.performCheckForUpdates()
        #expect(updater.checks == 1)

        let off = NotchContextMenu(updater: FakeUpdater(unavailableReason: .missingPublicKey))
        #expect(!off.checkForUpdatesItem.isEnabled)
    }
}
