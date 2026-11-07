import SwiftUI

/// A functional drain (DESIGN "Copied readout", "Peek alert panel"; UX-DR96): a 1px line, `ink-1` at 60 %
/// by default, over a `line` track, emptying toward the leading edge as time runs out. Used by the peek
/// dwell line, the `COPIED` drain and the notes clipboard drain.
///
/// The style comes from `theme.a11y.drainStyle`: a smooth slide normally; under Reduce motion a static full
/// line that disappears at the end. Two ways to drive it:
/// - `DrainLine(remaining:)`: the caller owns the clock (and any pause on hover) and passes 1 → 0.
/// - `DrainLine(duration:)`: the line runs on its own from when it appears, restarting when `trigger` changes.
public struct DrainLine: View {
    private enum Source: Equatable {
        case remaining(Double)
        case timed(Duration, trigger: Int)
    }

    @Environment(\.vigieTheme) private var theme
    private let source: Source
    private let foreground: ColorRole
    private let foregroundOpacity: Double
    private let showsTrack: Bool

    /// A caller-driven drain: `remaining` is 1 at the start and 0 at the end.
    public init(
        remaining: Double,
        foreground: ColorRole = .ink1,
        foregroundOpacity: Double = DrainLine.defaultForegroundOpacity,
        showsTrack: Bool = true
    ) {
        self.source = .remaining(remaining)
        self.foreground = foreground
        self.foregroundOpacity = foregroundOpacity
        self.showsTrack = showsTrack
    }

    /// A self-timed drain over `duration` (a `motion.*` token such as `peek-dwell` or `confirm-readout`, or
    /// a configured dwell). Changing `trigger` restarts it.
    public init(
        duration: Duration,
        trigger: Int = 0,
        foreground: ColorRole = .ink1,
        foregroundOpacity: Double = DrainLine.defaultForegroundOpacity,
        showsTrack: Bool = true
    ) {
        self.source = .timed(duration, trigger: trigger)
        self.foreground = foreground
        self.foregroundOpacity = foregroundOpacity
        self.showsTrack = showsTrack
    }

    /// `ink-1` at 60 % (DESIGN "Copied readout").
    public static let defaultForegroundOpacity = 0.6

    public var body: some View {
        switch source {
        case .remaining(let remaining):
            DrainLineBar(
                fraction: theme.a11y.drainStyle.visibleFraction(remaining: remaining),
                foreground: theme.color(foreground).opacity(foregroundOpacity),
                track: showsTrack ? theme.trackColor() : .clear)
        case .timed(let duration, let trigger):
            TimedDrainLine(
                duration: duration, trigger: trigger,
                foreground: theme.color(foreground).opacity(foregroundOpacity),
                track: showsTrack ? theme.trackColor() : .clear)
        }
    }
}

/// The drawn line: `fraction` of the width from the leading edge, over the track.
private struct DrainLineBar: View {
    let fraction: Double
    let foreground: Color
    let track: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(track)
                Rectangle().fill(foreground)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: ComponentMetrics.hairline)
        .accessibilityHidden(true)
    }
}

private struct TimedDrainLine: View {
    @Environment(\.vigieTheme) private var theme
    let duration: Duration
    let trigger: Int
    let foreground: Color
    let track: Color
    @State private var remaining = 1.0

    var body: some View {
        DrainLineBar(
            fraction: theme.a11y.drainStyle.visibleFraction(remaining: remaining),
            foreground: foreground, track: track
        )
        .task(id: TaskKey(trigger: trigger, style: theme.a11y.drainStyle)) { await run() }
    }

    private struct TaskKey: Equatable {
        let trigger: Int
        let style: DrainStyle
    }

    private func run() async {
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { remaining = 1 }
        let components = duration.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        switch theme.a11y.drainStyle {
        case .animated:
            withAnimation(.linear(duration: seconds)) { remaining = 0 }
        case .staticFullLine:
            // Full line, then gone at the end: never a slide.
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            withTransaction(still) { remaining = 0 }
        }
    }
}

#Preview("Drain line") {
    let theme = PreviewThemes.theme(.dark)
    VStack(spacing: theme.spacing(.rowGap)) {
        DrainLine(remaining: 0.6)
        DrainLine(duration: theme.motion(.confirmReadout))
    }
    .padding(theme.spacing(.gridPaddingX))
    .background(theme.color(.island))
    .vigieTheme(theme)
}
