import AppKit
import KeyboardShortcuts
import ModuleKit
import Observation
import SwiftUI
import Testing
import VigieUI

@testable import VigieCore

/// Login item fake: records calls, `status` settable to simulate System Settings.
@MainActor
final class FakeLoginItem: LoginItemControlling {
    var status: LoginItemStatus = .notRegistered
    var registerCalls = 0
    var unregisterCalls = 0
    var openCalls = 0
    var failNext = false

    func register() throws {
        registerCalls += 1
        if failNext { throw CocoaError(.featureUnsupported) }
        status = .enabled
    }

    func unregister() throws {
        unregisterCalls += 1
        if failNext { throw CocoaError(.featureUnsupported) }
        status = .notRegistered
    }

    func openSystemSettings() { openCalls += 1 }
}

@MainActor @Observable
final class CustomSettingsModule: NotchModule {
    let manifest: ModuleManifest
    var state: ModuleState = .ambient

    init(manifest: ModuleManifest) { self.manifest = manifest }

    func start(context: any ModuleContext) async throws {}
    func stop() async {}
    func settingsView() -> AnyView? { AnyView(Text(verbatim: "custom settings")) }
}

let calendarManifest = ModuleManifest(
    id: "calendar.test", name: "Calendar", icon: "calendar", permissions: [.calendar],
    settings: [SettingDescriptor(key: "reminders", label: "Reminders", kind: .bool(default: true))])

let customManifest = ModuleManifest(
    id: "custom.test", name: "Custom", icon: "star",
    settings: [
        SettingDescriptor(key: "hotkey", label: "Shortcut", kind: .hotkey(default: nil)),
        SettingDescriptor(key: "token", label: "Token", kind: .secret),
        SettingDescriptor(key: "ratio", label: "Ratio", kind: .double(default: 0.5, min: 0, max: 1, step: 0.1)),
        SettingDescriptor(key: "folders", label: "Folders", kind: .list(of: .path, default: ["~/Code"])),
        SettingDescriptor(
            key: "name", label: "Name", kind: .string(default: "x"), help: "Shown on the card."),
    ])

@MainActor
struct SettingsHarness {
    let fixture = ConfigFixture()
    let store: ConfigStore
    let watcher: ManualDirectoryWatcher
    let checker = FakePermissionChecker()
    let coordinator: PermissionsCoordinator
    let registry: ModuleRegistry
    let loginItem = FakeLoginItem()
    let activityStore: ActivityStore
    let controller: SettingsController
    var openedURLs: [URL] { recorder.urls }
    let recorder = URLRecorder()

    @MainActor final class URLRecorder {
        var urls: [URL] = []
    }

    init(config: String? = nil, sessions: ModuleManifest = testManifest, secretStore: KeychainSecretStore? = nil)
        async throws
    {
        let manifests = [sessions, calendarManifest, customManifest]
        (store, watcher) = try await fixture.makeStore(manifests: manifests, config: config)
        checker.set(.calendar, .denied)
        let (stream, _) = AsyncStream.makeStream(of: Void.self)
        coordinator = PermissionsCoordinator(checker: checker, activationNotifications: stream)
        let descriptors = [
            ModuleDescriptor(manifest: sessions) { SpyModule(manifest: sessions, shouldThrow: false) },
            ModuleDescriptor(manifest: calendarManifest) { CustomSettingsModule(manifest: calendarManifest) },
            ModuleDescriptor(manifest: customManifest) { CustomSettingsModule(manifest: customManifest) },
        ]
        registry = ModuleRegistry(
            descriptors: descriptors,
            enablement: TestEnablement(["agents.sessions": false, "calendar.test": true, "custom.test": true]),
            contextFactory: CoreModuleContextFactory(
                environment: fixture.environment, eventBus: InProcessEventBus(), permissions: coordinator,
                secretStore: secretStore),
            logger: testLogger, permissions: coordinator)
        activityStore = ActivityStore(environment: fixture.environment)
        controller = SettingsController(
            configStore: store, registry: registry, permissions: coordinator,
            hotkeyCenter: HotkeyCenter(binding: FakeHotkeyBinding()), activityStore: activityStore,
            cliInstaller: nil, manifests: manifests, loginItem: loginItem, secretStore: secretStore)
        let recorder = recorder
        controller.openURL = { recorder.urls.append($0) }
        // `open` creates the window, then calls this just before `makeKeyAndOrderFront`: park it off-screen and
        // inert instead of activating the app, so the suite never covers or takes focus from the developer's windows.
        controller.activateApp = { [unowned controller] in
            if let w = controller.window {
                quietOffscreen(w)
                w.alphaValue = 0
            }
        }
        await registry.start()
    }

