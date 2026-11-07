import SwiftUI
import Testing

@testable import VigieUI

@MainActor @Suite struct WingLaneTests {
    @Test func overflowAndReadoutCopyComeFromTheCatalog() {
        #expect(WingLane.overflowText(0) == nil)
        #expect(WingLane.overflowText(2) == "+2")
        #expect(TransientReadout.copied(lines: 3).text == "COPIED · 3 LINES")
        #expect(TransientReadout.copied(lines: 1).text == "COPIED · 1 LINE")
        #expect(TransientReadout.noTextFound.text == "NO TEXT FOUND")
    }

    @Test func overflowUsesTokensDefinedInTheIslandTheme() {
        let theme = IslandViewTests.darkTheme
        #expect(theme.defines(.ink3))
        #expect(theme.defines(.ink1))
        #expect(theme.spacing(.glyphGap) > 0)
    }

    @Test(arguments: [0, 3])
    func rendersWithTheBundledTheme(overflow: Int) throws {
        let lane = WingLane(
            entries: [
                .init(id: "a", view: AnyView(Text(verbatim: "A"))),
                .init(id: "t", view: AnyView(TransientReadoutView(.copied(lines: 2)))),
            ],
            overflowCount: overflow)
        let wings = IslandWings(leading: 120, notch: 200, trailing: 120)
        let view = IslandView(wings: wings, leading: { AnyView(lane) }, trailing: { AnyView(lane) })
            .frame(width: wings.totalWidth, height: 34)
            .vigieTheme(IslandViewTests.darkTheme)
        let image = try #require(ImageRenderer(content: view).cgImage)
        #expect(image.width > 0 && image.height > 0)
    }
}
