import AppKit
import SwiftUI
import Testing

@testable import VigieUI

/// Story 4.9: session glyphs in the closed notch (FR37, UX-DR56, UX-DR63).
@MainActor @Suite struct SessionGlyphTests {
    static func theme(
        _ look: Look, variant: String = ThemeLibrary.defaultVariantID, _ flags: AccessibilityAdjustments = .none,
        presence: PresenceLevel = .full
    ) -> Theme {
        var theme = Fixtures.library.resolve(themeID: variant, look: look, accessibility: flags).theme
        theme.presence = flags.reduceMotion ? .calm : presence
        return theme
    }

    nonisolated static let tactical = "twin-metal-tactical"

    @Test func motionPerStatusAtFullPresence() {
        let a = Self.theme(.dark)
        #expect(SessionGlyphMotion.resolve(.idle, theme: a) == .none)
        #expect(SessionGlyphMotion.resolve(.working, theme: a) == .spin)
        #expect(SessionGlyphMotion.resolve(.done, theme: a) == .none)
        #expect(SessionGlyphMotion.resolve(.blocked, theme: a) == .ripple)
        #expect(SessionGlyphMotion.resolve(.failed, theme: a) == .stutter)
        let c = Self.theme(.dark, variant: Self.tactical)
        #expect(SessionGlyphMotion.resolve(.working, theme: c) == .spin)
        #expect(SessionGlyphMotion.resolve(.blocked, theme: c) == .breathe)
        #expect(SessionGlyphMotion.resolve(.failed, theme: c) == .stutter)
    }

    @Test(arguments: [Look.dark, .light])
    func staleNeverMoves(look: Look) {
        for variant in ThemeLoader.builtInIDs {
            for presence in PresenceLevel.allCases {
                let theme = Self.theme(look, variant: variant, presence: presence)
                #expect(theme.a11y.motionEnabled)
                #expect(SessionGlyphMotion.resolve(.stale, theme: theme) == .none)
            }
        }
    }

    @Test func calmFreezesWorkingAndPulsesAlerts() {
        let calm = Self.theme(.dark, presence: .calm)
        #expect(SessionGlyphMotion.resolve(.working, theme: calm) == .none)
        #expect(SessionGlyphMotion.resolve(.blocked, theme: calm) == .calmPulse)
        #expect(SessionGlyphMotion.resolve(.failed, theme: calm) == .calmPulse)
    }

    @Test func reduceMotionStopsEverything() {
        let still = Self.theme(.dark, AccessibilityAdjustments(reduceMotion: true))
        for status in SessionStatus.allCases {
            #expect(SessionGlyphMotion.resolve(status, theme: still) == .none)
        }
    }

    @Test func glyphShapesFollowTheVariant() {
        #expect(
            SessionStatus.allCases.map { $0.glyph(in: Self.theme(.dark)) } == [
                .ring, .openArc, .ringCheck, .diamond, .cross, .dashedRingQuestion,
            ])
        #expect(
            SessionStatus.allCases.map { $0.glyph(in: Self.theme(.dark, variant: Self.tactical)) } == [
                .dotInCircle, .triangleInTickRing, .checkInCircle, .squareInBrackets, .crossInSquare,
                .dashedRingQuestion,
            ])
    }

    @Test func emptyReadoutsComeFromTheCatalog() {
        #expect(String(localized: VigieCopy.noAgentConnected.label) == "NO AGENT CONNECTED")
        #expect(String(localized: VigieCopy.noActiveSessions.label) == "NO ACTIVE SESSIONS")
    }

    /// Renders every status at 16 px (scale 4) in A dark, A light and C dark; checks each glyph draws ink in
    /// its box. Set `VIGIE_RENDER_DIR` to also write the PNGs there for review.
    @Test(arguments: [
        (Look.dark, ThemeLibrary.defaultVariantID), (.light, ThemeLibrary.defaultVariantID), (.dark, tactical),
    ])
    func rendersEveryStatus(look: Look, variant: String) throws {
        let theme = Self.theme(look, variant: variant)
        let background = theme.color(look == .dark ? .island : .surfacePanel)
        for status in SessionStatus.allCases {
            let view = SessionGlyphView(status, accessibilityLabel: "vigie, \(status.rawValue)")
                .padding(4)
                .background(background)
                .vigieTheme(theme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 4
            let image = try #require(renderer.cgImage)
            #expect(image.width == 24 * 4 && image.height == 24 * 4, "\(status)")
            #expect(Self.inkedPixels(image) > 40, "\(status) draws nothing in \(variant) \(look)")
        }
        try Self.writeSheet(theme: theme, name: "\(variant)-\(look.rawValue)")
    }

    /// A looping glyph keeps its animation to itself: the readout next to it still draws.
    @Test func loopDoesNotLeakIntoSiblings() throws {
        let theme = Self.theme(.dark)
        func inked(_ view: some View) throws -> Int {
            let renderer = ImageRenderer(content: view.padding(4).background(Color.black).vigieTheme(theme))
            renderer.scale = 4
            return Self.inkedPixels(try #require(renderer.cgImage))
        }
        let readout = try inked(WingEmptyReadout(VigieCopy.noActiveSessions))
        for status in [SessionStatus.working, .blocked, .failed] {
            let pair = try inked(
                HStack {
                    SessionGlyphView(status)
                    WingEmptyReadout(VigieCopy.noActiveSessions)
                })
            #expect(pair > readout, "\(status)")
        }
    }

    /// Pixels that differ from the top-left (background) pixel.
    static func inkedPixels(_ image: CGImage) -> Int {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let reference = bitmap.colorAt(x: 0, y: 0) else { return 0 }
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let pixel = bitmap.colorAt(x: x, y: y) else { continue }
                let delta =
                    abs(pixel.redComponent - reference.redComponent)
                    + abs(pixel.greenComponent - reference.greenComponent)
                    + abs(pixel.blueComponent - reference.blueComponent)
                if delta > 0.15 { count += 1 }
            }
        }
        return count
    }

    static func writeSheet(theme: Theme, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["VIGIE_RENDER_DIR"] else { return }
        let sheet = HStack(spacing: theme.spacing(.glyphGap)) {
            ForEach(SessionStatus.allCases, id: \.self) { SessionGlyphView($0) }
            WingEmptyReadout(VigieCopy.noActiveSessions)
        }
        .padding(8)
        .background(theme.color(theme.look == .dark ? .island : .surfacePanel))
        .vigieTheme(theme)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 4
        let image = try #require(renderer.cgImage)
        let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("glyphs-\(name).png"))
    }
}
