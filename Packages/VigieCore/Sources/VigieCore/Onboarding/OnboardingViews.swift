import AppKit
import ModuleKit
import SwiftUI
import VigieUI

/// Layout constants of the onboarding window (a regular macOS window, system text styles, UX-DR39).
enum OnboardingMetrics {
    static let windowSize = NSSize(width: 560, height: 540)
    static let padding: CGFloat = 24
    static let sectionSpacing: CGFloat = 16
    static let lineSpacing: CGFloat = 6
    static let cardSpacing: CGFloat = 12
    static let cardPadding: CGFloat = 12
    static let selectionLineWidth: CGFloat = 2
    static let selectionRadius: CGFloat = 10
    static let recheckInterval: Duration = .seconds(1)
}

/// Strings of the onboarding window (VigieCore catalog).
enum OnboardingText {
    static func string(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }

    static func format(_ key: String, _ arguments: any CVarArg...) -> String {
        String(
            format: string(key), locale: Locale(identifier: Bundle.module.preferredLocalizations.first ?? "en"),
            arguments: arguments)
    }

    static func resource(_ key: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(key), bundle: .atURL(Bundle.module.bundleURL))
    }
}

extension OnboardingStep {
    /// The agents step (UX-DR75): the detected agent CLIs with their hook diffs. App assembly composes it from the
    /// agent module's own view, so no module has to know about onboarding (AD-4).
    public static func agents(content: @escaping @MainActor @Sendable () -> AnyView) -> OnboardingStep {
        OnboardingStep(
            id: OnboardingStepKind.agents.id, title: OnboardingText.resource("onboarding.agents.title"),
            detail: OnboardingText.resource("onboarding.agents.detail"), content: content)
    }
}

