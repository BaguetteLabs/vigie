import AppKit
import ModuleKit
import Observation
import VigieUI
import os

/// Callbacks from the peek panel to its presenter.
@MainActor
public struct PeekHandlers {
    public var primary: @MainActor () -> Void
    public var secondary: @MainActor () -> Void
    public var hover: @MainActor (Bool) -> Void

    public init(
        primary: @escaping @MainActor () -> Void, secondary: @escaping @MainActor () -> Void,
        hover: @escaping @MainActor (Bool) -> Void
    ) {
        self.primary = primary
        self.secondary = secondary
        self.hover = hover
    }
}

/// The window side of a peek: ``PeekPanelController`` in the app, a recorder in tests.
@MainActor
public protocol PeekPanelDriver: AnyObject {
    /// Shows `content` grown out of the notch of `anchor`. The panel never becomes key.
    func present(_ content: PeekContent, dwell: PeekDwellState, anchor: PeekAnchor, handlers: PeekHandlers)
    /// The dwell paused, resumed or ended.
    func update(dwell: PeekDwellState)
    /// Retracts the visible panel over `motion.exit`.
    func retract()
}

/// The Notch Host's peek presenter (SPEC §5.2, AD-13, Story 3.2): the ``PeekSink`` given to `AlertCenter`.
///
/// - One peek is visible at a time; others queue by urgency (``PeekContentMapper/urgency(_:)``), then
///   severity, then arrival.
/// - A module cannot show a new peek within ``rateLimit`` (3 s, A52) of its previous one retracting; its next
///   peek waits in the queue while other modules' peeks may show.
/// - Each alert peeks once. A second `show` for the same alert id peeks again only when it is the reminder
///   replay (`ActiveAlert.isReminder`, set by `AlertCenter.fireReminder`), and only once.
/// - The dwell (`closed.peek_duration`, default 5 s) pauses while the pointer is over the panel and resumes
///   when it leaves; when it runs out the peek retracts.
/// - With `closed.peek = false` (or the module's peek off) `show` returns an inert token and nothing shows;
///   the other outputs are `AlertCenter`'s.
/// - Each peek posts a VoiceOver announcement without moving focus.
@MainActor @Observable
public final class PeekPresenter: PeekSink {
    /// The alert on screen, if any.
    public private(set) var visible: ActiveAlert?
    /// What the visible peek shows.
    public private(set) var visibleContent: PeekContent?
    /// The visible peek's dwell.
    public private(set) var dwellState: PeekDwellState?
    /// True while the pointer is over the visible peek.
    public private(set) var isHovered = false

    /// Receives the primary and Dismiss actions; `AlertCenter` sets itself here when given this sink.
    @ObservationIgnored public weak var events: (any PeekSinkEvents)?

    /// A52: the per-module gap between one peek retracting and the next showing.
    public let rateLimit: Duration

    private struct Entry {
        let token: PeekToken
        let alert: ActiveAlert
        let sequence: Int
        let urgency: Int
    }

    @ObservationIgnored private let anchors: any PeekAnchorProvider
    @ObservationIgnored private let themeController: ThemeController
    @ObservationIgnored private let driver: any PeekPanelDriver
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let elapsed: @MainActor () -> Duration
    @ObservationIgnored private let dwell: @MainActor () -> Duration
    @ObservationIgnored private let enabled: @MainActor (ModuleID) -> Bool
    @ObservationIgnored private let pointer: @MainActor () -> NSPoint?
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private let logger: Logger
    @ObservationIgnored private let shortcuts: TemporaryShortcuts?

    @ObservationIgnored private var queue: [Entry] = []
    @ObservationIgnored private var visibleToken: PeekToken?
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var shownIDs: Set<UUID> = []
    @ObservationIgnored private var remindedIDs: Set<UUID> = []
    @ObservationIgnored private var lastRetracted: [ModuleID: Duration] = [:]
    @ObservationIgnored private var remaining: Duration = .zero
    @ObservationIgnored private var segmentStart: Duration = .zero
    @ObservationIgnored private var dwellTask: Task<Void, Never>?
    @ObservationIgnored private var holdTask: Task<Void, Never>?

