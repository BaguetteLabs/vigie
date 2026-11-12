import CryptoKit
import Foundation
import ModuleKit
import Testing
import VigieUI

@testable import Integrations

/// Story 12.3: per-Mac confirmation of script files (AD-18, SPEC §9.2, UX-DR87). Temp folders only; records in
/// the in-memory ``MemoryScriptConfirmations`` (the `local.toml` side; VigieCore tests the real file).
@MainActor @Suite struct ConfirmationTests {
    typealias Folder = ScriptDiscoveryTests.Folder

    static let text = ScriptDiscoveryTests.script(id: "test.prs", code: "print('hi')")

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func start(_ folder: Folder, enabled: [String: Bool] = [:]) async throws
        -> (IntegrationsModule, FakeModuleContext)
    {
        try await ScriptDiscoveryTests().start(folder, enabled: enabled)
    }

    func rescan(_ module: IntegrationsModule, _ context: FakeModuleContext) async throws {
        try await ScriptDiscoveryTests().change(module, context)
    }

    func script(_ module: IntegrationsModule, _ name: String = "prs.md") throws -> ScriptModuleDefinition {
        try #require(module.scripts.first { $0.fileName == name })
    }

    func waitFor(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - State

    @Test func aNewFileAwaitsConfirmationAndIsNotEligible() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("prs.md", Self.text)
        let (module, _) = try await start(folder)
        let prs = try script(module)
        #expect(module.localState(for: prs) == .awaitingConfirmation)
        #expect(module.localStates == ["prs.md": .awaitingConfirmation])
        #expect(!module.isEligible(prs))
        await module.stop()
    }

    @Test func confirmRecordsTheRelativePathAndTheHashOfTheBytes() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("prs.md", Self.text)
        let (module, context) = try await start(folder)
        let prs = try script(module)
        module.openConfirmation(for: prs)
        #expect(module.reviewing == prs)

