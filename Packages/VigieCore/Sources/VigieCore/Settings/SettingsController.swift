import AppKit
import ModuleKit
import Observation
import SwiftUI
import VigieUI

/// What a module pane shows when its module waits for a permission (FR2, UX "Setup card").
public struct PermissionPrompt: Equatable, Sendable {
    public let permission: Permission
    /// Last known status (nil before the first check).
    public let status: PermissionStatus?
    /// The System Settings deep link for the permission.
    public let systemSettingsURL: URL

    /// `Grant` is offered only while macOS has not asked yet.
    public var canGrant: Bool { status == .notDetermined }
}

/// The generated Settings window (Story 2.14; FR5, FR93, UX-DR39, UX-DR74, AD-8, AD-21).
///
/// A regular, manually managed `NSWindow` hosting SwiftUI, in the system appearance (not the island look).
/// Opening it never changes the activation policy: Vigie stays `.accessory` and never shows a Dock icon
/// (AD-21). Every control writes through `ConfigStore` (AD-8) and re-renders on `ConfigStore.revision`, so an
/// outside edit of `config.toml` / `local.toml` updates the open window live.
///
/// Callers: the closed-notch context menu (`Settings…`), the expanded view's gear, `⌘,` while the expanded
/// view is key, setup-problem alerts and empty states, all through `open(pane:)`.
@MainActor @Observable
public final class SettingsController {
    /// Sidebar entries: the core panes, then one per module (pane id = module id).
    public private(set) var panes: [SettingsPane]
    /// The pane shown in the detail column.
    public var selectedPaneID: String = "general"
    /// Real login-item state, re-read on window activation and after a change.
    public private(set) var loginItemStatus: LoginItemStatus
    /// Inline error of the last `Launch at login` change.
    public private(set) var loginItemError: String?
    /// `CLIInstaller.diagnose()` result (nil without an installer or before the first refresh).
    public private(set) var cliStatus: CLIInstallStatus?
    public private(set) var cliPathHint: CLIPathHint?
    /// Activity log pane state (A80).
    public let activity: ActivityPaneModel
    /// Settings › Sounds state (Story 10.2). The App sets `sounds.player` to the alert sound player.
    public let sounds: SoundsPaneModel
    /// Privacy mode (Story 21.2): the window's views read `privacyActive` (reveal controls are unavailable while
    /// it is on). The App sets it before the window opens.
    public var privacy: CorePrivacyService?
    /// Settings › Home state (Story 11.1).
    public let home: HomePaneModel
    /// Home card providers that are not modules (scripts with the `home` surface, Epic 12); listed after the
    /// modules in Settings › Home.
    @ObservationIgnored public var additionalHomeProviders: @MainActor () -> [HomeProviderDescriptor] = { [] }

    @ObservationIgnored public let configStore: ConfigStore
    @ObservationIgnored public let registry: ModuleRegistry
    @ObservationIgnored public let permissions: PermissionsCoordinator
    @ObservationIgnored public let hotkeyCenter: HotkeyCenter
    @ObservationIgnored public let cliInstaller: CLIInstaller?
    @ObservationIgnored public let manifests: [ModuleManifest]
    @ObservationIgnored public let loginItem: any LoginItemControlling
    /// Backs `secret` rows (owner = module id, key = setting key); nil shows them disabled.
    @ObservationIgnored public let secretStore: KeychainSecretStore?
    @ObservationIgnored private let loginShellPath: (@Sendable () async -> String?)?
    @ObservationIgnored let services: SettingControlServices
    @ObservationIgnored public private(set) var window: NSWindow?
    @ObservationIgnored private var windowObserver: SettingsWindowObserver?
    /// Opens System Settings deep links (tests record them).
    @ObservationIgnored var openURL: @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// Brings Vigie forward; called only from `open(pane:)`, which is always a user action.
    @ObservationIgnored var activateApp: @MainActor () -> Void = { NSApp.activate(ignoringOtherApps: true) }

