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
@MainActor @Observable
public final class ShelfModule: NotchModule {
    nonisolated static let bundle = ShelfText.bundle

    /// SPEC §11 default for `ttl`.
    public nonisolated static let defaultTTL: Duration = .seconds(7 * 86_400)
    /// The Stash zone id.
    public nonisolated static let stashZoneID = "shelf.stash"
    /// Activity entry kind of a Stash outcome.
    nonisolated static let stashActivityKind = "shelf.stash"

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
        ],
        alertKinds: ["shelf.expiring"],
        defaultEnabled: true
    )

    public let manifest = ShelfModule.staticManifest
    /// `ambient` while the shelf holds items (the count is ``itemCount``), `hidden` when empty.
    public private(set) var state: ModuleState = .hidden
    /// Every item, newest first.
    public private(set) var items: [ShelfItem] = []
    /// The resolved `ttl` setting.
    public private(set) var ttl: Duration = ShelfModule.defaultTTL
    /// True between `start` and `stop`: the Stash zone is enabled only then.
    public private(set) var isRunning = false
    /// The index and the module folder; nil until `start`.
    public private(set) var store: ShelfStore?

    public var itemCount: Int { items.count }

    @ObservationIgnored private let scope: any SecurityScopedResources
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored var settings: (any ModuleSettings)?
    @ObservationIgnored var activity: (any ActivityLog)?
    @ObservationIgnored var log: Logger?
    @ObservationIgnored var observeTasks: [Task<Void, Never>] = []

    public init(
        scope: any SecurityScopedResources = SystemSecurityScope(), now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.scope = scope
        self.now = now
    }

    // MARK: Lifecycle

    public func start(context: any ModuleContext) async throws {
        settings = context.settings
        activity = context.activity
        log = context.log
        let store = ShelfStore(storage: context.storage, scope: scope, log: context.log)
        self.store = store
        ttl = Self.resolvedTTL(context.settings)
        await store.load()
        if await store.recomputeExpiry(ttl: ttl) {
            context.log.info("Shelf expiry dates follow the current ttl")
        }
        await refresh()
        isRunning = true
        observe("ttl") { [weak self] in await self?.ttlChanged() }
    }

    public func stop() async {
        for task in observeTasks { task.cancel() }
        observeTasks = []
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
        await refresh()
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
            await refresh()
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

    public var dropZones: [DropZone] { [stashZone] }

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
