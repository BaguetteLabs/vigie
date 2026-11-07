import Foundation

/// The shape that carries a state's meaning on its own, so color is never the only cue (FR-63, DESIGN
/// "Status glyph", "Status vocabulary"; EXPERIENCE "Accessibility Floor"). Descriptors only: the glyph views
/// that draw them land with their surfaces.
public enum StatusGlyph: String, Sendable, CaseIterable, Equatable {
    // Chrome Hologram (A) session glyphs.
    /// Hollow ring (A idle; OK on the status vocabulary).
    case ring
    /// Turning open arc, a quarter ring (A working).
    case openArc
    /// Ring with a check and a tinted fill (A done).
    case ringCheck
    /// Solid diamond with a ripple outline (A blocked).
    case diamond
    /// Cross × (A failed; DOWN on the status vocabulary).
    case cross

    // Twin Metal Tactical (C) session glyphs.
    /// Dot in a circle (C idle).
    case dotInCircle
    /// Triangle inside a tick ring (C working).
    case triangleInTickRing
    /// Check in a circle (C done).
    case checkInCircle
    /// Solid square inside four corner brackets (C blocked).
    case squareInBrackets
    /// X inside a square frame (C failed).
    case crossInSquare

    // Neutral and shared glyphs.
    /// Dashed ring with a `?` inside (stale, both variants).
    case dashedRingQuestion
    /// Plain filled dot (process-only `RUNNING`, both variants).
    case dot
    /// Filled triangle (WARN on the status vocabulary; quota warning; shelf expiry).
    case triangle
    /// Hatched fill (quota warning bars and arcs).
    case hatch
    /// Solid fill (a meter or arc with nothing to flag).
    case solidFill
    /// No glyph of its own.
    case none
}

extension SessionStatus {
    /// The Chrome Hologram glyph (DESIGN "Status glyph" table, A column; stale from Story 1.7b).
    public var glyph: StatusGlyph {
        switch self {
        case .idle: .ring
        case .working: .openArc
        case .done: .ringCheck
        case .blocked: .diamond
        case .failed: .cross
        case .stale: .dashedRingQuestion
        }
    }

    /// The Twin Metal Tactical glyph (DESIGN "Status glyph" table, C column).
    public var tacticalGlyph: StatusGlyph {
        switch self {
        case .idle: .dotInCircle
        case .working: .triangleInTickRing
        case .done: .checkInCircle
        case .blocked: .squareInBrackets
        case .failed: .crossInSquare
        case .stale: .dashedRingQuestion
        }
    }

    /// The glyph for a theme: C shapes when the variant draws corner marks, else A.
    public func glyph(in theme: Theme) -> StatusGlyph {
        theme.defines(.structure) ? tacticalGlyph : glyph
    }
}

extension StatusMarkStyle.Shape {
    /// The shape as a ``StatusGlyph``.
    public var glyph: StatusGlyph {
        switch self {
        case .ring: .ring
        case .triangle: .triangle
        case .cross: .cross
        }
    }
}

extension StatusLevel {
    /// OK ring, WARN triangle, DOWN cross (DESIGN "Status vocabulary"), the same in every look.
    public var glyph: StatusGlyph { StatusMarkStyle(level: self, look: .dark).shape.glyph }
}

extension RunStatus {
    /// Running is the process-only dot; a failed exit is a cross with its `FAILED · EXIT n` label; levels
    /// use the status vocabulary.
    public var glyph: StatusGlyph {
        switch self {
        case .running: .dot
        case .failedExit: .cross
        case .ok, .warn, .down: level?.glyph ?? .none
        }
    }
}

/// Pace of a usage window (DESIGN "Pace and quota-warning colors"): within pace or ahead of it.
public enum PaceState: String, Sendable, CaseIterable, Equatable {
    /// Used ≤ elapsed + tolerance: `pace-on`, no label.
    case within
    /// Used > elapsed + tolerance: `pace-ahead`, labelled `AHEAD OF PACE` (EXPERIENCE "Accessibility Floor").
    case ahead

    public var colorRole: ColorRole {
        switch self {
        case .within: .paceOn
        case .ahead: .paceAhead
        }
    }

    /// The non-color cue: the fill shape and, when ahead, the text label.
    public var cue: NonColorCue {
        switch self {
        case .within: NonColorCue(glyph: .solidFill, label: nil)
        case .ahead: NonColorCue(glyph: .solidFill, label: L10n.string("usage.pace.ahead"))
        }
    }
}

/// Quota of a usage window: normal, or at or over the warning threshold (DESIGN "Pace and quota-warning
/// colors": never color-only, always hatch, triangle and `WARN`). Quota warning wins over pace-ahead.
public enum QuotaState: String, Sendable, CaseIterable, Equatable {
    case normal
    case warning

    /// The non-color cue: hatch and triangle with the `WARN` label when warning.
    public var cue: NonColorCue {
        switch self {
        case .normal: NonColorCue(glyph: .solidFill, label: nil)
        case .warning: NonColorCue(glyph: .hatch, secondaryGlyph: .triangle, label: L10n.string("status.warn"))
        }
    }
}

/// What tells a state apart without color: a glyph shape (plus an optional second mark) and a text label.
public struct NonColorCue: Sendable, Equatable, Hashable {
    public var glyph: StatusGlyph
    public var secondaryGlyph: StatusGlyph?
    public var label: String?

    public init(glyph: StatusGlyph, secondaryGlyph: StatusGlyph? = nil, label: String?) {
        self.glyph = glyph
        self.secondaryGlyph = secondaryGlyph
        self.label = label
    }
}
