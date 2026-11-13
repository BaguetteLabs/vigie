import AppKit
import Foundation
@_spi(Host) import ModuleKit
import SwiftUI
import Testing
import VigieUI

@testable import VigieCore

@MainActor
final class FakeFloatingPanel: FloatingPanelPresenting {
    private(set) var isKey = false
    private(set) var frame: CGRect?
    private(set) var log: [String] = []

    func show(frame: CGRect) {
        self.frame = frame
        log.append("show")
    }

    func takeKey() {
        isKey = true
        log.append("takeKey")
    }

    func dropKey() {
        isKey = false
        log.append("dropKey")
    }

    func hide() {
        frame = nil
        isKey = false
        log.append("hide")
    }

    /// The user clicked another app.
    func loseKey() { isKey = false }
}

@MainActor
final class FakeFocusReturn: AppFocusReturning {
    var frontmost: FocusReturnTarget? = FocusReturnTarget(processID: 4242)
    private(set) var returned: [FocusReturnTarget] = []

    func frontmostApp() -> FocusReturnTarget? { frontmost }
    func returnFocus(to app: FocusReturnTarget) { returned.append(app) }
}

/// Story 15.3: the module floating panel (no window is created, shown or made key here).
@MainActor @Suite struct FloatingPanelTests {
    static let screen = FloatingPanelScreen(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 945))

    let panel = FakeFloatingPanel()
    let focusReturn = FakeFocusReturn()
    let policy = FocusPolicy()
    let theme = try! ThemeLoader.loadBundled().resolve(themeID: "chrome-hologram", look: .dark).theme
    var clock = Date(timeIntervalSince1970: 1_800_000_000)

    func controller(now: Date? = nil) -> FloatingPanelController {
        let panel = panel
        let theme = theme
        let date = now ?? clock
        return FloatingPanelController(
            focusPolicy: policy, theme: { theme }, screen: { Self.screen }, makePresenter: { _ in panel },
            focusReturn: focusReturn, now: { date })
    }

    func intent(_ date: Date? = nil) -> UserIntent { UserIntent(issuedAt: date ?? clock) }

    final class Calls {
        var escapes = 0
        var closes = 0
    }

    func request(_ id: String = "notes.panel", calls: Calls = Calls()) -> FloatingPanelRequest {
        FloatingPanelRequest(
            id: id, content: { AnyView(EmptyView()) }, onEscape: { calls.escapes += 1 },
            onClose: { calls.closes += 1 })
    }

    // MARK: Geometry

    @Test func thePanelIsCentredBelowTheMenuBar() {
        let size = theme.notesPanelSize
        #expect(size == CGSize(width: 460, height: 372))
        #expect(theme.radius(.notesPanel) == 16)
        let frame = FloatingPanelController.panelFrame(size: size, screen: Self.screen, gap: 16)
        #expect(frame == CGRect(x: 526, y: 945 - 16 - 372, width: 460, height: 372))
    }

    @Test func geometryOnASecondaryScreenAndAnAutoHiddenMenuBar() {
        let screen = FloatingPanelScreen(
            frame: CGRect(x: 1512, y: -200, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1512, y: -200, width: 1920, height: 1080))
        let frame = FloatingPanelController.panelFrame(
            size: CGSize(width: 460, height: 372), screen: screen, gap: 16)
        #expect(frame.midX == screen.frame.midX)
        #expect(frame.maxY == screen.frame.maxY - 16)
        // A screen too small keeps the panel on screen.
        let tiny = FloatingPanelScreen(
            frame: CGRect(x: 0, y: 0, width: 400, height: 300),
            visibleFrame: CGRect(x: 0, y: 0, width: 400, height: 280))
        let clamped = FloatingPanelController.panelFrame(size: CGSize(width: 460, height: 372), screen: tiny, gap: 16)
        #expect(clamped.minX == 0)
        #expect(clamped.minY == 0)
    }

    // MARK: Requests

    @Test func aRequestWithoutALiveIntentIsRefused() {
        let controller = controller()
        #expect(!controller.present(request(), owner: "notes", focus: nil))
        #expect(!controller.present(request(), owner: "notes", focus: intent(clock.addingTimeInterval(-10))))
        #expect(controller.shown == nil)
        #expect(panel.log.isEmpty)
        #expect(policy.keySurfaceID == nil)
    }

    @Test func presentShowsTheRequestAndTakesFocusRememberingTheFrontmostApp() {
        let controller = controller()
        #expect(controller.present(request(), owner: "notes", focus: intent()))
        #expect(panel.log == ["show", "takeKey"])
        #expect(panel.frame == CGRect(x: 526, y: 945 - theme.floatingPanelTopGap - 372, width: 460, height: 372))
        #expect(controller.isKey)
        #expect(policy.keySurfaceID == FloatingPanelSurface.id)
        #expect(controller.shown?.owner == "notes")
        #expect(controller.shown?.previousApp == FocusReturnTarget(processID: 4242))
    }

    @Test func escRunsOnEscapeClosesAndReturnsFocus() {
        let controller = controller()
        let calls = Calls()
        controller.present(request(calls: calls), owner: "notes", focus: intent())
        controller.escapePressed()
        #expect(calls.escapes == 1)
        #expect(calls.closes == 1)
        #expect(controller.shown == nil)
        #expect(panel.log.last == "hide")
        #expect(policy.keySurfaceID == nil)
        #expect(focusReturn.returned == [FocusReturnTarget(processID: 4242)])
        controller.escapePressed()
        #expect(calls.escapes == 1)
    }

    @Test func oneAtATimeANewRequestReplacesTheShownOne() {
        let controller = controller()
        let first = Calls()
        let second = Calls()
        controller.present(request("a", calls: first), owner: "notes", focus: intent())
        focusReturn.frontmost = nil  // Vigie's own panel is frontmost now
        controller.present(request("b", calls: second), owner: "other", focus: intent())
        #expect(first.closes == 1)
        #expect(second.closes == 0)
        #expect(controller.shown?.request.id == "b")
        #expect(focusReturn.returned.isEmpty)
        // Focus still goes back to the app the first panel came from.
        #expect(controller.shown?.previousApp == FocusReturnTarget(processID: 4242))
        #expect(panel.isKey)
    }

    @Test func dismissIsPerOwnerAndAPanelThatLostFocusGivesNothingBack() {
        let controller = controller()
        let calls = Calls()
        controller.present(request(calls: calls), owner: "notes", focus: intent())
        controller.dismiss(owner: "calendar")
        #expect(controller.shown != nil)
        panel.loseKey()
        controller.panelDidResignKey()
        #expect(policy.keySurfaceID == nil)
        controller.dismiss(owner: "notes")
        #expect(calls.closes == 1)
        #expect(focusReturn.returned.isEmpty)
    }

    @Test func anotherSurfaceTakingFocusResignsThePanel() {
        let controller = controller()
        controller.present(request(), owner: "notes", focus: intent())
        final class Other: KeySurface {
            var surfaceID: String { "other" }
            func makeKey() {}
            func resignKey() {}
            func close() {}
        }
        let other = Other()
        policy.present(other, focus: intent())
        #expect(!panel.isKey)
        #expect(controller.shown != nil)
    }

    // MARK: Host control

    @Test func hostControlDelegatesToTheLinkController() {
        let link = NotchHostLink()
        let control = CoreHostControl(moduleID: "notes", link: link)
        #expect(!control.presentFloatingPanel(request(), focus: intent()))
        let controller = controller()
        link.floatingPanels = controller
        #expect(!control.presentFloatingPanel(request(), focus: nil))
        #expect(control.presentFloatingPanel(request(), focus: intent()))
        #expect(controller.shown?.owner == "notes")
        CoreHostControl(moduleID: "calendar", link: link).dismissFloatingPanel()
        #expect(controller.shown != nil)
        control.dismissFloatingPanel()
        #expect(controller.shown == nil)
    }

    @Test func escapeKeyDetection() throws {
        let esc = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53))
        #expect(FloatingPanelWindow.isEscape(esc))
        let cmdEsc = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: 0,
                context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false,
                keyCode: 53))
        #expect(!FloatingPanelWindow.isEscape(cmdEsc))
    }
}
