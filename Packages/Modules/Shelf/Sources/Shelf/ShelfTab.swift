import Foundation
import ModuleKit
import SwiftUI
import VigieUI

/// The Shelf tab (Story 9.3): the snapshot the view reads and the handlers of its actions.
extension ShelfModule {
    /// The tab, bound to the live module: the rows re-render on every item change and on each expiry sweep
    /// (every minute), so time left keeps counting. The Home card is in HomeWidget.swift (Story 11.3).
    public func expandedView() -> AnyView? {
        AnyView(
            ShelfTabView(
                snapshot: { [weak self] in self?.tabSnapshot() ?? Self.placeholderSnapshot },
                actions: tabActions, sendTo: sendToCard))
    }

    var tabActions: ShelfTabActions {
        ShelfTabActions(
            select: { [weak self] id in self?.select(id) },
            quickLook: { [weak self] id in self?.showQuickLook(id) },
            reveal: { [weak self] id in
                guard let self else { return }
                Task { await self.reveal(id) }
            },
            togglePin: { [weak self] id in
                guard let self else { return }
                Task { await self.togglePin(id) }
            },
            beginDrag: { [weak self] id in self?.beginDrag(id) },
            endDrag: { [weak self] id, operation in
                guard let self else { return }
                Task { await self.endDrag(id, operation) }
            },
            sendToEntries: { [weak self] id in self?.sendToEntries(for: id) ?? [] },
            send: { [weak self] id, zoneID, modifiers in
                guard let self else { return }
                self.select(id)
                Task { await self.send(id, to: zoneID, modifiers: modifiers) }
            },
            paste: { [weak self] in
                guard let self else { return }
                Task { await self.paste() }
            })
    }

    nonisolated static var placeholderSnapshot: ShelfTabSnapshot {
        ShelfTabSnapshot(
            title: ShelfTabFormat.title(count: 0), ttlMeta: ShelfTabFormat.ttlMeta(defaultTTL), rows: [],
            emptySentence: ShelfTabFormat.emptySentence(defaultTTL))
    }

    /// What the tab shows at `now` (default: the last sweep, so labels move once a minute).
    public func tabSnapshot(now date: Date? = nil, calendar: Calendar = .current) -> ShelfTabSnapshot {
        let date = date ?? lastSweep ?? now()
        let rows = items.map { ShelfTabFormat.row($0, ttl: ttl, now: date, calendar: calendar) }
        return ShelfTabSnapshot(
            title: ShelfTabFormat.title(count: items.count),
            expiringMeta: ShelfExpiry.expiringMeta(count: items.filter { $0.isExpiring(now: date) }.count),
            ttlMeta: ShelfTabFormat.ttlMeta(ttl),
            rows: rows,
            selectedID: ShelfSelection.valid(selectedID, in: rows.map(\.id)),
            emptySentence: ShelfTabFormat.emptySentence(ttl),
            notice: notice)
    }

    // MARK: Actions

    func select(_ id: UUID?) {
        selectedID = id
        notice = nil
    }

    /// Space or the chip: Quick Look on the item's file, its access held until the panel closes.
    func showQuickLook(_ id: UUID) {
        select(id)
        guard let access = openFile(id) else {
            notice = ShelfText.string("shelf.notice.missing")
            return
        }
        if !quickLook.present(access.url, onClose: { access.close() }) {
            access.close()
            notice = ShelfText.string("shelf.notice.quickLookFocus")
        }
    }

    /// Finder at the file, inside its security scope.
    func reveal(_ id: UUID) async {
        select(id)
        guard let store else { return }
        let revealer = revealer
        do {
            try await store.withSecurityScopedAccess(id) { url in
                await MainActor.run { revealer.reveal(url) }
            }
        } catch {
            log?.error("Shelf reveal failed: \(String(describing: error), privacy: .public)")
            notice = ShelfText.string("shelf.notice.missing")
        }
    }

    func togglePin(_ id: UUID) async {
        select(id)
        guard let item = items.first(where: { $0.id == id }) else { return }
        await setPinned(id, !item.pinned)
    }

    /// A drag out starts: the file, its access held until ``endDrag(_:_:)``; nil when the file is gone.
    func beginDrag(_ id: UUID) -> URL? {
        activeDrags.removeValue(forKey: id)?.close()
        guard let access = openFile(id) else {
            notice = ShelfText.string("shelf.notice.missing")
            return nil
        }
        activeDrags[id] = access
        draggingItemID = id
        return access.url
    }

    /// The drag ended. A move takes the item off the shelf once its file has left the place it was dragged
    /// from (Finder finishes the move after the drop): a reference keeps nothing more, a copy or saved item
    /// also loses its empty `items/<id>/` folder. A copy, a cancelled drag or a "move" that left the file in
    /// place keeps the item.
    func endDrag(_ id: UUID, _ operation: ShelfDragOperation) async {
        if draggingItemID == id { draggingItemID = nil }
        guard let access = activeDrags.removeValue(forKey: id) else { return }
        let url = access.url
        defer { access.close() }
        guard operation == .move else { return }
        guard await Self.waitUntilGone(url, attempts: moveSettle.attempts, interval: moveSettle.interval) else {
            log?.info("Shelf drag reported a move but the file stayed; item kept")
            return
        }
        if let item = items.first(where: { $0.id == id }), item.mode != .reference {
            ExpirySweeper.removeEmptyFolder(url.deletingLastPathComponent())
        }
        if selectedID == id { selectedID = nil }
        await remove(id)
    }

