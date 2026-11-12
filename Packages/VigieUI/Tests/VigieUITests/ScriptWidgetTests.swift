import AppKit
import Foundation
import ModuleKit
import SwiftUI
import Testing

@testable import VigieUI

/// Story 12.5: the script widget templates, the side-slot item and the glyph-only status mark (DESIGN "Script
/// widget", "Side-slot item", "Status vocabulary"; UX-DR36, UX-DR82, UX-DR86; AD-24).
@MainActor @Suite struct ScriptWidgetTests {
    static let theme = Fixtures.library.resolve(themeID: ThemeLibrary.defaultVariantID, look: .dark).theme
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let utc = TimeZone(identifier: "UTC")!

    static func seed(_ n: Int) -> String { PrivacyTests.seed(n) }

    static let status = ScriptCardModel(
        name: "Site", target: seed(1), cadence: "EVERY 1M",
        body: .output(.status(level: .ok, qualifier: seed(2), value: seed(3))), meta: .checked(now),
        action: .open)
    static let number = ScriptCardModel(
        name: "GitHub PRs", target: seed(4), cadence: "EVERY 5M",
        body: .output(
            .number(value: "3", label: seed(5), detail: seed(6), bar: ScriptNumberBar(value: 3), level: .warn)),
        meta: .updated(now), warningBadge: true, action: .run)
    static let text = ScriptCardModel(
        name: "Release", cadence: "EVERY 1H", body: .output(.text(label: seed(7), value: seed(8), level: nil)),
        meta: .updated(now), action: .copy)

    // MARK: Number bar

    @Test func numberBarLightsWholeUnitsWithTheWarnSegmentLast() {
        let bar = ScriptNumberBar(value: 3)
        #expect(bar.segments == [.on, .on, .on, .off, .warn(lit: false)])
        #expect(ScriptNumberBar(value: 5).segments.last == .warn(lit: true))
        #expect(ScriptNumberBar(value: 120).filled == 5, "past the bar: all lit")
        #expect(ScriptNumberBar(value: 2.9).filled == 2)
        #expect(ScriptNumberBar(value: nil).filled == 0)
        #expect(ScriptNumberBar(value: -4).filled == 0)
        #expect(ScriptNumberBar(value: .nan).filled == 0)
    }

    @Test func aThresholdSetsTheWarnSegment() {
        let wide = ScriptNumberBar(value: 3, warnAt: 8)
        #expect(wide.segmentCount == 8)
        #expect(wide.warnIndex == 7)
        let narrow = ScriptNumberBar(value: 3, warnAt: 2)
        #expect(narrow.segmentCount == 5)
        #expect(narrow.segments[1] == .warn(lit: true))
    }

    // MARK: Glyphs

    @Test func glyphPerLevelFromTheSharedVocabulary() {
        #expect(StatusMarkStyle(level: .ok, look: .dark).shape == .ring)
        #expect(StatusMarkStyle(level: .ok, look: .dark).shapeRole == .statusIdle)
        #expect(StatusMarkStyle(level: .warn, look: .dark).shape == .triangle)
        #expect(StatusMarkStyle(level: .warn, look: .dark).shapeRole == .quotaWarning)
        #expect(StatusMarkStyle(level: .down, look: .dark).shape == .cross)
        #expect(StatusMarkStyle(level: .down, look: .dark).shapeRole == .statusFailed)
        #expect(StatusMarkSize.large.length(in: Self.theme) == 26)
        #expect(StatusMarkSize.medium.length(in: Self.theme) == 16)
        for level in StatusLevel.allCases {
            for size in [StatusMarkSize.large, .medium] {
                let hosting = NSHostingView(rootView: StatusMarkGlyph(level: level, size: size).vigieTheme(Self.theme))
                let side = size.length(in: Self.theme)
                #expect(hosting.fittingSize == CGSize(width: side, height: side), "\(level) \(size)")
            }
        }
    }

    // MARK: Meta line

