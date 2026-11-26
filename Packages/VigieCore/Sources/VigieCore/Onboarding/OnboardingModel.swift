import Foundation
import ModuleKit
import OSLog
import Observation
import VigieUI

/// One entry of the onboarding sequence (Story 17.1, UX-DR75).
public enum OnboardingStepKind: Hashable, Sendable {
    case theme
    /// Composed by App assembly (AD-4): the detected agent CLIs and their hook diffs.
    case agents
    case accessibility
    case displays
    /// A step a running module contributed through ModuleKit.
    case contributed(String)
    case sounds
    case launchAtLogin

    public var id: String {
        switch self {
        case .theme: "theme"
        case .agents: "agents"
        case .accessibility: "accessibility"
        case .displays: "displays"
        case .contributed(let id): id
        case .sounds: "sounds"
        case .launchAtLogin: "launchAtLogin"
        }
    }
}

/// How a step ended.
public enum OnboardingOutcome: Equatable, Sendable {
    case continued
    case skipped
}

/// The state of the first-launch onboarding (Story 17.1, FR94, AD-4, AD-21, AD-22).
///
/// Steps in order: theme, agents, Accessibility, displays, contributed steps, sounds, launch at login. Each one
/// ends with Continue or Skip. Nothing is written until ``finish()``, which runs when the last step ends or the
/// window closes early: a step that was continued is applied, a step that was not reached counts as skipped.
/// On the first run a skipped theme means Chrome Hologram, a skipped sounds step means `[sounds] enabled = false`
/// (A31) and a skipped display step records the one-time display prompt as answered (A60). When setup runs again
/// from Settings, a skipped step changes nothing. The end sets `[onboarding] complete` in `local.toml`.
@MainActor @Observable
public final class OnboardingModel {
    /// The steps, in order.
    public let steps: [OnboardingStepKind]
    /// The steps that come from outside this file (agents, contributed), by id.
    public let externalSteps: [String: OnboardingStep]
    public private(set) var currentIndex = 0
    public private(set) var outcomes: [String: OnboardingOutcome] = [:]
    public private(set) var isFinished = false

    // Choices, applied by `finish()` for the steps that were continued.
    public var themeChoice: String
    public var soundsEnabled = true
    public var launchAtLogin = true
    public var displayChoice: DisplaySelection = .notched

    /// Last known Accessibility status (nil before the first check).
    public private(set) var accessibilityStatus: PermissionStatus?
    /// The first run decides what a skip means.
    public let isFirstRun: Bool

    @ObservationIgnored public let themes: ThemeController
    @ObservationIgnored private let configStore: ConfigStore
    @ObservationIgnored private let permissions: PermissionsCoordinator
    @ObservationIgnored private let displayPrompt: DisplayPromptRecord
    @ObservationIgnored private let setLaunchAtLogin: @MainActor (Bool) async -> Void
    @ObservationIgnored private let displaysProvider: @MainActor () -> [DisplayInfo]
    @ObservationIgnored let openURL: @MainActor (URL) -> Void
    /// The theme variant in effect when the sequence opened, restored when the theme step is not continued.
    @ObservationIgnored private let initialTheme: String
    @ObservationIgnored private var onFinish: @MainActor () -> Void
    @ObservationIgnored private let log: Logger

    /// The two looks the theme step previews (UX-DR75).
    public static let themeChoices = [ThemeLibrary.defaultVariantID, "twin-metal-tactical"]

    /// - Parameters:
    ///   - agents: the agents step App assembly composed, nil to leave it out (no agent module running).
    ///   - contributed: steps from running modules.
    ///   - setLaunchAtLogin: registers or unregisters the login item (`SettingsController.setLaunchAtLogin`).
    ///   - onFinish: called once after the end has been applied (the window closes).
    public init(
        configStore: ConfigStore,
        permissions: PermissionsCoordinator,
        themes: ThemeController,
        displayPrompt: DisplayPromptRecord,
        isFirstRun: Bool,
        agents: OnboardingStep? = nil,
        contributed: [OnboardingStep] = [],
        setLaunchAtLogin: @escaping @MainActor (Bool) async -> Void,
        displays: @escaping @MainActor () -> [DisplayInfo] = { DisplayInfo.current() },
        openURL: @escaping @MainActor (URL) -> Void = { _ in },
        onFinish: @escaping @MainActor () -> Void = {},
        log: Logger = Logger(subsystem: "fr.baguettelabs.vigie", category: "onboarding")
    ) {
        var kinds: [OnboardingStepKind] = [.theme]
        var external: [String: OnboardingStep] = [:]
        if let agents {
            kinds.append(.agents)
            external[OnboardingStepKind.agents.id] = agents
        }
        kinds += [.accessibility, .displays]
        let reserved: Set<String> = ["theme", "agents", "accessibility", "displays", "sounds", "launchAtLogin"]
        for step in contributed where external[step.id] == nil && !reserved.contains(step.id) {
            kinds.append(.contributed(step.id))
            external[step.id] = step
        }
        kinds += [.sounds, .launchAtLogin]
        steps = kinds
        externalSteps = external
        self.configStore = configStore
        self.permissions = permissions
        self.themes = themes
        self.displayPrompt = displayPrompt
        self.isFirstRun = isFirstRun
        self.setLaunchAtLogin = setLaunchAtLogin
        self.displaysProvider = displays
        self.openURL = openURL
        self.onFinish = onFinish
        self.log = log
        initialTheme = themes.variantID
        themeChoice = isFirstRun ? ThemeLibrary.defaultVariantID : themes.variantID
    }

