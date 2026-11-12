import AppKit
import Foundation
import SwiftUI
import Testing

@testable import VigieUI

/// Story 12.10: the line diff, the update variant of the Script Confirmation and the `UPDATE AVAILABLE` badge.
@MainActor @Suite struct ScriptUpdateTests {
    typealias Line = ScriptLineDiff.Line

    // MARK: - Line diff

    @Test func identicalFilesAreAllContext() {
        let text = "a\nb\nc\n"
        #expect(
            ScriptLineDiff.lines(old: text, new: text) == [
                .context("a", 1, 1), .context("b", 2, 2), .context("c", 3, 3),
            ])
        #expect(ScriptLineDiff.counts(ScriptLineDiff.lines(old: text, new: text)) == (0, 0))
    }

    @Test func emptyFiles() {
        #expect(ScriptLineDiff.lines(old: "", new: "").isEmpty)
        #expect(ScriptLineDiff.lines(old: "", new: "a\nb") == [.added("a", 1), .added("b", 2)])
        #expect(ScriptLineDiff.lines(old: "a\nb\n", new: "") == [.removed("a", 1), .removed("b", 2)])
        #expect(ScriptLineDiff.rows([]).isEmpty)
    }

    @Test func insertion() {
        #expect(
            ScriptLineDiff.lines(old: "a\nc\n", new: "a\nb\nc\n") == [
                .context("a", 1, 1), .added("b", 2), .context("c", 2, 3),
            ])
    }

    @Test func deletion() {
        #expect(
            ScriptLineDiff.lines(old: "a\nb\nc", new: "a\nc") == [
                .context("a", 1, 1), .removed("b", 2), .context("c", 3, 2),
            ])
    }

    @Test func changeListsRemovedBeforeAdded() {
        #expect(
            ScriptLineDiff.lines(old: "a\nb\nc\nd", new: "a\nB\nc\nD\ne") == [
                .context("a", 1, 1), .removed("b", 2), .added("B", 2), .context("c", 3, 3), .removed("d", 4),
                .added("D", 4), .added("e", 5),
            ])
    }

    @Test func crlfAndFinalNewlineDoNotCountAsChanges() {
        #expect(ScriptLineDiff.split("a\r\nb\r\n") == ["a", "b"])
        #expect(ScriptLineDiff.counts(ScriptLineDiff.lines(old: "a\nb", new: "a\nb\n")) == (0, 0))
    }

    /// Myers finds the shortest script: moving one line costs one removal and one addition.
    @Test func diffIsMinimalAndReplaysBothFiles() {
        let old = (1...40).map { "line \($0)" }
        var new = old
        new.remove(at: 5)
        new.insert("moved", at: 30)
        new[12] = "changed"
        let lines = ScriptLineDiff.lines(old: old, new: new)
        #expect(ScriptLineDiff.counts(lines) == (2, 2))
        #expect(lines.filter { $0.kind != .added }.map(\.text) == old)
        #expect(lines.filter { $0.kind != .removed }.map(\.text) == new)
        #expect(lines.compactMap(\.newNumber) == Array(1...new.count))
        #expect(lines.compactMap(\.oldNumber) == Array(1...old.count))
    }

    @Test func aRewriteBeyondTheEditLimitIsRemoveAllThenAddAll() {
        let old = (0..<700).map { "o\($0)" }
        let new = (0..<700).map { "n\($0)" }
        let lines = ScriptLineDiff.lines(old: old, new: new)
        #expect(lines.prefix(700).allSatisfy { $0.kind == .removed })
        #expect(lines.suffix(700).allSatisfy { $0.kind == .added })
    }

    @Test func rowsFoldLongUnchangedRuns() {
        let old = (1...20).map { "l\($0)" }
        var new = old
        new[9] = "x"
        let rows = ScriptLineDiff.rows(ScriptLineDiff.lines(old: old, new: new), context: 2)
        #expect(rows.first == .skipped(7))
        #expect(rows.last == .skipped(8))
        #expect(rows.count == 1 + 2 + 2 + 2 + 1)
        #expect(ScriptLineDiff.rows(ScriptLineDiff.lines(old: "a\nb", new: "a\nb")) == [.skipped(2)])
    }

    // MARK: - Update sheet

    static func update(_ verification: ScriptConfirmationContent.Verification) -> ScriptConfirmationContent {
        var content = ScriptConfirmationTests.install(verification)
        content.update = .init(
            diff: ScriptLineDiff.lines(old: "id: a\necho 1\n", new: "id: a\necho 2\n"), oldVersion: "1.0.0",
            newVersion: nil)
        return content
    }

    @Test func updateCopy() {
        #expect(ScriptConfirmationCopy.version(old: "1.0.0", new: nil) == "Version 1.0.0 → not given")
        #expect(ScriptConfirmationCopy.changeCounts(added: 3, removed: 1) == "+3 −1 lines")
        #expect(ScriptConfirmationCopy.skipped(12) == "12 unchanged lines")
        #expect(ScriptConfirmationCopy.spoken(.added("x", 1)) == "Added: x")
        #expect(ScriptConfirmationCopy.spoken(.removed("x", 1)) == "Removed: x")
        #expect(ScriptUpdateBadge.text == "UPDATE AVAILABLE")
    }

    @Test func privacyDisablesConfirmOnAnUpdate() {
        let content = Self.update(.verified)
        #expect(ScriptConfirmationView.confirmEnabled(content, privacyActive: false))
        #expect(!ScriptConfirmationView.confirmEnabled(content, privacyActive: true))
    }

    @Test func updateSheetRendersInBothPrivacyStatesForEveryVerification() {
        for verification in [ScriptConfirmationContent.Verification.verified, .unsigned, .badSignature, .otherSite] {
            for privacy in [false, true] {
                let view = ScriptConfirmationView(
                    content: Self.update(verification), onConfirm: {}, onDecline: {}, onCancel: {}
                )
                .privacyActive(privacy)
                .frame(width: 640, height: 640)
                #expect(ImageRenderer(content: view).cgImage != nil)
            }
        }
    }

    /// UX-DR98: the diff, author and source are masked; the verification line and title stay.
    @Test func privacyMasksTheDiff() {
        func strings(_ privacy: Bool) -> String {
            let view = ScriptConfirmationView(
                content: Self.update(.unsigned), onConfirm: {}, onDecline: {}, onCancel: {}
            )
            .privacyActive(privacy)
            return PrivacyTests.accessibilityStrings(view, size: CGSize(width: 640, height: 640)).joined(separator: "|")
        }
        let open = strings(false)
        #expect(open.contains("Review script update"))
        #expect(open.contains("Added: echo 2"))
        #expect(open.contains("Removed: echo 1"))
        let masked = strings(true)
        #expect(!masked.contains("echo"))
        #expect(!masked.contains("Léa"))
        #expect(masked.contains("Not verified: this file is not signed."))
    }

    @Test func diffViewRendersInBothPrivacyStates() {
        for privacy in [false, true] {
            let view = ScriptDiffView(lines: ScriptLineDiff.lines(old: "a\nb\n", new: "a\nc\n"))
                .privacyActive(privacy)
                .vigieTheme(PreviewThemes.theme(.dark))
                .frame(width: 400, height: 200)
            #expect(ImageRenderer(content: view).cgImage != nil)
        }
    }

    // MARK: - Badge

    @Test func badgeReachesCardAndPageLabels() {
        let now = Date()
        var card = ScriptCardModel(name: "Site", cadence: "EVERY 1M", body: .notConfirmed)
        #expect(!card.accessibilityLabel(now: now).contains("UPDATE AVAILABLE"))
        card.updateAvailable = true
        #expect(card.accessibilityLabel(now: now).hasSuffix("UPDATE AVAILABLE"))
        let page = ScriptPageModel(
            hero: card, kind: .status, documentation: "",
            runs: ScriptRunsCardModel(
                runtime: "sh", interval: .seconds(60), timeout: .seconds(30), fileName: "a.md", folder: "~/m/",
                runs: [], nextRunAt: nil, isRunning: false))
        #expect(page.heroAccessibilityLabel(now: now).contains("UPDATE AVAILABLE"))
        for privacy in [false, true] {
            let view = ScriptCard(model: card, now: now, onReviewUpdate: {})
                .privacyActive(privacy)
                .vigieTheme(PreviewThemes.theme(.dark))
            #expect(ImageRenderer(content: view).cgImage != nil)
            let pageView = ScriptPage(model: page, now: now)
                .privacyActive(privacy)
                .vigieTheme(PreviewThemes.theme(.dark))
                .frame(width: 640, height: 400)
            #expect(ImageRenderer(content: pageView).cgImage != nil)
        }
    }
}