    /// - Parameters:
    ///   - anchors: the Notch Host: the island under the pointer, else the main Vigie display.
    ///   - theme: the panel theme (body look follows macOS; the band stays black).
    ///   - driver: the panel; by default a ``PeekPanelController``.
    ///   - clock: drives the dwell and the rate limit.
    ///   - dwell: `closed.peek_duration` (default 5 s).
    ///   - enabled: `closed.peek` (and a per-module peek setting when one exists) for the posting module.
    ///   - pointer: the pointer location in global coordinates.
    ///   - announce: posts a VoiceOver announcement; by default ``postAnnouncement(_:)``.
    ///   - shortcuts: `⌥⌘↵` / `⌥⌘⌫`, bound while a peek is visible (Story 3.3); nil binds none.
    public init(
        anchors: any PeekAnchorProvider,
        theme: ThemeController,
        driver: (any PeekPanelDriver)? = nil,
        clock: any Clock<Duration> = ContinuousClock(),
        dwell: @escaping @MainActor () -> Duration = { PeekPresenter.defaultDwell },
        enabled: @escaping @MainActor (ModuleID) -> Bool = { _ in true },
        pointer: @escaping @MainActor () -> NSPoint? = { NSEvent.mouseLocation },
        announce: @escaping @MainActor (String) -> Void = { PeekPresenter.postAnnouncement($0) },
        rateLimit: Duration = PeekPresenter.defaultRateLimit,
        shortcuts: TemporaryShortcuts? = nil,
        logger: Logger = Logger(subsystem: "fr.baguettelabs.vigie", category: "peek")
    ) {
        self.anchors = anchors
        self.themeController = theme
        self.driver = driver ?? PeekPanelController(themeController: theme)
        self.clock = clock
        self.elapsed = Self.stopwatch(clock)
        self.dwell = dwell
        self.enabled = enabled
        self.pointer = pointer
        self.announce = announce
        self.rateLimit = rateLimit
        self.shortcuts = shortcuts
        self.logger = logger
    }

    /// `closed.peek_duration` default (SPEC §11).
    public static let defaultDwell: Duration = .seconds(5)
    /// A52.
    public static let defaultRateLimit: Duration = .seconds(3)

    /// The queued alerts in the order they will show (rate limits aside).
    public var queuedAlerts: [ActiveAlert] { queue.sorted(by: Self.precedes).map(\.alert) }

    // MARK: PeekSink

    public func show(_ alert: ActiveAlert) -> PeekToken {
        guard enabled(alert.module) else { return PeekToken() }
        if shownIDs.contains(alert.id) {
            guard alert.isReminder, !remindedIDs.contains(alert.id) else {
                logger.debug("Peek for \(alert.kind, privacy: .public) already shown; not peeking again")
                return PeekToken()
            }
        }
        if let queued = queue.first(where: { $0.alert.id == alert.id }) { return queued.token }
        let token = PeekToken()
        sequence += 1
        queue.append(
            Entry(token: token, alert: alert, sequence: sequence, urgency: PeekContentMapper.urgency(alert)))
        pump()
        return token
    }

    public func retract(_ token: PeekToken) {
        if token == visibleToken {
            retractVisible()
        } else {
            queue.removeAll { $0.token == token }
        }
    }

    // MARK: Panel events

    /// The pointer entered or left the visible peek: pauses or resumes the dwell.
    public func hoverChanged(_ inside: Bool) {
        guard visibleToken != nil, inside != isHovered else { return }
        isHovered = inside
        if inside {
            dwellTask?.cancel()
            dwellTask = nil
            remaining = max(.zero, remaining - (elapsed() - segmentStart))
        } else {
            startDwell()
        }
        publishDwell()
    }

    /// `⌥⌘↵` or a click on the primary action: retracts the peek, then has ``events`` perform the alert's action
    /// with `intent` (minted for the click when nil).
    public func performPrimary(intent: UserIntent? = nil) {
        guard let alert = visible, visibleContent?.primary != nil else { return }
        let intent = intent ?? UserIntentMinter.mint(source: .peekAction)
        retractVisible()
        events?.peekPrimary(alert, intent: intent)
    }

    /// `⌥⌘⌫` or a click on Dismiss: retracts the peek and has ``events`` cancel its reminder. The module's state
    /// is untouched.
    public func performSecondary() {
        guard let alert = visible else { return }
        retractVisible()
        events?.peekDismissed(alert)
    }

