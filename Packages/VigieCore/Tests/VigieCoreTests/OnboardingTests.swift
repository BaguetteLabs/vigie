import Foundation
import ModuleKit
import SwiftUI
import Testing
import VigieUI

@testable import VigieCore

@MainActor
final class LoginRecorder {
    var calls: [Bool] = []
}

@MainActor
struct OnboardingHarness {
    let fixture = ConfigFixture()
    let store: ConfigStore
    let checker = FakePermissionChecker()
    let coordinator: PermissionsCoordinator
    let themes: ThemeController
    let suite = "vigie.tests.onboarding.\(UUID().uuidString)"
    let record: DisplayPromptRecord
    let login = LoginRecorder()
    let opened = URLRecorderBox()

    @MainActor final class URLRecorderBox {
        var urls: [URL] = []
    }

    init(config: String? = nil, local: String? = nil) async throws {
        (store, _) = try await fixture.makeStore(config: config, local: local)
        let (stream, _) = AsyncStream.makeStream(of: Void.self)
        coordinator = PermissionsCoordinator(checker: checker, activationNotifications: stream)
        themes = ThemeController(library: try ThemeLoader.loadBundled())
        record = DisplayPromptRecord(suiteName: suite)
    }

    func cleanUp() { UserDefaults().removePersistentDomain(forName: suite) }

    func model(
        firstRun: Bool = true, agents: OnboardingStep? = nil, contributed: [OnboardingStep] = [],
        displays: [DisplayInfo] = []
    ) -> OnboardingModel {
        let login = login
        let opened = opened
        return OnboardingModel(
            configStore: store, permissions: coordinator, themes: themes, displayPrompt: record,
            isFirstRun: firstRun, agents: agents, contributed: contributed,
            setLaunchAtLogin: { login.calls.append($0) }, displays: { displays },
            openURL: { opened.urls.append($0) })
    }

    func controller(
        agents: OnboardingStep? = nil, contributed: [OnboardingStep] = []
    ) -> OnboardingController {
        let login = login
        return OnboardingController(
            configStore: store, permissions: coordinator, themes: themes, displayPrompt: record,
            agentsStep: { agents }, contributedSteps: { contributed },
            setLaunchAtLogin: { login.calls.append($0) })
    }

    var soundsEnabled: Bool? { store.value(CoreSettings.path("sounds", "enabled"), as: Bool.self) }
    var themeSetting: String? { store.value(CoreSettings.path("appearance", "theme"), as: String.self) }
    var complete: Bool? { store.value(CoreSettings.path("onboarding", "complete"), as: Bool.self) }
    var displaySetting: String? { store.value(CoreSettings.path("display", "display"), as: String.self) }
}

let agentsTestStep = OnboardingStep.agents { AnyView(Text(verbatim: "agents")) }

private func plainDisplay(_ name: String, id: CGDirectDisplayID) -> DisplayInfo {
    DisplayInfo(
        id: id, name: name, kind: .plain, isMain: false, isBuiltIn: false,
        metrics: ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), safeAreaTop: 0, auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil))
}

@MainActor @Suite struct OnboardingTests {
    // MARK: Sequence

