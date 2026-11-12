import AppKit
import Foundation
import ModuleKit
import SwiftUI
import Testing

@testable import VigieUI

/// Story 20.6: the closed-notch Time readout (DESIGN "Time readout (closed notch)").
@MainActor @Suite struct TimeClosedReadoutTests {
    static let theme = Fixtures.library.resolve(themeID: ThemeLibrary.defaultVariantID, look: .dark).theme

    static func model(
        _ variant: TimeClosedVariant, label: String = "WORK · 2/4", frozen: Bool = false, dashed: Bool = false
    ) -> TimeClosedReadoutModel {
        TimeClosedReadoutModel(
            variant: variant, value: "18:42", label: label, fractionLeft: 0.75, dashed: dashed, frozen: frozen,
            accessibilityLabel: "Pomodoro, Work, cycle 2 of 4, 18 minutes, 42 seconds left, ends 15:07")
    }

    static func size(_ model: TimeClosedReadoutModel, band: CGFloat? = nil) -> CGSize {
        let theme = band.map { Self.theme.withBandHeight($0) } ?? Self.theme
        let hosting = NSHostingView(rootView: TimeClosedReadout(model: model).fixedSize().vigieTheme(theme))
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize
    }

    @Test func variantsDrawTheirParts() {
        let time = Self.model(.time)
        #expect(time.showsText && !time.showsRing && !time.showsPauseMark)
        let ring = Self.model(.ring)
        #expect(ring.showsRing && !ring.showsText && !ring.showsPauseMark)
        let both = Self.model(.both)
        #expect(both.showsRing && both.showsText)
        #expect(Self.model(.ring, frozen: true).showsPauseMark, "ring-only Away: the pause mark")
        #expect(!Self.model(.both, frozen: true).showsPauseMark, "the label says AWAY · PAUSED")
        #expect(!Self.model(.time, frozen: true).showsPauseMark)
    }

    @Test func layoutMatchesTheVariant() {
        let ring = Self.size(Self.model(.ring))
        #expect(ring == CGSize(width: 23, height: 23), "the 23px closed ring")
        let time = Self.size(Self.model(.time))
        let both = Self.size(Self.model(.both))
        #expect(time.width > 23)
        #expect(both.width > time.width + 23, "ring, gap, then the text")
        #expect(Self.size(Self.model(.ring, frozen: true)) == ring, "the pause mark sits inside the ring")
        // A 24 pt band: the ring caps at 20 pt (Story 2.16).
        #expect(Self.size(Self.model(.ring), band: 24) == CGSize(width: 20, height: 20))
    }

    @Test func rendersEveryVariantAndState() throws {
        for variant in [TimeClosedVariant.time, .ring, .both] {
            for frozen in [false, true] {
                for dashed in [false, true] {
                    let view = TimeClosedReadout(model: Self.model(variant, frozen: frozen, dashed: dashed))
                        .padding(Self.theme.spacing(.gridPaddingX))
                        .background(Self.theme.color(.band))
                        .vigieTheme(Self.theme)
                    let image = try #require(ImageRenderer(content: view).cgImage, "\(variant) \(frozen) \(dashed)")
                    #expect(image.width > 0)
                }
            }
        }
    }

    @Test func accessibilityLabelIsTheItemAndTimeLeft() {
        let strings = PrivacyTests.accessibilityStrings(
            TimeClosedReadout(model: Self.model(.ring)), size: CGSize(width: 120, height: 34))
        #expect(strings.contains("Pomodoro, Work, cycle 2 of 4, 18 minutes, 42 seconds left, ends 15:07"))
    }

    @Test func privacyMasksAUserLabel() {
        var model = Self.model(.time, label: "SEEDED-SECRET-1")
        model.labelIsUserText = true
        model.sensitiveText = "SEEDED-SECRET-1"
        model.accessibilityLabel = "SEEDED-SECRET-1, 5 minute timer, 3 minutes left"
        let redacted = model.redacted()
        #expect(redacted.label == PrivacyMask.text)
        #expect(redacted.accessibilityLabel == "\(PrivacyMask.text), 5 minute timer, 3 minutes left")
        #expect(redacted.value == "18:42")
        #expect(Self.model(.time).redacted().label == "WORK · 2/4", "a phase label is not user text")
        let strings = PrivacyTests.accessibilityStrings(
            TimeClosedReadout(model: model).privacyActive(true), size: CGSize(width: 160, height: 34))
        PrivacyTests.expectNoSeed(strings)
    }

    @Test func reportsWhenItShows() {
        final class Box { var events: [Bool] = [] }
        let box = Box()
        let view = TimeClosedReadout(snapshot: { Self.model(.time) }, visibility: { box.events.append($0) })
            .vigieTheme(Self.theme)
        let (window, hosting) = hostOffscreen(view, size: CGSize(width: 120, height: 34))
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        #expect(box.events.first == true)
        window.close()
    }
}
