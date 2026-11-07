import Foundation
import ModuleKit

// The outputs `AlertCenter` routes to. Later stories provide the real ones: peek (Notch Host, Story 3.2),
// system (macOS notifications, Story 3.6), sound (Story 10.1). Until then the recording defaults collect calls.

/// A delivered alert, as outputs and the alert lists see it.
public struct ActiveAlert: Identifiable, Hashable, Sendable {
    /// Also the `AlertHandle` id.
    public let id: UUID
    public let module: ModuleID
    public let event: NotifierEvent
    public let outputs: Set<AlertOutput>
    public let postedAt: Date
    /// True when this delivery is the reminder replay.
    public var isReminder: Bool

    public init(
        id: UUID, module: ModuleID, event: NotifierEvent, outputs: Set<AlertOutput>, postedAt: Date,
        isReminder: Bool = false
    ) {
        self.id = id
        self.module = module
        self.event = event
        self.outputs = outputs
        self.postedAt = postedAt
        self.isReminder = isReminder
    }

    public var kind: String { event.kind }
    public var severity: AlertSeverity { event.severity }
}

/// Identifies one shown peek so it can be retracted.
public struct PeekToken: Hashable, Sendable {
    public let id: UUID
    public init(id: UUID = UUID()) { self.id = id }
}

/// The Notch Host's peek presenter (AD-13: only the host shows peeks).
@MainActor public protocol PeekSink: AnyObject {
    func show(_ alert: ActiveAlert) -> PeekToken
    /// Retracts the peek if it is still visible or queued; otherwise does nothing.
    func retract(_ token: PeekToken)
    /// Where the sink reports what the user did with a peek. `AlertCenter` sets itself here; hold it weakly.
    var events: (any PeekSinkEvents)? { get set }
}

/// What happened to a shown peek, reported by the ``PeekSink`` to `AlertCenter` (Story 3.3).
@MainActor public protocol PeekSinkEvents: AnyObject {
    /// The user took the peek's primary action (`⌥⌘↵` or a click). The peek has retracted.
    func peekPrimary(_ alert: ActiveAlert, intent: UserIntent)
    /// The user dismissed the peek (`⌥⌘⌫` or a click on Dismiss). The peek has retracted.
    func peekDismissed(_ alert: ActiveAlert)
    /// A more urgent alert replaced the alert's visible peek (Story 3.9). It keeps its state and peeks again only
    /// through its reminder.
    func peekPreempted(_ alert: ActiveAlert)
}

/// macOS notification output.
@MainActor public protocol SystemOutputSink: AnyObject {
    func deliver(_ alert: ActiveAlert)
}

/// Sound output; it maps the kind to its `[sounds]` key.
@MainActor public protocol SoundSink: AnyObject {
    func play(for alert: ActiveAlert)
}

/// Carries out alert actions (AD-13).
@MainActor public protocol AlertActionRouter: AnyObject {
    /// `.module(...)`, delivered to the module that posted the alert.
    func routeToModule(_ id: ModuleID, actionID: String, payload: Data)
    /// `.module(...)` with the `UserIntent` of the gesture that took it (peek `⌥⌘↵` or click); nil when the action
    /// did not come from a user gesture. Defaults to ``routeToModule(_:actionID:payload:)``.
    func routeToModule(_ id: ModuleID, actionID: String, payload: Data, intent: UserIntent?)
    func openSettings(pane: String)
    func openURL(_ url: URL)
}

extension AlertActionRouter {
    public func routeToModule(_ id: ModuleID, actionID: String, payload: Data, intent: UserIntent?) {
        routeToModule(id, actionID: actionID, payload: payload)
    }
}

/// Delivers `.module` alert actions to modules (Story 3.3), for the App's ``AlertActionRouter``.
public enum ModuleAlertActions {
    /// Hands the action to `module` when it adopts `AlertActionHandler`. Returns false when there is no such
    /// running module (the action is then dropped; the caller logs it).
    @MainActor @discardableResult
    public static func deliver(
        _ actionID: String, payload: Data, intent: UserIntent?, to module: (any NotchModule)?
    ) -> Bool {
        guard let handler = module as? any AlertActionHandler else { return false }
        handler.handleAlertAction(actionID, payload: payload, intent: intent)
        return true
    }
}

/// The output and action endpoints of one `AlertCenter`.
@MainActor public struct AlertSinks {
    public var peek: any PeekSink
    public var system: any SystemOutputSink
    public var sound: any SoundSink
    public var actionRouter: any AlertActionRouter

    public init(
        peek: any PeekSink = RecordingPeekSink(),
        system: any SystemOutputSink = RecordingSystemSink(),
        sound: any SoundSink = RecordingSoundSink(),
        actionRouter: any AlertActionRouter = RecordingActionRouter()
    ) {
        self.peek = peek
        self.system = system
        self.sound = sound
        self.actionRouter = actionRouter
    }
}

// MARK: - Recording defaults (no output; used until the real sinks exist, and by tests)

@MainActor public final class RecordingPeekSink: PeekSink {
    public private(set) var shown: [ActiveAlert] = []
    public private(set) var retracted: [PeekToken] = []
    public private(set) var tokens: [PeekToken] = []
    public weak var events: (any PeekSinkEvents)?

    public init() {}

    public func show(_ alert: ActiveAlert) -> PeekToken {
        let token = PeekToken()
        shown.append(alert)
        tokens.append(token)
        return token
    }

    public func retract(_ token: PeekToken) { retracted.append(token) }
}

@MainActor public final class RecordingSystemSink: SystemOutputSink {
    public private(set) var delivered: [ActiveAlert] = []
    public init() {}
    public func deliver(_ alert: ActiveAlert) { delivered.append(alert) }
}

@MainActor public final class RecordingSoundSink: SoundSink {
    public private(set) var played: [ActiveAlert] = []
    public init() {}
    public func play(for alert: ActiveAlert) { played.append(alert) }
}

@MainActor public final class RecordingActionRouter: AlertActionRouter {
    public enum Call: Hashable, Sendable {
        case module(ModuleID, actionID: String, payload: Data)
        case settings(pane: String)
        case url(URL)
    }

    public private(set) var calls: [Call] = []
    /// The intent passed with each `.module` call, in order (nil for a call without one).
    public private(set) var moduleIntents: [UserIntent?] = []
    public init() {}

    public func routeToModule(_ id: ModuleID, actionID: String, payload: Data) {
        routeToModule(id, actionID: actionID, payload: payload, intent: nil)
    }
    public func routeToModule(_ id: ModuleID, actionID: String, payload: Data, intent: UserIntent?) {
        calls.append(.module(id, actionID: actionID, payload: payload))
        moduleIntents.append(intent)
    }
    public func openSettings(pane: String) { calls.append(.settings(pane: pane)) }
    public func openURL(_ url: URL) { calls.append(.url(url)) }
}
