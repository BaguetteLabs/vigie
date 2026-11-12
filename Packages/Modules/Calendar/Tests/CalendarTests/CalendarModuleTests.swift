import Foundation
import ModuleKit
import SwiftUI
import Testing

@testable import Calendar

@MainActor
struct Harness {
    let source: FakeCalendarSource
    let context: FakeModuleContext
    let module: CalendarModule
    let activations: AsyncStream<Void>.Continuation
    let opened: Recorder

    @MainActor final class Recorder {
        var urls: [URL] = []
        var panes: [String] = []
    }

    init(
        settings: [String: any SettingValue] = [:], access: PermissionStatus = .notDetermined,
        answer: PermissionStatus = .granted, source: FakeCalendarSource = FakeCalendarSource()
    ) {
        self.source = source
        context = FakeModuleContext(settings: settings, calendarAccess: access, answer: answer)
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        activations = continuation
        let opened = Recorder()
        self.opened = opened
        nonisolated(unsafe) let activationStream = stream
        module = CalendarModule(
            source: source,
            openSettings: { pane in opened.panes.append(pane) },
            openURL: { url in opened.urls.append(url) },
            activations: { activationStream },
            now: { Fixture.start },
            calendar: Fixture.calendar)
    }

    func start() async throws { try await module.start(context: context) }
}

/// Polls `condition` on the main actor for up to two seconds.
@MainActor
func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

@MainActor @Suite struct CalendarModuleTests {
    // MARK: Manifest and closed notch

    @Test func manifestDeclaresCalendarAccessAndIsOffByDefault() {
        let manifest = CalendarModule.staticManifest
        #expect(manifest.id == "calendar")
        #expect(manifest.icon == "calendar")
        #expect(manifest.permissions == [.calendar])
        #expect(!manifest.defaultEnabled)
        #expect(manifest.startsWithoutPermissions)
        #expect(manifest.alertKinds.isEmpty)  // calendar.reminder arrives with Story 13.4
        let settings = Dictionary(uniqueKeysWithValues: manifest.settings.map { ($0.key, $0) })
        #expect(settings["reminders"]?.kind == .bool(default: true))
        #expect(settings["hide_all_day"]?.kind == .bool(default: false))
        #expect(settings["calendars"]?.kind == .list(of: .string, default: []))
        #expect(settings["calendars"]?.customControl == true)
        #expect(settings["reminders"]?.customControl == false)
        #expect(settings.keys.contains("lead_time") == false)  // amended 2026-11-07
    }

    @Test func noClosedNotchGlance() async throws {
        let h = Harness(access: .granted)
        try await h.start()
        #expect(h.module.leftWingItems().isEmpty)
        for size in CompactSize.allCases { #expect(h.module.compactView(size: size) == nil) }
        #expect(h.module.homeCard() == nil)
        #expect(h.module.dropZones.isEmpty)
        #expect(h.module.expandedView() != nil)
        #expect(h.module.settingsView() != nil)
        #expect(h.module.state == .hidden)
        await h.module.stop()
    }

    // MARK: Access

    @Test func notStartedTouchesNothing() async throws {
        // Disabled (the default) means the Registry never calls start: building the module asks nothing.
        let h = Harness()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(h.context.fakePermissions.requests.isEmpty)
        #expect(h.context.fakePermissions.statusChecks == 0)
        #expect(h.source.totalCalls == 0)
        #expect(h.module.access == .unknown)
        #expect(h.module.tabContent == .checking)
    }

    @Test func enabledStartAsksOnceThenOnlyRechecks() async throws {
        let h = Harness(access: .notDetermined, answer: .granted)
        try await h.start()
        #expect(h.context.fakePermissions.requests == [.calendar])
        #expect(h.module.access == .granted)
        h.activations.yield()
        await h.module.recheckAccess()
        #expect(await eventually { h.context.fakePermissions.statusChecks >= 3 })
        #expect(h.context.fakePermissions.requests == [.calendar])
        await h.module.stop()
    }

    @Test func alreadyGrantedIsNotAskedAgain() async throws {
        let h = Harness(access: .granted)
        try await h.start()
        #expect(h.context.fakePermissions.requests.isEmpty)
        #expect(h.module.access == .granted)
        #expect(h.source.accessResets == 1)
        await h.module.stop()
    }

    @Test(arguments: [PermissionStatus.denied, .notDetermined])
    func deniedShowsTheSetupCard(answer: PermissionStatus) async throws {
        let h = Harness(access: .notDetermined, answer: answer)
        try await h.start()
        #expect(h.module.access == .missing)
        #expect(h.module.tabContent == .setup)
        #expect(h.module.events.isEmpty && h.module.calendars.isEmpty)
        #expect(h.source.totalCalls == 0)
        #expect(h.source.subscribers == 0)
        await h.module.stop()
    }

    @Test func setupCardButtonsOpenSystemSettingsAndThePane() async throws {
        let h = Harness(access: .denied)
        try await h.start()
        #expect(h.context.fakePermissions.requests.isEmpty)  // denied is final: macOS would not ask again
        h.module.openSystemSettings()
        h.module.openCalendarSettings()
        #expect(
            h.opened.urls == [URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!]
        )
        #expect(h.opened.panes == ["calendar"])
        await h.module.stop()
    }

