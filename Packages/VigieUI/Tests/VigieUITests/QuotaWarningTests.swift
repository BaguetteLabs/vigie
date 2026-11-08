import AppKit
import SwiftUI
import Testing

@testable import VigieUI

/// Story 7.6: quota warning on the dial and its peek (FR51, UX-DR12, UX-DR16, UX-DR58, UX-DR91, UX-DR93, A36).
@MainActor @Suite struct QuotaWarningTests {
    static func window(
        _ kind: QuotaWindowKind, _ used: Double, elapsed: Double? = nil, warning: Bool
    ) -> QuotaDialModel.Window {
        .init(kind: kind, fraction: used / 100, elapsedFraction: elapsed.map { $0 / 100 }, isWarning: warning)
    }

    /// 5h at 82 %, far ahead of pace and in warning; weekly normal.
    static let fiveHourWarning = QuotaDialModel(
        providerName: "Claude", primary: window(.fiveHour, 82, elapsed: 30, warning: true),
        secondary: window(.weekly, 52, warning: false))
    /// Weekly in warning on the outer ring.
    static let weeklyWarning = QuotaDialModel(
        providerName: "Claude", primary: window(.fiveHour, 20, elapsed: 50, warning: false),
        secondary: window(.weekly, 91, warning: true))
    /// Weekly in warning but not drawn (`rings = "5h"`).
    static let hiddenWarning = QuotaDialModel(
        providerName: "Claude", primary: window(.fiveHour, 20, elapsed: 50, warning: false), hiddenWarning: true)
    static let normal = QuotaDialModel(
        providerName: "Claude", primary: window(.fiveHour, 72, elapsed: 30, warning: false))

    @Test func anyWindowInWarningPutsTheTriangleOnTheCentre() {
        #expect(Self.fiveHourWarning.hasWarning)
        #expect(Self.weeklyWarning.hasWarning)
        #expect(Self.hiddenWarning.hasWarning)
        #expect(!Self.normal.hasWarning)
        #expect(Self.fiveHourWarning.primary?.quota == .warning)
        #expect(QuotaState.warning.cue.secondaryGlyph == .triangle && QuotaState.warning.cue.glyph == .hatch)
    }

