import SwiftUI

/// One step of the first-launch onboarding (Story 17.1, AD-4). Modules contribute steps through
/// ``NotchModule/onboardingSteps()``; App assembly composes the steps that need agent adapters and hands every
/// step to the onboarding window. Every step can be skipped.
public struct OnboardingStep: Identifiable, Sendable {
    /// Unique across all steps (`agents`, `<module id>.<name>`).
    public let id: String
    /// Window heading of the step.
    public let title: LocalizedStringResource
    /// One or two sentences under the heading.
    public let detail: LocalizedStringResource
    /// The step's controls, drawn in the system appearance (the window is a regular macOS window).
    public let content: @MainActor @Sendable () -> AnyView

    public init(
        id: String,
        title: LocalizedStringResource,
        detail: LocalizedStringResource,
        content: @escaping @MainActor @Sendable () -> AnyView
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.content = content
    }
}