    // MARK: - Navigation

    public var currentStep: OnboardingStepKind { steps[currentIndex] }
    public var isLastStep: Bool { currentIndex == steps.count - 1 }
    public var canGoBack: Bool { currentIndex > 0 && !isFinished }

    /// Continue: keeps the step's choice and moves on; on the last step it finishes.
    public func continueStep() async {
        await end(.continued)
    }

    /// Skip: leaves the step's choice out and moves on; on the last step it finishes.
    public func skipStep() async {
        await end(.skipped)
    }

    public func back() {
        guard canGoBack else { return }
        currentIndex -= 1
    }

    private func end(_ outcome: OnboardingOutcome) async {
        guard !isFinished else { return }
        outcomes[currentStep.id] = outcome
        if currentStep == .theme, outcome == .skipped {
            themes.variantID = isFirstRun ? ThemeLibrary.defaultVariantID : initialTheme
        }
        if isLastStep {
            await finish()
        } else {
            currentIndex += 1
        }
    }

    // MARK: - Theme (live preview)

    /// Picks a look: the notch and every Vigie panel show it now. Written to `[appearance] theme` at the end.
    public func previewTheme(_ id: String) {
        guard Self.themeChoices.contains(id) else { return }
        themeChoice = id
        themes.variantID = id
    }

    // MARK: - Accessibility

    public func refreshAccessibility() async {
        accessibilityStatus = await permissions.status(of: .accessibility)
    }

    /// Asks macOS for Accessibility (its own dialog), then re-reads the status.
    public func requestAccessibility() async {
        accessibilityStatus = await permissions.request(.accessibility)
    }

    public func openAccessibilitySettings() {
        openURL(SettingsController.systemSettingsURL(for: .accessibility))
    }

    // MARK: - Displays

    /// Connected displays, for the display step.
    public var displays: [DisplayInfo] { displaysProvider() }

    /// True when some connected display has no notch, so Vigie can draw a virtual one there.
    public var hasPlainDisplay: Bool { displays.contains { $0.kind.usesVirtualNotch } }

    // MARK: - End

    /// Applies the sequence and records it as done. Runs once; later calls do nothing.
    public func finish() async {
        guard !isFinished else { return }
        isFinished = true
        await applyTheme()
        await applySounds()
        await applyDisplays()
        await applyLaunchAtLogin()
        await write(CoreSettings.path("onboarding", "complete"), .bool(true))
        log.info("onboarding finished")
        onFinish()
    }

    private func outcome(of kind: OnboardingStepKind) -> OnboardingOutcome {
        outcomes[kind.id] ?? .skipped
    }

    private func applyTheme() async {
        let path = CoreSettings.path("appearance", "theme")
        if outcome(of: .theme) == .continued {
            themes.variantID = themeChoice
            await write(path, .string(themeChoice))
        } else if isFirstRun {
            themes.variantID = ThemeLibrary.defaultVariantID
            await write(path, .string(ThemeLibrary.defaultVariantID))
        } else {
            themes.variantID = initialTheme
        }
    }

    private func applySounds() async {
        let path = CoreSettings.path("sounds", "enabled")
        if outcome(of: .sounds) == .continued {
            await write(path, .bool(soundsEnabled))
        } else if isFirstRun {
            // A31: the sounds step skipped means sounds off.
            await write(path, .bool(false))
        }
    }

    private func applyDisplays() async {
        let answer: DisplayPromptAnswer? =
            switch outcome(of: .displays) {
            case .continued: .choose(displayChoice)
            case .skipped: isFirstRun ? .dismissed : nil
            }
        guard let answer else { return }
        do {
            try await answer.apply(store: configStore, record: displayPrompt)
        } catch {
            log.error("onboarding display answer not written: \(String(describing: error), privacy: .public)")
        }
    }

    private func applyLaunchAtLogin() async {
        guard outcome(of: .launchAtLogin) == .continued else { return }
        await setLaunchAtLogin(launchAtLogin)
    }

    private func write(_ path: ConfigKeyPath, _ value: ConfigResolvedValue) async {
        do {
            try await configStore.set(path, to: value)
        } catch {
            log.error(
                "onboarding: \(path.description, privacy: .public) not written: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