    @Test func voiceOverPrefixesQuotaWarningAndDropsAheadUnderIt() {
        #expect(
            Self.fiveHourWarning.accessibilityLabel
                == "Quota warning, Claude, 5 hour window 82 percent, weekly 52 percent")
        #expect(
            Self.weeklyWarning.accessibilityLabel
                == "Quota warning, Claude, 5 hour window 20 percent, weekly 91 percent")
        #expect(Self.hiddenWarning.accessibilityLabel == "Quota warning, Claude, 5 hour window 20 percent")
        #expect(Self.normal.accessibilityLabel == "Claude, 5 hour window 72 percent, ahead of pace")
    }

    @Test func hatchPatternComesFromTheTheme() {
        let theme = SessionGlyphTests.theme(.dark)
        #expect(HatchPattern(theme: theme) == HatchPattern(angle: 135, solid: 3, period: 5, lightAlpha: 0.4))
        #expect(
            HatchPattern(css: "repeating-linear-gradient(45deg, warning 0 2px, warning@50% 2px 6px)")
                == HatchPattern(angle: 45, solid: 2, period: 6, lightAlpha: 0.5))
        #expect(HatchPattern(css: "linear-gradient(red, blue)") == nil)
    }

    @Test(arguments: [
        (Look.dark, ThemeLibrary.defaultVariantID), (.light, ThemeLibrary.defaultVariantID),
        (.dark, SessionGlyphTests.tactical), (.light, SessionGlyphTests.tactical),
    ])
    func warningRendersHatchedWithATriangleAndWinsOverPaceAhead(look: Look, variant: String) throws {
        let theme = SessionGlyphTests.theme(look, variant: variant)
        let warning = try QuotaPaceTests.pixels(
            QuotaDialView(model: Self.fiveHourWarning, size: .tab), matching: .quotaWarning, theme: theme)
        let normal = try QuotaPaceTests.pixels(
            QuotaDialView(model: Self.normal, size: .tab), matching: .quotaWarning, theme: theme)
        #expect(warning > 200, "warning arc and triangle in quota-warning (\(variant) \(look))")
        #expect(normal < 20)
        // The 5h window is far ahead of pace, but the warning wins: no pace-ahead on the arc.
        let ahead = try QuotaPaceTests.pixels(
            QuotaDialView(model: Self.fiveHourWarning, size: .tab), matching: .paceAhead, theme: theme)
        let aheadWithout = try QuotaPaceTests.pixels(
            QuotaDialView(model: Self.normal, size: .tab), matching: .paceAhead, theme: theme)
        // Only anti-aliased edges may come close to the pace-ahead hue.
        #expect(ahead < aheadWithout / 8, "pace-ahead under a warning (\(variant) \(look))")
        let triangleOnly = try QuotaPaceTests.pixels(
            QuotaDialView(model: Self.hiddenWarning, size: .tab), matching: .quotaWarning, theme: theme)
        #expect(triangleOnly > 30, "triangle drawn for a hidden window's warning")
        #expect(triangleOnly < warning)
        try Self.writeSheet(theme: theme, name: "\(variant)-\(look.rawValue)")
    }

    @Test func warningShowsUnderCalmAndFlatSurfaces() throws {
        for theme in [
            SessionGlyphTests.theme(.dark, presence: .calm),
            SessionGlyphTests.theme(.dark, AccessibilityAdjustments(increaseContrast: true)),
            SessionGlyphTests.theme(.dark, .init(reduceTransparency: true)),
        ] {
            #expect(
                try QuotaPaceTests.pixels(
                    QuotaDialView(model: Self.fiveHourWarning, size: .tab), matching: .quotaWarning, theme: theme)
                    > 200)
        }
    }

    // MARK: Peek

    /// The peek as VigieCore's `PeekContentMapper` builds it for `usage.quota_warning` (catalog spellings).
    static let peek = PeekContent(
        kind: .quotaWarning, kicker: "Quota · warn", title: "CLAUDE · 5H 82 %", body: "RESET 16:40 · IN 1H52",
        primary: PeekAction(
            label: LocalizedStringResource(stringLiteral: "Open usage"), shortcut: PeekAction.primaryShortcut),
        secondary: PeekAction(
            label: LocalizedStringResource(stringLiteral: "Dismiss"), shortcut: PeekAction.secondaryShortcut),
        accentRole: .quotaWarning)

    @Test(arguments: [
        (Look.dark, ThemeLibrary.defaultVariantID), (.light, ThemeLibrary.defaultVariantID),
        (.dark, SessionGlyphTests.tactical), (.light, SessionGlyphTests.tactical),
    ])
    func quotaWarningPeekRenders(look: Look, variant: String) throws {
        let theme = PeekViewTests.theme(look, variant: variant)
        #expect(Self.peek.kickerRole(look: look) == (look == .light ? .quotaWarningText : .quotaWarning))
        let margin = theme.peekShadow.margin
        let view = PeekView(content: Self.peek, dwell: PeekViewTests.dwell)
            .padding(.horizontal, margin)
            .padding(.bottom, margin)
            .background(look == .dark ? Color(white: 0.22) : Color(white: 0.85))
        let renderer = ImageRenderer(content: view.vigieTheme(theme).environment(\.timeZone, .gmt))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        let hue = try #require(NSColor(theme.color(.quotaWarning)).usingColorSpace(.sRGB))
        var tinted = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                guard let p = bitmap.colorAt(x: x, y: y) else { continue }
                if abs(p.redComponent - hue.redComponent) + abs(p.greenComponent - hue.greenComponent)
                    + abs(p.blueComponent - hue.blueComponent) < 0.12
                {
                    tinted += 1
                }
            }
        }
        #expect(tinted > 50, "beacon triangle, rim and dwell line in quota-warning (\(variant) \(look))")
        if let directory = ProcessInfo.processInfo.environment["VIGIE_RENDER_DIR"] {
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(
                to: URL(fileURLWithPath: directory).appendingPathComponent(
                    "peek-quotaWarning-\(variant)-\(look.rawValue).png"))
        }
    }

    static func writeSheet(theme: Theme, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["VIGIE_RENDER_DIR"] else { return }
        let models = [Self.fiveHourWarning, Self.weeklyWarning, Self.hiddenWarning, Self.normal]
        let sheet = VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: theme.spacing(.glyphGap)) {
                ForEach(models, id: \.self) { QuotaDialView(model: $0, size: .wing) }
            }
            HStack(spacing: 12) {
                QuotaReadoutView(model: Self.fiveHourWarning)
                QuotaReadoutView(model: Self.hiddenWarning)
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
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("warning-\(name).png"))
    }
}
