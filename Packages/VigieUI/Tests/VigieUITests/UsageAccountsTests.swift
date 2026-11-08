import AppKit
import Foundation
import SwiftUI
import Testing

@testable import VigieUI

/// Story 7.10: Account labels (UX-DR99) on the dial, the readout, the Usage cards and the Home rows.
@MainActor @Suite struct UsageAccountsTests {
    static func account(_ card: UsageProviderCardModel, id: String, account: String, used: Double)
        -> UsageProviderCardModel
    {
        var bars: [UsageBarModel] = []
        if case .windows(_, let existing) = card.content {
            bars = existing.map { bar in
                var bar = bar
                bar.window.fraction = bar.window.kind == .fiveHour ? used : bar.window.fraction
                return bar
            }
        }
        let dial = QuotaDialModel(
            providerName: "Claude", primary: bars.first?.window, secondary: bars.dropFirst().first?.window,
            accountLabel: account)
        // With several Accounts the module names the card after the plan provider (`Claude`), as the wing does.
        return UsageProviderCardModel(
            id: id, name: "Claude", meta: UsageCardMeta(kind: .warn(threshold: 80)),
            content: .windows(dial: dial, bars: bars), providerID: card.providerID, account: account)
    }

    static var personal: UsageProviderCardModel {
        account(UsageTabTests.claude, id: "claude", account: "Personal", used: 0.62)
    }
    static var work: UsageProviderCardModel {
        var card = account(UsageTabTests.claude, id: "claude.work", account: "Work", used: 0.82)
        card.meta.stale = "STALE · 14:02"
        return card
    }

    @Test func wingLabelCarriesTheAccountOnlyWhenSet() {
        let one = QuotaDialModel(providerName: "Claude", primary: .init(kind: .fiveHour, fraction: 0.82))
        #expect(one.nameLabel == "CLAUDE")
        #expect(one.readoutLabel == "CLAUDE · 5H")
        let work = QuotaDialModel(
            providerName: "Claude", primary: .init(kind: .fiveHour, fraction: 0.82), accountLabel: "Work")
        #expect(work.nameLabel == "CLAUDE · WORK")
        #expect(work.readoutLabel == "CLAUDE · WORK · 5H")
        #expect(work.accessibilityLabel.hasPrefix("Claude · Work"))
        let long = QuotaDialModel(
            providerName: "Claude", primary: .init(kind: .fiveHour, fraction: 0.1), accountLabel: "Personal")
        #expect(long.nameLabel == "CLAUDE · PERSON")
        #expect(QuotaDialModel(providerName: "Claude", primary: nil, accountLabel: "").accountLabel == nil)
    }

    @Test func cardTitleCarriesTheAccountOnlyWhenSet() {
        #expect(UsageTabTests.claude.title == "Claude Code")
        #expect(Self.work.title == "Claude · Work")
        #expect(Self.work.providerID == "claude")
        let snapshot = UsageTabSnapshot(providers: [Self.personal, Self.work, UsageTabTests.codex])
        #expect(snapshot.providerOrder == ["claude", "codex"])
    }

    @Test func homeRowsNameTheAccountAndStaleStaysOnItsRow() {
        let rows = UsageHomeCardView(snapshot: { UsageTabSnapshot(providers: [Self.personal, Self.work]) })
            .rowsValue()
        #expect(rows.map(\.name) == ["Claude · Personal", "Claude · Work"])
        #expect(rows.map(\.stale) == [nil, "STALE · 14:02"])
    }

    @Test(arguments: [Look.dark, .light])
    func rendersTheTabWithTwoAccounts(look: Look) throws {
        let theme = SessionsTabTests.theme(look, variant: ThemeLibrary.defaultVariantID)
        let cost = UsageCostList(
            rows: [.init(name: "vigie", path: "/w/vigie", cost: 3.2, fraction: 1)], total: 4.1, isApproximate: false,
            accountRows: [
                .init(name: "CLAUDE · WORK", path: nil, cost: 3.0, fraction: 1),
                .init(name: "CLAUDE · PERSONAL", path: nil, cost: 1.1, fraction: 0.37),
            ])
        let snapshot = UsageTabSnapshot(providers: [Self.personal, Self.work], cost: .list(cost))
        var tab = UsageTabView(snapshot: { snapshot }, onOpenSettings: {})
        tab.scrolls = false
        let image = try SessionsTabTests.render(tab, theme: theme, name: "usage-accounts-\(look.rawValue)")
        #expect(SessionGlyphTests.inkedPixels(image) > 5000)
        try Self.save(image, "usage-tab-accounts-\(look.rawValue)")
    }

    @Test(arguments: [Look.dark, .light])
    func rendersTheHomeCardWithTwoAccounts(look: Look) throws {
        let theme = SessionsHomeCardTests.theme(look)
        let size = HomeMetrics.cardSize(theme)
        var card = UsageHomeCardView(snapshot: { UsageTabSnapshot(providers: [Self.personal, Self.work]) })
        card.scrolls = false
        let view = card.frame(width: size.width, height: size.height).padding(20)
            .background(look == .dark ? Color(white: 0.22) : Color(white: 0.85)).vigieTheme(theme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        try Self.save(image, "usage-home-accounts-\(look.rawValue)")
    }

    @Test func rendersTheWingDialWithTheAccount() throws {
        let theme = SessionsTabTests.theme(.dark, variant: ThemeLibrary.defaultVariantID)
        let model = QuotaDialModel(
            providerName: "Claude", primary: .init(kind: .fiveHour, fraction: 0.82),
            secondary: .init(kind: .weekly, fraction: 0.4), accountLabel: "Work")
        let view = HStack(spacing: 16) {
            QuotaDialView(model: model, size: .wing)
            QuotaReadoutView(model: model)
        }
        .padding(12).background(Color.black).vigieTheme(theme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        try Self.save(try #require(renderer.cgImage), "usage-wing-account")
    }

    static func save(_ image: CGImage, _ name: String) throws {
        let dir = "/private/tmp/claude-501/-Users-me-www-vigie/03a97dc6-097f-4d60-a649-a2f93afa8536/scratchpad/s7.10"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
