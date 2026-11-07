import AppKit
import Testing

@testable import VigieCore

@Suite struct DisplaySelectorTests {
    static let builtIn = DisplayInfo.notched(1)
    static let external = DisplayInfo.plain(2, x: 1512, main: true, name: "LG HDR 4K")
    static let second = DisplayInfo.plain(3, x: 3432, name: "DELL U2720Q")

    func ids(_ displays: [DisplayInfo], _ selection: DisplaySelection) -> [CGDirectDisplayID] {
        DisplaySelector.select(displays, selection: selection).map(\.id)
    }

    @Test func parsesConfigValues() {
        #expect(DisplaySelection(rawValue: "") == .notched)
        #expect(DisplaySelection(rawValue: "notched") == .notched)
        #expect(DisplaySelection(rawValue: "Main") == .main)
        #expect(DisplaySelection(rawValue: "all") == .all)
        #expect(DisplaySelection(rawValue: " LG HDR 4K ") == .named("LG HDR 4K"))
        #expect(DisplaySelection.named("LG HDR 4K").rawValue == "LG HDR 4K")
        #expect(DisplaySelection.all.rawValue == "all")
    }

    @Test func defaultUsesTheNotchedDisplayEvenWhenItIsNotMain() {
        #expect(ids([Self.builtIn, Self.external], .notched) == [1])
    }

    @Test func defaultFallsBackToTheMainDisplayWithoutANotch() {
        #expect(ids([Self.second, Self.external], .notched) == [2])
    }

    @Test func clamshellUsesTheMainExternalDisplay() {
        // Lid closed: the built-in display is gone from the list.
        #expect(ids([Self.external, Self.second], .notched) == [2])
    }

    @Test func mainPicksTheMainDisplay() {
        #expect(ids([Self.builtIn, Self.external, Self.second], .main) == [2])
    }

    @Test func allShowsEveryDisplayWithTheDefaultOneFirst() {
        #expect(ids([Self.external, Self.builtIn, Self.second], .all) == [1, 2, 3])
        #expect(ids([Self.second, Self.external], .all) == [2, 3])
    }

    @Test func namedMatchesByNameOrIDAndFallsBackToTheDefaultRule() {
        let displays = [Self.builtIn, Self.external, Self.second]
        #expect(ids(displays, .named("dell u2720q")) == [3])
        #expect(ids(displays, .named("3")) == [3])
        #expect(ids(displays, .named("Studio Display")) == [1])
        #expect(ids([Self.external, Self.second], .named("Studio Display")) == [2])
    }

    @Test func noDisplayNoSelection() {
        #expect(ids([], .all).isEmpty)
        #expect(DisplaySelector.defaultDisplay([]) == nil)
    }

    #if DEBUG
        @Test func simulatedNotchTurnsTheMainDisplayIntoANotchedOne() {
            let displays = DisplayInfo.simulatingNotch([Self.second, Self.external])
            #expect(displays.map(\.kind) == [.plain, .physical])
            #expect(ids(displays, .notched) == [2])
            // A real notch wins: nothing is simulated.
            #expect(DisplayInfo.simulatingNotch([Self.builtIn, Self.external]) == [Self.builtIn, Self.external])
        }
    #endif
}

@MainActor @Suite struct MultiDisplayHostTests {
    @Test func allShowsTheSameStateOnEveryDisplay() async throws {
        let f = DisplayHostFixture([.notched(1), .plain(2, x: 1512, main: true), .plain(3, x: 3432)])
        f.selection = .all
        f.host.start()
        defer { f.host.stop() }
        #expect(f.host.islands.map(\.display.id) == [1, 2, 3])
        #expect(f.host.activeDisplayID == 1)
        #expect(f.host.panels.count == 3)
        #expect(f.panels.filter(\.isShown).count == 3)
        await f.makeBusy()
        let virtualWings = f.host.islands.filter(\.geometry.isVirtual).map(\.geometry.wings.leading)
        #expect(virtualWings == [120, 120])
        #expect(f.host.peekAnchors.count == 3)
    }

    @Test func anchorsFollowTheDisplayUnderThePointerElseTheMainVigieDisplay() throws {
        let f = DisplayHostFixture([.notched(1), .plain(2, x: 1512, main: true)])
        f.selection = .all
        f.host.start()
        defer { f.host.stop() }
        let onExternal = try #require(f.host.anchor(forDisplayUnder: CGPoint(x: 2000, y: 500)))
        #expect(onExternal.screenFrame.minX == 1512)
        f.selection = .notched
        f.host.reloadDisplayConfiguration()
        let fallback = try #require(f.host.anchor(forDisplayUnder: CGPoint(x: 2000, y: 500)))
        #expect(fallback.screenFrame.minX == 0)  // the external display shows no island now
    }

