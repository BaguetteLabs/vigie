import AgentKit
import Foundation
import ModuleKit
import Testing
import VigieUI

@testable import AgentsUsage

/// Story 21.2: with Privacy mode active and seeded Account labels and project names, nothing seeded reaches the
/// Usage tab, its Home card or the closed-notch rings; providers, windows, values and costs stay (AD-24).
@MainActor @Suite struct PrivacyModeTests {
    typealias A = AccountUsageTests
    typealias O = UsageOverviewTests
    static let seedPrefix = "SEEDED-SECRET"

    static func dumped(_ value: Any) -> String {
        var out = ""
        dump(value, to: &out)
        return out
    }

    @Test func accountLabelsAreHiddenOnCardsAndRings() async {
        var values = A.twoAccounts
        values["account.work.label"] = "SEEDED-SECRET-1"
        let harness = A.Harness(
            values,
            results: [
                .default: .success([A.window("5h", used: 30, resetIn: 3600)]),
                "work": .success([A.window("5h", used: 40, resetIn: 3600)]),
            ])
        let module = harness.module
        await module.refreshPlans()
        let raw = module.usageTabSnapshot()
        #expect(Self.dumped(raw).contains(Self.seedPrefix))
        let shown = raw.privacy(true)
        #expect(!Self.dumped(shown).contains(Self.seedPrefix))
        #expect(shown.providers.map(\.id) == raw.providers.map(\.id))
        #expect(shown.providers.last?.title == "Claude · \(PrivacyMask.text)")
        for ring in module.quotaRings {
            let model = ring.model.redacted()
            #expect(!model.nameLabel.contains(Self.seedPrefix))
            #expect(!model.readoutLabel.contains(Self.seedPrefix))
            #expect(!model.accessibilityLabel.contains(Self.seedPrefix))
            #expect(model.valueText == ring.model.valueText)
        }
    }

    @Test func costByProjectAndByAccountIsHidden() {
        let panel = AgentsUsageModule.costPanel(
            today: O.today([
                "/Users/me/SEEDED-SECRET-2": O.totals(10, cost: 2), "/Users/me/SEEDED-SECRET-3": O.totals(5, cost: 1),
            ]),
            accountNames: [UsageAccountKey(provider: "claude", account: "work"): "SEEDED-SECRET-4"])
        guard case .list(let list) = panel else {
            Issue.record("no list")
            return
        }
        let shown = UsageTabSnapshot(providers: [], cost: panel).privacy(true)
        guard case .list(let masked) = shown.cost else {
            Issue.record("shape changed")
            return
        }
        #expect(!Self.dumped(masked).contains(Self.seedPrefix))
        #expect(masked.totalText == list.totalText)
        #expect(masked.rows.map(\.costText) == list.rows.map(\.costText))
        #expect(masked.rows.allSatisfy { $0.name == PrivacyMask.text })
    }
}
