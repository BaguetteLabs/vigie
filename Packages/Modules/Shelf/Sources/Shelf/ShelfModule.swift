import Foundation
import ModuleKit
import Observation
import SwiftUI
import os

/// `shelf` (SPEC §7.3): the Stash drop zone and the items it keeps.
///
/// Storage (AD-11): the index is `index.json` in `context.storage`; copies and saved items live under the
/// module folder's `items/`. References are security-scoped bookmarks (AD-19), used only through
/// ``ShelfStore/withSecurityScopedAccess(_:_:)``.
///
/// A Stash drop that cannot be stored adds nothing, returns `DropResult.readout("NOT STASHED")` (the host shows
/// it on the left wing for 2 s) and writes a `shelf.stash` activity entry; no alert, peek or sound (UX-DR101).
///
/// Image to Text (Story 9.9, `ImageToText.swift`): an image or PDF dropped on it is recognized on the Mac and
/// its text copied through `context.clipboard`, with a `COPIED · <n> LINES` / `NO TEXT FOUND` readout.
///
/// Expiry (Story 9.4): ``ExpirySweeper`` runs at start, every 60 s and after every change. Items expire
/// `ttl` after they were stashed unless pinned; references leave the shelf, copies and saved items go to the
/// Trash. With `expiry_notification` on, `shelf.expiring` is posted once per item in its last 24 h.
@MainActor @Observable
public final class ShelfModule: NotchModule {
    nonisolated static let bundle = ShelfText.bundle

    /// SPEC §11 default for `ttl`.
    public nonisolated static let defaultTTL: Duration = .seconds(7 * 86_400)
    /// The Stash zone id.
    public nonisolated static let stashZoneID = "shelf.stash"
    /// Activity entry kind of a Stash outcome.
    nonisolated static let stashActivityKind = "shelf.stash"
    /// How often the expiry sweep runs.
    public nonisolated static let sweepInterval: Duration = .seconds(60)

    public nonisolated static let staticManifest = ModuleManifest(
        id: "shelf",
        name: LocalizedStringResource("shelf.module.name", bundle: bundle),
        icon: "tray",
        settings: [
            SettingDescriptor(
                key: "ttl",
                label: LocalizedStringResource("shelf.setting.ttl", bundle: bundle),
                kind: .duration(default: defaultTTL),
                scope: .synced,
                help: LocalizedStringResource("shelf.setting.ttl.help", bundle: bundle)),
            SettingDescriptor(
                key: "mode",
                label: LocalizedStringResource("shelf.setting.mode", bundle: bundle),
                kind: .enumeration(options: StashMode.allCases.map(\.rawValue), default: StashMode.reference.rawValue),
                scope: .synced,
                help: LocalizedStringResource("shelf.setting.mode.help", bundle: bundle)),
            SettingDescriptor(
                key: "expiry_notification",
                label: LocalizedStringResource("shelf.setting.expiryNotification", bundle: bundle),
                kind: .bool(default: false),
                scope: .synced,
                help: LocalizedStringResource("shelf.setting.expiryNotification.help", bundle: bundle)),
            SettingDescriptor(
                key: imageToTextSetting,
                label: LocalizedStringResource("shelf.setting.imageToText", bundle: bundle),
                kind: .bool(default: false),
                scope: .synced,
                help: LocalizedStringResource("shelf.setting.imageToText.help", bundle: bundle)),
        ],
        alertKinds: ["shelf.expiring"],
        defaultEnabled: true
    )

    public let manifest = ShelfModule.staticManifest
    /// `ambient` while the shelf holds items (the count is ``itemCount``), `hidden` when empty.
    public private(set) var state: ModuleState = .hidden
    /// Every item, newest first.
    public private(set) var items: [ShelfItem] = []
    /// The last Image to Text copy (lines, when), for the `SEND TO` card meta `LAST · 3 LINES · 14:48` (9.7).
    public internal(set) var lastImageToText: ImageToTextRun?
    /// The resolved `ttl` setting.
    public private(set) var ttl: Duration = ShelfModule.defaultTTL
    /// True between `start` and `stop`: the Stash zone is enabled only then.
    public private(set) var isRunning = false
    /// The index and the module folder; nil until `start`.
    public private(set) var store: ShelfStore?

    /// When the last expiry sweep ran (views that show time left re-read on it).
    public private(set) var lastSweep: Date?

    public var itemCount: Int { items.count }

    /// Items in their last 24 h before expiry, as of the last sweep.
    public var expiringCount: Int {
        let now = lastSweep ?? now()
        return items.filter { $0.isExpiring(now: now) }.count
    }

    /// The card meta `1 EXPIRING` (Story 9.3 shows it), nil when nothing is expiring.
    public var expiringMeta: String? { ShelfExpiry.expiringMeta(count: expiringCount) }

