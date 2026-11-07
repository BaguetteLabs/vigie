import SwiftUI

/// A short-lived readout the host slips into the left-wing lane (SPEC §5, DESIGN "Image to Text"): it sits
/// after the first item for `motion.confirm-readout` and pushes the last visible item into `+X` meanwhile.
public enum TransientReadout: Hashable, Sendable {
    /// `COPIED · 3 LINES`
    case copied(lines: Int)
    /// `NO TEXT FOUND`
    case noTextFound

    /// The readout text, uppercase, from the VigieUI catalog.
    public var text: String {
        switch self {
        case .copied(let lines): L10n.format("closed.copied.lines", lines)
        case .noTextFound: L10n.string("closed.noTextFound")
        }
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
