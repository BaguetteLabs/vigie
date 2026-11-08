import SwiftUI

/// A plan window a quota dial can show (SPEC §7.2: 5h, weekly, daily). The raw value is the window name
/// usage providers report (`UsageWindow.name`).
public enum QuotaWindowKind: String, Sendable, Hashable, CaseIterable {
    case fiveHour = "5h"
    case weekly
    case daily

    /// The window part of the readout label, uppercase: `5H`, `WEEK`, `DAY`.
    public var readoutLabel: String { L10n.string("usage.window.\(rawValue).short") }

    /// The spoken window name: "5 hour window", "weekly", "daily".
    public var spokenName: String { L10n.string("usage.window.\(rawValue).spoken") }

    /// The window's length. Plan endpoints report only `resets_at`, so the start is `resetsAt − length`
    /// (Story 7.5).
    public var length: TimeInterval {
        switch self {
        case .fiveHour: 5 * 3600
        case .weekly: 7 * 24 * 3600
        case .daily: 24 * 3600
        }
    }

    /// The share of the window elapsed at `now`, clamped to 0…1: 0 before the window starts, 1 once it has
    /// reset (until the next refresh brings the new window). nil without a reset time.
    public func elapsedFraction(resetsAt: Date?, now: Date) -> Double? {
        guard let resetsAt else { return nil }
        let start = resetsAt.addingTimeInterval(-length)
        let elapsed = now.timeIntervalSince(start) / length
        return elapsed.isFinite ? min(1, max(0, elapsed)) : nil
    }
}

/// What one provider's quota dial shows (DESIGN "Quota dial"; UX-DR16, UX-DR58).
///
/// `primary` is the inner ring and the value inside: the 5h window, or the only window the plan has.
/// `secondary` is the outer, thinner weekly ring, present only when both are tracked (`rings = "5h+weekly"`).
/// A model built with only `secondary` is normalized so that window becomes `primary`: a single window is
/// always one ring at single-ring size, never an empty ring.
public struct QuotaDialModel: Hashable, Sendable {
    /// One window's share used.
    public struct Window: Hashable, Sendable {
        public var kind: QuotaWindowKind
        /// Share used, clamped to 0…1.
        public var fraction: Double
        public var resetsAt: Date?
        /// The share of the window elapsed, 0…1, when this is the paced window and `pace` is on (Story 7.5):
        /// the dial draws the pace tick there. nil = no tick, `pace-on` fill.
        public var elapsedFraction: Double?
        /// `pace_tolerance` in points (default 5): ahead only when used > elapsed + tolerance.
        public var paceTolerance: Int
        /// At or over the provider's `warn_threshold` (Story 7.6): hatched `quota-warning` arc, triangle on the
        /// ring centre; wins over pace-ahead.
        public var isWarning: Bool

        public init(
            kind: QuotaWindowKind, fraction: Double, resetsAt: Date? = nil, elapsedFraction: Double? = nil,
            paceTolerance: Int = QuotaDialModel.defaultPaceTolerance, isWarning: Bool = false
        ) {
            self.kind = kind
            self.fraction = fraction.isFinite ? min(1, max(0, fraction)) : 0
            self.resetsAt = resetsAt
            self.elapsedFraction = elapsedFraction.map { $0.isFinite ? min(1, max(0, $0)) : 0 }
            self.paceTolerance = max(0, paceTolerance)
            self.isWarning = isWarning
        }

        /// Normal or warning (DESIGN "Pace and quota-warning colors").
        public var quota: QuotaState { isWarning ? .warning : .normal }

        /// Within or ahead of pace (FR52); nil when the window is not paced. Compared in points, so the
        /// tolerance edge itself is within pace.
        public var pace: PaceState? {
            guard let elapsedFraction else { return nil }
            let lead = fraction * 100 - elapsedFraction * 100
            return lead > Double(paceTolerance) + 1e-9 ? .ahead : .within
        }

        /// The window part of the readout label (`5H`, `WEEK`).
        public var label: String { kind.readoutLabel }

        /// Whole percent used, 0…100.
        public var percent: Int { Int((fraction * 100).rounded()) }
    }