    @Test func relativeTimesCountWholeMinutesFromNow() {
        let now = Self.now
        #expect(ScriptCardMeta.checked(now.addingTimeInterval(-150)).text(now: now) == "CHECKED 2 MIN AGO")
        // Flow 7 (UX-DR106, Story 12.9): the first run of a just-installed status script reads `CHECKED JUST NOW`.
        #expect(ScriptCardMeta.checked(now.addingTimeInterval(-20)).text(now: now) == "CHECKED JUST NOW")
        #expect(ScriptCardMeta.checked(now).text(now: now) == "CHECKED JUST NOW")
        #expect(ScriptCardMeta.checked(now.addingTimeInterval(-60)).text(now: now) == "CHECKED 1 MIN AGO")
        #expect(ScriptCardMeta.updated(now.addingTimeInterval(-240)).text(now: now) == "UPDATED 4 MIN AGO")
        #expect(ScriptCardMeta.updated(now).text(now: now) == "UPDATED <1 MIN AGO")
        #expect(ScriptCardMeta.updated(now.addingTimeInterval(-112 * 60)).text(now: now) == "UPDATED 1H52 AGO")
        // A clock ahead of `now` never reads negative.
        #expect(ScriptCardMeta.updated(now.addingTimeInterval(60)).text(now: now) == "UPDATED <1 MIN AGO")
        let midnight: TimeInterval = 1_800_000_000 - 1_800_000_000.truncatingRemainder(dividingBy: 86_400)
        let down = Date(timeIntervalSince1970: midnight + TimeInterval(14 * 3600 + 44 * 60))
        #expect(ScriptCardMeta.downSince(down).text(now: now, timeZone: Self.utc) == "DOWN SINCE 14:44")
        #expect(ScriptCardMeta.label("EXIT 3").text(now: now) == "EXIT 3")
    }

    @Test func catalogKeysResolve() {
        for key in [
            "script.widget.text", "script.meta.updatedUnderMinute", "script.meta.updatedMinutesAgo",
            "script.meta.updatedAgo",
        ] {
            #expect(L10n.string(key) != key, "\(key) does not resolve")
        }
        for action in ScriptWidgetAction.allCases {
            #expect(!action.hint.hasPrefix("script."), "\(action) hint does not resolve")
        }
        #expect(ScriptTextWidget.defaultLabel == "TEXT")
    }

    // MARK: Card

    @Test func headerIsNameAndTarget() {
        #expect(Self.status.title == "Site · \(Self.seed(1))")
        #expect(Self.text.title == "Release")
        #expect(Self.status.redacted().title == "Site · \(PrivacyMask.text)")
    }

    @Test func cardSizeComesFromTheTheme() {
        let size = ScriptCardMetrics.size(Self.theme)
        #expect(size == CGSize(width: 222, height: 138))
        let hosting = NSHostingView(
            rootView: ScriptCard(model: Self.status, now: Self.now).vigieTheme(Self.theme))
        #expect(hosting.fittingSize == size)
    }

    @Test func viewsRenderInBothPrivacyStates() throws {
        let cards = [
            Self.status, Self.number, Self.text,
            ScriptCardModel(name: "New", cadence: "EVERY 1M", body: .notConfirmed),
            ScriptCardModel(name: "New", cadence: "EVERY 1M", body: .state("WAITING · FIRST RUN")),
            ScriptCardModel(
                name: "Broken", cadence: "EVERY 1M", body: .state("EXIT 3"), meta: .label("EXIT 3"),
                warningBadge: true),
        ]
        let items = [
            ScriptSideItemModel(name: "vigie.app", content: .level(.down, target: Self.seed(1))),
            ScriptSideItemModel(name: "PRs", content: .value("3", label: Self.seed(2), valueIsText: false)),
            ScriptSideItemModel(name: "New", content: .state("NOT CONFIRMED")),
        ]
        for privacy in [false, true] {
            for look in [Look.dark, .light] {
                let theme = Fixtures.library.resolve(themeID: ThemeLibrary.defaultVariantID, look: look).theme
                for card in cards {
                    let view = ScriptCard(model: card, now: Self.now, onActivate: {})
                        .privacyActive(privacy).vigieTheme(theme)
                    #expect(ImageRenderer(content: view).cgImage != nil)
                }
                for item in items {
                    let view = ScriptSideItem(model: item).privacyActive(privacy).vigieTheme(theme)
                    #expect(ImageRenderer(content: view).cgImage != nil)
                }
            }
        }
    }

