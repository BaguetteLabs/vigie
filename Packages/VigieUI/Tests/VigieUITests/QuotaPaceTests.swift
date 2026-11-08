import AppKit
import SwiftUI
import Testing

@testable import VigieUI

/// Story 7.5: pace indicator on the quota dial (FR52, UX-DR12, UX-DR16 pace marker, UX-DR58 pace ahead).
@MainActor @Suite struct QuotaPaceTests {
    static let reset = Date(timeIntervalSince1970: 1_800_000_000)

    /// A 5h window `used` percent used with `elapsed` percent of the window gone.
    static func window(_ used: Double, elapsed: Double?, tolerance: Int = 5) -> QuotaDialModel.Window {
        .init(
            kind: .fiveHour, fraction: used / 100, resetsAt: reset, elapsedFraction: elapsed.map { $0 / 100 },
            paceTolerance: tolerance)
    }

    static let within = QuotaDialModel(
        providerName: "Claude", primary: window(38, elapsed: 60), secondary: .init(kind: .weekly, fraction: 0.52))
    static let ahead = QuotaDialModel(
        providerName: "Claude", primary: window(72, elapsed: 40), secondary: .init(kind: .weekly, fraction: 0.52))
    static let weeklyAhead = QuotaDialModel(
        providerName: "Claude", primary: nil,
        secondary: .init(kind: .weekly, fraction: 0.66, elapsedFraction: 0.3))
    static let unpaced = QuotaDialModel(providerName: "Claude", primary: window(72, elapsed: nil))

    // MARK: Elapsed math

    @Test func windowLengthsFollowTheKind() {
        #expect(QuotaWindowKind.fiveHour.length == 5 * 3600)
        #expect(QuotaWindowKind.weekly.length == 7 * 86400)
        #expect(QuotaWindowKind.daily.length == 86400)
    }