    @Test func hotPlugAddsAndRemovesPanelsAndKeepsTheSurvivingOne() throws {
        let f = DisplayHostFixture([.plain(2, main: true)])
        f.selection = .all
        f.host.start()
        defer { f.host.stop() }
        let first = try #require(f.panel(2))

        f.displays.append(.plain(3, x: 1920))
        f.host.layout()
        #expect(f.host.panels.count == 2)
        #expect(f.panel(2) === first)

        f.displays.removeLast()
        f.host.layout()
        #expect(f.host.panels.count == 1)
        #expect(f.panel(2) === first)
        let gone = f.panels.first { $0.displayID == 3 }
        #expect(gone?.isShown == false)
        #expect(f.panels.count == 2)  // no duplicate panel was ever created
    }

    @Test func resolutionChangeMovesTheSamePanel() throws {
        let f = DisplayHostFixture([.plain(2, main: true)])
        f.host.start()
        defer { f.host.stop() }
        let panel = try #require(f.panel(2))
        f.displays[0].metrics.frame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        f.host.layout()
        #expect(f.panel(2) === panel)
        #expect(panel.frame?.midX == 1280)
        #expect(panel.frame?.maxY == 1440)
    }

    @Test func lidClosedMovesTheIslandToTheMainExternalDisplay() throws {
        let f = DisplayHostFixture([.notched(1), .plain(2, x: 1512, main: true)])
        f.host.start()
        defer { f.host.stop() }
        #expect(f.host.activeDisplayID == 1)
        #expect(f.host.geometry?.isVirtual == false)

        f.displays.removeFirst()  // clamshell
        f.host.layout()
        #expect(f.host.activeDisplayID == 2)
        #expect(f.host.geometry?.isVirtual == true)
        #expect(f.panel(1) == nil)
        #expect(f.panel(2)?.isShown == true)

        f.displays.insert(.notched(1), at: 0)  // lid opened
        f.host.layout()
        #expect(f.host.activeDisplayID == 1)
        #expect(f.host.panels.count == 1)
    }

    @Test func screenParameterNotificationsReplaceOnTheNextRunLoopTurn() async throws {
        let f = DisplayHostFixture([.plain(2, main: true)])
        f.host.start()
        defer { f.host.stop() }
        f.displays = [.plain(2, main: true), .plain(3, x: 1920)]
        f.selection = .all
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(f.host.panels.count == 1)  // not yet: next run-loop turn
        for _ in 0..<50 where f.host.panels.count != 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(f.host.panels.count == 2)
        #expect(f.panels.count == 2)
    }

    @Test func hideInFullScreenReachesEveryPanel() {
        let f = DisplayHostFixture([.plain(2, main: true), .plain(3, x: 1920)])
        f.selection = .all
        f.host.start()
        defer { f.host.stop() }
        #expect(f.panels.map(\.hidesInFullScreen) == [true, true])
        f.hideInFullScreen = false
        f.host.reloadDisplayConfiguration()
        #expect(f.panels.map(\.hidesInFullScreen) == [false, false])
    }

    @Test func displayPromptWaitsWhenAPlainDisplayIsConnected() {
        let f = DisplayHostFixture([.notched(1)])
        f.promptPending = true
        f.host.start()
        defer { f.host.stop() }
        #expect(!f.host.showsDisplayPrompt)  // only a notched display
        f.displays.append(.plain(2, x: 1512, main: true))
        f.host.layout()
        #expect(f.host.showsDisplayPrompt)
        #expect(!f.host.isExpanded)  // it never opens the view by itself
    }

    @Test func displayPromptThisDisplayWritesItsName() {
        let f = DisplayHostFixture([.notched(1), .plain(2, x: 1512, main: true, name: "LG HDR 4K")])
        f.promptPending = true
        f.pointer = CGPoint(x: 2000, y: 500)
        f.host.start()
        defer { f.host.stop() }
        #expect(f.host.showsDisplayPrompt)
        f.host.answerDisplayPromptWithThisDisplay()
        #expect(f.answers == [.choose(.named("LG HDR 4K"))])
        #expect(!f.host.showsDisplayPrompt)
        f.host.layout()
        #expect(!f.host.showsDisplayPrompt)  // not shown again
    }

    @Test func displayPromptDismissIsFinal() {
        let f = DisplayHostFixture([.plain(2, main: true)])
        f.promptPending = true
        f.host.start()
        defer { f.host.stop() }
        f.host.answerDisplayPrompt(.dismissed)
        #expect(f.answers == [.dismissed])
        f.host.reloadDisplayConfiguration()
        #expect(!f.host.showsDisplayPrompt)
    }

    @Test func displayPromptNotPendingNeverShows() {
        let f = DisplayHostFixture([.plain(2, main: true)])
        f.host.start()
        defer { f.host.stop() }
        #expect(!f.host.showsDisplayPrompt)
    }
}