    @Test func stepsRunInTheStoryOrder() async throws {
        let h = try await OnboardingHarness()
        defer { h.cleanUp() }
        #expect(
            h.model(agents: agentsTestStep).steps == [
                .theme, .agents, .accessibility, .displays, .sounds, .launchAtLogin,
            ])
    }

    @Test func theAgentsStepIsLeftOutWhenNoAgentModuleRuns() async throws {
        let h = try await OnboardingHarness()
        defer { h.cleanUp() }
        #expect(h.model().steps == [.theme, .accessibility, .displays, .sounds, .launchAtLogin])
    }

    @Test func contributedStepsComeBeforeSounds() async throws {
        let h = try await OnboardingHarness()
        defer { h.cleanUp() }
        let extra = OnboardingStep(
            id: "demo.step", title: "Demo", detail: "Detail", content: { AnyView(EmptyView()) })
        let model = h.model(agents: agentsTestStep, contributed: [extra])
        #expect(
            model.steps == [
                .theme, .agents, .accessibility, .displays, .contributed("demo.step"), .sounds, .launchAtLogin,
            ])
        #expect(model.externalSteps["demo.step"] != nil)
    }

    @Test func aContributedStepCannotReplaceACoreStep() async throws {
        let h = try await OnboardingHarness()
        defer { h.cleanUp() }
        let clash = OnboardingStep(id: "sounds", title: "x", detail: "y", content: { AnyView(EmptyView()) })
        #expect(h.model(contributed: [clash]).steps == [.theme, .accessibility, .displays, .sounds, .launchAtLogin])
    }

    @Test func adapterStepsAreComposedByTheAppAndModulesContributeThroughModuleKit() async throws {
        let h = try await OnboardingHarness()
        defer { h.cleanUp() }
        let module = OnboardingContributingModule()
        let controller = h.controller(agents: agentsTestStep, contributed: module.onboardingSteps())
        let model = controller.makeModel()
        #expect(model.externalSteps["agents"] != nil)
        #expect(model.externalSteps["contrib.step"] != nil)
        #expect(model.steps.contains(.agents))
        #expect(model.steps.contains(.contributed("contrib.step")))
    }

    @Test func everyStepHasCatalogText() {
        for kind in [
            OnboardingStepKind.theme, .agents, .accessibility, .displays, .sounds, .launchAtLogin,
        ] {
            for key in ["onboarding.\(kind.id).title", "onboarding.\(kind.id).detail"] {
                #expect(OnboardingText.string(key) != key)
            }
        }
        for key in [
            "onboarding.window.title", "onboarding.progress", "onboarding.back", "onboarding.skip",
            "onboarding.continue", "onboarding.finish", "settings.setup.runAgain",
        ] {
            #expect(OnboardingText.string(key) != key)
        }
        #expect(OnboardingText.format("onboarding.progress", 2, 6) == "Step 2 of 6")
    }

    @Test func navigationMovesAndGoesBack() async throws {
        let h = try await OnboardingHarness()
        defer { h.cleanUp() }
        let model = h.model()
        #expect(model.currentStep == .theme)
        #expect(!model.canGoBack)
        await model.continueStep()
        #expect(model.currentStep == .accessibility)
        #expect(model.canGoBack)
        model.back()
        #expect(model.currentStep == .theme)
    }

    // MARK: Skipping

    @Test func everyStepCanBeSkippedAndEndsTheSequence() async throws {
        let h = try await OnboardingHarness()
        defer { h.cleanUp() }
        let model = h.model(agents: agentsTestStep)
        for _ in model.steps {
            #expect(!model.isFinished)
            await model.skipStep()
        }
        #expect(model.isFinished)
        #expect(model.outcomes.values.allSatisfy { $0 == .skipped })
        #expect(h.complete == true)
    }

    @Test func skippingTheSoundsStepTurnsSoundsOff() async throws {
        let h = try await OnboardingHarness()
        defer { h.cleanUp() }
        #expect(h.soundsEnabled == true)  // the schema default
        let model = h.model()
        for _ in model.steps { await model.skipStep() }
        #expect(h.soundsEnabled == false)
        #expect(try String(contentsOf: h.fixture.configURL, encoding: .utf8).contains("enabled = false"))
    }

    @Test func skippingTheThemeStepKeepsChromeHologram() async throws {
        let h = try await OnboardingHarness()
        defer { h.cleanUp() }
        let model = h.model()
        model.previewTheme("twin-metal-tactical")
        #expect(h.themes.variantID == "twin-metal-tactical")
        await model.skipStep()  // the theme step
        #expect(h.themes.variantID == ThemeLibrary.defaultVariantID)
        for _ in 1..<model.steps.count { await model.skipStep() }
        #expect(h.themeSetting == "chrome-hologram")
    }

    @Test func skippingTheDisplayStepRecordsThePromptAsAnswered() async throws {
        let h = try await OnboardingHarness()
        defer { h.cleanUp() }
        #expect(h.record.isPending)
        let model = h.model()
        for _ in model.steps { await model.skipStep() }
        #expect(!h.record.isPending)
        #expect(h.displaySetting == "notched")  // the default rule stays
    }

    @Test func skippingTheLoginStepDoesNotRegisterTheLoginItem() async throws {
        let h = try await OnboardingHarness()
        defer { h.cleanUp() }
        let model = h.model()
        for _ in model.steps { await model.skipStep() }
        #expect(h.login.calls.isEmpty)
    }

    @Test func closingTheWindowEarlySkipsTheStepsNotReached() async throws {
        let h = try await OnboardingHarness()
        defer { h.cleanUp() }
        let model = h.model()
        model.previewTheme("twin-metal-tactical")
        await model.continueStep()  // theme kept
        await model.finish()  // the window was closed here
        #expect(model.isFinished)
        #expect(h.themeSetting == "twin-metal-tactical")
        #expect(h.soundsEnabled == false)
        #expect(h.complete == true)
        #expect(h.login.calls.isEmpty)
    }

    // MARK: Choices

    @Test func continuedChoicesAreApplied() async throws {
        let h = try await OnboardingHarness()
        defer { h.cleanUp() }
        let model = h.model(displays: [plainDisplay("Studio Display", id: 2)])
        model.previewTheme("twin-metal-tactical")
        await model.continueStep()  // theme
        await model.continueStep()  // accessibility
        model.displayChoice = .named("Studio Display")
        await model.continueStep()  // displays
        model.soundsEnabled = true
        await model.continueStep()  // sounds
        #expect(model.launchAtLogin)  // preselected on
        await model.continueStep()  // launch at login: the last step
        #expect(model.isFinished)
        #expect(h.themeSetting == "twin-metal-tactical")
        #expect(h.soundsEnabled == true)
        #expect(h.displaySetting == "Studio Display")
        #expect(!h.record.isPending)
        #expect(h.login.calls == [true])
        #expect(h.complete == true)
    }

    @Test func soundsCanBeContinuedOff() async throws {
        let h = try await OnboardingHarness()
        defer { h.cleanUp() }
        let model = h.model()
        await model.skipStep()
        await model.skipStep()
        await model.skipStep()
        model.soundsEnabled = false
        await model.continueStep()
        await model.skipStep()
        #expect(h.soundsEnabled == false)
    }

    @Test func launchAtLoginCanBeContinuedOff() async throws {
        let h = try await OnboardingHarness()
        defer { h.cleanUp() }
        let model = h.model()
        for _ in 0..<4 { await model.skipStep() }
        model.launchAtLogin = false
        await model.continueStep()
        #expect(h.login.calls == [false])
    }

    @Test func theThemePreviewIsLive() async throws {
        let h = try await OnboardingHarness()
        defer { h.cleanUp() }
        let model = h.model()
        #expect(OnboardingModel.themeChoices == ["chrome-hologram", "twin-metal-tactical"])
        model.previewTheme("twin-metal-tactical")
        #expect(h.themes.theme.variantID == "twin-metal-tactical")
        model.previewTheme("chrome-hologram")
        #expect(h.themes.theme.variantID == "chrome-hologram")
        model.previewTheme("not-a-look")
        #expect(h.themes.variantID == "chrome-hologram")
    }

    // MARK: Accessibility

    @Test func accessibilityIsRequestedAndRechecked() async throws {
        let h = try await OnboardingHarness()
        defer { h.cleanUp() }
        let model = h.model()
        #expect(model.accessibilityStatus == nil)
        await model.refreshAccessibility()
        #expect(model.accessibilityStatus == .notDetermined)
        h.checker.grantOnRequest(.accessibility)
        await model.requestAccessibility()
        #expect(model.accessibilityStatus == .granted)
        #expect(h.checker.requests == [.accessibility])
    }

    @Test func accessibilityOpensItsSystemSettingsPane() async throws {
        let h = try await OnboardingHarness()
        defer { h.cleanUp() }
        h.model().openAccessibilitySettings()
        #expect(h.opened.urls == [SettingsController.systemSettingsURL(for: .accessibility)])
    }

    // MARK: Displays

    @Test func theDisplayStepOffersAVirtualNotchPerPlainDisplay() async throws {
        let h = try await OnboardingHarness()
        defer { h.cleanUp() }
        let only = h.model(displays: [plainDisplay("Studio Display", id: 2)])
        #expect(only.hasPlainDisplay)
        #expect(only.displays.map(\.name) == ["Studio Display"])
        #expect(!h.model(displays: []).hasPlainDisplay)
    }

    // MARK: Completion

    @Test func onboardingDoesNotReappearOnceDone() async throws {
        let h = try await OnboardingHarness()
        defer { h.cleanUp() }
        let controller = h.controller()
        #expect(controller.isPending)
        let model = controller.makeModel()
        #expect(model.isFirstRun)
        await model.finish()
        #expect(!controller.isPending)
        #expect(!controller.presentIfNeeded())
        #expect(controller.window == nil)
        #expect(try String(contentsOf: h.fixture.localURL, encoding: .utf8).contains("complete = true"))
    }

    @Test func aSavedFlagStopsOnboardingAtTheNextLaunch() async throws {
        let h = try await OnboardingHarness(local: "[onboarding]\ncomplete = true\n")
        defer { h.cleanUp() }
        let controller = h.controller()
        #expect(!controller.isPending)
        #expect(!controller.presentIfNeeded())
    }

    @Test func runningSetupAgainKeepsWhatASkippedStepWouldOtherwiseReset() async throws {
        let h = try await OnboardingHarness(
            config: "[sounds]\nenabled = true\n[appearance]\ntheme = \"twin-metal-tactical\"\n",
            local: "[onboarding]\ncomplete = true\n")
        defer { h.cleanUp() }
        h.themes.variantID = "twin-metal-tactical"
        let controller = h.controller()
        let model = controller.makeModel()
        #expect(!model.isFirstRun)
        for _ in model.steps { await model.skipStep() }
        #expect(h.soundsEnabled == true)
        #expect(h.themeSetting == "twin-metal-tactical")
        #expect(h.themes.variantID == "twin-metal-tactical")
        #expect(h.record.isPending)
        #expect(h.complete == true)
    }

    @Test func settingsGeneralCanRunSetupAgain() async throws {
        let h = try await SettingsHarness()
        var runs = 0
        #expect(h.controller.runSetupAgain == nil)
        h.controller.runSetupAgain = { runs += 1 }
        h.controller.runSetupAgain?()
        #expect(runs == 1)
    }
}

@MainActor @Observable
final class OnboardingContributingModule: NotchModule {
    let manifest = ModuleManifest(id: "contrib.test", name: "Contrib", icon: "circle")
    var state: ModuleState = .hidden

    func start(context: any ModuleContext) async throws {}
    func stop() async {}
    func onboardingSteps() -> [OnboardingStep] {
        [
            OnboardingStep(
                id: "contrib.step", title: "Contributed", detail: "From a module",
                content: { AnyView(EmptyView()) })
        ]
    }
}