    /// `pace_tolerance` default, in points (SPEC §11).
    public static let defaultPaceTolerance = 5

    /// The provider name as the user knows it (`Claude`); shown uppercase.
    public var providerName: String
    public private(set) var primary: Window?
    public private(set) var secondary: Window?
    /// The last refresh failed: the values are the last good ones, drawn in the stale look.
    public var stale: Bool
    /// A window the dial does not draw (weekly with `rings = "5h"`) is at or over the threshold: the triangle
    /// still replaces the value.
    public var hiddenWarning: Bool

    public init(
        providerName: String, primary: Window?, secondary: Window? = nil, stale: Bool = false,
        hiddenWarning: Bool = false
    ) {
        self.providerName = providerName
        self.primary = primary ?? secondary
        self.secondary = primary == nil ? nil : secondary
        self.stale = stale
        self.hiddenWarning = hiddenWarning
    }

    /// Any window of the provider is in quota warning (A36: the triangle replaces the value).
    public var hasWarning: Bool {
        hiddenWarning || primary?.isWarning == true || secondary?.isWarning == true
    }

    /// Both rings are drawn, nested.
    public var isNested: Bool { primary != nil && secondary != nil }

    /// Whether there is anything to draw.
    public var hasWindow: Bool { primary != nil }

    /// The value inside the ring (and in the single-provider readout): the primary window's percent.
    public var valueText: String? { primary.map { String($0.percent) } }

    /// `CLAUDE` under the ring (readout-label style).
    public var nameLabel: String { providerName.uppercased(with: L10n.catalogLocale) }

    /// Single-provider readout value: `38 %`.
    public var readoutValue: String? { primary.map { L10n.format("usage.readout.percent", $0.percent) } }

    /// Single-provider readout label: the provider and the window the value belongs to, `CLAUDE · 5H` or
    /// `CLAUDE · WEEK` (UX-DR17).
    public var readoutLabel: String {
        guard let primary else { return nameLabel }
        return L10n.format("usage.readout.label", nameLabel, primary.label)
    }

    /// "Claude, 5 hour window 38 percent, weekly 52 percent"; absent windows are left out; a window ahead of
    /// pace adds "ahead of pace" (not under a quota warning, which wins); a quota warning prefixes "Quota
    /// warning".
    public var accessibilityLabel: String {
        let windows = [primary, secondary].compactMap { $0 }.map { window in
            let base = L10n.format("usage.dial.a11y.window", window.kind.spokenName, window.percent)
            return !window.isWarning && window.pace == .ahead ? L10n.format("usage.dial.a11y.ahead", base) : base
        }
        var label = providerName
        for window in windows {
            label = L10n.format("usage.dial.a11y.join", label, window)
        }
        if stale { label = L10n.format("usage.dial.a11y.stale", label) }
        return hasWarning ? L10n.format("usage.dial.a11y.warning", label) : label
    }
}

/// The three dial sizes (DESIGN `components.quota-dial`).
public enum QuotaDialSize: Sendable, Hashable, CaseIterable {
    /// 24 px: a ring on the left wing (alone, or next to non-ring items).
    case wing
    /// 23 px: the stacked multi-provider layout.
    case stacked
    /// 58 px: the Usage tab card (Story 7.7).
    case tab

    var tokenKey: String {
        switch self {
        case .wing: "size"
        case .stacked: "size-stacked"
        case .tab: "size-usage-tab"
        }
    }

    /// The DESIGN value, used only if a theme lacks the token.
    var fallback: CGFloat {
        switch self {
        case .wing: 24
        case .stacked: 23
        case .tab: 58
        }
    }

    /// The side length in points, from `components.quota-dial.<size>`.
    public func length(in theme: Theme) -> CGFloat {
        theme.componentLength("quota-dial", tokenKey) ?? fallback
    }
}

