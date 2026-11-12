import AppKit
import ModuleKit
import SwiftUI
import Testing

@testable import VigieUI

/// Story 2.16: closed-notch content scales to a band shorter than the designed 34 px (a virtual notch is as tall
/// as its display's menu bar), and nothing changes at 34 px or above.
@MainActor @Suite struct ClosedBandTests {
    static func theme(_ variant: String, band: CGFloat? = nil) -> Theme {
        let theme = Fixtures.library.resolve(themeID: variant, look: .dark).theme
        return band.map { theme.withBandHeight($0) } ?? theme
    }

    static let single = QuotaDialModel(providerName: "Claude", primary: .init(kind: .fiveHour, fraction: 0.38))
    static let nested = QuotaDialModel(
        providerName: "Claude", primary: .init(kind: .fiveHour, fraction: 0.38),
        secondary: .init(kind: .weekly, fraction: 0.52), accountLabel: "Work")

    /// Every closed-notch item a lane can show, by name.
    static var closedItems: [(String, AnyView)] {
        var items: [(String, AnyView)] = [
            ("quota readout", AnyView(QuotaReadoutView(model: single))),
            ("dial with name", AnyView(QuotaDialView(model: single, size: .wing))),
            ("stacked dial", AnyView(QuotaDialView(model: nested, size: .stacked))),
            ("bare dial", AnyView(QuotaDialView(model: nested, size: .wing, showsName: false))),
            ("break due", AnyView(TimeBreakDueReadout(value: "15:00", accessibilityLabel: "Break due"))),
            ("break due ring", AnyView(TimeBreakDueReadout(value: "5:00", ringOnly: true, accessibilityLabel: "Due"))),
            ("wing readout", AnyView(WingReadout(value: "38 %", label: "CLAUDE · 5H"))),
            ("empty readout", AnyView(WingEmptyReadout(VigieCopy.noActiveSessions))),
            ("transient readout", AnyView(TransientReadoutView(.copied(lines: 3)))),
            (
                "lane",
                AnyView(
                    WingLane(
                        entries: [.init(id: "a", view: AnyView(QuotaDialView(model: single, size: .stacked)))],
                        overflowCount: 2))
            ),
        ]
        for status in SessionStatus.allCases {
            items.append(("glyph \(status)", AnyView(SessionGlyphView(status))))
        }
        return items
    }

    static func fittingSize(_ view: AnyView, theme: Theme) -> CGSize {
        let hosting = NSHostingView(rootView: view.fixedSize().vigieTheme(theme))
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize
    }

    // MARK: Theme band

    @Test func withBandHeightLowersAndRaises() {
        let theme = Self.theme(ThemeLibrary.defaultVariantID)
        #expect(theme.spacing(.bandHeight) == 34)
        #expect(theme.withBandHeight(24).spacing(.bandHeight) == 24)
        #expect(theme.withBandHeight(37).spacing(.bandHeight) == 37)
        #expect(theme.withBandHeight(34) == theme)
        #expect(theme.withBandHeight(0) == theme)
        #expect(theme.withBandHeight(.infinity) == theme)
        // The one-way helper still only raises (the physical band, the expanded view and peeks).
        #expect(theme.withBandHeight(atLeast: 24) == theme)
        #expect(theme.withBandHeight(atLeast: 39).spacing(.bandHeight) == 39)
        // Lowering touches only the band.
        var lowered = theme.withBandHeight(24)
        lowered.spacing[SpacingRole.bandHeight.rawValue] = theme.spacing[SpacingRole.bandHeight.rawValue]
        #expect(lowered == theme)
    }

    // MARK: Metrics

    @Test(arguments: [CGFloat(34), 37, 40])
    func designedBandAndTallerKeepTheDesignedValues(band: CGFloat) {
        let metrics = ClosedBandMetrics(bandHeight: band)
        #expect(!metrics.isCompact)
        #expect(metrics.scale == 1)
        for designed in [CGFloat(16), 23, 24, 26] {
            #expect(metrics.rowLength(designed) == designed)
            #expect(metrics.stackedLength(designed) == designed)
        }
        for variant in ThemeLoader.builtInIDs {
            let theme = Self.theme(variant, band: band)
            #expect(metrics.fontSpec(.readoutValue, in: theme) == theme.fontSpec(.readoutValue))
            #expect(metrics.fontSpec(.readoutLabel, in: theme) == theme.fontSpec(.readoutLabel))
        }
    }

    @Test func aThemeWithoutABandIsNotCompact() {
        #expect(!ClosedBandMetrics(bandHeight: 0).isCompact)
        #expect(ClosedBandMetrics(theme: .empty).scale == 1)
    }

