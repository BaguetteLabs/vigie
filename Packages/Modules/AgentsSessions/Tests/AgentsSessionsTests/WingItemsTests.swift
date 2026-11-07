import AgentKit
import Foundation
import ModuleKit
import SwiftUI
import Testing
import VigieUI

@testable import AgentsSessions

/// Story 4.9: the right wing (FR37, A19, UX-DR63).
@MainActor @Suite struct WingItemsTests {
    typealias S = LivenessTests

    /// What `ClosedNotchArbiter` does with one module's items (VigieCore, not importable here): sort by state
    /// (descending), then priority, then order; show `slots`, count the rest as `+X`.
    static func arbitrate(_ items: [LeftWingItem], slots: Int) -> (shown: [String], overflow: Int) {
        let ranked = items.sorted { lhs, rhs in
            let (ls, rs) = (lhs.state ?? .ambient, rhs.state ?? .ambient)
            if ls != rs { return ls > rs }
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.order < rhs.order
        }
        return (ranked.prefix(slots).map(\.id), max(0, ranked.count - slots))
    }

    func module(sessions: [Session], adapters: [any AgentAdapter] = [FakeAdapter()]) -> AgentsSessionsModule {
        let module = AgentsSessionsModule(
            adapters: AgentAdapters(adapters), terminals: TerminalAdapters([]), liveness: FakeLiveness())
        module.store.load(sessions)
        module.syncState(now: S.t0 + 60)
        return module
    }

    @Test func fiveSessionsInThreeSlotsMostUrgentFirst() {
        let module = module(sessions: [
            S.session("idle", .idle, since: S.t0 - 10),
            S.session("working", .working, since: S.t0, lastEvent: S.t0 + 50),
            S.session("done", .done, since: S.t0 - 5),
            S.session("failed", .failed, since: S.t0 - 30),
            S.session("blocked", .blocked, since: S.t0 - 20),
        ])
        let items = module.leftWingItems()
        #expect(items.map(\.id.sessionPart) == ["blocked", "failed", "done", "working", "idle"])
        #expect(items.map(\.state) == [.alert, .alert, .active, .active, .ambient])
        let wing = Self.arbitrate(items, slots: 3)
        #expect(wing.shown.map(\.sessionPart) == ["blocked", "failed", "done"])
        #expect(wing.overflow == 2)
    }

    @Test func alertsOutnumberingSlotsShowTheMostRecent() {
        let module = module(sessions: [
            S.session("f-old", .failed, since: S.t0 - 300),
            S.session("b-new", .blocked, since: S.t0),
            S.session("w", .working, since: S.t0 + 30, lastEvent: S.t0 + 30),
            S.session("f-new", .failed, since: S.t0 - 10),
            S.session("b-old", .blocked, since: S.t0 - 100),
        ])
        let wing = Self.arbitrate(module.leftWingItems(), slots: 3)
        #expect(wing.shown.map(\.sessionPart) == ["b-new", "f-new", "b-old"])
        #expect(wing.overflow == 2)
    }

    @Test func staleSessionsRankWithIdle() {
        let module = module(sessions: [
            S.session("stale", .working, since: S.t0 - 3600, lastEvent: S.t0 - 900),
            S.session("idle", .idle, since: S.t0 - 10),
        ])
        let items = module.leftWingItems()
        #expect(items.map(\.id.sessionPart) == ["idle", "stale"])
        #expect(items.map(\.state) == [.ambient, .ambient])
        #expect(module.state == .ambient)
    }

    @Test func emptyStates() throws {
        let none = module(sessions: [], adapters: [])
        #expect(none.wingEmptyState == .noAgentConnected)
        let idle = module(sessions: [])
        #expect(idle.wingEmptyState == .noActiveSessions)
        #expect(module(sessions: [S.session("a", .idle)]).wingEmptyState == nil)

        let item = try #require(none.leftWingItems().first)
        #expect(none.leftWingItems().count == 1)
        #expect(item.id == AgentsSessionsModule.emptyItemID)
        #expect(item.compactView(.wide) != nil)
        #expect(item.compactView(.icon) == nil)
        #expect(String(localized: WingEmptyState.noAgentConnected.copy.label) == "NO AGENT CONNECTED")
        #expect(String(localized: WingEmptyState.noActiveSessions.copy.label) == "NO ACTIVE SESSIONS")
    }

    @Test func glyphItemsRenderAtEverySize() throws {
        let module = module(sessions: [S.session("a", .blocked)])
        let item = try #require(module.leftWingItems().first)
        for size in CompactSize.allCases { #expect(item.compactView(size) != nil) }
    }

    @Test func accessibilityLabelFormat() {
        let text = SessionRowText()
        let now = S.t0 + 120
        #expect(
            text.accessibilityLabel(S.session("a", .blocked, cwd: "/Users/me/www/vigie"), now: now)
                == "vigie, blocked, 2 minutes")
        #expect(text.accessibilityLabel(S.session("a", .idle, cwd: "/Users/me/www/vigie"), now: now) == "vigie, idle")
        #expect(text.accessibilityLabel(S.session("a", .failed), now: now) == "fake, failed, 2 minutes")
    }
}

extension String {
    /// `fake:<id>` → `<id>`.
    fileprivate var sessionPart: Substring { split(separator: ":", maxSplits: 1).last ?? Substring(self) }
}