/// One provider's quota dial with its name under it (DESIGN "Quota dial"; UX-DR16): track ring in `line`; the
/// inner (or only) ring in `pace-on` (A iris gradient, C Volt; flat silver in Calm, solid under Reduce
/// transparency / Increase contrast) or `pace-ahead` when ahead of pace, the outer weekly ring thinner in A
/// `line-silver` / C `struct`; the pace tick on the paced window (Story 7.5); the primary value inside. C adds the dashed tick bezel turning every `motion.dial-bezel`. Stale keeps the last values
/// with a dashed `ink-3` track and neutral arcs. On the island the theme is the dark look (UX-DR12).
///
/// At `.tab` size no name is drawn (the Usage card header names the provider).
public struct QuotaDialView: View {
    @Environment(\.vigieTheme) private var theme
    private let model: QuotaDialModel
    private let size: QuotaDialSize
    private let showsName: Bool
    private let showsValue: Bool

    /// - Parameters:
    ///   - showsName: the provider name under the ring (ignored at `.tab`).
    ///   - showsValue: the primary value inside the ring (off in the single-provider readout, which carries it).
    public init(model: QuotaDialModel, size: QuotaDialSize, showsName: Bool = true, showsValue: Bool = true) {
        self.model = model
        self.size = size
        self.showsName = showsName && size != .tab
        self.showsValue = showsValue
    }

    public var body: some View {
        let length = size.length(in: theme)
        VStack(spacing: length / 24) {
            QuotaDialRing(model: model, length: length, showsValue: showsValue)
            if showsName {
                Text(verbatim: model.nameLabel)
                    .font(theme.font(.readoutLabel))
                    .tracking(theme.tracking(.readoutLabel))
                    .foregroundStyle(theme.color(.ink2))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: model.accessibilityLabel))
    }
}

/// The single-provider left wing (DESIGN "Closed, left wing"; UX-DR17): the dial (no value inside) followed by
/// a readout, `38 %` over `CLAUDE · 5H` (or `CLAUDE · WEEK` for a plan without 5h).
public struct QuotaReadoutView: View {
    @Environment(\.vigieTheme) private var theme
    private let model: QuotaDialModel

    public init(model: QuotaDialModel) {
        self.model = model
    }

    public var body: some View {
        HStack(spacing: theme.spacing(.glyphGap)) {
            QuotaDialRing(model: model, length: QuotaDialSize.wing.length(in: theme), showsValue: false)
            WingReadout(value: model.readoutValue ?? "", label: model.readoutLabel, stale: model.stale)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: model.accessibilityLabel))
    }
}

/// A closed-notch readout (DESIGN "Readout"): value over label, `typography.*-readout-value` in `ink-1` over
/// `*-readout-label` in `ink-3`. Stale values are drawn in `ink-2`.
public struct WingReadout: View {
    @Environment(\.vigieTheme) private var theme
    private let value: String
    private let label: String
    private let stale: Bool

