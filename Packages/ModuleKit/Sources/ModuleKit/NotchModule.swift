import Observation
import SwiftUI

/// A built-in module (SPEC §4.2, FR4).
///
/// Conformers are `@MainActor @Observable` classes (AD-3). The host observes `state` (and anything else it
/// renders) with `withObservationTracking`, so `state` must be a stored, observed property.
///
/// Lifecycle (SPEC §4.3): the Registry instantiates a module only when it is enabled, calls
/// `start(context:)` once, and on disable or quit calls `stop()`; everything registered through the context
/// (hotkeys, scheduler jobs, event subscriptions, power assertions) is then removed automatically.
/// A module never references another module or VigieCore (AD-1, FR6).
@MainActor
public protocol NotchModule: AnyObject, Observable {
    /// Instance property so dynamic (script) modules can each carry their own (AD-18).
    var manifest: ModuleManifest { get }

    /// Current relevance; observed by the host for arbitration.
    var state: ModuleState { get }

    /// Closed-notch view for a size; nil if the module can't render at that size. Default: nil.
    func compactView(size: CompactSize) -> AnyView?

    /// Summary card on the Home tab. Default: nil.
    func homeCard() -> AnyView?

    /// Full tab in the expanded notch. Default: nil.
    func expandedView() -> AnyView?

    /// Drop zones laid out by the host's drop display (AD-19). Default: none.
    var dropZones: [DropZone] { get }

    /// Items this module offers to the closed notch's left-wing lane (SPEC §5). Default: none.
    /// Each item's state is its module's `state` unless the item overrides it.
    func leftWingItems() -> [LeftWingItem]

    /// Extra settings shown in the module's Settings pane **below** the generated controls, never instead of
    /// them (FR5). Asked only while the module runs. Default: nil.
    func settingsView() -> AnyView?

    /// Steps this module adds to the first-launch onboarding (Story 17.1, AD-4), asked only while the module
    /// runs. Steps that need agent adapters are composed by App assembly instead. Default: none.
    func onboardingSteps() -> [OnboardingStep]

    func start(context: any ModuleContext) async throws
    func stop() async
}

extension NotchModule {
    public func compactView(size: CompactSize) -> AnyView? { nil }
    public func homeCard() -> AnyView? { nil }
    public func expandedView() -> AnyView? { nil }
    public var dropZones: [DropZone] { [] }
    public func leftWingItems() -> [LeftWingItem] { [] }
    public func settingsView() -> AnyView? { nil }
    public func onboardingSteps() -> [OnboardingStep] { [] }
}

/// One item in the closed notch's shared left-wing lane (SPEC §5): pooled across modules, sorted by
/// state then `priority`, the rest collapse into `+X`.
public struct LeftWingItem: Identifiable, Sendable {
    /// Unique within the offering module.
    public let id: String
    /// Lower number = higher in the lane (SPEC §5.1).
    public let priority: Int
    /// This item's own state, when it differs from its module's (e.g. one provider ring in quota warning).
    /// nil = the module's `state`.
    public let state: ModuleState?
    /// Tie-breaker after `priority` (e.g. the usage provider `order`).
    public let order: Int
    public let compactView: @MainActor @Sendable (CompactSize) -> AnyView?

    public init(
        id: String,
        priority: Int,
        state: ModuleState? = nil,
        order: Int = 0,
        compactView: @escaping @MainActor @Sendable (CompactSize) -> AnyView?
    ) {
        self.id = id
        self.priority = priority
        self.state = state
        self.order = order
        self.compactView = compactView
    }
}
