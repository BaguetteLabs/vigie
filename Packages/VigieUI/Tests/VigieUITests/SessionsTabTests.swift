import AppKit
import Foundation
import SwiftUI
import Testing

@testable import VigieUI

@MainActor @Suite struct SessionsTabTests {
    static func theme(_ look: Look, variant: String = ThemeLibrary.defaultVariantID) -> Theme {
        Fixtures.library.resolve(themeID: variant, look: look).theme
    }

    static func row(
        _ id: String, _ status: SessionStatus, terminal: String? = "Warp", canDismiss: Bool = false,
        label: String? = nil, action: String? = "Bash"
    ) -> SessionRowModel {
        SessionRowModel(
            id: id, glyphStatus: status, agentName: "Claude Code", project: id, lastAction: action,
            terminalName: terminal, statusLabel: label ?? status.rawValue.uppercased(), canDismiss: canDismiss,
            accessibilityLabel: "\(id), \(status.rawValue)")
    }

    static let four: [SessionRowModel] = [
        SessionRowModel(
            id: "claude:a", glyphStatus: .blocked, agentName: "Claude Code", project: "vigie",
            lastAction: "Bash", terminalName: "Ghostty", statusLabel: "BLOCKED · 12M",
            accessibilityLabel: "vigie, blocked, 12 minutes"),
        SessionRowModel(
            id: "claude:b", glyphStatus: .failed, agentName: "Claude Code", project: "infra-backup",
            lastAction: "Login required", terminalName: "Terminal", statusLabel: "FAILED · 41M", canDismiss: true,
            accessibilityLabel: "infra-backup, failed, 41 minutes"),
        SessionRowModel(
            id: "claude:c", glyphStatus: .working, agentName: "Claude Code", project: "acme-billing",
            lastAction: "Edit", terminalName: "Warp", statusLabel: "WORKING · 6M",
            accessibilityLabel: "acme-billing, working, 6 minutes"),
        SessionRowModel(
            id: "claude:d", glyphStatus: .idle, agentName: "Claude Code", project: "dotfiles", lastAction: nil,
            terminalName: "Warp", statusLabel: "IDLE", accessibilityLabel: "dotfiles, idle"),
    ]

    // MARK: Model