    public init(value: String, label: String, stale: Bool = false) {
        self.value = value
        self.label = label
        self.stale = stale
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.glyphGap) / 2) {
            Text(verbatim: value)
                .font(theme.font(.readoutValue))
                .tracking(theme.tracking(.readoutValue))
                .foregroundStyle(theme.color(stale ? .ink2 : .ink1))
            Text(verbatim: label)
                .font(theme.font(.readoutLabel))
                .tracking(theme.tracking(.readoutLabel))
                .foregroundStyle(theme.color(.ink3))
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// Dial proportions not in the tokens.
enum QuotaDialMetrics {
    /// Stroke widths of the 58 px tab dial against the 24 px geometry scaled up.
    static let cardStrokeScale: CGFloat = 0.65
}

// MARK: - Quota-warning hatch

/// `components.quota-warning-fill.pattern`, a CSS `repeating-linear-gradient(135deg, warning 0 3px,
/// warning@40% 3px 5px)`: the stripe angle, the solid band, the period and the light band's alpha.
struct HatchPattern: Equatable {
    var angle: Double
    var solid: CGFloat
    var period: CGFloat
    var lightAlpha: Double

    /// DESIGN values, used when a theme lacks the component or it does not parse.
    static let fallback = HatchPattern(angle: 135, solid: 3, period: 5, lightAlpha: 0.4)

    init(angle: Double, solid: CGFloat, period: CGFloat, lightAlpha: Double) {
        self.angle = angle
        self.solid = solid
        self.period = period
        self.lightAlpha = lightAlpha
    }

    init(theme: Theme) {
        self = theme.component("quota-warning-fill", "pattern").flatMap(HatchPattern.init(css:)) ?? .fallback
    }

    /// Parses `repeating-linear-gradient(<a>deg, <c> 0 <s>px, <c>@<alpha> <s>px <p>px)`.
    init?(css: String) {
        guard let open = css.firstIndex(of: "("), let close = css.lastIndex(of: ")") else { return nil }
        let parts = css[css.index(after: open)..<close].split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 3, parts[0].hasSuffix("deg"), let angle = Double(parts[0].dropLast(3)) else {
            return nil
        }
        let solidStops = parts[1].split(separator: " ")
        let lightStops = parts[2].split(separator: " ")
        guard solidStops.count == 3, lightStops.count == 3, let solid = ThemeValue.length(String(solidStops[2])),
            let period = ThemeValue.length(String(lightStops[2])), period > solid, solid > 0
        else { return nil }
        let alpha = lightStops[0].split(separator: "@").last.flatMap {
            Double(String($0).replacingOccurrences(of: "%", with: ""))
        }
        guard let alpha else { return nil }
        self.init(angle: angle, solid: solid, period: period, lightAlpha: alpha > 1 ? alpha / 100 : alpha)
    }
}

/// The solid bands of a ``HatchPattern`` across the whole rect (CSS angle: 0° points up, clockwise).
struct HatchStripes: Shape {
    let pattern: HatchPattern

    func path(in rect: CGRect) -> Path {
        let radians = pattern.angle * .pi / 180
        // Gradient direction (screen coordinates, y down) and the band direction perpendicular to it.
        let direction = CGPoint(x: sin(radians), y: -cos(radians))
        let along = CGPoint(x: -direction.y, y: direction.x)
        let reach = hypot(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        func point(_ offset: CGFloat, _ extent: CGFloat) -> CGPoint {
            CGPoint(
                x: center.x + direction.x * offset + along.x * extent,
                y: center.y + direction.y * offset + along.y * extent)
        }
        var path = Path()
        var offset = -reach / 2 - pattern.period
        while offset < reach / 2 + pattern.period {
            path.move(to: point(offset, -reach))
            path.addLine(to: point(offset, reach))
            path.addLine(to: point(offset + pattern.solid, reach))
            path.addLine(to: point(offset + pattern.solid, -reach))
            path.closeSubpath()
            offset += pattern.period
        }
        return path
    }
}

// MARK: - Ring drawing

/// The dial in a 24-unit box (geometry of `mockups/key-closed-notch-states.html`): single ring r 7.5 / 1.6;
/// nested inner r 7 / 1.5 and outer r 10 / 1.3; C bezel r 11.2 / 1.4 (single) or r 11.6 / 0.8 (nested).
struct QuotaDialRing: View {
    @Environment(\.vigieTheme) private var theme
    let model: QuotaDialModel
    let length: CGFloat
    let showsValue: Bool

    @State private var bezelTurned = false

    /// Points per DESIGN pixel (1 at 24 px).
    private var unit: CGFloat { length / 24 }
    /// The 58 px Usage tab dial sits on a card: strokes thinner than the scaled 24 px geometry (mockup
    /// `key-usage-tab.html`: 2.8 / 1.7 / 1.4 in a 64 box) and the pace tick keylined in the card colour.
    private var onCard: Bool { length > QuotaDialSize.stacked.fallback * 2 }
    /// Stroke points per DESIGN pixel.
    private var strokeUnit: CGFloat { onCard ? unit * QuotaDialMetrics.cardStrokeScale : unit }
    private var tactical: Bool { theme.defines(.structure) }

    var body: some View {
        ZStack {
            if tactical { bezel }
            if model.isNested {
                ring(model.secondary, radius: 10, width: 1.3, isPrimary: false)
                ring(model.primary, radius: 7, width: 1.5, isPrimary: true)
            } else {
                ring(model.primary, radius: 7.5, width: 1.6, isPrimary: true)
            }
            if model.hasWarning {
                // A36: the triangle replaces the value on the ring centre.
                WarningTriangle()
                    .fill(theme.color(.quotaWarning))
                    .frame(width: 8 * unit, height: 8 * unit)
            } else if showsValue, let value = model.valueText {
                Text(verbatim: value)
                    .font(valueFont.font)
                    .foregroundStyle(theme.color(model.stale ? .ink2 : .ink1))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: length, height: length)
    }

    private func ring(_ window: QuotaDialModel.Window?, radius: CGFloat, width: CGFloat, isPrimary: Bool)
        -> some View
    {
        let inset = (12 - radius) * unit
        let arc = Circle().inset(by: inset).trim(from: 0, to: window?.fraction ?? 0)
        let arcStyle = StrokeStyle(lineWidth: width * strokeUnit, lineCap: .round)
        return ZStack {
            Circle().inset(by: inset)
                .stroke(trackColor, style: trackStyle(width: width * strokeUnit))
            if window?.isWarning == true {
                hatchedArc(arc, style: arcStyle)
            } else {
                arc.stroke(fill(window, isPrimary: isPrimary), style: arcStyle)
                    .rotationEffect(.degrees(-90))
            }
            if let elapsed = window?.elapsedFraction {
                paceTick(at: elapsed, radius: radius)
            }
        }
    }

    /// The pace marker (DESIGN `components.pace-marker.ring`): a short radial tick across the ring at the
    /// elapsed-time position, with a 1px black keyline so it reads over any arc. Geometry of the mockup: 2.7
    /// units long, 1.2 wide over a 2.8 keyline; A platinum (`ink-1`), C `gold-text`.
    private func paceTick(at elapsed: Double, radius: CGFloat) -> some View {
        let angle = elapsed * 2 * .pi - .pi / 2
        let center = length / 2
        func point(_ r: CGFloat) -> CGPoint {
            CGPoint(x: center + cos(angle) * r * unit, y: center + sin(angle) * r * unit)
        }
        let tick = Path { path in
            path.move(to: point(radius - 1.35))
            path.addLine(to: point(radius + 1.35))
        }
        let color: Color = model.stale ? theme.color(.ink3) : theme.color(tactical ? .goldText : .ink1)
        return ZStack {
            tick.stroke(
                theme.color(onCard ? .surfaceCard : .island),
                style: StrokeStyle(lineWidth: 2.8 * strokeUnit, lineCap: .round))
            tick.stroke(color, style: StrokeStyle(lineWidth: 1.2 * strokeUnit, lineCap: .round))
        }
        .frame(width: length, height: length)
    }

    /// The quota-warning arc (DESIGN `components.quota-warning-fill`): `quota-warning` stripes over the same
    /// hue at the pattern's alpha, clipped to the arc. Drawn in every presence level and in the stale look (the
    /// warning holds for the last known values).
    private func hatchedArc(_ arc: some Shape, style: StrokeStyle) -> some View {
        let pattern = HatchPattern(theme: theme)
        let hue = theme.color(.quotaWarning)
        return ZStack {
            arc.stroke(hue.opacity(pattern.lightAlpha), style: style)
                .rotationEffect(.degrees(-90))
            HatchStripes(pattern: pattern)
                .fill(hue)
                .mask(arc.stroke(style: style).rotationEffect(.degrees(-90)))
        }
    }

    /// `line`; under Increase contrast at least `ink-3` 40 % (DESIGN "Increase contrast"); stale: `ink-3`.
    private var trackColor: Color {
        if model.stale { return theme.color(.ink3) }
        let floor = theme.a11y.minTrackOpacity
        return floor > 0 ? theme.color(.ink3).opacity(floor) : theme.color(.line)
    }

    /// Solid, or the stale dashed look (DESIGN `components.status-glyph.stale` dash, per variant).
    private func trackStyle(width: CGFloat) -> StrokeStyle {
        guard model.stale else { return StrokeStyle(lineWidth: width) }
        let dash = tactical ? [1.6 * unit, 1.6 * unit] : [2.1 * unit, 1.8 * unit]
        return StrokeStyle(lineWidth: width, dash: dash)
    }

    /// The arc fill outside a quota warning (DESIGN "Quota dial" fills; UX-DR12): stale `ink-2`; Calm flat silver (C `struct`); ahead
    /// of pace `pace-ahead` (A Ember, C gold); else the primary ring in `pace-on` (A iris gradient running
    /// along the arc, light: filaments, solid `pace-on` under Reduce transparency / Increase contrast; C Volt)
    /// and the outer weekly ring in A `line-silver` / C `struct`.
    private func fill(_ window: QuotaDialModel.Window?, isPrimary: Bool) -> AnyShapeStyle {
        if model.stale { return AnyShapeStyle(theme.color(.ink2)) }
        if theme.presence == .calm { return AnyShapeStyle(theme.color(tactical ? .structure : .ink2)) }
        if window?.pace == .ahead { return AnyShapeStyle(theme.color(.paceAhead)) }
        guard isPrimary else { return secondaryFill }
        if tactical || theme.a11y.flatSurfaces { return AnyShapeStyle(theme.color(.paceOn)) }
        let roles: [ColorRole] =
            theme.look == .light && theme.defines(.filament1)
            ? [.filament1, .filament2, .filament3] : [.iris1, .iris2, .iris3]
        // Drawn before the -90° rotation, so 0° is where the arc starts.
        let sweep = 360 * max(window?.fraction ?? 1, 0.01)
        return AnyShapeStyle(
            AngularGradient(
                colors: roles.map(theme.color), center: .center, startAngle: .zero, endAngle: .degrees(sweep)))
    }

    /// The outer weekly ring: A `line-silver`, C `struct`.
    private var secondaryFill: AnyShapeStyle {
        AnyShapeStyle(theme.color(tactical ? .structure : .lineSilver))
    }

    /// C dashed tick bezel, turning every `motion.dial-bezel` at full presence; static otherwise.
    private var bezel: some View {
        let nested = model.isNested
        let radius: CGFloat = nested ? 11.6 : 11.2
        let width: CGFloat = nested ? 0.8 : 1.4
        let dash: [CGFloat] = nested ? [0.6 * unit, 2.3 * unit] : [0.7 * unit, 2.2 * unit]
        let animation = theme.loopAnimation(.dialBezel)
        return Circle().inset(by: (12 - radius) * unit)
            .stroke(theme.color(.ink3), style: StrokeStyle(lineWidth: width * unit, dash: dash))
            .rotationEffect(.degrees(bezelTurned ? 360 : 0))
            .animation(animation, value: bezelTurned)
            .onAppear {
                if animation != nil { bezelTurned = true }
            }
    }

    /// The value inside: the readout-value family at 7 px per 24 (mockup `.dv`), tabular digits.
    private var valueFont: FontSpec {
        let family = theme.fontSpec(.readoutValue).family
        return FontSpec(family: family, size: 7 * unit, weight: tactical ? 600 : 500, tabularDigits: true)
    }
}

#Preview("Quota dials") {
    QuotaDialPreview()
}

private struct QuotaDialPreview: View {
    var body: some View {
        let both = QuotaDialModel(
            providerName: "Claude", primary: .init(kind: .fiveHour, fraction: 0.38),
            secondary: .init(kind: .weekly, fraction: 0.52))
        let weekly = QuotaDialModel(
            providerName: "Claude", primary: nil, secondary: .init(kind: .weekly, fraction: 0.38))
        VStack(alignment: .leading) {
            ForEach(Look.allCases, id: \.self) { look in
                ForEach(ThemeLoader.builtInIDs, id: \.self) { variant in
                    let theme = PreviewThemes.theme(look, variant: variant)
                    HStack(spacing: theme.spacing(.glyphGap)) {
                        QuotaReadoutView(model: weekly)
                        QuotaDialView(model: both, size: .stacked)
                        QuotaDialView(model: both, size: .tab)
                    }
                    .padding(theme.spacing(.gridPaddingX))
                    .background(theme.color(look == .dark ? .island : .surfacePanel))
                    .vigieTheme(theme)
                }
            }
        }
    }
}
