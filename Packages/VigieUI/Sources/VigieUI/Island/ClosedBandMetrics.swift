import SwiftUI

/// Closed-notch sizes derived from the band the island gives its content (Story 2.16, SPEC §5.5).
///
/// The closed-notch components are designed for the 34 px band of a notched MacBook (DESIGN
/// `spacing.band-height`). A virtual notch is exactly as tall as its display's menu bar (24 pt on a default
/// external display), and the host hands its content a theme whose `spacing.band-height` is that height
/// (``Theme/withBandHeight(_:)``). Views read their closed-notch sizes here so they scale to that band:
///
/// - a ring or glyph alone on the row is capped at the band minus ``minimumInset`` above and below
///   (``rowLength(_:)``): a 16 px session glyph stays 16 px in a 24 pt band, a 23 px ring becomes 20 pt;
/// - a two-row readout (value over label) scales together by ``scale``, the band over the designed band
///   (``stackedLength(_:)``, ``fontSpec(_:in:)``), so it keeps its proportions;
/// - a dial drops the name under it (``isCompact``) and keeps the row at ``rowLength(_:)``.
///
/// At the designed band or taller (`scale == 1`, ``isCompact`` false) every value is the designed one, so the
/// physical-notch band, the expanded view and the peeks (whose bands are never lower than 34 px) are unchanged.
/// Romain's ruling: no legibility floor, the content follows the band.
public struct ClosedBandMetrics: Sendable, Equatable {
    /// The band the closed-notch components are designed for (DESIGN `spacing.band-height`).
    public static let designedBandHeight: CGFloat = 34
    /// Space kept above and below a ring or glyph that has to shrink to fit a short band.
    public static let minimumInset: CGFloat = 2

    /// The band height the island gives its content.
    public let bandHeight: CGFloat

    public init(bandHeight: CGFloat) {
        self.bandHeight = bandHeight
    }

    /// The band of the theme in the environment (`spacing.band-height`).
    public init(theme: Theme) {
        self.init(bandHeight: theme.spacing(.bandHeight))
    }

    /// True when the band is shorter than designed. A theme without a band (0) is not compact.
    public var isCompact: Bool { bandHeight > 0 && bandHeight < Self.designedBandHeight }

    /// The band over the designed band, at most 1: what two-row stacks are scaled by.
    public var scale: CGFloat { isCompact ? bandHeight / Self.designedBandHeight : 1 }

    /// The tallest a single-row ring or glyph may be in a compact band.
    public var maxRowLength: CGFloat { max(bandHeight - 2 * Self.minimumInset, 0) }

    /// A ring or glyph of `designed` side alone on the row: unchanged when it fits, else capped to the band.
    public func rowLength(_ designed: CGFloat) -> CGFloat {
        isCompact ? min(designed, maxRowLength) : designed
    }

    /// A length inside a two-row readout (the gap between value and label).
    public func stackedLength(_ designed: CGFloat) -> CGFloat { designed * scale }

    /// A typography role for a two-row readout: size, tracking and line height scaled by ``scale``.
    public func fontSpec(_ role: TypographyRole, in theme: Theme) -> FontSpec {
        var spec = theme.fontSpec(role)
        guard isCompact else { return spec }
        spec.size *= scale
        spec.tracking *= scale
        spec.lineHeight = spec.lineHeight.map { $0 * scale }
        return spec
    }
}

extension Theme {
    /// The closed-notch sizes for this theme's band (``ClosedBandMetrics``).
    public var closedBand: ClosedBandMetrics { ClosedBandMetrics(theme: self) }
}
