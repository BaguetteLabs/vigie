import CryptoKit
import Foundation
@_spi(Host) import ModuleKit
import Testing
import VigieUI

@testable import Integrations

/// A clock tests move by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
}

/// Story 12.10: script update checks, the `UPDATE AVAILABLE` badge and the update review (SPEC §9.5, AD-18,
/// UX-DR87, UX-DR106). Fake downloader, fake scheduler and clock, a throwaway Ed25519 key; no network.
@MainActor @Suite struct UpdateTests {
    typealias Folder = ScriptDiscoveryTests.Folder

    static let fileURL = InstallTests.fileURL
    static let key = InstallTests.key
    static let day: TimeInterval = 24 * 60 * 60
    static let v1 = InstallTests.script()
    static let v2 = InstallTests.script(extra: "\nversion: 1.1.0")
    static let v3 = InstallTests.script(extra: "\nversion: 1.2.0")

    static func hash(_ text: String) -> String { ScriptModuleDefinition.sha256(Data(text.utf8)) }

    @MainActor final class Setup {
        let folder: Folder
        let temp: URL
        let downloader = FakeDownloader()
        let clock = TestClock()
        let context: FakeModuleContext
        var module = IntegrationsModule()

        var confirmations: MemoryScriptConfirmations { context.fakeScriptFolder.fakeConfirmations }
        var storage: URL { context.fakeStorage.directory }

        init(settings: [String: any SettingValue] = [:], trusted: [Curve25519.Signing.PrivateKey] = [UpdateTests.key])
            throws
        {
            folder = try Folder()
            temp = folder.root.appendingPathComponent("tmp", isDirectory: true)
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            context = FakeModuleContext(settings: settings, scriptFolder: FakeScriptFolder(url: folder.url))
            configure(module, trusted: trusted.map { $0.publicKey.rawRepresentation })
        }

        func configure(_ module: IntegrationsModule, trusted: [Data] = [UpdateTests.key.publicKey.rawRepresentation]) {
            let temp = temp
            module.installer = ScriptInstaller(
                downloader: downloader, trustedKeys: trusted, temporaryDirectory: { _ in temp })
            module.updateChecker = ScriptUpdateChecker(downloader: downloader, trustedKeys: trusted)
            let clock = clock
            module.now = { clock.now }
        }

        /// A script installed from a link on this Mac: the file, its confirmation and its source record.
        func install(
            _ name: String = "ci-status.md", _ text: String = UpdateTests.v1, source: String? = UpdateTests.fileURL
        )
            async throws
        {
            try folder.write(name, text)
            try await confirmations.confirm("modules/" + name, sha256: UpdateTests.hash(text))
            if let source {
                try await confirmations.recordSource(
                    "modules/" + name,
                    ScriptSourceRecord(url: URL(string: source)!, signatureURL: nil, installedAt: .distantPast))
            }
        }

        /// Starts the module and waits for the start-up check.
        func start() async throws {
            try await module.start(context: context)
            try await waitFor { self.module.completedUpdateTicks >= 1 && !self.module.updateCheck.isRunning }
        }

        func waitFor(_ condition: @MainActor () -> Bool) async throws {
            let deadline = ContinuousClock.now + .seconds(5)
            while !condition() {
                guard ContinuousClock.now < deadline else { throw CancellationError() }
                try await Task.sleep(for: .milliseconds(5))
            }
        }

        /// Fires the 15-minute tick as the scheduler would.
        func tick() async throws {
            let job = try #require(context.fakeScheduler.liveRepeating.first)
            #expect(job.interval == ScriptUpdateChecker.tickInterval)
            await job.body()
        }

        func serve(_ text: String, signed: Bool = false, url: String = UpdateTests.fileURL) {
            downloader.set(url, .ok(Data(text.utf8)))
            downloader.set(url + ".sig", signed ? .ok(InstallTests.sign(text)) : .status(404))
        }

        func definition(_ name: String = "ci-status.md") throws -> ScriptModuleDefinition {
            try #require(module.scripts.first { $0.fileName == name })
        }

        func fileText(_ name: String = "ci-status.md") throws -> String {
            try String(contentsOf: folder.url.appendingPathComponent(name), encoding: .utf8)
        }

        func storedCandidate(_ name: String = "ci-status.md") -> String? {
            try? String(
                contentsOf: storage.appendingPathComponent("updates").appendingPathComponent(name), encoding: .utf8)
        }

        func review(_ name: String = "ci-status.md") async throws -> ScriptUpdateReview {
            await module.openUpdate(for: try definition(name))
            return try #require(module.updateReview)
        }

        func cleanUp() async {
            await module.stop()
            folder.cleanUp()
            try? FileManager.default.removeItem(at: storage)
        }
    }

    // MARK: - Cadence