    @Test func grantInSystemSettingsIsSeenOnActivation() async throws {
        let h = Harness(access: .denied)
        try await h.start()
        #expect(h.module.access == .missing)
        h.context.fakePermissions.set(.granted)
        h.activations.yield()
        #expect(await eventually { h.module.access == .granted && !h.module.events.isEmpty })
        #expect(h.context.fakePermissions.requests.isEmpty)
        // Revoked later: back to the setup card, nothing kept.
        h.context.fakePermissions.set(.denied)
        h.activations.yield()
        #expect(await eventually { h.module.access == .missing })
        #expect(h.module.events.isEmpty && h.module.tabContent == .setup)
        await h.module.stop()
    }

    @Test func tabAppearingRechecksAccess() async throws {
        let h = Harness(access: .denied)
        try await h.start()
        h.context.fakePermissions.set(.granted)
        await h.module.recheckAccess()  // what the tab's and the pane's `.task` call
        #expect(h.module.access == .granted)
        await h.module.stop()
    }

    // MARK: Events

    @Test func grantedLoadsTodayThroughTheNext14Days() async throws {
        let h = Harness(access: .granted)
        try await h.start()
        let window = try #require(h.module.window)
        #expect(window.start == Sample.at(day: 6, hour: 0))
        #expect(window.end == Sample.at(day: 21, hour: 0))
        #expect(h.module.events.map(\.eventID) == ["holiday", "standup", "dinner", "review"])
        #expect(h.module.calendars.map(\.id) == ["work", "family", "personal"])  // account, then title
        #expect(h.source.eventQueries.last?.calendars == nil)  // all calendars
        #expect(h.module.todayEvents.map(\.eventID) == ["holiday", "standup"])
        #expect(h.module.tabContent == .grid(todayCount: 2))
        #expect(h.module.events.first { $0.eventID == "standup" }?.alarms == [.relative(-600)])
        await h.module.stop()
    }

    @Test func hideAllDayFiltersAllDayEvents() async throws {
        let h = Harness(settings: ["hide_all_day": true], access: .granted)
        try await h.start()
        #expect(h.module.options.hideAllDay)
        #expect(h.module.events.map(\.eventID) == ["standup", "dinner", "review"])
        try await h.context.fakeSettings.set(false, for: "hide_all_day")
        #expect(await eventually { h.module.events.count == 4 })
        await h.module.stop()
    }

    @Test func includedCalendarsFilterTheQuery() async throws {
        let h = Harness(settings: ["calendars": ["work"]], access: .granted)
        try await h.start()
        #expect(h.source.eventQueries.last?.calendars == ["work"])
        #expect(h.module.events.map(\.eventID) == ["standup", "review"])
        #expect(h.module.calendars.count == 3)  // Settings still lists every calendar
        try await h.context.fakeSettings.set(["work", "family"], for: "calendars")
        #expect(await eventually { h.module.events.map(\.eventID) == ["standup", "dinner", "review"] })
        await h.module.stop()
    }