        try await module.confirm(prs)
        let hash = Self.sha256(Self.text)
        #expect(context.fakeScriptFolder.fakeConfirmations.writes == [.confirm("modules/prs.md", hash)])
        #expect(
            context.fakeScriptFolder.fakeConfirmations.records == [
                "modules/prs.md": ScriptConfirmationRecord(confirmedSHA256: hash)
            ])
        #expect(module.localState(for: prs) == .confirmed)
        #expect(module.localStates["prs.md"] == .confirmed)
        #expect(module.isEligible(prs))
        #expect(module.reviewing == nil)
        await module.stop()
    }

    @Test func oneChangedByteReturnsTheScriptToAwaitingConfirmation() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("prs.md", Self.text)
        let (module, context) = try await start(folder)
        try await module.confirm(try script(module))

        try folder.write("prs.md", Self.text.replacingOccurrences(of: "'hi'", with: "'ho'"))
        try await rescan(module, context)
        let changed = try script(module)
        #expect(module.localState(for: changed) == .awaitingConfirmation)
        #expect(module.localStates["prs.md"] == .awaitingConfirmation)
        #expect(!module.isEligible(changed))
        // The old record stays; it just no longer matches.
        let record = context.fakeScriptFolder.fakeConfirmations.records["modules/prs.md"]
        #expect(record?.confirmedSHA256 == Self.sha256(Self.text))
        #expect(record?.confirmedSHA256 != changed.contentHash)
        await module.stop()
    }

    @Test func declineDisablesOnThisMacAndConfirmAfterwardsClearsIt() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("prs.md", Self.text)
        let (module, context) = try await start(folder)
        let prs = try script(module)
        let records = context.fakeScriptFolder.fakeConfirmations

        try await module.decline(prs)
        #expect(module.localState(for: prs) == .declined)
        #expect(!module.isEligible(prs))
        #expect(records.records["modules/prs.md"] == ScriptConfirmationRecord(declinedSHA256: prs.contentHash))
        // Nothing else happens: no alert, no dynamic module, state unchanged.
        #expect(context.fakeNotifier.posted.isEmpty)
        #expect(module.state == .hidden)

        try await module.confirm(prs)
        #expect(module.localState(for: prs) == .confirmed)
        #expect(records.records["modules/prs.md"] == ScriptConfirmationRecord(confirmedSHA256: prs.contentHash))
        #expect(
            records.writes == [
                .decline("modules/prs.md", prs.contentHash), .confirm("modules/prs.md", prs.contentHash),
            ])
        await module.stop()
    }

    /// Decided (SPEC §9.2 "whose content changes in any way shows as awaiting confirmation"): a byte change clears
    /// a decline too, so the new content is reviewed again.
    @Test func aChangedFileIsReviewedAgainAfterADecline() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("prs.md", Self.text)
        let (module, context) = try await start(folder)
        try await module.decline(try script(module))
        try folder.write("prs.md", Self.text + "\n")
        try await rescan(module, context)
        #expect(module.localState(for: try script(module)) == .awaitingConfirmation)
        await module.stop()
    }

    @Test func aDeletedFileLeavesItsHarmlessRecord() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("prs.md", Self.text)
        let (module, context) = try await start(folder)
        try await module.confirm(try script(module))
        try folder.remove("prs.md")
        try await rescan(module, context)
        #expect(module.scripts.isEmpty)
        #expect(module.localStates.isEmpty)
        #expect(context.fakeScriptFolder.fakeConfirmations.records["modules/prs.md"] != nil)

        // The same bytes back under the same name are still confirmed (same path, same hash).
        try folder.write("prs.md", Self.text)
        try await rescan(module, context)
        #expect(module.localState(for: try script(module)) == .confirmed)
        await module.stop()
    }

    @Test func recordsChangedOutsideTheAppAreApplied() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("prs.md", Self.text)
        let (module, context) = try await start(folder)
        let prs = try script(module)
        let records = context.fakeScriptFolder.fakeConfirmations

        records.edit("modules/prs.md", ScriptConfirmationRecord(confirmedSHA256: prs.contentHash.uppercased()))
        try await waitFor { module.localStates["prs.md"] == .confirmed }
        // A hand edit holding both reads the safe way.
        records.edit(
            "modules/prs.md",
            ScriptConfirmationRecord(confirmedSHA256: prs.contentHash, declinedSHA256: prs.contentHash))
        try await waitFor { module.localStates["prs.md"] == .declined }
        records.edit("modules/prs.md", nil)
        try await waitFor { module.localStates["prs.md"] == .awaitingConfirmation }

        await module.stop()
        try await waitFor { records.subscribers == 0 }
    }

    @Test func eligibleMeansParsedEnabledAndConfirmed() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("prs.md", Self.text)
        try folder.write("off.md", ScriptDiscoveryTests.script(id: "test.off"))
        try folder.write("broken.md", "---\nid: test.broken\n---\nno code")
        let (module, _) = try await start(folder, enabled: ["modules/off.md": false])
        for name in ["prs.md", "off.md", "broken.md"] { try await module.confirm(try script(module, name)) }
        #expect(module.isEligible(try script(module, "prs.md")))
        #expect(module.localState(for: try script(module, "off.md")) == .confirmed)
        #expect(!module.isEligible(try script(module, "off.md")))
        #expect(module.localState(for: try script(module, "broken.md")) == .confirmed)
        #expect(!module.isEligible(try script(module, "broken.md")))
        await module.stop()
    }

    // MARK: - Review

    @Test func cancelRecordsNothing() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("prs.md", Self.text)
        let (module, context) = try await start(folder)
        module.openConfirmation(for: try script(module))
        module.cancelConfirmation()
        #expect(module.reviewing == nil)
        #expect(context.fakeScriptFolder.fakeConfirmations.writes.isEmpty)
        #expect(module.localState(for: try script(module)) == .awaitingConfirmation)
        await module.stop()
    }

    /// The user confirms what they saw: a file rewritten while the review was open stays awaiting confirmation.
    @Test func confirmingAStaleReviewDoesNotConfirmTheNewBytes() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("prs.md", Self.text)
        let (module, context) = try await start(folder)
        let reviewed = try script(module)
        module.openConfirmation(for: reviewed)
        try folder.write("prs.md", Self.text.replacingOccurrences(of: "print", with: "exec"))
        try await rescan(module, context)
        try await module.confirm(reviewed)
        #expect(module.localState(for: try script(module)) == .awaitingConfirmation)
        #expect(!module.isEligible(try script(module)))
        await module.stop()
    }

    @Test func aFailedWriteChangesNothing() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("prs.md", Self.text)
        let (module, context) = try await start(folder)
        context.fakeScriptFolder.fakeConfirmations.failure = ModuleServiceError.notAvailable
        let prs = try script(module)
        await #expect(throws: ModuleServiceError.notAvailable) { try await module.confirm(prs) }
        #expect(module.localState(for: prs) == .awaitingConfirmation)
        await module.stop()
    }

    @Test func theReviewShowsTheWholeFileAndTheWarning() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("prs.md", Self.text)
        let (module, _) = try await start(folder)
        let prs = try script(module)
        let content = module.confirmationContent(for: prs)
        #expect(content.fileName == "prs.md")
        #expect(content.path == prs.url.path)
        #expect(content.documentation == "Docs for test.prs.")
        #expect(content.frontMatter == "id: test.prs\nname: Test\ninterval: 5m\nruntime: bash\nwidget: text")
        #expect(content.code == "print('hi')")
        #expect(content.language == "bash")
        #expect(content.fileText == Self.text)
        #expect(content.problem == nil)
        #expect(
            ScriptConfirmationCopy.warning
                == "Scripts run as the user, with no sandbox. Only install scripts you trust.")
        #expect(module.settingsView() != nil)
        await module.stop()
    }

    @Test func anErroredFileShowsItsProblemInTheReview() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("broken.md", "---\nid: test.broken\n---\nno code")
        let (module, _) = try await start(folder)
        let broken = try script(module, "broken.md")
        let content = module.confirmationContent(for: broken)
        #expect(content.code == nil)
        #expect(content.problem != nil)
        #expect(content.problem == broken.errorMessage)
        await module.stop()
    }

    @Test func stopClosesTheReviewAndDropsTheRecords() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("prs.md", Self.text)
        let (module, context) = try await start(folder)
        #expect(context.fakeScriptFolder.fakeConfirmations.subscribers == 1)
        module.openConfirmation(for: try script(module))
        await module.stop()
        #expect(module.reviewing == nil)
        #expect(module.confirmations is NoScriptConfirmations)
        try await waitFor { context.fakeScriptFolder.fakeConfirmations.subscribers == 0 }
    }

    // MARK: - Catalog

    @Test func everyShippedLocaleHasTheConfirmationStrings() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Integrations/Resources/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let strings = try #require(catalog?["strings"] as? [String: Any])
        var locales: Set<String> = []
        for case let entry as [String: Any] in strings.values {
            locales.formUnion((entry["localizations"] as? [String: Any])?.keys ?? [:].keys)
        }
        let keys = strings.keys.filter { $0.hasPrefix("script.settings.") }
        // 7 from Story 12.3, 11 from Settings › Scripts (12.6), 6 from Add example (12.7), 7 from updates (12.10)
        #expect(keys.count == 31)
        for key in keys {
            let entry = try #require(strings[key] as? [String: Any])
            let localized = Set((entry["localizations"] as? [String: Any])?.keys ?? [:].keys)
            #expect(localized == locales, "\(key) is missing a locale")
            #expect(IntegrationsText.string(key) != key, "\(key) does not resolve")
        }
    }
}