/// The window's content: heading, the current step's controls, then Back, Skip and Continue.
struct OnboardingRootView: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: OnboardingMetrics.sectionSpacing) {
            header
            ScrollView {
                stepContent
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .padding(OnboardingMetrics.padding)
        .frame(
            minWidth: OnboardingMetrics.windowSize.width, maxWidth: .infinity,
            minHeight: OnboardingMetrics.windowSize.height, maxHeight: .infinity, alignment: .topLeading
        )
        .id(model.currentStep.id)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: OnboardingMetrics.lineSpacing) {
            Text(
                verbatim: OnboardingText.format(
                    "onboarding.progress", model.currentIndex + 1, model.steps.count)
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(title).font(.title2.bold())
            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var title: LocalizedStringResource {
        model.externalSteps[model.currentStep.id]?.title ?? Self.title(of: model.currentStep)
    }

    private var detail: LocalizedStringResource {
        model.externalSteps[model.currentStep.id]?.detail ?? Self.detail(of: model.currentStep)
    }

    static func title(of kind: OnboardingStepKind) -> LocalizedStringResource {
        OnboardingText.resource("onboarding.\(kind.id).title")
    }

    static func detail(of kind: OnboardingStepKind) -> LocalizedStringResource {
        OnboardingText.resource("onboarding.\(kind.id).detail")
    }

    @ViewBuilder private var stepContent: some View {
        if let external = model.externalSteps[model.currentStep.id] {
            external.content()
        } else {
            switch model.currentStep {
            case .theme: OnboardingThemeStep(model: model)
            case .accessibility: OnboardingAccessibilityStep(model: model)
            case .displays: OnboardingDisplaysStep(model: model)
            case .sounds: OnboardingSoundsStep(model: model)
            case .launchAtLogin: OnboardingLoginStep(model: model)
            case .agents, .contributed: EmptyView()
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                model.back()
            } label: {
                Text(OnboardingText.resource("onboarding.back"))
            }
            .disabled(!model.canGoBack)
            Spacer()
            Button {
                Task { await model.skipStep() }
            } label: {
                Text(OnboardingText.resource("onboarding.skip"))
            }
            Button {
                Task { await model.continueStep() }
            } label: {
                Text(OnboardingText.resource(model.isLastStep ? "onboarding.finish" : "onboarding.continue"))
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Theme

/// Two cards, each drawing a closed-notch sample from its own theme; picking one applies it to the real notch now.
struct OnboardingThemeStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: OnboardingMetrics.cardSpacing) {
            ForEach(OnboardingModel.themeChoices, id: \.self) { id in
                ThemeChoiceCard(
                    name: model.themes.library.builtIns[id]?.name ?? id,
                    theme: model.themes.library.resolve(themeID: id, look: .dark).theme,
                    isSelected: model.themeChoice == id
                ) {
                    model.previewTheme(id)
                }
            }
        }
    }
}

private struct ThemeChoiceCard: View {
    let name: String
    let theme: Theme
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: OnboardingMetrics.lineSpacing) {
                HStack {
                    Text(verbatim: name).font(.headline)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                    }
                }
                ThemeSample(theme: theme)
            }
            .padding(OnboardingMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                RoundedRectangle(cornerRadius: OnboardingMetrics.selectionRadius)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                        lineWidth: isSelected ? OnboardingMetrics.selectionLineWidth : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A closed notch in one look: the island, and the working, blocked and done glyph colors (read from the theme).
private struct ThemeSample: View {
    let theme: Theme

    var body: some View {
        let band = theme.spacing(.bandHeight)
        let dot = band * 0.3
        HStack(spacing: theme.spacing(.glyphGap)) {
            ForEach([ColorRole.statusWorking, .statusBlocked, .statusDone, .statusIdle], id: \.self) { role in
                Circle().fill(theme.color(role)).frame(width: dot, height: dot)
            }
        }
        .padding(.horizontal, theme.spacing(.wingPaddingX))
        .frame(height: band)
        .background(theme.color(.island), in: RoundedRectangle(cornerRadius: theme.radius(.islandClosed)))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius(.islandClosed))
                .strokeBorder(theme.color(.line), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}

// MARK: - Accessibility

struct OnboardingAccessibilityStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: OnboardingMetrics.cardSpacing) {
            Label {
                Text(
                    OnboardingText.resource(
                        model.accessibilityStatus == .granted
                            ? "onboarding.accessibility.granted" : "onboarding.accessibility.notGranted"))
            } icon: {
                Image(systemName: model.accessibilityStatus == .granted ? "checkmark.circle.fill" : "circle.dashed")
            }
            if model.accessibilityStatus != .granted {
                HStack {
                    Button {
                        Task { await model.requestAccessibility() }
                    } label: {
                        Text(OnboardingText.resource("onboarding.accessibility.allow"))
                    }
                    Button {
                        model.openAccessibilitySettings()
                    } label: {
                        Text(OnboardingText.resource("onboarding.accessibility.openSettings"))
                    }
                }
                Text(OnboardingText.resource("onboarding.accessibility.skipNote"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            // The grant happens in System Settings: look again while this step shows.
            while !Task.isCancelled {
                await model.refreshAccessibility()
                try? await Task.sleep(for: OnboardingMetrics.recheckInterval)
            }
        }
    }
}

// MARK: - Displays

/// The display prompt of Story 2.7 as a step: where Vigie appears, with a virtual notch offered per display without
/// a notch (A60). The answer is the same `DisplayPromptAnswer` the in-notch prompt writes.
struct OnboardingDisplaysStep: View {
    let model: OnboardingModel

    var body: some View {
        let displays = model.displays
        VStack(alignment: .leading, spacing: OnboardingMetrics.cardSpacing) {
            if !model.hasPlainDisplay {
                Text(OnboardingText.resource("onboarding.displays.none"))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisplayOption(
                title: OnboardingText.string("onboarding.displays.default"), detail: nil,
                isSelected: model.displayChoice == .notched
            ) { model.displayChoice = .notched }
            DisplayOption(
                title: OnboardingText.string("onboarding.displays.all"), detail: nil,
                isSelected: model.displayChoice == .all
            ) { model.displayChoice = .all }
            ForEach(displays) { display in
                DisplayOption(
                    title: display.name,
                    detail: OnboardingText.string(
                        display.kind.usesVirtualNotch ? "onboarding.displays.virtual" : "onboarding.displays.physical"),
                    isSelected: model.displayChoice == .named(display.name)
                ) { model.displayChoice = .named(display.name) }
            }
        }
    }
}

private struct DisplayOption: View {
    let title: String
    let detail: String?
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading) {
                    Text(verbatim: title)
                    if let detail {
                        Text(verbatim: detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Sounds and launch at login

struct OnboardingSoundsStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: OnboardingMetrics.cardSpacing) {
            Toggle(isOn: $model.soundsEnabled) {
                Text(OnboardingText.resource("onboarding.sounds.toggle"))
            }
            .toggleStyle(.switch)
            Text(OnboardingText.resource("onboarding.sounds.skipNote"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct OnboardingLoginStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        Toggle(isOn: $model.launchAtLogin) {
            Text(OnboardingText.resource("onboarding.launchAtLogin.toggle"))
        }
        .toggleStyle(.switch)
    }
}
