import Foundation

/// One decrypted note (Story 15.2). Lives in memory only (AD-10): its `description`, `debugDescription` and mirror
/// show the id and the body length, never the title or the body, so a stray `print` or interpolation in a log
/// cannot leak note text.
public struct Note: Identifiable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    /// Longest title kept, in characters.
    public static let maxTitleLength = 120

    /// Stable across edits: the file is `<id>.vnote`.
    public let id: UUID
    /// The first non-empty line of the body, trimmed (leading Markdown `#` removed), at most ``maxTitleLength``
    /// characters; a conflict copy carries `<title> (conflict)` until its body is edited.
    public var title: String
    /// Markdown.
    public var body: String
    public var created: Date
    public var modified: Date

    public init(id: UUID = UUID(), title: String, body: String, created: Date, modified: Date) {
        self.id = id
        self.title = title
        self.body = body
        self.created = created
        self.modified = modified
    }

    /// A note whose title is derived from `body`.
    public init(id: UUID = UUID(), body: String, created: Date, modified: Date) {
        self.init(id: id, title: Note.title(of: body), body: body, created: created, modified: modified)
    }

    /// The title of a body: its first non-empty line, trimmed, without leading Markdown heading marks, cut to
    /// ``maxTitleLength`` characters. Empty when the body has no text.
    public static func title(of body: String) -> String {
        for line in body.split(whereSeparator: \.isNewline) {
            var text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("#") {
                text = String(text.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            }
            guard !text.isEmpty else { continue }
            return String(text.prefix(maxTitleLength))
        }
        return ""
    }

    /// The file name of a note id.
    public static func fileName(for id: UUID) -> String {
        "\(id.uuidString.lowercased()).\(NotesFolder.noteExtension)"
    }

    public var description: String { "Note(\(id.uuidString.lowercased()), \(body.count) chars)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["id": id, "bodyLength": body.count]) }
}
