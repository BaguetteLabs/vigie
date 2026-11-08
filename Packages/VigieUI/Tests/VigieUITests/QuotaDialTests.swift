import AppKit
import SwiftUI
import Testing

@testable import VigieUI

/// Story 7.4: quota rings in the closed notch (FR50, UX-DR16, UX-DR17, UX-DR58).
@MainActor @Suite struct QuotaDialTests {
    static let both = QuotaDialModel(
        providerName: "Claude", primary: .init(kind: .fiveHour, fraction: 0.38),
        secondary: .init(kind: .weekly, fraction: 0.52))
    static let fiveHourOnly = QuotaDialModel(providerName: "Claude", primary: .init(kind: .fiveHour, fraction: 0.38))
    static let weeklyOnly = QuotaDialModel(
        providerName: "Claude", primary: nil, secondary: .init(kind: .weekly, fraction: 0.38))
    static let stale = QuotaDialModel(
        providerName: "Claude", primary: .init(kind: .fiveHour, fraction: 0.38),
        secondary: .init(kind: .weekly, fraction: 0.52), stale: true)

    @Test func voiceOverLabelNamesEachWindowAndOmitsAbsentOnes() {
        #expect(Self.both.accessibilityLabel == "Claude, 5 hour window 38 percent, weekly 52 percent")
        #expect(Self.fiveHourOnly.accessibilityLabel == "Claude, 5 hour window 38 percent")
        #expect(Self.weeklyOnly.accessibilityLabel == "Claude, weekly 38 percent")
        #expect(Self.stale.accessibilityLabel == "Claude, 5 hour window 38 percent, weekly 52 percent, stale")
    }

    @Test func aSingleWindowIsAlwaysThePrimaryRing() {
        #expect(!Self.weeklyOnly.isNested)
        #expect(Self.weeklyOnly.primary?.kind == .weekly && Self.weeklyOnly.secondary == nil)
        #expect(Self.both.isNested && Self.both.valueText == "38")
        #expect(!QuotaDialModel(providerName: "Claude", primary: nil).hasWindow)
    }

    @Test func readoutNamesTheWindowItShows() {
        #expect(Self.both.readoutValue == "38 %")
        #expect(Self.both.readoutLabel == "CLAUDE · 5H")
        #expect(Self.weeklyOnly.readoutLabel == "CLAUDE · WEEK")
        #expect(Self.both.nameLabel == "CLAUDE")
    }

    @Test func fractionsAreClamped() {
        #expect(QuotaDialModel.Window(kind: .daily, fraction: 1.7).percent == 100)
        #expect(QuotaDialModel.Window(kind: .daily, fraction: -1).percent == 0)
        #expect(QuotaDialModel.Window(kind: .daily, fraction: .nan).percent == 0)
    }

    @Test func sizesComeFromTheTheme() {
        let theme = SessionGlyphTests.theme(.dark)
        #expect(QuotaDialSize.wing.length(in: theme) == 24)
        #expect(QuotaDialSize.stacked.length(in: theme) == 23)
        #expect(QuotaDialSize.tab.length(in: theme) == 58)
    }

    /// Renders every model at wing and stacked size in A dark, A light, C dark and C light, and the readout;
    /// checks each draws. Set `VIGIE_RENDER_DIR` to write one sheet per look for review.
    @Test(arguments: [
        (Look.dark, ThemeLibrary.defaultVariantID), (.light, ThemeLibrary.defaultVariantID),
        (.dark, SessionGlyphTests.tactical), (.light, SessionGlyphTests.tactical),
    ])
    func rendersEveryLayout(look: Look, variant: String) throws {
        let theme = SessionGlyphTests.theme(look, variant: variant)
        let models = [Self.both, Self.fiveHourOnly, Self.weeklyOnly, Self.stale]
        for model in models {
            for size in [QuotaDialSize.wing, .stacked] {
                let inked = try Self.inked(QuotaDialView(model: model, size: size), theme: theme)
                #expect(inked > 60, "\(model.accessibilityLabel) \(size) draws nothing in \(variant) \(look)")
            }
        }
        // The nested dial draws more than the single ring.
        let nested = try Self.inked(QuotaDialView(model: Self.both, size: .wing, showsName: false), theme: theme)
        let single = try Self.inked(
            QuotaDialView(model: Self.fiveHourOnly, size: .wing, showsName: false), theme: theme)
        #expect(nested > single)
        #expect(try Self.inked(QuotaReadoutView(model: Self.both), theme: theme) > nested)
        try Self.writeSheet(theme: theme, models: models, name: "\(variant)-\(look.rawValue)")
    }

    @Test func flatSurfacesAndCalmStillDraw() throws {
        for flags in [AccessibilityAdjustments(increaseContrast: true), .init(reduceTransparency: true)] {
            let theme = SessionGlyphTests.theme(.dark, flags)
            #expect(try Self.inked(QuotaDialView(model: Self.both, size: .wing), theme: theme) > 60)
        }
        let calm = SessionGlyphTests.theme(.dark, presence: .calm)
        #expect(try Self.inked(QuotaDialView(model: Self.both, size: .wing), theme: calm) > 60)
    }

    static func background(_ theme: Theme) -> Color {
        theme.color(theme.look == .dark ? .island : .surfacePanel)
    }

    static func inked(_ view: some View, theme: Theme) throws -> Int {
        let renderer = ImageRenderer(content: view.padding(4).background(background(theme)).vigieTheme(theme))
        renderer.scale = 4
        return SessionGlyphTests.inkedPixels(try #require(renderer.cgImage))
    }

    static func writeSheet(theme: Theme, models: [QuotaDialModel], name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["VIGIE_RENDER_DIR"] else { return }
        let sheet = VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: theme.spacing(.glyphGap)) {
                ForEach(models, id: \.self) { QuotaDialView(model: $0, size: .wing) }
            }
            HStack(alignment: .top, spacing: theme.spacing(.glyphGap)) {
                ForEach(models, id: \.self) { QuotaDialView(model: $0, size: .stacked) }
            }
            HStack(spacing: 12) {
                QuotaReadoutView(model: Self.both)
                QuotaReadoutView(model: Self.weeklyOnly)
                QuotaReadoutView(model: Self.stale)
            }
            QuotaDialView(model: Self.both, size: .tab)
        }
        .padding(8)
        .background(background(theme))
        .vigieTheme(theme)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 4
        let image = try #require(renderer.cgImage)
        let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("quota-\(name).png"))
    }
}