    @Test func elapsedIsMeasuredFromResetMinusTheWindowLength() throws {
        let kind = QuotaWindowKind.fiveHour
        // 2 h before the reset of a 5 h window: 3 h elapsed = 60 %.
        let elapsed = try #require(kind.elapsedFraction(resetsAt: Self.reset, now: Self.reset - 2 * 3600))
        #expect(abs(elapsed - 0.6) < 1e-9)
        let week = try #require(
            QuotaWindowKind.weekly.elapsedFraction(resetsAt: Self.reset, now: Self.reset - 3.5 * 86400))
        #expect(abs(week - 0.5) < 1e-9)
        #expect(kind.elapsedFraction(resetsAt: nil, now: Self.reset) == nil)
    }

    @Test func elapsedIsClampedBeforeTheStartAndAfterTheReset() {
        let kind = QuotaWindowKind.fiveHour
        // Clock before the window start (skew or a future window).
        #expect(kind.elapsedFraction(resetsAt: Self.reset, now: Self.reset - 6 * 3600) == 0)
        // The window has reset and the refresh has not brought the next one yet.
        #expect(kind.elapsedFraction(resetsAt: Self.reset, now: Self.reset + 60) == 1)
        #expect(kind.elapsedFraction(resetsAt: Self.reset, now: Self.reset) == 1)
        #expect(QuotaDialModel.Window(kind: .daily, fraction: 0.1, elapsedFraction: 3).elapsedFraction == 1)
    }

    // MARK: Within / ahead

    @Test func aheadOnlyPastElapsedPlusTolerance() {
        // Edge: used = elapsed + tolerance is still within pace.
        #expect(Self.window(55, elapsed: 50).pace == .within)
        #expect(Self.window(56, elapsed: 50).pace == .ahead)
        #expect(Self.window(30, elapsed: 50).pace == .within)
        // Tolerance from `pace_tolerance`.
        #expect(Self.window(58, elapsed: 50, tolerance: 8).pace == .within)
        #expect(Self.window(59, elapsed: 50, tolerance: 8).pace == .ahead)
        #expect(Self.window(51, elapsed: 50, tolerance: 0).pace == .ahead)
        #expect(Self.window(50, elapsed: 50, tolerance: 0).pace == .within)
        // Edges that do not add up exactly in binary.
        #expect(Self.window(15, elapsed: 10).pace == .within)
        #expect(Self.window(35, elapsed: 30).pace == .within)
    }

    @Test func noElapsedMeansNoPace() {
        #expect(Self.unpaced.primary?.pace == nil)
        #expect(QuotaDialModel.Window(kind: .fiveHour, fraction: 0.9).pace == nil)
    }

    @Test func voiceOverSaysAheadOfPace() {
        #expect(Self.within.accessibilityLabel == "Claude, 5 hour window 38 percent, weekly 52 percent")
        #expect(
            Self.ahead.accessibilityLabel == "Claude, 5 hour window 72 percent, ahead of pace, weekly 52 percent")
        #expect(Self.weeklyAhead.accessibilityLabel == "Claude, weekly 66 percent, ahead of pace")
        #expect(Self.unpaced.accessibilityLabel == "Claude, 5 hour window 72 percent")
    }

    // MARK: Rendering

    @Test(arguments: [
        (Look.dark, ThemeLibrary.defaultVariantID), (.light, ThemeLibrary.defaultVariantID),
        (.dark, SessionGlyphTests.tactical), (.light, SessionGlyphTests.tactical),
    ])
    func aheadFillsInPaceAheadWithinInPaceOn(look: Look, variant: String) throws {
        let theme = SessionGlyphTests.theme(look, variant: variant)
        let ahead = try Self.pixels(QuotaDialView(model: Self.ahead, size: .tab), matching: .paceAhead, theme: theme)
        let within = try Self.pixels(
            QuotaDialView(model: Self.within, size: .tab), matching: .paceAhead, theme: theme)
        #expect(ahead > 200, "ahead arc in pace-ahead (\(variant) \(look))")
        #expect(within < ahead / 10, "within pace draws no pace-ahead (\(variant) \(look))")
        if variant == SessionGlyphTests.tactical {
            // C inverted: Volt within pace.
            let volt = try Self.pixels(QuotaDialView(model: Self.within, size: .tab), matching: .paceOn, theme: theme)
            #expect(volt > 100)
        }
        // The tick draws: a paced dial inks more than the same dial without elapsed.
        let paced = try QuotaDialTests.inked(QuotaDialView(model: Self.ahead, size: .wing), theme: theme)
        var bare = Self.ahead
        bare = QuotaDialModel(
            providerName: "Claude", primary: Self.window(72, elapsed: nil), secondary: bare.secondary)
        let unpaced = try QuotaDialTests.inked(QuotaDialView(model: bare, size: .wing), theme: theme)
        #expect(paced != unpaced)
        try Self.writeSheet(theme: theme, name: "\(variant)-\(look.rawValue)")
    }

    @Test func paceOffFillsInPaceOn() throws {
        let c = SessionGlyphTests.theme(.dark, variant: SessionGlyphTests.tactical)
        let off = QuotaDialModel(providerName: "Claude", primary: Self.window(72, elapsed: nil))
        #expect(try Self.pixels(QuotaDialView(model: off, size: .tab), matching: .paceAhead, theme: c) < 20)
        #expect(try Self.pixels(QuotaDialView(model: off, size: .tab), matching: .paceOn, theme: c) > 100)
    }

    @Test func flatSurfacesAndCalm() throws {
        for flags in [AccessibilityAdjustments(increaseContrast: true), .init(reduceTransparency: true)] {
            let theme = SessionGlyphTests.theme(.dark, flags)
            #expect(
                try Self.pixels(QuotaDialView(model: Self.ahead, size: .tab), matching: .paceAhead, theme: theme)
                    > 200)
            #expect(
                try Self.pixels(QuotaDialView(model: Self.within, size: .tab), matching: .paceOn, theme: theme)
                    > 100)
        }
        // Calm: arcs step back to flat silver, the tick stays.
        let calm = SessionGlyphTests.theme(.dark, presence: .calm)
        #expect(try Self.pixels(QuotaDialView(model: Self.ahead, size: .tab), matching: .paceAhead, theme: calm) < 20)
        #expect(try QuotaDialTests.inked(QuotaDialView(model: Self.ahead, size: .wing), theme: calm) > 60)
    }

    // MARK: Helpers

    /// Pixels within a small distance of `role`'s color.
    static func pixels(_ view: some View, matching role: ColorRole, theme: Theme) throws -> Int {
        let renderer = ImageRenderer(
            content: view.padding(4).background(QuotaDialTests.background(theme)).vigieTheme(theme))
        renderer.scale = 4
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        let target = try #require(NSColor(theme.color(role)).usingColorSpace(.sRGB))
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let pixel = bitmap.colorAt(x: x, y: y) else { continue }
                let delta =
                    abs(pixel.redComponent - target.redComponent) + abs(pixel.greenComponent - target.greenComponent)
                    + abs(pixel.blueComponent - target.blueComponent)
                if delta < 0.12 { count += 1 }
            }
        }
        return count
    }

    static func writeSheet(theme: Theme, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["VIGIE_RENDER_DIR"] else { return }
        let models = [Self.within, Self.ahead, Self.weeklyAhead, Self.unpaced]
        let sheet = VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: theme.spacing(.glyphGap)) {
                ForEach(models, id: \.self) { QuotaDialView(model: $0, size: .wing) }
            }
            HStack(spacing: 12) {
                QuotaReadoutView(model: Self.within)
                QuotaReadoutView(model: Self.ahead)
            }
            HStack(spacing: 12) {
                ForEach(models, id: \.self) { QuotaDialView(model: $0, size: .tab) }
            }
        }
        .padding(8)
        .background(QuotaDialTests.background(theme))
        .vigieTheme(theme)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 4
        let image = try #require(renderer.cgImage)
        let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("pace-\(name).png"))
    }
}