    @Test func eachSourceIsFetchedAtMostOnceADayAndTheLastCheckSurvivesARelaunch() async throws {
        let setup = try Setup()
        let other = "https://scripts.example.com/b/other.md"
        try await setup.install()
        try await setup.install("other.md", InstallTests.script(id: "other.script"), source: other)
        setup.serve(Self.v1)
        setup.serve(InstallTests.script(id: "other.script"), url: other)
        try await setup.start()
        #expect(Set(setup.downloader.requested) == [Self.fileURL, other], "one fetch per source at start")

        setup.clock.advance(60 * 60)
        try await setup.tick()
        #expect(setup.downloader.requested.count == 2, "not again within the day")

        // A relaunch two hours later reads the persisted last check: no fetch.
        await setup.module.stop()
        setup.module = IntegrationsModule()
        setup.configure(setup.module)
        setup.clock.advance(60 * 60)
        try await setup.start()
        #expect(setup.downloader.requested.count == 2)
        #expect(setup.context.fakeStorage.data(ScriptUpdateState.name) != nil)

        setup.clock.advance(Self.day)
        try await setup.tick()
        #expect(setup.downloader.requested.count == 4, "both again once a day has passed")
        await setup.cleanUp()
    }

    @Test func checkForUpdatesFetchesAtOnce() async throws {
        let setup = try Setup()
        try await setup.install()
        setup.serve(Self.v1)
        try await setup.start()
        #expect(setup.downloader.requested == [Self.fileURL])
        #expect(setup.module.canCheckForUpdates)
        await setup.module.checkForUpdatesNow()
        #expect(setup.downloader.requested == [Self.fileURL, Self.fileURL])
        #expect(setup.module.updateCheck.lastChecked == 1)
        #expect(setup.module.updateCheck.lastAvailable == 0)
        await setup.cleanUp()
    }

    @Test func turnedOffMakesNoRequestAtAll() async throws {
        let setup = try Setup(settings: [IntegrationsModule.updateChecksKey: false])
        try await setup.install()
        setup.serve(Self.v2)
        try await setup.start()
        setup.clock.advance(3 * Self.day)
        try await setup.tick()
        await setup.module.checkForUpdatesNow()
        #expect(!setup.module.canCheckForUpdates)
        #expect(setup.downloader.requested.isEmpty)

        // Turning it back on checks at once.
        try await setup.context.fakeSettings.set(true, for: IntegrationsModule.updateChecksKey)
        try await setup.waitFor { setup.module.updateAvailable(for: (try? setup.definition())!) }
        #expect(setup.downloader.requested.first == Self.fileURL)
        await setup.cleanUp()
    }

    @Test func aSyncedFileFallsBackToItsFrontMatterSource() async throws {
        let setup = try Setup()
        let source = "https://scripts.example.com/ci/ci-status.md"
        let text = InstallTests.script(extra: "\nsource: \(source)")
        try await setup.install("ci-status.md", text, source: nil)
        try setup.folder.write("local.md", InstallTests.script(id: "local.only"))
        setup.serve(text)
        try await setup.start()
        #expect(setup.downloader.requested == [source], "no source, no fetch for local.md")
        await setup.cleanUp()
    }

    // MARK: - Outcomes

    @Test func identicalContentShowsNoBadge() async throws {
        let setup = try Setup()
        try await setup.install()
        setup.serve(Self.v1)
        try await setup.start()
        #expect(!setup.module.updateAvailable(for: try setup.definition()))
        #expect(setup.module.pendingUpdates.isEmpty)
        #expect(setup.storedCandidate() == nil)
        #expect(setup.downloader.requested == [Self.fileURL], "no signature fetch when nothing changed")
        await setup.cleanUp()
    }

    @Test func changedContentShowsTheBadgeEverywhereWhileTheConfirmedVersionRuns() async throws {
        let setup = try Setup()
        try await setup.install()
        setup.serve(Self.v2)
        try await setup.start()
        let definition = try setup.definition()
        #expect(setup.module.updateAvailable(for: definition))
        #expect(setup.module.pendingUpdates["modules/ci-status.md"]?.sha256 == Self.hash(Self.v2))
        #expect(setup.storedCandidate() == Self.v2)
        #expect(try setup.fileText() == Self.v1, "the installed file is untouched")
        #expect(setup.module.isEligible(definition), "the confirmed version keeps running")

        // Card, page hero and Settings › Scripts.
        let module = try #require(setup.module.scriptModules["ci-status.md"])
        #expect(module.snapshot.updateAvailable)
        #expect(ScriptSurfaces.card(module.snapshot).updateAvailable)
        #expect(module.pageModel.hero.updateAvailable)
        #expect(setup.module.paneRows().first?.updateAvailable == true)
        #expect(setup.module.updateCheck.lastAvailable == 1)
        await setup.cleanUp()
    }

