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

        public init(kind: QuotaWindowKind, fraction: Double, resetsAt: Date? = nil) {
            self.kind = kind
            self.fraction = fraction.isFinite ? min(1, max(0, fraction)) : 0
            self.resetsAt = resetsAt
        }

        /// The window part of the readout label (`5H`, `WEEK`).
        public var label: String { kind.readoutLabel }

        /// Whole percent used, 0…100.
        public var percent: Int { Int((fraction * 100).rounded()) }
    }

    /// The provider name as the user knows it (`Claude`); shown uppercase.
    public var providerName: String
    public private(set) var primary: Window?
    public private(set) var secondary: Window?
    /// The last refresh failed: the values are the last good ones, drawn in the stale look.
    public var stale: Bool

    public init(providerName: String, primary: Window?, secondary: Window? = nil, stale: Bool = false) {
        self.providerName = providerName
        self.primary = primary ?? secondary
        self.secondary = primary == nil ? nil : secondary
        self.stale = stale
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

    /// "Claude, 5 hour window 38 percent, weekly 52 percent"; absent windows are left out.
    public var accessibilityLabel: String {
        let windows = [primary, secondary].compactMap { $0 }.map {
            L10n.format("usage.dial.a11y.window", $0.kind.spokenName, $0.percent)
        }
        var label = providerName
        for window in windows {
            label = L10n.format("usage.dial.a11y.join", label, window)
        }
        return stale ? L10n.format("usage.dial.a11y.stale", label) : label
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
/// inner (or only) ring in the primary fill (A iris gradient, C gold; flat silver in Calm, solid under Reduce
/// transparency / Increase contrast), the outer weekly ring thinner in A `line-silver` / C `struct`; the primary
/// value inside. C adds the dashed tick bezel turning every `motion.dial-bezel`. Stale keeps the last values
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
    private var tactical: Bool { theme.defines(.structure) }

    var body: some View {
        ZStack {
            if tactical { bezel }
            if model.isNested {
                ring(model.secondary, radius: 10, width: 1.3, fill: secondaryFill)
                ring(model.primary, radius: 7, width: 1.5, fill: primaryFill(model.primary))
            } else {
                ring(model.primary, radius: 7.5, width: 1.6, fill: primaryFill(model.primary))
            }
            if showsValue, let value = model.valueText {
                Text(verbatim: value)
                    .font(valueFont.font)
                    .foregroundStyle(theme.color(model.stale ? .ink2 : .ink1))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: length, height: length)
    }

    private func ring(_ window: QuotaDialModel.Window?, radius: CGFloat, width: CGFloat, fill: AnyShapeStyle)
        -> some View
    {
        let inset = (12 - radius) * unit
        return ZStack {
            Circle().inset(by: inset)
                .stroke(trackColor, style: trackStyle(width: width * unit))
            Circle().inset(by: inset)
                .trim(from: 0, to: window?.fraction ?? 0)
                .stroke(fill, style: StrokeStyle(lineWidth: width * unit, lineCap: .round))
                .rotationEffect(.degrees(-90))
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

    /// A: iris gradient running along the arc (light: filaments); C: gold (`components.quota-dial.a-arc` /
    /// `c-arc`). Calm: flat silver. Reduce transparency / Increase contrast: solid `pace-on`. Stale: `ink-2`.
    private func primaryFill(_ window: QuotaDialModel.Window?) -> AnyShapeStyle {
        if model.stale { return AnyShapeStyle(theme.color(.ink2)) }
        if theme.presence == .calm { return AnyShapeStyle(theme.color(tactical ? .structure : .ink2)) }
        if tactical { return AnyShapeStyle(theme.color(.gold)) }
        if theme.a11y.flatSurfaces { return AnyShapeStyle(theme.color(.paceOn)) }
        let roles: [ColorRole] =
            theme.look == .light && theme.defines(.filament1)
            ? [.filament1, .filament2, .filament3] : [.iris1, .iris2, .iris3]
        // Drawn before the -90° rotation, so 0° is where the arc starts.
        let sweep = 360 * max(window?.fraction ?? 1, 0.01)
        return AnyShapeStyle(
            AngularGradient(
                colors: roles.map(theme.color), center: .center, startAngle: .zero, endAngle: .degrees(sweep)))
    }

    /// The outer weekly ring: A `line-silver`, C `struct`; stale `ink-2`.
    private var secondaryFill: AnyShapeStyle {
        if model.stale { return AnyShapeStyle(theme.color(.ink2)) }
        return AnyShapeStyle(theme.color(tactical ? .structure : .lineSilver))
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
