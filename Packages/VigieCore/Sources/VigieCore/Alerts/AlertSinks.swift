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
}

/// macOS notification output.
@MainActor public protocol SystemNotificationSink: AnyObject {
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
    func openSettings(pane: String)
    func openURL(_ url: URL)
}

/// The output and action endpoints of one `AlertCenter`.
@MainActor public struct AlertSinks {
    public var peek: any PeekSink
    public var system: any SystemNotificationSink
    public var sound: any SoundSink
    public var actionRouter: any AlertActionRouter

    public init(
        peek: any PeekSink = RecordingPeekSink(),
        system: any SystemNotificationSink = RecordingSystemSink(),
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

    public init() {}

    public func show(_ alert: ActiveAlert) -> PeekToken {
        let token = PeekToken()
        shown.append(alert)
        tokens.append(token)
        return token
    }

    public func retract(_ token: PeekToken) { retracted.append(token) }
}

@MainActor public final class RecordingSystemSink: SystemNotificationSink {
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
    public init() {}

    public func routeToModule(_ id: ModuleID, actionID: String, payload: Data) {
        calls.append(.module(id, actionID: actionID, payload: payload))
    }
    public func openSettings(pane: String) { calls.append(.settings(pane: pane)) }
    public func openURL(_ url: URL) { calls.append(.url(url)) }
}