    @Test func pendingCandidatesSurviveARelaunch() async throws {
        let setup = try Setup()
        try await setup.install()
        setup.serve(Self.v2)
        try await setup.start()
        await setup.module.stop()
        setup.module = IntegrationsModule()
        setup.configure(setup.module)
        try await setup.start()
        #expect(setup.module.updateAvailable(for: try setup.definition()))
        #expect(setup.downloader.requested.count == 2, "file and signature, once")
        await setup.cleanUp()
    }

    @Test func aDeclinedUpdateIsNeverOfferedAgainButANewChangeIs() async throws {
        let setup = try Setup()
        try await setup.install()
        setup.serve(Self.v2)
        try await setup.start()
        _ = try await setup.review()
        try await setup.module.declineUpdate()
        #expect(setup.module.updateReview == nil)
        #expect(setup.confirmations.declinedUpdateRecords["modules/ci-status.md"] == Self.hash(Self.v2))
        #expect(!setup.module.updateAvailable(for: try setup.definition()))
        #expect(try setup.fileText() == Self.v1)
        #expect(setup.module.isEligible(try setup.definition()), "the old version keeps running")
        #expect(setup.storedCandidate() == nil)

        setup.clock.advance(Self.day)
        try await setup.tick()
        #expect(!setup.module.updateAvailable(for: try setup.definition()), "same bytes: no badge")

        setup.serve(Self.v3)
        await setup.module.checkForUpdatesNow()
        #expect(setup.module.updateAvailable(for: try setup.definition()), "a different change shows again")
        await setup.cleanUp()
    }

    // MARK: - Review

    @Test func closeLeavesTheCandidatePending() async throws {
        let setup = try Setup()
        try await setup.install()
        setup.serve(Self.v2)
        try await setup.start()
        _ = try await setup.review()
        setup.module.closeUpdate()
        #expect(setup.module.updateReview == nil)
        #expect(setup.module.updateAvailable(for: try setup.definition()))
        #expect(setup.storedCandidate() == Self.v2)
        #expect(setup.confirmations.declinedUpdateRecords.isEmpty)
        await setup.cleanUp()
    }

    @Test func confirmReplacesTheFileConfirmsTheNewHashAndRefreshesTheSource() async throws {
        let setup = try Setup()
        try await setup.install()
        setup.serve(Self.v2, signed: true)
        try await setup.start()
        let review = try await setup.review()
        let content = setup.module.updateContent(for: review.candidate)
        #expect(content.update?.oldVersion == nil)
        #expect(content.update?.newVersion == "1.1.0")
        #expect(content.update?.diff.contains { $0.kind == .added && $0.text == "version: 1.1.0" } == true)
        #expect(content.verification == .verified)

        setup.clock.advance(60)
        try await setup.module.confirmUpdate()
        #expect(try setup.fileText() == Self.v2)
        #expect(setup.confirmations.records["modules/ci-status.md"]?.confirmedSHA256 == Self.hash(Self.v2))
        let source = try #require(setup.confirmations.sourceRecords["modules/ci-status.md"])
        #expect(source.installedAt == setup.clock.now)
        #expect(source.signatureURL?.absoluteString == Self.fileURL + ".sig")
        #expect(setup.module.updateReview == nil)
        #expect(setup.module.pendingUpdates.isEmpty)
        #expect(setup.storedCandidate() == nil)
        let definition = try setup.definition()
        #expect(definition.contentHash == Self.hash(Self.v2), "rescanned")
        #expect(setup.module.isEligible(definition), "the new version runs")
        #expect(!setup.module.updateAvailable(for: definition))
        // Nothing left in the temporary directory.
        #expect((try? FileManager.default.contentsOfDirectory(atPath: setup.temp.path))?.isEmpty == true)
        await setup.cleanUp()
    }

    @Test func aFailedConfirmKeepsTheOldFile() async throws {
        let setup = try Setup()
        try await setup.install()
        setup.serve(Self.v2)
        try await setup.start()
        _ = try await setup.review()
        setup.confirmations.failure = ModuleServiceError.notAvailable
        await #expect(throws: ScriptUpdateError.self) { try await setup.module.confirmUpdate() }
        #expect(try setup.fileText() == Self.v1, "old bytes put back")
        #expect(setup.module.updateAvailable(for: try setup.definition()), "still offered")
        setup.confirmations.failure = nil

        // The file changed on disk since the review: nothing is replaced.
        try setup.folder.write("ci-status.md", Self.v1 + "\n<!-- hand edit -->\n")
        await #expect(throws: ScriptUpdateError.changedOnDisk) { try await setup.module.confirmUpdate() }
        #expect(try setup.fileText().hasSuffix("hand edit -->\n"))
        await setup.cleanUp()
    }