    nonisolated static func waitUntilGone(_ url: URL, attempts: Int, interval: Duration) async -> Bool {
        for attempt in 0..<max(attempts, 1) {
            if !FileManager.default.fileExists(atPath: url.path) { return true }
            if attempt < attempts - 1 { try? await Task.sleep(for: interval) }
        }
        return !FileManager.default.fileExists(atPath: url.path)
    }

    /// The item's file, opened: a reference's bookmark resolved and its scope started (stopped by
    /// ``ShelfFileAccess/close()``); a copy or saved item's file under the module folder. Nil when missing.
    func openFile(_ id: UUID) -> ShelfFileAccess? {
        guard let item = items.first(where: { $0.id == id }) else { return nil }
        guard item.mode == .reference else {
            guard let url = store?.fileURL(for: item), FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }
            return ShelfFileAccess(url: url) {}
        }
        guard let bookmark = item.bookmark, let resolved = try? scope.resolve(bookmark) else { return nil }
        let url = resolved.url
        let scope = scope
        let started = scope.startAccessing(url)
        let access = ShelfFileAccess(url: url) { if started { scope.stopAccessing(url) } }
        guard FileManager.default.fileExists(atPath: url.path) else {
            access.close()
            return nil
        }
        return access
    }
}

/// The tab's texts, from the Shelf catalog.
enum ShelfTabFormat {
    static func title(count: Int) -> String { ShelfText.format("shelf.tab.title", count) }

    /// `TTL 7D`, or `TTL 12H` when the ttl is not whole days.
    static func ttlMeta(_ ttl: Duration) -> String {
        if let days = ShelfModule.wholeDays(ttl) { return ShelfText.format("shelf.tab.ttl.days", days) }
        return ShelfText.format("shelf.tab.ttl.hours", ShelfModule.hours(ttl))
    }

    /// "Drag a file, text or image onto the notch, or press ⌘V, to keep it here for 7 days." (UX-DR44, UX-DR100)
    static func emptySentence(_ ttl: Duration) -> LocalizedStringResource {
        if let days = ShelfModule.wholeDays(ttl) {
            return LocalizedStringResource(
                "shelf.empty.days",
                defaultValue:
                    "Drag a file, text or image onto the notch, or press ⌘V, to keep it here for \(days) days.",
                bundle: ShelfModule.bundle)
        }
        let hours = ShelfModule.hours(ttl)
        return LocalizedStringResource(
            "shelf.empty.hours",
            defaultValue: "Drag a file, text or image onto the notch, or press ⌘V, to keep it here for \(hours) hours.",
            bundle: ShelfModule.bundle)
    }

    static func row(_ item: ShelfItem, ttl: Duration, now: Date, calendar: Calendar) -> ShelfRowModel {
        let sizeMode = sizeMode(item)
        let expiry = expiry(item, ttl: ttl, now: now)
        let expiryText: String =
            switch expiry {
            case .timeLeft(let text, _), .expiring(let text, _): text
            case .pinned: ShelfText.string("shelf.row.a11y.pinned")
            }
        return ShelfRowModel(
            id: item.id, name: item.name, kind: kind(item.name), sizeMode: sizeMode, sourceApp: item.sourceApp,
            addedTime: addedTime(item.addedAt, calendar: calendar),
            addedDay: addedDay(item.addedAt, now: now, calendar: calendar), expiry: expiry,
            accessibilityLabel: ShelfText.format("shelf.row.a11y", item.name, sizeMode, expiryText))
    }

    /// `184 KB · REF`.
    static func sizeMode(_ item: ShelfItem) -> String {
        ShelfText.format("shelf.row.sizeMode", size(item.size), ShelfText.string("shelf.mode.\(item.mode.rawValue)"))
    }

    /// `184 KB`, `1.2 MB` (file sizes, decimal units, in the catalog's locale; capitals like the mode tag).
    static func size(_ bytes: Int64) -> String {
        bytes.formatted(
            ByteCountFormatStyle(
                style: .file, allowedUnits: .all, spellsOutZero: false, locale: ShelfText.catalogLocale)
        ).uppercased(with: ShelfText.catalogLocale)
    }

    /// The tile label: the extension in capitals, at most 4 letters.
    static func kind(_ name: String) -> String {
        String((name as NSString).pathExtension.uppercased().prefix(4))
    }

    /// Time left over the TTL bar; in the last 24 h (or past due, before the sweep) the warning form.
    static func expiry(_ item: ShelfItem, ttl: Duration, now: Date) -> ShelfRowModel.Expiry {
        guard let label = item.timeLeftLabel(now: now), let remaining = ShelfExpiry.remaining(item, now: now) else {
            return .pinned
        }
        let fraction = ttl.timeInterval > 0 ? min(max(remaining / ttl.timeInterval, 0), 1) : 0
        return remaining <= ShelfExpiry.warningWindow
            ? .expiring(label, fraction: fraction) : .timeLeft(label, fraction: fraction)
    }

    /// `14:31`.
    static func addedTime(_ date: Date, calendar: Calendar) -> String {
        formatter(ShelfText.string("shelf.added.timeFormat"), calendar: calendar).string(from: date)
    }

    /// `TODAY`; `TUE 03` earlier this month; `FRI 30 OCT` before (mockup, Wed 04 Nov).
    static func addedDay(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return ShelfText.string("shelf.added.today") }
        let sameMonth = calendar.isDate(date, equalTo: now, toGranularity: .month)
        let key = sameMonth ? "shelf.added.weekdayFormat" : "shelf.added.dateFormat"
        return formatter(ShelfText.string(key), calendar: calendar).string(from: date).uppercased(
            with: ShelfText.catalogLocale)
    }

    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = ShelfText.catalogLocale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}