    /// - Parameters:
    ///   - manifests: modules that get a pane, in sidebar order (usually `registry.descriptors.map(\.manifest)`).
    ///   - loginShellPath: the login shell's `PATH` for the CLI hint (nil = no hint, never a false alarm).
    ///   - secretStore: the launch's secret store, for `secret` settings (AD-9); never ConfigStore.
    public init(
        configStore: ConfigStore,
        registry: ModuleRegistry,
        permissions: PermissionsCoordinator,
        hotkeyCenter: HotkeyCenter,
        activityStore: ActivityStore,
        cliInstaller: CLIInstaller?,
        manifests: [ModuleManifest],
        loginItem: any LoginItemControlling = SMAppServiceLoginItem(),
        loginShellPath: (@Sendable () async -> String?)? = nil,
        secretStore: KeychainSecretStore? = nil
    ) {
        self.configStore = configStore
        self.registry = registry
        self.permissions = permissions
        self.hotkeyCenter = hotkeyCenter
        self.cliInstaller = cliInstaller
        self.manifests = manifests
        self.loginItem = loginItem
        self.loginShellPath = loginShellPath
        self.secretStore = secretStore
        self.activity = ActivityPaneModel(store: activityStore)
        sounds = SoundsPaneModel(configStore: configStore)
        var extraHomeProviders: (@MainActor () -> [HomeProviderDescriptor])?
        home = HomePaneModel(configStore: configStore) {
            Self.moduleHomeProviders(registry) + (extraHomeProviders?() ?? [])
        }
        services = CoreSettingServices.make()
        loginItemStatus = loginItem.status
        for manifest in manifests { configStore.register(manifest: manifest) }
        panes = SettingsPaneCatalog.corePanes() + manifests.map(SettingsPaneCatalog.modulePane)
        extraHomeProviders = { [weak self] in self?.additionalHomeProviders() ?? [] }
    }

    /// Running modules that offer a `homeCard()`, in registry order (Settings › Home).
    static func moduleHomeProviders(_ registry: ModuleRegistry) -> [HomeProviderDescriptor] {
        _ = registry.statuses  // module starts and stops
        return registry.runningModules.compactMap { module in
            guard module.homeCard() != nil else { return nil }
            return HomeProviderDescriptor(
                id: module.manifest.id.rawValue, name: String(localized: module.manifest.name))
        }
    }

    // MARK: - Window

    /// Opens Settings (creating the window once), selects `pane` when given, makes the window key and brings
    /// Vigie forward. Unknown pane ids fall back to General. The activation policy is never touched.
    public func open(pane: String? = nil) {
        if let pane { selectedPaneID = resolvePane(pane) }
        let window = window ?? makeWindow()
        activateApp()
        window.makeKeyAndOrderFront(nil)
        Task { await refresh() }
    }

    /// Closes the window (it is kept for the next `open`).
    public func close() {
        window?.performClose(nil)
    }

    public var isOpen: Bool { window?.isVisible ?? false }