    @Test func theCandidatesVerificationStateIsShown() async throws {
        let tampered = Self.v2.replacingOccurrences(of: "1.1.0", with: "6.6.6")
        let cases: [(served: String, sig: FakeDownloader.Answer, expected: ScriptConfirmationContent.Verification)] = [
            (Self.v2, .ok(InstallTests.sign(Self.v2)), .verified),
            (Self.v2, .status(404), .unsigned),
            (tampered, .ok(InstallTests.sign(Self.v2)), .badSignature),
        ]
        for item in cases {
            let setup = try Setup()
            try await setup.install()
            setup.downloader.set(Self.fileURL, .ok(Data(item.served.utf8)))
            setup.downloader.set(Self.fileURL + ".sig", item.sig)
            try await setup.start()
            let review = try await setup.review()
            let content = setup.module.updateContent(for: review.candidate)
            #expect(content.verification == item.expected)
            #expect(ScriptConfirmationView.confirmEnabled(content, privacyActive: false))
            #expect(!ScriptConfirmationView.confirmEnabled(content, privacyActive: true), "Privacy disables Confirm")
            await setup.cleanUp()
        }
    }

    // MARK: - Same-id link

    @Test func aSameIDLinkContinuesAsAnUpdateWithADiff() async throws {
        let setup = try Setup()
        try await setup.install("mine.md", Self.v1, source: nil)
        try await setup.start()
        let link = "https://other.example.com/ci-status.md"
        setup.serve(Self.v2, url: link)
        setup.module.beginInstall(ScriptInstallRequest(fileURL: URL(string: link)!))
        try await setup.waitFor { setup.module.installReview?.phase != .downloading }
        let review = try #require(setup.module.installReview)
        guard case .update(let candidate) = review.phase else {
            Issue.record("expected an update, got \(review.phase)")
            return
        }
        #expect(candidate.installed.fileName == "mine.md")
        let content = setup.module.installContent(for: review)
        #expect(content.update != nil)
        #expect(content.availability.canConfirm)
        #expect(setup.module.isEligible(try setup.definition("mine.md")), "the old version runs meanwhile")

        let url = try await setup.module.confirmInstall()
        #expect(url.lastPathComponent == "mine.md")
        #expect(try setup.fileText("mine.md") == Self.v2)
        #expect(
            ((try? FileManager.default.contentsOfDirectory(atPath: setup.folder.url.path)) ?? []) == ["mine.md"])
        #expect(setup.confirmations.sourceRecords["modules/mine.md"]?.url.absoluteString == link)
        #expect(setup.module.installReview == nil)
        await setup.cleanUp()
    }

    @Test func declineOnASameIDLinkRecordsTheDeclinedContent() async throws {
        let setup = try Setup()
        try await setup.install()
        setup.serve(Self.v1)
        try await setup.start()
        setup.serve(Self.v2)
        setup.module.beginInstall(ScriptInstallRequest(fileURL: URL(string: Self.fileURL)!))
        try await setup.waitFor { setup.module.installReview?.phase != .downloading }
        try await setup.module.declineInstall()
        #expect(setup.module.installReview == nil)
        #expect(setup.confirmations.declinedUpdateRecords["modules/ci-status.md"] == Self.hash(Self.v2))
        #expect(try setup.fileText() == Self.v1)
        await setup.cleanUp()
    }

    // MARK: - Catalog

    @Test func updateStringsResolve() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Integrations/Resources/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let strings = try #require(catalog?["strings"] as? [String: Any])
        var locales: Set<String> = []
        for case let entry as [String: Any] in strings.values {
            locales.formUnion((entry["localizations"] as? [String: Any])?.keys ?? [:].keys)
        }
        let keys = strings.keys.filter {
            $0.hasPrefix("script.update.") || $0.hasPrefix("integrations.setting.updateChecks")
                || $0.hasPrefix("script.settings.checkUpdates") || $0 == "script.settings.reviewUpdate"
                || $0 == "script.settings.updated" || $0.hasPrefix("script.install.failed.alreadyInstalled")
                || $0 == "script.install.detail.alreadyInstalled"
        }
        #expect(keys.count == 13)
        for key in keys {
            let entry = try #require(strings[key] as? [String: Any])
            #expect(Set((entry["localizations"] as? [String: Any])?.keys ?? [:].keys) == locales, "\(key)")
            #expect(IntegrationsText.string(key) != key, "\(key) resolves")
        }
        for error in [ScriptUpdateError.noFolder, .changedOnDisk, .writeFailed("disk full")] {
            #expect(!error.message.hasPrefix("script."))
        }
        let setting = try #require(IntegrationsModule.staticManifest.settings.first)
        #expect(setting.key == "update_checks")
        #expect(setting.kind == .bool(default: true))
    }
}