    func configText() -> String { (try? String(contentsOf: fixture.configURL, encoding: .utf8)) ?? "" }
    func localText() -> String { (try? String(contentsOf: fixture.localURL, encoding: .utf8)) ?? "" }

    func tearDown() async {
        controller.window?.close()
        await registry.shutdown()
        store.stop()
    }
}

@MainActor @Suite(.serialized) struct SettingsControllerTests {
    @Test func paneListHasCorePanesAndEveryModule() async throws {
        let h = try await SettingsHarness()
        let ids = h.controller.panes.map(\.id)
        for id in SettingsPaneCatalog.corePaneIDs { #expect(ids.contains(id)) }
        for id in ["agents.sessions", "calendar.test", "custom.test"] { #expect(ids.contains(id)) }
        #expect(Array(ids.prefix(SettingsPaneCatalog.corePaneIDs.count)) == SettingsPaneCatalog.corePaneIDs)
        // Every core key has a row in exactly one pane, except [appearance.colors] (free-form) and
        // `[home] cards`, which the Settings › Home card list edits (Story 11.1), and `[updates] channel`, which has
        // no row until the beta feed exists (A63, Story 6.3), and `[config] folder` (Story 16.1).
        let placed = h.controller.panes.flatMap { pane -> [ConfigKeyPath] in
            if case .core(let sections) = pane.content { return sections.flatMap(\.keys) }
            return []
        }
        let core = Set(CoreSettings.all.map(\.path)).subtracting([
            CoreSettings.path("general", "launch_at_login"), HomePaneModel.cardsPath, FocusFilterSetup.path,
            CoreSettings.path("updates", "channel"),
            // `[config] folder` is edited by the Config folder section (Story 16.1), never as a generated row.
            ConfigStore.folderRecordPath,
        ])
        #expect(Set(placed) == core)
        #expect(placed.count == core.count)
        await h.tearDown()
    }

    @Test func openSelectsPaneAndNeverShowsADockIcon() async throws {
        let h = try await SettingsHarness()
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        h.controller.open(pane: "custom.test")
        #expect(h.controller.selectedPaneID == "custom.test")
        let window = try #require(h.controller.window)
        #expect(window.isVisible)
        #expect(window.title == "Settings")
        #expect(window.styleMask.contains(.resizable))
        #expect(window.contentLayoutRect.width == SettingsWindowMetrics.size.width)
        #expect(window.contentLayoutRect.height >= SettingsWindowMetrics.size.height)
        #expect(app.activationPolicy() == .prohibited)
        h.controller.open(pane: "privacy")
        #expect(h.controller.selectedPaneID == "general")
        try await Task.sleep(for: .milliseconds(100))
        #expect(window.title == "Settings")
        #expect(h.controller.window === window)
        h.controller.open(pane: "nope")
        #expect(h.controller.selectedPaneID == "general")
        h.controller.selectedPaneID = "sounds"
        h.controller.open()
        #expect(h.controller.selectedPaneID == "sounds")
        #expect(app.activationPolicy() == .prohibited)
        // ⌘W closes.
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "w", charactersIgnoringModifiers: "w",
                isARepeat: false, keyCode: 13))
        #expect(window.performKeyEquivalent(with: event))
        #expect(!window.isVisible)
        #expect(app.activationPolicy() == .prohibited)
        await h.tearDown()
    }

