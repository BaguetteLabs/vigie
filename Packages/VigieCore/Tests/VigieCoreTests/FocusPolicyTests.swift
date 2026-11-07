import ModuleKit
import Testing

@testable import VigieCore

@MainActor
final class FakeSurface: KeySurface {
    let surfaceID: String
    private(set) var isKey = false
    private(set) var isClosed = false
    private(set) var log: [String] = []

    init(_ id: String) { surfaceID = id }

    func makeKey() {
        isKey = true
        log.append("makeKey")
    }

    func resignKey() {
        isKey = false
        log.append("resignKey")
    }

    func close() {
        isKey = false
        isClosed = true
        log.append("close")
    }
}

@MainActor
@Suite struct FocusPolicyTests {
    let policy = FocusPolicy()

    @Test func twoSurfacesWithIntentOnlyTheSecondIsKey() {
        let notch = FakeSurface("notch")
        let notes = FakeSurface("notes")
        policy.present(notch, focus: UserIntentMinter.mint(source: .click))
        policy.present(notes, focus: UserIntentMinter.mint(source: .hotkey("notes.new")))
        #expect(!notch.isKey)
        #expect(notes.isKey)
        #expect(notch.log == ["makeKey", "resignKey"])
        #expect(policy.keySurfaceID == "notes")
        #expect(policy.presentedSurfaceIDs == ["notch", "notes"])
    }

    @Test func presentWithoutIntentTakesNoFocus() {
        let notch = FakeSurface("notch")
        policy.present(notch, focus: nil)
        #expect(!notch.isKey)
        #expect(notch.log.isEmpty)
        #expect(policy.keySurfaceID == nil)
        #expect(policy.presentedSurfaceIDs == ["notch"])
    }

    @Test func presentWithoutIntentLeavesTheCurrentKeySurfaceKey() {
        let notes = FakeSurface("notes")
        let notch = FakeSurface("notch")
        policy.present(notes, focus: UserIntentMinter.mint(source: .menu("new-note")))
        policy.present(notch, focus: nil)  // e.g. opened during a drag
        #expect(notes.isKey)
        #expect(!notch.isKey)
        #expect(policy.keySurfaceID == "notes")
    }

    @Test func escapeClosesOnlyTheKeySurface() {
        let notch = FakeSurface("notch")
        let notes = FakeSurface("notes")
        policy.present(notch, focus: nil)
        policy.present(notes, focus: UserIntentMinter.mint(source: .click))
        #expect(policy.handleEscape())
        #expect(notes.isClosed)
        #expect(!notch.isClosed)
        #expect(policy.keySurfaceID == nil)
        #expect(policy.presentedSurfaceIDs == ["notch"])
        // Nothing is key now: Esc is not consumed and closes nothing.
        #expect(!policy.handleEscape())
        #expect(!notch.isClosed)
    }

    @Test func escapeWithNoKeySurfaceReturnsFalse() {
        #expect(!policy.handleEscape())
    }

    @Test func dismissingTheKeySurfaceMovesFocusNowhere() {
        let notch = FakeSurface("notch")
        let notes = FakeSurface("notes")
        policy.present(notch, focus: UserIntentMinter.mint(source: .click))
        policy.present(notes, focus: UserIntentMinter.mint(source: .click))
        policy.dismissed(notes)
        #expect(policy.keySurfaceID == nil)
        #expect(!notch.isKey)
        #expect(policy.presentedSurfaceIDs == ["notch"])
    }

    @Test func resignedOutsideThePolicyClearsKey() {
        let notch = FakeSurface("notch")
        policy.present(notch, focus: UserIntentMinter.mint(source: .click))
        policy.surfaceDidResignKey(notch)
        #expect(policy.keySurfaceID == nil)
        #expect(!policy.handleEscape())
        #expect(!notch.isClosed)
    }

    @Test func representingTheKeySurfaceWithIntentDoesNotResignIt() {
        let notch = FakeSurface("notch")
        policy.present(notch, focus: UserIntentMinter.mint(source: .click))
        policy.present(notch, focus: UserIntentMinter.mint(source: .click))
        #expect(notch.log == ["makeKey", "makeKey"])
        #expect(policy.presentedSurfaceIDs == ["notch"])
    }

    @Test func minterIssuesFreshTokens() {
        let first = UserIntentMinter.mint(source: .peekAction)
        let second = UserIntentMinter.mint(source: .peekAction)
        #expect(first.id != second.id)
    }
}
