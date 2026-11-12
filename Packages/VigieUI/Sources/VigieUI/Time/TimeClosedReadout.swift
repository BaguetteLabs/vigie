import ModuleKit
import SwiftUI

/// `[modules.time] closed_notch` (SPEC §7.7, §11): the closed-notch Time readout's variant, `off` by default.
public enum TimeClosedVariant: String, CaseIterable, Sendable {
    /// Nothing on the closed notch but a due break (`BREAK DUE`, Story 20.4).
    case off
    /// Remaining time over the label.
    case time
    /// The 23px ring alone.
    case ring
    /// The ring, then remaining time over the label.
    case both
}

/// What the closed-notch Time readout shows now (DESIGN "Time readout (closed notch)", Story 20.6): the running
/// item nearest its end, every text already formatted by the Time module from its catalog.
public struct TimeClosedReadoutModel: Equatable, Sendable {
    public var variant: TimeClosedVariant
    /// Remaining time (`18:42`), tabular numerals.
    public var value: String
    /// `TEA`, `WORK · 2/4`, `BREAK · 2/4`, `LONG BREAK`, `AWAY · PAUSED`.
    public var label: String
    /// True when ``label`` is user text (a Timer's or Countdown's name, AD-24): Privacy mode masks it.
    public var labelIsUserText: Bool
    /// The user text inside ``accessibilityLabel``, scrubbed in Privacy mode.
    public var sensitiveText: String?
    /// 0...1, the accent arc.
    public var fractionLeft: Double
    /// A break arc (2.2 / 2 dashes); work and timers are solid.
    public var dashed: Bool
    /// Paused (Away, or by the user): ring in `ink-3`, value in `ink-2`; the ring-only variant adds the pause mark.
    public var frozen: Bool
    /// The item and its remaining time ("Tea, 5 minute timer, 3 minutes, 12 seconds left, ends 14:52").
    public var accessibilityLabel: String

    public init(
        variant: TimeClosedVariant, value: String, label: String, labelIsUserText: Bool = false,
        sensitiveText: String? = nil, fractionLeft: Double, dashed: Bool = false, frozen: Bool = false,
        accessibilityLabel: String
    ) {
        self.variant = variant
        self.value = value
        self.label = label
        self.labelIsUserText = labelIsUserText
        self.sensitiveText = sensitiveText
        self.fractionLeft = min(max(fractionLeft, 0), 1)
        self.dashed = dashed
        self.frozen = frozen
        self.accessibilityLabel = accessibilityLabel
    }

    /// The ring is drawn (`ring`, `both`).
    public var showsRing: Bool { variant != .time }
    /// Value over label is drawn (`time`, `both`).
    public var showsText: Bool { variant != .ring }
    /// The ring-only pause mark (two 1px bars), so the frozen state is not told by color alone.
    public var showsPauseMark: Bool { variant == .ring && frozen }
}

extension TimeClosedReadoutModel: PrivacyRedactable {
    /// A user label masked, in the readout and its VoiceOver label; phase labels and the time stay.
    public func redacted() -> TimeClosedReadoutModel {
        var copy = self
        if labelIsUserText { copy.label = PrivacyMask.text }
        copy.accessibilityLabel = PrivacyMask.scrub(accessibilityLabel, removing: [sensitiveText])
        return copy
    }
}

/// The closed-notch Time readout (DESIGN "Time readout (closed notch)", mockup 1.7e, Story 20.6): a left-wing
/// lane item. `time`: remaining time over its label; `ring`: the 23px ring alone (accent arc = time left, solid
/// for work and timers, dashed for breaks); `both`: ring then time. Frozen (Away): ring in `ink-3`, value in
/// `ink-2`, and in ring-only a center pause mark. Sizes follow the band (``ClosedBandMetrics``, Story 2.16).
///
/// `snapshot` is read in `body`, so an `@Observable` source redraws it when it changes (the module refreshes
/// it at most once per second, and only between `visibility(true)` and `visibility(false)`).
public struct TimeClosedReadout: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.privacyActive) private var privacyActive
    private let snapshot: @MainActor () -> TimeClosedReadoutModel?
    private let visibility: @MainActor (Bool) -> Void

    /// - Parameters:
    ///   - snapshot: what to show now; nil draws nothing.
    ///   - visibility: the readout appeared (true) or went away (false): the module ticks only while it shows.
    public init(
        snapshot: @escaping @MainActor () -> TimeClosedReadoutModel?,
        visibility: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.snapshot = snapshot
        self.visibility = visibility
    }

    /// A static readout (previews, tests).
    public init(model: TimeClosedReadoutModel) {
        self.init(snapshot: { model })
    }

    public var body: some View {
        Group {
            if let model = snapshot()?.privacy(privacyActive) {
                content(model)
            }
        }
        .onAppear { visibility(true) }
        .onDisappear { visibility(false) }
    }

    @ViewBuilder private func content(_ model: TimeClosedReadoutModel) -> some View {
        let side = theme.closedBand.rowLength(
            theme.componentLength("time-ring", "size-closed") ?? TimeMetrics.wingRingSize)
        HStack(spacing: theme.spacing(.glyphGap)) {
            if model.showsRing {
                ZStack {
                    TimeRing(
                        fractionLeft: model.fractionLeft, dashed: model.dashed, dimmed: model.frozen, size: side,
                        lineWidth: TimeMetrics.wingRingStroke)
                    if model.showsPauseMark {
                        TimePauseMark(role: .ink2)
                    }
                }
            }
            if model.showsText {
                WingReadout(value: model.value, label: model.label, stale: model.frozen)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: model.accessibilityLabel))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview("Time closed readout") {
    let theme = PreviewThemes.theme(.dark)
    let work = TimeClosedReadoutModel(
        variant: .both, value: "18:42", label: "WORK · 2/4", fractionLeft: 0.75, accessibilityLabel: "Pomodoro")
    var away = work
    away.variant = .ring
    away.frozen = true
    var breakRing = work
    breakRing.label = "BREAK · 2/4"
    breakRing.dashed = true
    return HStack(spacing: theme.spacing(.gridGap)) {
        TimeClosedReadout(model: work)
        TimeClosedReadout(model: away)
        TimeClosedReadout(model: breakRing)
    }
    .padding(theme.spacing(.gridPaddingX))
    .background(theme.color(.band))
    .vigieTheme(theme)
}