    @Test func shortBandCapsRingsAndScalesStacks() {
        let metrics = ClosedBandMetrics(bandHeight: 24)
        #expect(metrics.isCompact)
        #expect(metrics.maxRowLength == 20)
        #expect(metrics.rowLength(16) == 16)  // a session glyph already fits
        #expect(metrics.rowLength(23) == 20)
        #expect(metrics.rowLength(24) == 20)
        #expect(abs(metrics.scale - 24 / 34) < 1e-9)
        #expect(abs(metrics.stackedLength(34) - 24) < 1e-9)
        let theme = Self.theme(ThemeLibrary.defaultVariantID, band: 24)
        let label = metrics.fontSpec(.readoutLabel, in: theme)
        let designed = theme.fontSpec(.readoutLabel)
        #expect(abs(label.size - designed.size * 24 / 34) < 1e-9)
        #expect(abs(label.tracking - designed.tracking * 24 / 34) < 1e-9)
        #expect(label.family == designed.family && label.weight == designed.weight)
    }

    // MARK: Layout

    /// No closed-notch item is taller than a 24 pt (default external display) or 26 pt (with the default
    /// `notch_overlap`) band, in either variant.
    @Test(arguments: [CGFloat(24), 26])
    func closedItemsFitAShortBand(band: CGFloat) {
        for variant in ThemeLoader.builtInIDs {
            let theme = Self.theme(variant, band: band)
            for (name, view) in Self.closedItems {
                let size = Self.fittingSize(view, theme: theme)
                #expect(size.height > 0, "\(variant) \(name)")
                #expect(size.height <= band + 0.01, "\(variant) \(name): \(size.height) in a \(band) band")
            }
        }
    }

    /// At 34 px every item lays out exactly as at any taller band (both are the designed metrics). (Some designed
    /// stacks, a dial over its name in Twin Metal Tactical, are already a point or two taller than 34 px and
    /// are centred and clipped by the wing; that is today's look and stays.)
    @Test func designedBandLayoutIsUnchanged() {
        for variant in ThemeLoader.builtInIDs {
            let designed = Self.theme(variant)
            let taller = Self.theme(variant, band: 40)
            for (name, view) in Self.closedItems {
                let size = Self.fittingSize(view, theme: designed)
                #expect(size == Self.fittingSize(view, theme: taller), "\(variant) \(name)")
            }
            // The designed ring sizes.
            #expect(
                Self.fittingSize(AnyView(QuotaDialView(model: Self.nested, size: .stacked)), theme: designed).width
                    >= 23)
            #expect(
                Self.fittingSize(
                    AnyView(QuotaDialView(model: Self.nested, size: .wing, showsName: false)), theme: designed)
                    == CGSize(width: 24, height: 24))
            #expect(
                Self.fittingSize(AnyView(SessionGlyphView(.working)), theme: designed) == CGSize(width: 16, height: 16))
        }
    }

    @Test func shortBandDropsTheNameUnderADial() {
        let theme = Self.theme(ThemeLibrary.defaultVariantID, band: 24)
        let named = Self.fittingSize(AnyView(QuotaDialView(model: Self.nested, size: .stacked)), theme: theme)
        #expect(named == CGSize(width: 20, height: 20))
        let designed = Self.fittingSize(
            AnyView(QuotaDialView(model: Self.nested, size: .stacked)), theme: Self.theme(ThemeLibrary.defaultVariantID)
        )
        #expect(designed.height > 23)  // the name is under the ring at 34 px
    }

    @Test func shortBandShrinksRingsButNotGlyphs() {
        let theme = Self.theme(ThemeLibrary.defaultVariantID, band: 24)
        #expect(
            Self.fittingSize(AnyView(QuotaDialView(model: Self.nested, size: .wing, showsName: false)), theme: theme)
                == CGSize(width: 20, height: 20))
        #expect(Self.fittingSize(AnyView(SessionGlyphView(.blocked)), theme: theme) == CGSize(width: 16, height: 16))
    }

    /// The whole island at 24 pt renders, with the content in its wings.
    @Test func islandRendersAtAMenuBarTallBand() throws {
        let theme = Self.theme(ThemeLibrary.defaultVariantID, band: 24)
        let wings = IslandWings(leading: 120, notch: 200, trailing: 120)
        for floating in [false, true] {
            let view = IslandView(
                wings: wings, floating: floating,
                leading: { AnyView(QuotaReadoutView(model: Self.single)) },
                trailing: { AnyView(SessionGlyphView(.working)) }
            )
            .frame(width: wings.totalWidth, height: 24)
            .vigieTheme(theme)
            let image = try #require(ImageRenderer(content: view).cgImage)
            #expect(image.width > 0 && image.height > 0)
        }
    }

    // MARK: Island corners

    @Test func cornerRadiiClampToAShortBand() {
        // Flush top, 34 px and 24 pt: the 14 px bottom corners fit.
        #expect(IslandShape.radii(top: 0, bottom: 14, in: CGSize(width: 440, height: 34)) == (0, 14))
        #expect(IslandShape.radii(top: 0, bottom: 14, in: CGSize(width: 440, height: 24)) == (0, 14))
        // Floating at 34 px: unchanged; at 24 pt: half the height so the pill does not fold over itself.
        #expect(IslandShape.radii(top: 14, bottom: 14, in: CGSize(width: 440, height: 34)) == (14, 14))
        #expect(IslandShape.radii(top: 14, bottom: 14, in: CGSize(width: 440, height: 24)) == (12, 12))
    }
}
