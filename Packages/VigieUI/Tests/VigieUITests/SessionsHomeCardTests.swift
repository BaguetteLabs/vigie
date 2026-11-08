import AppKit
import SwiftUI
import Testing

@testable import VigieUI

@MainActor @Suite struct SessionsHomeCardTests {
    static func theme(_ look: Look) -> Theme {
        Fixtures.library.resolve(themeID: ThemeLibrary.defaultVariantID, look: look).theme
    }

    static let rows: [SessionRowModel] = (0..<6).map { index in
        let statuses: [SessionStatus] = [.blocked, .failed, .working, .working, .idle, .idle]
        return SessionsTabTests.row(
            "claude:\(index)", statuses[index],
            label: index < 2 ? "\(statuses[index].rawValue.uppercased()) · 12M" : nil)
    }

    @Test func rowGridIsTheHomeGrid() {
        #expect(SessionsHomeCardMetrics.glyph == 18)
        #expect(SessionsHomeCardMetrics.agent == 92)
        #expect(SessionsHomeCardMetrics.status == 64)
    }

    @Test func copy() {
        #expect(L10n.string("sessions.home.title") == "Agents")
        #expect(L10n.format("sessions.home.meta", 3) == "3 active")
    }

    @Test func emptyStatesAreTheTabs() {
        for empty in [SessionsEmptyState.noAgentConnected, .noActiveSessions] {
            let card = SessionsHomeCardView(rows: [], emptyState: empty, onFocus: { _ in })
            #expect(card.snapshotForTests().empty == empty)
        }
    }

    @Test func rowsPassThroughUncappedAndInOrder() {
        let card = SessionsHomeCardView(rows: Self.rows, emptyState: .noActiveSessions, onFocus: { _ in })
        let snapshot = card.snapshotForTests()
        #expect(snapshot.rows.map(\.id) == Self.rows.map(\.id))
        #expect(snapshot.empty == nil)
    }

    @Test(arguments: [0, 2, 6], [Look.dark, .light])
    func rendersInsideTheCell(count: Int, look: Look) throws {
        let theme = Self.theme(look)
        let size = HomeMetrics.cardSize(theme)
        let rows = Array(Self.rows.prefix(count))
        let view = SessionsHomeCardView(
            rows: rows, emptyState: .noActiveSessions, onFocus: { _ in }
        )
        .frame(width: size.width, height: size.height)
        .padding(20)
        .background(look == .dark ? Color(white: 0.22) : Color(white: 0.85))
        .vigieTheme(theme)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: size.width + 40, height: size.height + 40)
        hosting.layoutSubtreeIfNeeded()
        #expect(hosting.fittingSize.height <= size.height + 40 + 0.5)
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        if let dir = ProcessInfo.processInfo.environment["VIGIE_HOME_RENDER_DIR"] {
            let file = "sessions-card-\(count)-\(look.rawValue).png"
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(file))
        }
    }
}

extension SessionsHomeCardView {
    @MainActor func snapshotForTests() -> SessionsSnapshot { snapshotValue(Date(timeIntervalSince1970: 0)) }
}