    // MARK: Announcement

    /// Posts `text` as a high-priority VoiceOver announcement; VoiceOver and keyboard focus do not move.
    public static func postAnnouncement(_ text: String) {
        guard let app = NSApp else { return }
        NSAccessibility.post(
            element: app, notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
    }

    // MARK: Queue

    private static func precedes(_ a: Entry, _ b: Entry) -> Bool {
        if a.urgency != b.urgency { return a.urgency > b.urgency }
        if a.alert.severity != b.alert.severity { return a.alert.severity > b.alert.severity }
        return a.sequence < b.sequence
    }

    private func releaseTime(_ module: ModuleID) -> Duration {
        lastRetracted[module].map { $0 + rateLimit } ?? .zero
    }

    /// Shows the most urgent queued peek whose module is out of its rate limit, or waits for the first release.
    private func pump() {
        guard visibleToken == nil else { return }
        holdTask?.cancel()
        holdTask = nil
        queue.removeAll { !enabled($0.alert.module) }
        let now = elapsed()
        let ordered = queue.sorted(by: Self.precedes)
        if let next = ordered.first(where: { releaseTime($0.alert.module) <= now }) {
            present(next)
            return
        }
        guard let release = ordered.map({ releaseTime($0.alert.module) }).min() else { return }
        let clock = clock
        holdTask = Task { @MainActor [weak self] in
            do {
                try await clock.sleep(for: release - now)
            } catch {
                return
            }
            self?.holdTask = nil
            self?.pump()
        }
    }

    private func present(_ entry: Entry) {
        queue.removeAll { $0.token == entry.token }
        let alert = entry.alert
        if alert.isReminder && shownIDs.contains(alert.id) { remindedIDs.insert(alert.id) }
        shownIDs.insert(alert.id)
        guard let anchor = anchors.anchor(forDisplayUnder: pointer()) else {
            logger.info("No island to anchor the peek for \(alert.kind, privacy: .public); skipped")
            pump()
            return
        }
        let content = PeekContentMapper.content(for: alert, theme: themeController.theme)
        visible = alert
        visibleContent = content
        visibleToken = entry.token
        isHovered = false
        let total = dwell()
        remaining = total
        let state = PeekDwellState(total: total, remaining: total, isRunning: true)
        dwellState = state
        driver.present(
            content, dwell: state, anchor: anchor,
            handlers: PeekHandlers(
                primary: { [weak self] in self?.performPrimary() },
                secondary: { [weak self] in self?.performSecondary() },
                hover: { [weak self] in self?.hoverChanged($0) }))
        var primary: (@MainActor (UserIntent) -> Void)?
        if content.primary != nil {
            primary = { [weak self] intent in self?.performPrimary(intent: intent) }
        }
        shortcuts?.activate(primary: primary, secondary: { [weak self] _ in self?.performSecondary() })
        announce(PeekContentMapper.announcement(for: content))
        startDwell()
    }

    private func startDwell() {
        guard let token = visibleToken else { return }
        dwellTask?.cancel()
        segmentStart = elapsed()
        let clock = clock
        let remaining = remaining
        dwellTask = Task { @MainActor [weak self] in
            do {
                try await clock.sleep(for: remaining)
            } catch {
                return
            }
            guard let self, self.visibleToken == token else { return }
            self.dwellTask = nil
            self.retractVisible()
        }
    }

    private func publishDwell() {
        guard let total = dwellState?.total else { return }
        let state = PeekDwellState(total: total, remaining: remaining, isRunning: !isHovered)
        dwellState = state
        driver.update(dwell: state)
    }

    private func retractVisible() {
        guard let alert = visible else { return }
        dwellTask?.cancel()
        dwellTask = nil
        lastRetracted[alert.module] = elapsed()
        visible = nil
        visibleContent = nil
        visibleToken = nil
        dwellState = nil
        isHovered = false
        shortcuts?.deactivate()
        driver.retract()
        pump()
    }

    /// Time since the presenter started, read from `clock`.
    private static func stopwatch<C: Clock>(_ clock: C) -> @MainActor () -> Duration where C.Duration == Duration {
        let start = clock.now
        return { start.duration(to: clock.now) }
    }
}