    @Test func boolChangeWritesThroughConfigStoreAndResets() async throws {
        let h = try await SettingsHarness()
        let row = try #require(h.controller.rowModel(for: CoreSettings.path("general", "open_on_hover")))
        #expect(row.currentValue == .bool(false))
        let state = SettingFieldState()
        #expect(await state.apply(.bool(true), to: row.binding, services: h.controller.services))
        #expect(h.configText().contains("open_on_hover = true"))
        #expect(row.currentValue == .bool(true))
        #expect(await state.apply(nil, to: row.binding, services: h.controller.services))
        #expect(!h.configText().contains("open_on_hover = true"))
        #expect(row.currentValue == .bool(false))
        await h.tearDown()
    }

    @Test func localKeyGoesToLocalFile() async throws {
        let h = try await SettingsHarness()
        let row = try #require(h.controller.rowModel(for: CoreSettings.path("virtual_notch", "idle")))
        try await row.binding.set(.string("hide"))
        #expect(h.localText().contains("idle = \"hide\""))
        #expect(!h.configText().contains("idle = \"hide\""))
        await h.tearDown()
    }

    @Test func outsideEditUpdatesTheBinding() async throws {
        let h = try await SettingsHarness()
        let row = try #require(h.controller.rowModel(for: CoreSettings.path("closed", "slots")))
        let before = h.store.revision
        try h.fixture.writeConfig("[closed]\nslots = 2\n")
        await h.store.fireAndSettle(h.watcher)
        #expect(h.store.revision > before)
        #expect(row.currentValue == .int(2))
        await h.tearDown()
    }

    @Test func invalidDurationShowsLocalizedErrorAndWritesNothing() async throws {
        let h = try await SettingsHarness()
        let row = try #require(h.controller.rowModel(for: CoreSettings.path("general", "hover_delay")))
        let before = h.configText()
        let state = SettingFieldState()
        #expect(!(await state.commitDuration("15 minutes", to: row.binding, services: h.controller.services)))
        #expect(state.error == "Enter a duration such as 90s, 15m or 1h30m.")
        #expect(h.configText() == before)
        #expect(await state.commitDuration("20m", to: row.binding, services: h.controller.services))
        #expect(state.error == nil)
        #expect(h.configText().contains("hover_delay = \"20m\""))
        await h.tearDown()
    }

    @Test func refusedWriteShowsCatalogTextNotTheEnglishReason() async throws {
        let h = try await SettingsHarness()
        let row = try #require(h.controller.rowModel(for: CoreSettings.path("closed", "slots")))
        let state = SettingFieldState()
        let before = h.configText()
        #expect(!(await state.commitInt("9", to: row.binding, services: h.controller.services)))
        #expect(state.error == "This value is not allowed here.")
        #expect(h.configText() == before)
        for error in [
            ConfigError.unknownSetting("x"), .invalidValue(key: "k", reason: "r"), .unsupportedLocation(key: "k"),
            .fileUnavailable(file: "config.toml", reason: "r"), .fileHasErrors(file: "config.toml"),
            .verificationFailed(key: "k"), .writeFailed(file: "config.toml", reason: "r"),
        ] {
            let text = try #require(SettingWriteError(error).errorDescription)
            #expect(!text.hasPrefix("settings.error"))
            #expect(!text.contains("%@"))
        }
        await h.tearDown()
    }

    @Test func hotkeyRecorderWritesCanonicalStringAndRejectsOptionOnly() async throws {
        let h = try await SettingsHarness()
        let row = try #require(h.controller.rowModel(for: CoreSettings.path("general", "expand_hotkey")))
        let state = SettingFieldState()
        await HotkeyRecorderField.write(
            KeyboardShortcuts.Shortcut(.k, modifiers: [.command, .shift]), binding: row.binding, state: state,
            services: h.controller.services)
        #expect(h.configText().contains("expand_hotkey = \"cmd+shift+k\""))
        let before = h.configText()
        await HotkeyRecorderField.write(
            KeyboardShortcuts.Shortcut(.k, modifiers: [.option]), binding: row.binding, state: state,
            services: h.controller.services)
        #expect(state.error == SettingsText.string("settings.error.hotkey"))
        #expect(h.configText() == before)
        #expect(HotkeyRecorderField.shortcut(from: .string("cmd+shift+k")) == .init(.k, modifiers: [.command, .shift]))
        await HotkeyRecorderField.write(nil, binding: row.binding, state: state, services: h.controller.services)
        #expect(h.configText().contains("expand_hotkey = \"\""))
        await h.tearDown()
    }