    /// The Shelf tab's selected row (Story 9.3); kept here so ↑↓ and Space survive re-renders.
    public internal(set) var selectedID: UUID?
    /// A short footer line after a tab action could not run (`FILE NOT FOUND`); cleared by the next action.
    public internal(set) var notice: String?

    @ObservationIgnored let scope: any SecurityScopedResources
    @ObservationIgnored private let recycler: any Recycler
    @ObservationIgnored let revealer: any FileRevealer
    @ObservationIgnored private let quickLookOverride: (any QuickLookPresenting)?
    @ObservationIgnored private var presenter: (any QuickLookPresenting)?
    /// The Quick Look panel, created on first use.
    var quickLook: any QuickLookPresenting {
        if let presenter { return presenter }
        let made = quickLookOverride ?? QuickLookPresenter()
        presenter = made
        return made
    }
    /// How long a drag's "move" may take to leave the source (Finder moves after the drop).
    @ObservationIgnored var moveSettle: (attempts: Int, interval: Duration) = (10, .milliseconds(200))
    /// Files held open by a drag out of the tab, released when it ends.
    @ObservationIgnored var activeDrags: [UUID: ShelfFileAccess] = [:]
    @ObservationIgnored var sweeper: ExpirySweeper?
    @ObservationIgnored private var sweepToken: RegistrationToken?
    /// The last queued sweep; each sweep waits for the one before it.
    @ObservationIgnored private var sweepTask: Task<Void, Never>?
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored var settings: (any ModuleSettings)?
    @ObservationIgnored var activity: (any ActivityLog)?
    @ObservationIgnored var log: Logger?
    /// `context.clipboard` (copy-only), for Image to Text.
    @ObservationIgnored var clipboard: (any ClipboardService)?
    @ObservationIgnored let recognizer: any TextRecognizing
    @ObservationIgnored var observeTasks: [Task<Void, Never>] = []