    @Test func storeChangeReloads() async throws {
        let h = Harness(access: .granted)
        try await h.start()
        #expect(await eventually { h.source.subscribers == 1 })
        let added = Sample.event("added", calendar: "work", day: 8, hour: 11)
        h.source.setEvents(Sample.events + [added])
        h.source.sendChange()
        #expect(await eventually { h.module.events.contains { $0.eventID == "added" } })
        await h.module.stop()
        #expect(await eventually { h.source.subscribers == 0 })
    }

    @Test func hourlyReloadIsScheduledAndCancelledOnStop() async throws {
        let h = Harness(access: .granted)
        try await h.start()
        let job = try #require(h.context.fakeScheduler.liveRepeating.first)
        #expect(job.interval == .seconds(3600))
        let before = h.source.eventQueries.count
        await job.body()
        #expect(h.source.eventQueries.count == before + 2)  // the 15-day window and the grid month
        await h.module.stop()
        #expect(h.context.fakeScheduler.liveRepeating.isEmpty)
    }

    @Test func noReloadWithoutAccess() async throws {
        let h = Harness(access: .denied)
        try await h.start()
        await h.module.reload()
        await h.context.fakeScheduler.liveRepeating.first?.body()
        #expect(h.source.totalCalls == 0)
        await h.module.stop()
    }

    // MARK: Settings

    @Test func uncheckingFromAllWritesTheOthers() async throws {
        let h = Harness(access: .granted)
        try await h.start()
        #expect(h.module.isIncluded("family"))
        try await h.module.setIncluded("family", false)
        #expect(h.context.fakeSettings.value("calendars", as: [String].self) == ["work", "personal"])
        #expect(!h.module.isIncluded("family"))
        #expect(await eventually { !h.module.events.contains { $0.calendarID == "family" } })
        try await h.module.setIncluded("family", true)
        #expect(h.context.fakeSettings.value("calendars", as: [String].self) == [])
        #expect(h.module.isIncluded("family"))
        await h.module.stop()
    }

    @Test func includedListKeepsStoreOrderAndCollapsesToAll() {
        let all = ["a", "b", "c"]
        #expect(CalendarModule.includedList(current: [], all: all, toggling: "b", on: false) == ["a", "c"])
        #expect(CalendarModule.includedList(current: ["c"], all: all, toggling: "a", on: true) == ["a", "c"])
        #expect(CalendarModule.includedList(current: ["a", "c"], all: all, toggling: "b", on: true) == [])
        // The last checked calendar stays on: an empty list would mean every calendar.
        #expect(CalendarModule.includedList(current: ["a"], all: all, toggling: "a", on: false) == ["a"])
    }

    @Test func settingsGroupsByAccount() {
        let groups = CalendarSettingsView.groups([Sample.work, Sample.family, Sample.personal])
        #expect(groups.map(\.account) == ["Google", "iCloud"])
        #expect(groups[1].calendars.map(\.id) == ["family", "personal"])
    }

    // MARK: Catalog

    @Test func everyCatalogKeyHasEveryLocaleAndResolves() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Calendar/Resources/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let strings = try #require(catalog?["strings"] as? [String: Any])
        var locales: Set<String> = []
        for case let entry as [String: Any] in strings.values {
            locales.formUnion((entry["localizations"] as? [String: Any])?.keys ?? [:].keys)
        }
        #expect(locales.contains("en"))
        for key in strings.keys {
            let entry = try #require(strings[key] as? [String: Any])
            let localized = Set((entry["localizations"] as? [String: Any])?.keys ?? [:].keys)
            #expect(localized == locales, "\(key) is missing a locale")
            #expect(CalendarText.string(key) != key, "\(key) does not resolve")
        }
        for descriptor in CalendarModule.staticManifest.settings {
            #expect(!String(localized: descriptor.label).hasPrefix("calendar."), "\(descriptor.key) label")
        }
        #expect(String(localized: CalendarModule.staticManifest.name) == "Calendar")
        #expect(CalendarModule.todayLabel(count: 3) == "3 EVENTS TODAY")
        #expect(CalendarModule.todayLabel(count: 1) == "1 EVENT TODAY")
    }
}
