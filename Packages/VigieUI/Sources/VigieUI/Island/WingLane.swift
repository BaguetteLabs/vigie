import SwiftUI

/// A short-lived readout the host slips into the left-wing lane (SPEC §5, DESIGN "Image to Text"): it sits
/// after the first item for `motion.confirm-readout` and pushes the last visible item into `+X` meanwhile.
public enum TransientReadout: Hashable, Sendable {
    /// `COPIED · 3 LINES`
    case copied(lines: Int)
    /// `NO TEXT FOUND`
    case noTextFound
    /// Text a module asked for, already localized (a drop handler's `DropResult.readout`, e.g. `NOT STASHED`).
    case message(String)
    /// A module's confirmation readout, already localized (a drop handler's `DropResult.confirmation`, e.g.
    /// `COPIED · 3 LINES`): `announcement` is posted to VoiceOver, `drains` draws the drain line.
    case confirmation(String, announcement: String?, drains: Bool)

    /// The readout text, uppercase, from the VigieUI catalog.
    public var text: String {
        switch self {
        case .copied(let lines): L10n.format("closed.copied.lines", lines)
        case .noTextFound: L10n.string("closed.noTextFound")
        case .message(let text): text
        case .confirmation(let text, _, _): text
        }
    }

    /// What VoiceOver announces when the readout appears ("Copied 3 lines"); nil for none.
    public var announcement: String? {
        switch self {
        case .copied(let lines): L10n.format("closed.copied.announcement", lines)
        case .noTextFound: L10n.string("closed.noTextFound.announcement")
        case .message: nil
        case .confirmation(_, let announcement, _): announcement
        }
    }

    /// True when the readout carries the 1px drain line (DESIGN "Copied readout").
    public var drains: Bool {
        switch self {
        case .copied, .noTextFound: true
        case .message: false
        case .confirmation(_, _, let drains): drains
        }
    }
}

/// The drain line of a transient readout while it shows (DESIGN "Copied readout"): running over the readout's
/// duration, or held full while the pointer is over the notch (the readout holds meanwhile).
public enum TransientDrain: Hashable, Sendable {
    /// Draining over `duration`; a new `trigger` restarts it from full.
    case draining(Duration, trigger: Int)
    /// Held full: the pointer is over the notch.
    case held
}

/// The 1px drain line of a transient readout, `copied-readout` drain inset above the island bottom, across the
/// left wing between its paddings. Under Reduce motion it is a static full line that disappears at the end
/// (``DrainLine``).
public struct TransientReadoutDrain: View {
    @Environment(\.vigieTheme) private var theme
    private let drain: TransientDrain

    public init(_ drain: TransientDrain) {
        self.drain = drain
    }

    /// `components.copied-readout.drain`: 6px above the island bottom.
    public static let bottomInset: CGFloat = 6

    public var body: some View {
        Group {
            switch drain {
            case .draining(let duration, let trigger):
                DrainLine(duration: duration, trigger: trigger)
            case .held:
                DrainLine(remaining: 1)
            }
        }
        .padding(.horizontal, theme.spacing(.wingPaddingX))
        .padding(.bottom, Self.bottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One wing of the closed island as a lane (SPEC §5, DESIGN "Overflow"): the shown entries side by side,
/// `spacing.glyph-gap` apart, then `+X` (readout-label style, `ink-3`) after the last visible entry when
/// some did not fit. Content is clipped to the frame the island gives the wing.
public struct WingLane: View {
    /// A lane entry; `id` keeps entry identity stable across re-arbitration.
    public struct Entry: Identifiable {
        public let id: String
        public let view: AnyView

        public init(id: String, view: AnyView) {
            self.id = id
            self.view = view
        }
    }

    @Environment(\.vigieTheme) private var theme
    private let entries: [Entry]
    private let overflowCount: Int

    public init(entries: [Entry], overflowCount: Int) {
        self.entries = entries
        self.overflowCount = overflowCount
    }

    /// The `+X` text, or nil when nothing overflows.
    public static func overflowText(_ count: Int) -> String? {
        count > 0 ? L10n.format("closed.overflow", count) : nil
    }

    public var body: some View {
        HStack(spacing: theme.spacing(.glyphGap)) {
            ForEach(entries) { entry in
                entry.view.fixedSize()
            }
            if let overflow = Self.overflowText(overflowCount) {
                Text(verbatim: overflow)
                    .font(theme.font(.readoutLabel))
                    .tracking(theme.tracking(.readoutLabel))
                    .foregroundStyle(theme.color(.ink3))
                    .fixedSize()
            }
        }
        .lineLimit(1)
        .clipped()
    }
}

/// A ``TransientReadout`` in the lane: readout-label style, `ink-1` (DESIGN "Image to Text").
public struct TransientReadoutView: View {
    @Environment(\.vigieTheme) private var theme
    private let readout: TransientReadout

    public init(_ readout: TransientReadout) {
        self.readout = readout
    }

    public var body: some View {
        Text(verbatim: readout.text)
            .font(theme.font(.readoutLabel))
            .tracking(theme.tracking(.readoutLabel))
            .foregroundStyle(theme.color(.ink1))
            .lineLimit(1)
            .accessibilityAddTraits(.updatesFrequently)
    }
}
