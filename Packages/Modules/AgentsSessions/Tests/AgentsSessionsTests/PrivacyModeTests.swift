import AgentKit
import AppKit
import Foundation
import ModuleKit
import SwiftUI
import Testing
import VigieUI

@testable import AgentsSessions

/// Story 21.2: with Privacy mode active and seeded user text, nothing seeded reaches the Agents tab, the Home
/// card rows, the closed-notch glyph labels or a peek (AD-24).
@MainActor @Suite struct PrivacyModeTests {
    typealias T = AgentsTabTests
    static let seedPrefix = "SEEDED-SECRET"

    static func dumped(_ value: Any) -> String {
        var out = ""
        dump(value, to: &out)
        return out
    }

    /// A session `s<n>` in the seeded project folder `SEEDED-SECRET-<n>` (session ids are not shown).
    static func context(_ n: Int, at: Date = T.now) -> AgentEventContext {
        AgentEventContext(
            sessionKey: SessionKey(agentID: "fake", sessionID: "s\(n)"),
            cwd: URL(fileURLWithPath: "/Users/me/SEEDED-SECRET-\(n)/SEEDED-SECRET-\(n + 10)"),
            tty: "/dev/ttys00\(n)",
            terminal: TerminalHint(program: "WarpTerminal", sessionID: nil, warpFocusURL: nil, bundleID: nil),
            agentProcess: nil, at: at)
    }

    static func seededModule() -> AgentsSessionsModule {
        let module = T.setup().module
        module.apply(
            [
                .needsInput(context(1, at: T.now - 120), reason: .permissionPrompt),
                .toolStart(context(2, at: T.now - 60), tool: "SEEDED-SECRET-3"),
                .sessionError(context(4), message: "SEEDED-SECRET-5 failed"),
            ], now: T.now)
        return module
    }

    @Test func tabSnapshotHidesProjectsAndMessages() {
        let raw = Self.seededModule().tabSnapshot(now: T.now)
        #expect(Self.dumped(raw).contains(Self.seedPrefix))
        let shown = raw.privacy(true)
        #expect(!Self.dumped(shown).contains(Self.seedPrefix))
        #expect(shown.rows.count == 3)
        // Status labels and glyphs stay.
        #expect(shown.rows.map(\.statusLabel) == raw.rows.map(\.statusLabel))
        #expect(shown.rows.map(\.glyphStatus) == raw.rows.map(\.glyphStatus))
        #expect(shown.header == raw.header)
    }

    @Test func wingGlyphLabelsHideTheProject() {
        let module = Self.seededModule()
        for item in module.leftWingItems() {
            guard let view = item.compactView(.icon) else { continue }
            let labels = Self.accessibilityStrings(view.privacyActive(true))
            #expect(!labels.isEmpty)
            #expect(!labels.contains { $0.contains(Self.seedPrefix) }, "\(labels)")
            #expect(labels.contains { $0.contains(PrivacyMask.text) })
        }
    }

    @Test func alertTitleAndBodyAreSensitive() {
        let module = Self.seededModule()
        let session = module.sessions.first { $0.key.sessionID == "s1" }!
        let event = module.notifierEvent(.blocked, session: session, previous: nil)
        #expect(event.title.contains(Self.seedPrefix))
        #expect(event.$title.masked == PrivacyMask.text)
        #expect(event.$body.masked == PrivacyMask.text)
    }

    static func accessibilityStrings(_ view: some View) -> [String] {
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        // SwiftUI builds its accessibility tree only for an AX client; this is how one announces itself.
        _ = NSApp.perform(
            NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: NSNumber(value: true),
            with: "AXEnhancedUserInterface")
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        var strings: [String] = []
        func visit(_ element: Any, depth: Int) {
            guard depth < 20, let object = element as? NSObject else { return }
            for key in ["accessibilityLabel", "accessibilityValue"]
            where object.responds(to: NSSelectorFromString(key)) {
                if let text = object.value(forKey: key) as? String, !text.isEmpty { strings.append(text) }
            }
            guard object.responds(to: NSSelectorFromString("accessibilityChildren")) else { return }
            for child in object.value(forKey: "accessibilityChildren") as? [Any] ?? [] {
                visit(child, depth: depth + 1)
            }
        }
        visit(hosting, depth: 0)
        window.close()
        return strings
    }
}