    // MARK: Privacy (AD-24)

    @Test func privacyMasksScriptTextButKeepsLevelsNumbersAndName() {
        let status = Self.status.redacted()
        #expect(status.name == "Site")
        #expect(status.target == PrivacyMask.text)
        #expect(status.body == .output(.status(level: .ok, qualifier: PrivacyMask.text, value: PrivacyMask.text)))
        let number = Self.number.redacted()
        #expect(
            number.body
                == .output(
                    .number(
                        value: "3", label: PrivacyMask.text, detail: PrivacyMask.text, bar: ScriptNumberBar(value: 3),
                        level: .warn)))
        let text = Self.text.redacted()
        #expect(text.body == .output(.text(label: PrivacyMask.text, value: PrivacyMask.text, level: nil)))
        for model in [status, number, text] {
            PrivacyTests.expectNoSeed([PrivacyTests.dumped(model), model.accessibilityLabel(now: Self.now)])
        }
        let side = ScriptSideItemModel(name: "vigie.app", content: .level(.ok, target: Self.seed(9))).redacted()
        #expect(side.content == .level(.ok, target: PrivacyMask.text))
        let textItem = ScriptSideItemModel(
            name: "R", content: .value(Self.seed(1), label: Self.seed(2), valueIsText: true))
        #expect(textItem.redacted().content == .value(PrivacyMask.text, label: PrivacyMask.text, valueIsText: true))
        let numberItem = ScriptSideItemModel(name: "R", content: .value("3", label: "open", valueIsText: false))
        #expect(numberItem.redacted().content == .value("3", label: PrivacyMask.text, valueIsText: false))
    }

    @Test func renderedCardsLeakNoScriptTextUnderPrivacy() {
        for card in [Self.status, Self.number, Self.text] {
            let strings = PrivacyTests.accessibilityStrings(
                ScriptCard(model: card, now: Self.now, onActivate: {}).privacyActive(true),
                size: CGSize(width: 222, height: 138))
            PrivacyTests.expectNoSeed(strings, "\(card.name)")
            #expect(strings.contains { $0.hasPrefix(card.name) }, "the name stays")
        }
        let side = PrivacyTests.accessibilityStrings(
            ScriptSideItem(model: ScriptSideItemModel(name: "vigie.app", content: .level(.ok, target: Self.seed(1))))
                .privacyActive(true),
            size: CGSize(width: 120, height: 34))
        PrivacyTests.expectNoSeed(side)
    }

    // MARK: Accessibility

    @Test func sideItemReadsNameThenLevel() {
        let item = ScriptSideItemModel(name: "vigie.app", content: .level(.ok, target: "vigie.app"))
        #expect(item.accessibilityLabel == "vigie.app, OK")
        #expect(
            ScriptSideItemModel(name: "Site", content: .level(.down, target: "api")).accessibilityLabel
                == "Site, DOWN")
        let number = ScriptSideItemModel(name: "PRs", content: .value("3", label: "open", valueIsText: false))
        #expect(number.accessibilityLabel == "PRs, 3")
        let warned = ScriptSideItemModel(
            name: "PRs", content: .value("3", label: "open", valueIsText: false), level: .warn)
        #expect(warned.accessibilityLabel == "PRs, WARN")
        let strings = PrivacyTests.accessibilityStrings(
            ScriptSideItem(model: item), size: CGSize(width: 120, height: 34))
        #expect(strings.contains("vigie.app, OK"))
    }

    @Test func cardLabelCarriesNameValuesAndMeta() {
        let label = Self.status.accessibilityLabel(now: Self.now.addingTimeInterval(120))
        #expect(label == "Site, \(Self.seed(1)), OK, \(Self.seed(2)), \(Self.seed(3)), CHECKED 2 MIN AGO")
        let number = Self.number.accessibilityLabel(now: Self.now)
        #expect(number.contains("WARN, 3"))
        #expect(number.hasSuffix("WARN, UPDATED <1 MIN AGO"), "the badge, then the meta line")
    }
}
