import Foundation

/// The floating panel's copy (catalog-backed, Story 15.3).
enum NotesPanelText {
    /// `NOTES · <title>` (`NOTES · UNTITLED` for an empty title), as one string: VoiceOver and tests. The panel
    /// draws the title apart so Privacy mode can mask it.
    static func header(title: String) -> String {
        NotesText.format("notes.panel.header", title.isEmpty ? NotesText.string("notes.untitled") : title)
            .uppercased(with: NotesText.catalogLocale)
    }

    /// `SYNCED · ENCRYPTED · ESC`, or `ENCRYPTED · ESC` when the folder is not in iCloud Drive.
    static func meta(synced: Bool) -> LocalizedStringResource {
        NotesText.resource(synced ? "notes.panel.meta.synced" : "notes.panel.meta")
    }

    /// `EDITED 14:31`: the edit time, short, in `locale`.
    static func edited(_ date: Date, locale: Locale, timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
        style.timeZone = timeZone
        return NotesText.format("notes.panel.edited", date.formatted(style))
    }
}
