import ModuleKit
import SwiftUI
import VigieUI

/// The Calendar pane's own part, below the generated `reminders` and `hide_all_day` rows (Story 13.1): the
/// calendars to include as checkboxes grouped by account, each with its calendar color, or the setup card's copy
/// while access is missing. Native controls (DESIGN "Settings window").
struct CalendarSettingsView: View {
    let module: CalendarModule
    @State private var failure: String?

    var body: some View {
        Group {
            switch module.access {
            case .unknown:
                EmptyView()
            case .missing:
                accessMissing
            case .granted:
                calendarList
            }
        }
        .task { await module.recheckAccess() }
    }

    private var accessMissing: some View {
        let copy = VigieCopy.calendarAccess
        return VStack(alignment: .leading) {
            Text(copy.title).font(.headline)
            Text(copy.sentence).font(.callout).foregroundStyle(.secondary)
            Button {
                module.openSystemSettings()
            } label: {
                Text(copy.primaryAction)
            }
        }
    }

    @ViewBuilder private var calendarList: some View {
        Text(CalendarText.resource("calendar.setting.calendars")).font(.headline)
        if module.calendars.isEmpty {
            Text(CalendarText.resource("calendar.settings.noCalendars")).font(.callout).foregroundStyle(.secondary)
        }
        ForEach(CalendarSettingsView.groups(module.calendars), id: \.account) { group in
            VStack(alignment: .leading) {
                Text(verbatim: group.account).font(.subheadline).foregroundStyle(.secondary).sensitive()
                ForEach(group.calendars) { info in
                    Toggle(isOn: binding(info.id)) {
                        Label {
                            Text(verbatim: info.title).sensitive()
                        } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(info.color.color)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
        if let failure {
            Text(verbatim: failure).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { module.isIncluded(id) },
            set: { on in
                Task { @MainActor in
                    do {
                        try await module.setIncluded(id, on)
                        failure = nil
                    } catch {
                        failure = String(describing: error)
                    }
                }
            })
    }

    /// Calendars grouped by account, in the module's order (account, then title).
    static func groups(_ calendars: [CalendarInfo]) -> [(account: String, calendars: [CalendarInfo])] {
        var result: [(account: String, calendars: [CalendarInfo])] = []
        for info in calendars {
            if let index = result.firstIndex(where: { $0.account == info.account }) {
                result[index].calendars.append(info)
            } else {
                result.append((info.account, [info]))
            }
        }
        return result
    }
}