    public init(
        scope: any SecurityScopedResources = SystemSecurityScope(), recycler: any Recycler = WorkspaceRecycler(),
        revealer: any FileRevealer = WorkspaceRevealer(), quickLook: (any QuickLookPresenting)? = nil,
        recognizer: any TextRecognizing = VisionTextRecognizer(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.recognizer = recognizer
        self.scope = scope
        self.recycler = recycler
        self.revealer = revealer
        self.quickLookOverride = quickLook
        self.now = now
    }

    // MARK: Lifecycle

    public func start(context: any ModuleContext) async throws {
        settings = context.settings
        activity = context.activity
        log = context.log
        clipboard = context.clipboard
        let store = ShelfStore(storage: context.storage, scope: scope, log: context.log)
        self.store = store
        ttl = Self.resolvedTTL(context.settings)
        await store.load()
        if await store.recomputeExpiry(ttl: ttl) {
            context.log.info("Shelf expiry dates follow the current ttl")
        }
        sweeper = ExpirySweeper(recycler: recycler, notifier: context.notifier, log: context.log)
        isRunning = true
        await sweep()
        sweepToken = context.scheduler.every(Self.sweepInterval) { [weak self] in await self?.sweep() }
        observe("ttl") { [weak self] in await self?.ttlChanged() }
    }

    public func stop() async {
        for task in observeTasks { task.cancel() }
        observeTasks = []
        sweepToken?.cancel()
        sweepToken = nil
        for access in activeDrags.values { access.close() }
        activeDrags = [:]
        isRunning = false
    }

    private func observe(_ key: String, _ onChange: @escaping @MainActor @Sendable () async -> Void) {
        guard let stream = settings?.observe(key) else { return }
        observeTasks.append(
            Task { @MainActor in
                for await _ in stream {
                    guard !Task.isCancelled else { return }
                    await onChange()
                }
            })
    }

    func ttlChanged() async {
        guard let settings, let store else { return }
        ttl = Self.resolvedTTL(settings)
        await store.recomputeExpiry(ttl: ttl)
        await sweep()
    }

    /// Runs the expiry sweep, then refreshes items and state. Sweeps never overlap: a call made while one
    /// runs queues another pass after it and returns when that pass is done.
    public func sweep() async {
        let previous = sweepTask
        let task = Task { @MainActor [weak self] in
            await previous?.value
            await self?.sweepOnce()
        }
        sweepTask = task
        await task.value
    }

    private func sweepOnce() async {
        guard let store, let sweeper, isRunning else {
            await refresh()
            return
        }
        let date = now()
        let notify = settings?.value("expiry_notification", as: Bool.self) ?? false
        let report = await sweeper.sweep(store, now: date, notify: notify)
        if !report.expired.isEmpty {
            log?.info(
                "Shelf: \(report.expired.count, privacy: .public) item(s) expired, \(report.recycled.count, privacy: .public) moved to the Trash"
            )
        }
        lastSweep = date
        await refresh()
    }

    // MARK: Item actions (the Shelf tab's handlers are in ShelfTab.swift)

    /// Pins (never expires) or unpins (expires `ttl` after it was stashed) an item.
    public func setPinned(_ id: UUID, _ pinned: Bool) async {
        guard let store else { return }
        await store.setPinned(id, pinned, ttl: ttl)
        await sweep()
    }

    /// Takes an item off the shelf; its file is left where it is (nothing is deleted).
    @discardableResult
    public func remove(_ id: UUID) async -> ShelfItem? {
        guard let store else { return nil }
        let removed = await store.remove(id)
        await sweep()
        return removed
    }

    /// Re-reads the store's items and recomputes the state.
    func refresh() async {
        guard let store else { return }
        items = await store.items
        state = items.isEmpty ? .hidden : .ambient
    }

    /// `ttl`, or the default when unset or not positive.
    nonisolated static func resolvedTTL(_ settings: any ModuleSettings) -> Duration {
        guard let value = settings.value("ttl", as: Duration.self), value > .zero else { return defaultTTL }
        return value
    }

    var mode: StashMode {
        settings?.value("mode", as: String.self).flatMap(StashMode.init(rawValue:)) ?? .reference
    }

    // MARK: Stash

    /// The Stash zone handler: stores the payload, or answers `NOT STASHED`.
    public func stash(_ payload: DropPayload) async -> DropResult {
        guard let store, isRunning else { return .rejected }
        do {
            let added = try await store.stash(payload, mode: mode, ttl: ttl, now: now())
            log?.info("Stashed \(added.count, privacy: .public) item(s)")
            await sweep()
            return .accepted
        } catch {
            let failure = (error as? StashFailure) ?? .writeFailed
            log?.error("Stash failed: \(failure.reason, privacy: .public)")
            activity?.record(
                ActivityEntry(
                    at: now(), category: .module, kind: Self.stashActivityKind, outcome: .custom("failed"),
                    detail: ["reason": failure.reason]))
            return .readout(ShelfText.resource("shelf.stash.notStashed"))
        }
    }

    // MARK: Drop zones

    /// Stash, then Image to Text (hidden unless `image_to_text` is on). Zones are read each time a drag arrives.
    public var dropZones: [DropZone] { [stashZone, imageToTextZone] }

    /// Stash (SPEC §4.6, DESIGN layout B): column 1 row 1, 2 × 2, primary; takes anything.
    public var stashZone: DropZone {
        DropZone(
            id: Self.stashZoneID,
            label: ShelfText.resource("shelf.stash.label"),
            glyph: "drop.stash",
            accentToken: "iris-2",
            role: .primary,
            cell: DropCell(preferredColumn: 1, preferredRow: 1, span: .init(columns: 2, rows: 2)),
            order: 0,
            accepts: [],
            handler: { [weak self] payload in await self?.stash(payload) ?? .rejected },
            meta: stashMeta,
            releaseLine: ShelfText.resource("shelf.stash.release"),
            accessibilityLabel: stashAccessibilityLabel,
            isEnabled: isRunning)
    }

    /// `KEEP 7 DAYS · 5 ITEMS` (`KEEP 12 HOURS · …` when `ttl` is not whole days).
    var stashMeta: LocalizedStringResource {
        let count = items.count
        if let days = Self.wholeDays(ttl) {
            return LocalizedStringResource(
                "shelf.stash.meta.days", defaultValue: "KEEP \(days) DAYS · \(count) ITEMS", bundle: Self.bundle)
        }
        let hours = Self.hours(ttl)
        return LocalizedStringResource(
            "shelf.stash.meta.hours", defaultValue: "KEEP \(hours) HOURS · \(count) ITEMS", bundle: Self.bundle)
    }

    /// "Stash, keep 7 days, 5 items".
    var stashAccessibilityLabel: LocalizedStringResource {
        let count = items.count
        if let days = Self.wholeDays(ttl) {
            return LocalizedStringResource(
                "shelf.stash.a11y.days", defaultValue: "Stash, keep \(days) days, \(count) items", bundle: Self.bundle)
        }
        let hours = Self.hours(ttl)
        return LocalizedStringResource(
            "shelf.stash.a11y.hours", defaultValue: "Stash, keep \(hours) hours, \(count) items", bundle: Self.bundle)
    }

    nonisolated static func wholeDays(_ ttl: Duration) -> Int? {
        let seconds = ttl.components.seconds
        guard seconds >= 86_400, seconds % 86_400 == 0 else { return nil }
        return Int(seconds / 86_400)
    }

    /// Whole hours, at least 1.
    nonisolated static func hours(_ ttl: Duration) -> Int {
        max(Int((ttl.timeInterval / 3600).rounded()), 1)
    }
}