    @Test func moduleEnabledToggleWritesModuleTable() async throws {
        let h = try await SettingsHarness()
        let row = try #require(h.controller.rowModel(for: .moduleEnabled("agents.sessions")))
        #expect(String(localized: row.label) == "Enabled")
        try await row.binding.set(.bool(true))
        #expect(h.configText().contains("[modules.\"agents.sessions\"]"))
        #expect(h.configText().contains("enabled = true"))
        #expect(h.controller.moduleRows(testManifest).map(\.id).contains("modules.\"agents.sessions\".local.terminal"))
        await h.tearDown()
    }

    @Test func needsPermissionShowsBlockWithDeepLink() async throws {
        let h = try await SettingsHarness()
        #expect(h.controller.moduleStatus("calendar.test") == .needsPermission(.calendar))
        let prompt = try #require(h.controller.permissionPrompt(for: "calendar.test"))
        #expect(prompt.permission == .calendar)
        #expect(
            prompt.systemSettingsURL.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        #expect(prompt.status == .denied)
        #expect(!prompt.canGrant)
        h.controller.openSystemSettings(for: .calendar)
        #expect(h.openedURLs == [prompt.systemSettingsURL])
        #expect(h.controller.permissionPrompt(for: "custom.test") == nil)
        #expect(
            SettingsController.systemSettingsURL(for: .accessibility).absoluteString.hasSuffix("?Privacy_Accessibility")
        )
        #expect(
            SettingsController.systemSettingsURL(for: .automation(bundleID: "com.apple.Terminal")).absoluteString
                .hasSuffix("?Privacy_Automation"))
        #expect(
            SettingsController.systemSettingsURL(for: .screenRecording).absoluteString.hasSuffix(
                "?Privacy_ScreenCapture"))
        let status = ModulePaneContent.statusText(.needsPermission(.calendar))
        #expect(status == "Waiting for Calendars")

        // The pane renders the block (title text present in the hosted view's accessibility tree is not
        // reliable offscreen; the hosted view must lay out with content).
        let view = NSHostingView(
            rootView: SettingsPaneView(controller: h.controller, pane: try #require(h.controller.pane("calendar.test")))
                .environment(\.settingControlServices, h.controller.services))
        view.frame = NSRect(origin: .zero, size: SettingsWindowMetrics.size)
        view.layoutSubtreeIfNeeded()
        #expect(view.fittingSize.height > 0)
        await h.tearDown()
    }

    @Test func customModuleViewRendersBelowGeneratedRows() async throws {
        let h = try await SettingsHarness()
        #expect(h.controller.moduleStatus("custom.test") == .running)
        #expect(h.controller.customSettingsView("custom.test") != nil)
        #expect(h.controller.customSettingsView("agents.sessions") == nil)
        #expect(h.controller.moduleRows(customManifest).count == customManifest.settings.count)
        await h.tearDown()
    }

    @Test func customControlSettingsHaveNoGeneratedRow() async throws {
        let h = try await SettingsHarness()
        let manifest = ModuleManifest(
            id: "custom.test", name: "Custom", icon: "star",
            settings: customManifest.settings.map { descriptor in
                SettingDescriptor(
                    key: descriptor.key, label: descriptor.label, kind: descriptor.kind, scope: descriptor.scope,
                    help: descriptor.help, customControl: descriptor.key == "folders")
            })
        let ids = h.controller.moduleRows(manifest).map(\.id)
        #expect(ids.count == customManifest.settings.count - 1)
        #expect(!ids.contains { $0.hasSuffix(".folders") })
        await h.tearDown()
    }

    @Test func launchAtLoginTogglesTheLoginItemAndMirrorsItsState() async throws {
        let h = try await SettingsHarness()
        let path = CoreSettings.path("general", "launch_at_login")
        #expect(!h.controller.loginItemStatus.isOn)
        await h.controller.setLaunchAtLogin(true)
        #expect(h.loginItem.registerCalls == 1)
        #expect(h.controller.loginItemStatus == .enabled)
        #expect(await eventually { h.store.value(path, as: Bool.self) == true })
        #expect(h.localText().contains("launch_at_login = true"))

        // Turned off in System Settings › Login Items: the next refresh mirrors it.
        h.loginItem.status = .notRegistered
        h.controller.refreshLoginItem()
        #expect(!h.controller.loginItemStatus.isOn)
        #expect(await eventually { h.store.value(path, as: Bool.self) == false })

        h.loginItem.status = .requiresApproval
        h.controller.refreshLoginItem()
        #expect(h.controller.loginItemStatus.isOn)

        await h.controller.setLaunchAtLogin(false)
        #expect(h.loginItem.unregisterCalls == 1)
        #expect(h.controller.loginItemStatus == .notRegistered)

        h.loginItem.failNext = true
        await h.controller.setLaunchAtLogin(true)
        #expect(h.controller.loginItemError == SettingsText.string("settings.login.registerFailed"))
        #expect(!h.controller.loginItemStatus.isOn)
        await h.tearDown()
    }

    @Test func cliStatusAndPathHint() async throws {
        let fixture = ConfigFixture()
        let home = makeTempDirectory()
        let helper = home.appendingPathComponent("vigie-dev")
        FileManager.default.createFile(atPath: helper.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        let installer = CLIInstaller(environment: fixture.environment, bundledCLIURL: helper, homeDirectory: home)
        let h = try await SettingsHarness()
        let controller = SettingsController(
            configStore: h.store, registry: h.registry, permissions: h.coordinator,
            hotkeyCenter: HotkeyCenter(binding: FakeHotkeyBinding()), activityStore: h.activityStore,
            cliInstaller: installer, manifests: [], loginItem: h.loginItem, loginShellPath: { "/usr/bin:/bin" })
        await controller.refresh()
        #expect(controller.cliStatus == .missing(link: installer.linkURL))
        #expect(controller.cliPathHint?.binDirectory == installer.binDirectory)
        #expect(CLISection.text(for: .missing(link: installer.linkURL)) == SettingsText.string("settings.cli.missing"))
        #expect(!CLISection.text(for: .current(link: installer.linkURL)).contains("%@"))
        await h.tearDown()
    }

    @Test func activityPaneListsNewestFirstFiltersAndCopies() async throws {
        let h = try await SettingsHarness()
        let now = Date()
        await h.activityStore.append(
            .alert(
                module: "agents.sessions", kind: "session.blocked", severity: .warn, outcome: .posted,
                at: now.addingTimeInterval(-60)))
        await h.activityStore.append(.focus(module: nil, adapter: "warp", outcome: .focusExact, at: now))
        let model = h.controller.activity
        var copied = ""
        model.pasteboardWriter = { copied = $0 }
        await model.load()
        #expect(model.filtered.map(\.kind) == ["focus", "session.blocked"])
        #expect(model.modules == ["agents.sessions", "core"])
        model.moduleFilter = "agents.sessions"
        #expect(model.filtered.map(\.kind) == ["session.blocked"])
        model.moduleFilter = nil
        model.kindFilter = "focus"
        #expect(model.filtered.count == 1)
        let text = await model.copyDay()
        #expect(copied == text)
        #expect(text.contains("session.blocked"))
        #expect(model.summary.focusExact == 1)
        #expect(!ActivityPaneView.summaryText(model.summary).contains("%"))
        await h.tearDown()
    }

    @Test func catalogKeysResolve() async throws {
        let h = try await SettingsHarness()
        for pane in h.controller.panes where !pane.isModule {
            let title = String(localized: pane.title)
            #expect(!title.hasPrefix("settings."), "pane \(pane.id)")
        }
        for setting in CoreSettings.all {
            #expect(!String(localized: setting.descriptor.label).hasPrefix("config."))
            if case .enumeration(let options, _) = setting.descriptor.kind {
                for option in options {
                    let label = SettingsText.option(path: setting.path, value: option)
                    #expect(label != option, "\(setting.path) \(option)")
                }
            }
        }
        let keys = [
            "settings.window.title", "settings.sidebar.modules", "settings.section.privacy",
            "settings.section.virtualNotch", "settings.section.cli", "settings.general.showActivity",
            "settings.appearance.reduceMotion", "settings.module.enabled", "settings.module.status",
            "settings.module.status.disabled", "settings.module.status.running", "settings.module.status.stopped",
            "settings.module.status.errored", "settings.module.status.needsPermission",
            "settings.permission.accessibility", "settings.permission.automation", "settings.permission.calendar",
            "settings.permission.notifications", "settings.permission.screenRecording", "settings.permission.title",
            "settings.permission.sentence", "settings.permission.grant", "settings.permission.openSystemSettings",
            "settings.login.requiresApproval", "settings.login.openSettings", "settings.login.registerFailed",
            "settings.login.unregisterFailed", "settings.cli.current", "settings.cli.missing", "settings.cli.stale",
            "settings.cli.conflict", "settings.cli.bundledMissing", "settings.cli.pathHint",
            "settings.hotkey.conflict", "settings.hotkey.invalid", "settings.error.hotkey",
            "settings.activity.module", "settings.activity.kind", "settings.activity.all", "settings.activity.day",
            "settings.activity.summary", "settings.activity.summary.format", "settings.activity.copy",
            "settings.activity.entries", "settings.activity.empty",
        ]
        for key in keys { #expect(SettingsText.string(key) != key, "\(key)") }
        await h.tearDown()
    }

    /// Renders the General and a module pane offscreen; with `VIGIE_SETTINGS_SNAPSHOT_DIR` set, writes PNGs there.
    @Test func panesRenderOffscreen() async throws {
        let h = try await SettingsHarness()
        h.controller.additionalHomeProviders = {
            [
                HomeProviderDescriptor(id: "script.site", name: "vigie.app"),
                HomeProviderDescriptor(id: "x", name: "Other"),
            ]
        }
        await h.controller.home.setOn("x", true)
        h.controller.privacy = CorePrivacyService()
        h.controller.open(pane: "general")
        let window = try #require(h.controller.window)
        for pane in ["general", "custom.test", "calendar.test", "display", "activity", "home"] {
            h.controller.selectedPaneID = pane
            try await Task.sleep(for: .milliseconds(300))
            let view = try #require(window.contentView)
            view.layoutSubtreeIfNeeded()
            let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            #expect(rep.pixelsWide > 0)
            if let dir = ProcessInfo.processInfo.environment["VIGIE_SETTINGS_SNAPSHOT_DIR"],
                let png = rep.representation(using: .png, properties: [:])
            {
                try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("settings-\(pane).png"))
            }
        }
        // The window's sidebar is a glass view that `cacheDisplay` cannot capture; render the list alone.
        let (host, sidebar) = hostOffscreen(
            SettingsSidebar(controller: h.controller),
            size: CGSize(width: SettingsWindowMetrics.sidebarWidth, height: SettingsWindowMetrics.size.height))
        sidebar.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        defer { host.close() }
        let rep = try #require(sidebar.bitmapImageRepForCachingDisplay(in: sidebar.bounds))
        sidebar.cacheDisplay(in: sidebar.bounds, to: rep)
        if let dir = ProcessInfo.processInfo.environment["VIGIE_SETTINGS_SNAPSHOT_DIR"],
            let png = rep.representation(using: .png, properties: [:])
        {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("settings-sidebar.png"))
        }
        await h.tearDown()
    }
}