    @Test func headerCountsSessionsAndAlerts() {
        #expect(SessionsSnapshot(rows: Self.four).header == "SESSIONS · 4 · 2 ALERTS")
        #expect(
            SessionsSnapshot(rows: [Self.row("a", .blocked), Self.row("b", .idle)]).header
                == "SESSIONS · 2 · 1 ALERT")
        #expect(SessionsSnapshot(rows: [Self.row("a", .working)]).header == "SESSIONS · 1")
        #expect(SessionsSnapshot(rows: [], empty: .noActiveSessions).header == "SESSIONS · 0")
        #expect(SessionsSnapshot(rows: Self.four).alertCount == 2)
    }

    @Test func onlyBlockedAndFailedAreAlerts() {
        for status in SessionStatus.allCases {
            #expect(Self.row("x", status).isAlert == (status == .blocked || status == .failed), "\(status)")
        }
    }

    @Test func terminalColumnOnlyWithSeveralApps() {
        #expect(SessionsSnapshot(rows: Self.four).showsTerminalColumn)
        let warpOnly = [Self.row("a", .working), Self.row("b", .idle)]
        #expect(!SessionsSnapshot(rows: warpOnly).showsTerminalColumn)
        let unknown = [Self.row("a", .working, terminal: nil), Self.row("b", .idle)]
        #expect(!SessionsSnapshot(rows: unknown).showsTerminalColumn)
        let two = [Self.row("a", .working), Self.row("b", .idle, terminal: "iTerm2")]
        #expect(SessionsSnapshot(rows: two).showsTerminalColumn)
    }

    @Test func emptyStatesUseTheSpecifiedCopy() {
        let none = SessionsEmptyState.noAgentConnected
        #expect(String(localized: none.copy.label) == "NO AGENT CONNECTED")
        #expect(none.copy.sentence.map { String(localized: $0) } == "Connect Claude Code, Codex or Gemini in Settings.")
        #expect(none.offersSettings)
        let idle = SessionsEmptyState.noActiveSessions
        #expect(String(localized: idle.copy.label) == "NO ACTIVE SESSIONS")
        #expect(idle.copy.sentence.map { String(localized: $0) } == "Agent sessions appear here when they start.")
        #expect(!idle.offersSettings)
    }

    @Test func selectionMovesAndClamps() {
        let ids = ["a", "b", "c"]
        #expect(SessionsSelection.move(nil, by: 1, in: ids) == "a")
        #expect(SessionsSelection.move(nil, by: -1, in: ids) == "c")
        #expect(SessionsSelection.move("a", by: 1, in: ids) == "b")
        #expect(SessionsSelection.move("c", by: 1, in: ids) == "c")
        #expect(SessionsSelection.move("a", by: -1, in: ids) == "a")
        #expect(SessionsSelection.move("gone", by: 1, in: ids) == "a")
        #expect(SessionsSelection.move("a", by: 1, in: []) == nil)
        #expect(SessionsSelection.valid("gone", in: ids) == nil)
        #expect(SessionsSelection.valid("b", in: ids) == "b")
    }

    @Test func tintedRowsUseInk2InDarkLooks() {
        #expect(SessionAlertTint.secondaryRole(isAlert: true, look: .dark) == .ink2)
        #expect(SessionAlertTint.secondaryRole(isAlert: true, look: .light) == .ink3)
        #expect(SessionAlertTint.secondaryRole(isAlert: false, look: .dark) == .ink3)
    }

    @Test func columnsComeFromTheTheme() {
        let columns = SessionColumns(theme: Self.theme(.dark))
        #expect(columns.glyph == 18)
        #expect(columns.agent == 84)
        #expect(columns.terminal == 62)
        #expect(columns.status == 104)
        #expect(columns.action == 76)
        #expect(columns.height == 30)
    }

    @Test func catalogHasEveryTabString() {
        for key in [
            "sessions.hints", "sessions.sorted", "sessions.column.agent", "sessions.column.project",
            "sessions.column.terminal", "sessions.column.status", "sessions.action.focus", "sessions.action.dismiss",
        ] {
            #expect(L10n.string(key) != key, "\(key)")
        }
        #expect(L10n.string("sessions.hints") == "↑↓ SELECT · ↵ FOCUS · ⌘1–9 TABS · ESC")
    }

    // MARK: Render

    /// Renders the tab at 720 × 350 with four sessions (a blocked, a selected dismissable failed, a working and
    /// an idle row) in A dark, A light and C dark, plus both empty states. Set `VIGIE_RENDER_DIR` to keep the PNGs.
    @Test(arguments: [
        (Look.dark, ThemeLibrary.defaultVariantID), (.light, ThemeLibrary.defaultVariantID),
        (.dark, "twin-metal-tactical"),
    ])
    func rendersTheTab(look: Look, variant: String) throws {
        let theme = Self.theme(look, variant: variant)
        let snapshot = SessionsSnapshot(rows: Self.four)
        var tab = SessionsTabView(now: Date(), selection: "claude:b", snapshot: { _ in snapshot }, onFocus: { _ in })
        tab.scrolls = false
        let image = try Self.render(
            tab,
            theme: theme, name: "agents-\(variant)-\(look.rawValue)")
        #expect(SessionGlyphTests.inkedPixels(image) > 4000)

        let empty = try Self.render(
            SessionsTabView(
                now: Date(), snapshot: { _ in SessionsSnapshot(rows: [], empty: .noAgentConnected) },
                onFocus: { _ in }, openSettings: {}),
            theme: theme, name: "agents-empty-\(variant)-\(look.rawValue)")
        #expect(SessionGlyphTests.inkedPixels(empty) > 500)
    }

    static func render(_ view: some View, theme: Theme, name: String) throws -> CGImage {
        let framed =
            view
            .frame(width: 720, height: 350)
            .background(theme.color(.surfacePanel))
            .vigieTheme(theme)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        if let directory = ProcessInfo.processInfo.environment["VIGIE_RENDER_DIR"] {
            let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
        return image
    }
}