    private func makeWindow() -> NSWindow {
        let window = SettingsWindow(
            contentRect: NSRect(origin: .zero, size: SettingsWindowMetrics.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = SettingsText.string("settings.window.title")
        window.isReleasedWhenClosed = false
        window.minSize = SettingsWindowMetrics.minSize
        window.collectionBehavior.insert(.moveToActiveSpace)
        let root = PrivacyScope(privacy: privacy) { SettingsRootView(controller: self) }
            .environment(\.settingControlServices, services)
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(SettingsWindowMetrics.size)
        window.center()
        let observer = SettingsWindowObserver { [weak self] in
            Task { await self?.refresh() }
        }
        window.delegate = observer
        windowObserver = observer
        self.window = window
        return window
    }

    // MARK: - Panes

    /// The pane id `id` names: itself, an alias (`privacy` → `general`), or `general` when unknown.
    public func resolvePane(_ id: String) -> String {
        if panes.contains(where: { $0.id == id }) { return id }
        if let alias = SettingsPaneCatalog.aliases[id] { return alias }
        return "general"
    }

    public func pane(_ id: String) -> SettingsPane? {
        panes.first { $0.id == id }
    }

    public var selectedPane: SettingsPane {
        pane(selectedPaneID) ?? panes[0]
    }

    // MARK: - Rows

    /// The generated row for a known key; nil when ConfigStore does not know it. A module's `secret` row reads
    /// and writes through ``secretStore`` only; its config binding holds nothing and refuses writes.
    public func rowModel(for path: ConfigKeyPath) -> SettingRowModel? {
        guard let entry = configStore.schema.entries[path] else { return nil }
        if case .secret = entry.descriptor.kind {
            return SettingRowModel(
                id: path.description, label: entry.descriptor.label, help: entry.descriptor.help,
                kind: entry.descriptor.kind,
                binding: SettingBinding(
                    get: { nil }, set: { _ in throw SettingWriteError(.secretKey(path.description)) }),
                secret: entry.moduleID.flatMap { secretBinding(owner: $0.rawValue, key: entry.descriptor.key) })
        }
        let isEnabledKey = entry.moduleID != nil && path == ConfigKeyPath.moduleEnabled(entry.moduleID!)
        let label = isEnabledKey ? SettingsText.resource("settings.module.enabled") : entry.descriptor.label
        return SettingRowModel(
            id: path.description,
            label: label,
            help: entry.descriptor.help ?? hotkeyHelp(for: path, entry: entry),
            kind: entry.descriptor.kind,
            binding: configStore.settingBinding(for: path),
            optionLabel: { SettingsText.option(path: path, value: $0) })
    }

    /// The Keychain binding of a module's `secret` setting; nil without a store.
    func secretBinding(owner: String, key: String) -> SecretSettingBinding? {
        guard let secretStore else { return nil }
        return SecretSettingBinding(
            isSet: {
                do throws(SecretStoreError) {
                    return try await secretStore.exists(owner: owner, key: key)
                } catch {
                    throw SecretWriteError(error)
                }
            },
            set: { value in
                do throws(SecretStoreError) {
                    if let value {
                        try await secretStore.set(value, owner: owner, key: key)
                    } else {
                        do throws(SecretStoreError) {
                            try await secretStore.remove(owner: owner, key: key)
                        } catch .notFound {
                            // Already clear.
                        }
                    }
                } catch {
                    throw SecretWriteError(error)
                }
            })
    }

    /// Rows of a module pane: its descriptors, in manifest order.
    public func moduleRows(_ manifest: ModuleManifest) -> [SettingRowModel] {
        manifest.settings.compactMap { descriptor in
            rowModel(for: .module(manifest.id, descriptor.key, scope: descriptor.scope))
        }
    }

    /// The hotkey name `HotkeyConfigBridge` maps to `path` (`core.expand`, `<module id>.<key>`).
    private func hotkeyHelp(for path: ConfigKeyPath, entry: ConfigSchemaEntry) -> LocalizedStringResource? {
        guard case .hotkey = entry.descriptor.kind else { return nil }
        let name: String
        if let id = entry.moduleID {
            name = "\(id.rawValue).\(entry.descriptor.key)"
        } else if path == CoreSettings.path("general", "expand_hotkey") {
            name = CoreHotkeys.expandName
        } else {
            return nil
        }
        guard let problem = hotkeyCenter.problems.first(where: { $0.name == name }) else { return nil }
        switch problem.kind {
        case .conflict: return SettingsText.resource("settings.hotkey.conflict")
        case .invalid: return SettingsText.resource("settings.hotkey.invalid")
        }
    }

    // MARK: - Privacy mode (Story 21.3)

    /// True when a detector exists, so `Automatic (when sharing or recording)` can be turned on.
    public var privacyDetectionAvailable: Bool { privacy?.detector.isAvailable ?? false }

    /// The permission the detector needs but macOS denied, while automatic detection is on; nil otherwise.
    public var privacyDeniedPermission: Permission? {
        guard let permission = privacy?.detector.requiredPermission,
            configStore.value(CoreSettings.path("privacy", "auto"), as: Bool.self) == true,
            permissions.statuses[permission] == .denied
        else { return nil }
        return permission
    }

    // MARK: - Modules

    public func moduleStatus(_ id: ModuleID) -> ModuleStatus {
        registry.status(of: id)
    }

    /// The module's own settings view, shown below the generated rows (only while it runs).
    public func customSettingsView(_ id: ModuleID) -> AnyView? {
        registry.module(id)?.settingsView()
    }

    /// The permission block of a module pane, when the module waits for a permission.
    public func permissionPrompt(for id: ModuleID) -> PermissionPrompt? {
        guard case .needsPermission(let permission) = registry.status(of: id) else { return nil }
        return PermissionPrompt(
            permission: permission, status: permissions.statuses[permission],
            systemSettingsURL: Self.systemSettingsURL(for: permission))
    }

    /// Asks macOS for the permission (only offered while undetermined), then lets waiting modules re-check.
    public func grant(_ permission: Permission) async {
        _ = await permissions.request(permission)
        await permissions.recheckIfWaiting()
    }

    public func openSystemSettings(for permission: Permission) {
        openURL(Self.systemSettingsURL(for: permission))
    }

    /// System Settings deep links: Privacy & Security panes, and the Notifications pane (notification
    /// permission is not a Privacy & Security entry).
    public static func systemSettingsURL(for permission: Permission) -> URL {
        if permission == .notifications {
            return URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
        }
        let anchor =
            switch permission {
            case .accessibility: "Privacy_Accessibility"
            case .automation: "Privacy_Automation"
            case .calendar: "Privacy_Calendars"
            case .notifications: "Privacy_Notifications"  // unreachable, handled above
            case .screenRecording: "Privacy_ScreenCapture"
            }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }

    // MARK: - General extras

    /// Re-reads everything the system can change behind Vigie's back: login item, CLI link, permissions.
    public func refresh() async {
        refreshLoginItem()
        await refreshCLI()
        for permission in Set(manifests.flatMap(\.permissions)) {
            _ = await permissions.status(of: permission)
        }
    }

    /// Reads the real login-item state and keeps `[general] launch_at_login` (local) in step with it, so a
    /// change made in System Settings › Login Items shows in the toggle and the file.
    public func refreshLoginItem() {
        let status = loginItem.status
        if status != loginItemStatus { loginItemStatus = status }
        syncLaunchAtLoginKey()
    }

    /// `Launch at login` toggle: registers or unregisters `SMAppService.mainApp`, then mirrors the real state.
    public func setLaunchAtLogin(_ on: Bool) async {
        do {
            if on { try loginItem.register() } else { try loginItem.unregister() }
            loginItemError = nil
        } catch {
            loginItemError = SettingsText.string(
                on ? "settings.login.registerFailed" : "settings.login.unregisterFailed")
        }
        refreshLoginItem()
    }

    public func openLoginItemsSettings() {
        loginItem.openSystemSettings()
    }

    private func syncLaunchAtLoginKey() {
        let path = CoreSettings.path("general", "launch_at_login")
        let isOn = loginItemStatus.isOn
        guard configStore.value(path, as: Bool.self) != isOn else { return }
        Task { try? await configStore.set(path, to: .bool(isOn)) }
    }

    private func refreshCLI() async {
        guard let cliInstaller else { return }
        let status = await cliInstaller.diagnose()
        let path = await loginShellPath?()
        cliStatus = status
        cliPathHint = cliInstaller.pathHint(loginShellPath: path)
    }
}

/// Window size (SPEC §10.1: a regular macOS window).
enum SettingsWindowMetrics {
    static let size = NSSize(width: 760, height: 520)
    static let minSize = NSSize(width: 640, height: 400)
    static let sidebarWidth: CGFloat = 200
    static let sidebarMinWidth: CGFloat = 170
}

/// Refreshes on activation (System Settings may have changed the login item or a permission meanwhile).
final class SettingsWindowObserver: NSObject, NSWindowDelegate {
    private let onBecomeKey: @MainActor () -> Void

    init(onBecomeKey: @escaping @MainActor () -> Void) {
        self.onBecomeKey = onBecomeKey
    }

    func windowDidBecomeKey(_ notification: Notification) {
        MainActor.assumeIsolated { onBecomeKey() }
    }
}

/// The Settings window. Vigie is an accessory app without a main menu, so the standard window and editing
/// shortcuts are handled here: `⌘W` closes, `⌘X` / `⌘C` / `⌘V` / `⌘A` / `⌘Z` / `⇧⌘Z` reach the text fields.
final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([
            .capsLock, .numericPad, .function,
        ])
        guard flags == .command || flags == [.command, .shift],
            let key = event.charactersIgnoringModifiers?.lowercased()
        else { return false }
        let action: Selector?
        switch (key, flags == .command) {
        case ("w", true): action = #selector(NSWindow.performClose(_:))
        case ("x", true): action = #selector(NSText.cut(_:))
        case ("c", true): action = #selector(NSText.copy(_:))
        case ("v", true): action = #selector(NSText.paste(_:))
        case ("a", true): action = #selector(NSResponder.selectAll(_:))
        case ("z", true): action = Selector(("undo:"))
        case ("z", false): action = Selector(("redo:"))
        default: action = nil
        }
        guard let action else { return false }
        if action == #selector(NSWindow.performClose(_:)) {
            performClose(nil)
            return true
        }
        return NSApp.sendAction(action, to: nil, from: self)
    }
}
