import AppKit
import ModuleKit
import OSLog
import SwiftUI
import VigieUI

/// Opens the first-launch onboarding window (Story 17.1, FR94, UX-DR75, UX-DR39) and keeps the sequence's state.
///
/// A regular, manually managed `NSWindow` in the system appearance, like Settings: Vigie stays `.accessory` and
/// never shows a Dock icon (AD-21). Closing the window before the end counts as skipping every step left.
/// The App sets ``setLaunchAtLogin`` and the two step providers; agent steps are composed there (AD-4).
@MainActor @Observable
public final class OnboardingController {
    /// The open sequence; nil while the window is closed.
    public private(set) var model: OnboardingModel?
    @ObservationIgnored public private(set) var window: NSWindow?
    @ObservationIgnored private var windowObserver: OnboardingWindowObserver?

    @ObservationIgnored private let configStore: ConfigStore
    @ObservationIgnored private let permissions: PermissionsCoordinator
    @ObservationIgnored private let themes: ThemeController
    @ObservationIgnored private let displayPrompt: DisplayPromptRecord
    /// The agents step, composed by App assembly from the agent module and its adapters (AD-4).
    @ObservationIgnored private let agentsStep: @MainActor () -> OnboardingStep?
    /// Steps running modules contribute (`NotchModule.onboardingSteps()`).
    @ObservationIgnored private let contributedSteps: @MainActor () -> [OnboardingStep]
    @ObservationIgnored private let setLaunchAtLogin: @MainActor (Bool) async -> Void
    /// Brings Vigie forward; called only from `present()`, which is a launch or a user action.
    @ObservationIgnored var activateApp: @MainActor () -> Void = { NSApp.activate(ignoringOtherApps: true) }
    @ObservationIgnored var openURL: @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }

    public init(
        configStore: ConfigStore,
        permissions: PermissionsCoordinator,
        themes: ThemeController,
        displayPrompt: DisplayPromptRecord,
        agentsStep: @escaping @MainActor () -> OnboardingStep? = { nil },
        contributedSteps: @escaping @MainActor () -> [OnboardingStep] = { [] },
        setLaunchAtLogin: @escaping @MainActor (Bool) async -> Void
    ) {
        self.configStore = configStore
        self.permissions = permissions
        self.themes = themes
        self.displayPrompt = displayPrompt
        self.agentsStep = agentsStep
        self.contributedSteps = contributedSteps
        self.setLaunchAtLogin = setLaunchAtLogin
    }

    /// True until onboarding was completed or skipped once on this Mac (`[onboarding] complete` in `local.toml`).
    public var isPending: Bool {
        configStore.value(CoreSettings.path("onboarding", "complete"), as: Bool.self) != true
    }

    public var isOpen: Bool { window?.isVisible ?? false }

    /// First launch: opens the window when onboarding was never completed or skipped. Returns whether it opened.
    @discardableResult
    public func presentIfNeeded() -> Bool {
        guard isPending else { return false }
        present()
        return true
    }

    /// Opens the sequence (Settings › General › Run setup again), or brings the open one forward.
    public func present() {
        if model == nil || model?.isFinished == true { model = makeModel() }
        guard let model else { return }
        let window = window ?? makeWindow(model)
        activateApp()
        window.makeKeyAndOrderFront(nil)
    }

    func makeModel() -> OnboardingModel {
        OnboardingModel(
            configStore: configStore, permissions: permissions, themes: themes, displayPrompt: displayPrompt,
            isFirstRun: isPending, agents: agentsStep(), contributed: contributedSteps(),
            setLaunchAtLogin: setLaunchAtLogin, openURL: openURL,
            onFinish: { [weak self] in self?.closeWindow() })
    }

    private func makeWindow(_ model: OnboardingModel) -> NSWindow {
        let window = SettingsWindow(
            contentRect: NSRect(origin: .zero, size: OnboardingMetrics.windowSize),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = OnboardingText.string("onboarding.window.title")
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        let hosting = NSHostingController(rootView: OnboardingRootView(model: model))
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(OnboardingMetrics.windowSize)
        window.center()
        let observer = OnboardingWindowObserver { [weak self] in self?.windowWillClose() }
        window.delegate = observer
        windowObserver = observer
        self.window = window
        return window
    }

    /// The window was closed by hand: the steps not reached count as skipped.
    private func windowWillClose() {
        guard let model, !model.isFinished else { return }
        Task { await model.finish() }
    }

    private func closeWindow() {
        window?.close()
        window = nil
        windowObserver = nil
    }
}

/// Reports the close of the onboarding window.
final class OnboardingWindowObserver: NSObject, NSWindowDelegate {
    private let onClose: @MainActor () -> Void

    init(onClose: @escaping @MainActor () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { onClose() }
    }
}
