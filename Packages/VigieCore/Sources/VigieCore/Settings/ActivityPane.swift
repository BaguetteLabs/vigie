import AppKit
import ModuleKit
import Observation
import SwiftUI

/// Settings › General › Activity log (A80): read-only list newest first, filters by module and kind, the
/// summary of one day, and Copy as text. Days are the store's UTC day files.
@MainActor @Observable
public final class ActivityPaneModel {
    /// Filter value for core entries (no module).
    public static let coreModule = "core"
    /// How far back the list reads.
    public static let window: TimeInterval = 7 * 24 * 3600

    public private(set) var entries: [ActivityEntry] = []
    /// nil = all modules; `core` = entries without a module.
    public var moduleFilter: String?
    /// nil = all kinds.
    public var kindFilter: String?
    /// Start of the UTC day whose summary is shown and copied.
    public var day: Date
    public private(set) var summary = DaySummary()

    @ObservationIgnored private let store: ActivityStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored var pasteboardWriter: @MainActor (String) -> Void = { text in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    public init(store: ActivityStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
        day = Self.utc.startOfDay(for: now())
    }

    /// Entries passing both filters, newest first.
    public var filtered: [ActivityEntry] {
        entries.filter { entry in
            if let moduleFilter, (entry.module?.rawValue ?? Self.coreModule) != moduleFilter { return false }
            if let kindFilter, entry.kind != kindFilter { return false }
            return true
        }
    }

    public var modules: [String] {
        Set(entries.map { $0.module?.rawValue ?? Self.coreModule }).sorted()
    }

    public var kinds: [String] {
        Set(entries.map(\.kind)).sorted()
    }

    /// UTC days with entries, newest first, always including today.
    public var days: [Date] {
        let today = Self.utc.startOfDay(for: now())
        return Set(entries.map { Self.utc.startOfDay(for: $0.at) } + [today]).sorted(by: >)
    }

    public func load() async {
        let since = now().addingTimeInterval(-Self.window)
        entries = await store.entries(since: since)
        await loadSummary()
    }

    public func select(day: Date) async {
        self.day = Self.utc.startOfDay(for: day)
        await loadSummary()
    }

    private func loadSummary() async {
        summary = await store.summary(for: day)
    }

    /// Copies the selected day as text (`HH:mm:ss  module  kind  outcome`, oldest first) and returns it.
    @discardableResult
    public func copyDay() async -> String {
        let text = await store.copyAsText(day: day)
        pasteboardWriter(text)
        return text
    }
}

struct ActivityPaneView: View {
    let model: ActivityPaneModel

    var body: some View {
        @Bindable var model = model
        Section {
            Picker(selection: $model.moduleFilter) {
                Text(SettingsText.resource("settings.activity.all")).tag(String?.none)
                ForEach(model.modules, id: \.self) { module in
                    Text(verbatim: module).tag(String?.some(module))
                }
            } label: {
                Text(SettingsText.resource("settings.activity.module"))
            }
            Picker(selection: $model.kindFilter) {
                Text(SettingsText.resource("settings.activity.all")).tag(String?.none)
                ForEach(model.kinds, id: \.self) { kind in
                    Text(verbatim: kind).tag(String?.some(kind))
                }
            } label: {
                Text(SettingsText.resource("settings.activity.kind"))
            }
        }
        Section {
            Picker(
                selection: Binding(get: { model.day }, set: { day in Task { await model.select(day: day) } })
            ) {
                ForEach(model.days, id: \.self) { day in
                    Text(day, format: .dateTime.year().month().day().timeZone(.omitted)).tag(day)
                }
            } label: {
                Text(SettingsText.resource("settings.activity.day"))
            }
            LabeledContent {
                Text(verbatim: Self.summaryText(model.summary))
                    .multilineTextAlignment(.trailing)
            } label: {
                Text(SettingsText.resource("settings.activity.summary"))
            }
            HStack {
                Spacer()
                Button {
                    Task { await model.copyDay() }
                } label: {
                    Text(SettingsText.resource("settings.activity.copy"))
                }
            }
        }
        Section {
            if model.filtered.isEmpty {
                Text(SettingsText.resource("settings.activity.empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.filtered.prefix(500).enumerated()), id: \.offset) { _, entry in
                    ActivityRow(entry: entry)
                }
            }
        } header: {
            Text(SettingsText.resource("settings.activity.entries"))
        }
        .task { await model.load() }
    }

    static func summaryText(_ summary: DaySummary) -> String {
        SettingsText.format(
            "settings.activity.summary.format",
            summary.alertsByKind.values.reduce(0, +), summary.peeks, summary.reminders,
            summary.focusExact, summary.focusAppOnly, summary.focusFailed,
            summary.suppressedByReason.values.reduce(0, +))
    }
}

private struct ActivityRow: View {
    let entry: ActivityEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(entry.at, format: .dateTime.month().day().hour().minute().second())
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(verbatim: entry.module?.rawValue ?? ActivityPaneModel.coreModule)
            Text(verbatim: entry.kind)
                .foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: entry.outcome.encoded)
                .font(.callout.monospaced())
        }
        .accessibilityElement(children: .combine)
    }
}
