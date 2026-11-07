import Foundation

/// Specified copy for empty and setup states (EXPERIENCE "Surface states", UX-DR44, UX-DR100), from the
/// VigieUI String Catalog. Labels are uppercase in the catalog itself; sentences are terse, factual and
/// end without an exclamation mark (Voice and Tone). Modules pass these to ``EmptyStateBlock`` and
/// ``SetupCard``.
public enum VigieCopy {
    /// An empty state: uppercase label and an optional sentence.
    public struct EmptyState: Sendable {
        public let label: LocalizedStringResource
        public let sentence: LocalizedStringResource?

        public init(label: LocalizedStringResource, sentence: LocalizedStringResource? = nil) {
            self.label = label
            self.sentence = sentence
        }
    }

    /// A setup card: topic (for the `SETUP · <topic>` kicker), title, sentence and the two button labels.
    public struct Setup: Sendable {
        public let topic: LocalizedStringResource
        public let title: LocalizedStringResource
        public let sentence: LocalizedStringResource
        public let primaryAction: LocalizedStringResource
        public let secondaryAction: LocalizedStringResource

        public init(
            topic: LocalizedStringResource,
            title: LocalizedStringResource,
            sentence: LocalizedStringResource,
            primaryAction: LocalizedStringResource,
            secondaryAction: LocalizedStringResource
        ) {
            self.topic = topic
            self.title = title
            self.sentence = sentence
            self.primaryAction = primaryAction
            self.secondaryAction = secondaryAction
        }
    }

    // MARK: Agents

    /// `NO AGENT CONNECTED` · "Connect Claude Code, Codex or Gemini in Settings."
    public static var noAgentConnected: EmptyState {
        empty("empty.agents.noAgent")
    }

    /// `NO ACTIVE SESSIONS` · "Agent sessions appear here when they start."
    public static var noActiveSessions: EmptyState {
        empty("empty.agents.noSessions")
    }

    // MARK: Expanded view

    /// `NO TABS` · "Turn on a module in Settings to add a tab."
    public static var noTabs: EmptyState {
        empty("empty.expanded")
    }

    // MARK: Home

    /// `NO WIDGETS` · "Pick Home widgets in Settings."
    public static var noWidgets: EmptyState {
        empty("empty.home")
    }

    // MARK: Usage

    /// `NO USAGE PROVIDER` · one sentence; show with `Open settings ⌘,`.
    public static var noUsageProvider: EmptyState {
        empty("empty.usage")
    }

    /// `READING LOGS…` before the first read.
    public static var readingLogs: EmptyState {
        EmptyState(label: L10n.resource("empty.usage.readingLogs.label"))
    }

    /// `NO HISTORY YET` (7-day history).
    public static var noHistoryYet: EmptyState {
        EmptyState(label: L10n.resource("empty.usage.noHistory.label"))
    }

    /// `NO COST DATA` (cost, under `—`).
    public static var noCostData: EmptyState {
        EmptyState(label: L10n.resource("empty.usage.noCost.label"))
    }

    // MARK: Shelf

    /// `STASH EMPTY` · "Drag a file, text or image onto the notch, or press ⌘V, to keep it here for N days."
    public static func stashEmpty(days: Int) -> EmptyState {
        EmptyState(
            label: L10n.resource("empty.shelf.label"),
            sentence: LocalizedStringResource(
                "empty.shelf.sentence",
                defaultValue:
                    "Drag a file, text or image onto the notch, or press ⌘V, to keep it here for \(days) days.",
                bundle: .atURL(Bundle.module.bundleURL)))
    }

    // MARK: Calendar

    /// `NO EVENTS TODAY`.
    public static var noEventsToday: EmptyState {
        EmptyState(label: L10n.resource("empty.calendar.label"))
    }

    /// Calendar access missing: `SETUP · CALENDAR ACCESS`, "Vigie can't read your calendars",
    /// `Open System Settings` and `Calendar settings`.
    public static var calendarAccess: Setup {
        Setup(
            topic: L10n.resource("setup.calendar.topic"),
            title: L10n.resource("setup.calendar.title"),
            sentence: L10n.resource("setup.calendar.sentence"),
            primaryAction: openSystemSettings,
            secondaryAction: L10n.resource("setup.calendar.secondary"))
    }

    // MARK: Time

    /// `NOTHING RUNNING`.
    public static var nothingRunning: EmptyState {
        EmptyState(label: L10n.resource("empty.time.label"))
    }

    // MARK: Notes

    /// `NO NOTES` · "Press ⌥⌘N to write one."
    public static var noNotes: EmptyState {
        empty("empty.notes")
    }

    /// `NO MATCH` (search).
    public static var noMatch: EmptyState {
        EmptyState(label: L10n.resource("empty.notes.noMatch.label"))
    }

    /// `NOTES LOCKED` · "Waiting for iCloud Keychain, or enter your recovery key."
    public static var notesLocked: EmptyState {
        empty("empty.notes.locked")
    }

    // MARK: Shared

    /// `Open settings` (empty states, setup-problem alerts).
    public static var openSettings: LocalizedStringResource { L10n.resource("action.openSettings") }

    /// `Open System Settings` (setup cards).
    public static var openSystemSettings: LocalizedStringResource { L10n.resource("action.openSystemSettings") }

    /// `SCROLL ↓` footer hint.
    public static var scrollHint: LocalizedStringResource { L10n.resource("scroll.hint") }

    /// `SETUP · CALENDAR ACCESS`.
    public static func setupKicker(topic: String) -> String {
        L10n.format("setup.kicker", topic)
    }

    private static func empty(_ prefix: String) -> EmptyState {
        EmptyState(label: L10n.resource("\(prefix).label"), sentence: L10n.resource("\(prefix).sentence"))
    }
}
