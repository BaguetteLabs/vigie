import CryptoKit
import Foundation
@_spi(Host) import ModuleKit
import Testing
import VigieUI

@testable import Integrations

/// Answers by URL, records every request; no network (Story 12.9 tests).
final class FakeDownloader: ScriptDownloading, @unchecked Sendable {
    enum Answer {
        case ok(Data, finalURL: URL? = nil)
        case status(Int)
        case error(ScriptDownloadError)
    }

    private let lock = NSLock()
    private var answers: [String: Answer] = [:]
    private var log: [String] = []
    var requested: [String] { lock.withLock { log } }

    func set(_ url: String, _ answer: Answer) { lock.withLock { answers[url] = answer } }

    func download(_ url: URL, maxBytes: Int) async throws -> ScriptDownload {
        let answer = lock.withLock {
            log.append(url.absoluteString)
            return answers[url.absoluteString]
        }
        switch answer {
        case .ok(let data, let finalURL):
            if data.count > maxBytes { throw ScriptDownloadError.tooLarge(limit: maxBytes) }
            return ScriptDownload(data: data, statusCode: 200, url: finalURL ?? url)
        case .status(let code):
            return ScriptDownload(data: Data(), statusCode: code, url: url)
        case .error(let error):
            throw error
        case nil:
            return ScriptDownload(data: Data(), statusCode: 404, url: url)
        }
    }
}

/// Story 12.9: install scripts from `vigie://install` links (AD-18, SPEC §9.4, Flow 7, UX-DR98/100/106).
@MainActor @Suite struct InstallTests {
    typealias Folder = ScriptDiscoveryTests.Folder

    static let fileURL = "https://scripts.example.com/ci/ci-status.md"
    static let key = Curve25519.Signing.PrivateKey()
    static let otherKey = Curve25519.Signing.PrivateKey()

    static func script(id: String = "ci.status", extra: String = "") -> String {
        """
        ---
        schema: 2
        id: \(id)
        name: CI status
        interval: 5m
        runtime: sh
        widget: status
        author: Léa\(extra)
        ---

        Shows the CI status.

        ```sh
        echo '{"widget":{"type":"status","level":"ok"}}'
        ```
        """
    }

    static func sign(_ text: String, with key: Curve25519.Signing.PrivateKey = key) -> Data {
        Data(try! key.signature(for: Data(text.utf8)).base64EncodedString().utf8)
    }

    @MainActor struct Setup {
        let folder: Folder
        let temp: URL
        let downloader = FakeDownloader()
        let module = IntegrationsModule()
        let context: FakeModuleContext

        var confirmations: MemoryScriptConfirmations { context.fakeScriptFolder.fakeConfirmations }

        init(trusted: [Curve25519.Signing.PrivateKey] = [InstallTests.key]) throws {
            folder = try Folder()
            temp = folder.root.appendingPathComponent("tmp", isDirectory: true)
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            context = FakeModuleContext(scriptFolder: FakeScriptFolder(url: folder.url))
            let temp = temp
            module.installer = ScriptInstaller(
                downloader: downloader, trustedKeys: trusted.map { $0.publicKey.rawRepresentation },
                temporaryDirectory: { _ in temp })
        }

        func start() async throws { try await module.start(context: context) }

        func folderFiles() -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: folder.url.path)) ?? []).sorted()
        }

        /// Files left anywhere under the temporary directory.
        func tempFiles() -> [String] {
            FileManager.default.enumerator(atPath: temp.path)?.allObjects.compactMap { $0 as? String } ?? []
        }

        func install(_ link: String = InstallTests.fileURL, sig: String? = nil, intent: UserIntent? = nil) async throws
            -> ScriptInstallReview
        {
            module.beginInstall(
                ScriptInstallRequest(
                    fileURL: URL(string: link)!, signatureURL: sig.map { URL(string: $0)! }, intent: intent))
            let deadline = ContinuousClock.now + .seconds(5)
            while module.installReview?.phase == .downloading {
                guard ContinuousClock.now < deadline else { throw CancellationError() }
                try await Task.sleep(for: .milliseconds(5))
            }
            return try #require(module.installReview)
        }

        func cleanUp() async {
            await module.stop()
            folder.cleanUp()
        }
    }

    // MARK: - Fetch

    @Test func unsignedFileIsReviewableAndNothingIsWritten() async throws {
        let setup = try Setup()
        try await setup.start()
        setup.downloader.set(Self.fileURL, .ok(Data(Self.script().utf8)))
        let review = try await setup.install()
        let candidate = try #require(review.candidate)
        #expect(candidate.verification == .unsigned)
        #expect(setup.downloader.requested == [Self.fileURL, Self.fileURL + ".sig"])
        #expect(setup.folderFiles().isEmpty, "nothing in the scripts folder before Confirm")
        #expect(setup.tempFiles().count == 2, "one temporary directory with the file")

        let content = setup.module.installContent(for: review)
        #expect(content.availability == .ready)
        #expect(content.sourceURL == Self.fileURL)
        #expect(content.author == "Léa")
        #expect(content.verification == .unsigned)
        #expect(content.fileName == "ci-status.md")
        #expect(content.fileText == Self.script())
        #expect(ScriptConfirmationView.confirmEnabled(content, privacyActive: false))
        #expect(!ScriptConfirmationView.confirmEnabled(content, privacyActive: true), "UX-DR98")
        await setup.cleanUp()
    }

    @Test(arguments: [
        (FakeDownloader.Answer.status(404), ScriptInstallError.httpStatus(404)),
        (.ok(Data(count: ScriptInstaller.maxFileBytes + 1)), .tooLarge(limit: ScriptInstaller.maxFileBytes)),
        (.ok(Data("x".utf8), finalURL: URL(string: "http://scripts.example.com/ci.md")!), .insecureRedirect),
        (.error(.insecureRedirect), .insecureRedirect),
        (
            .error(.network("The Internet connection appears to be offline.")),
            .network("The Internet connection appears to be offline.")
        ),
    ])
    func downloadFailureOffersOnlyClose(_ answer: FakeDownloader.Answer, _ expected: ScriptInstallError) async throws {
        let setup = try Setup()
        try await setup.start()
        setup.downloader.set(Self.fileURL, answer)
        let review = try await setup.install()
        #expect(review.phase == .failed(expected))
        #expect(expected.isDownloadFailure)
        let content = setup.module.installContent(for: review)
        #expect(content.availability == .failed(title: "The script could not be downloaded.", detail: expected.detail))
        #expect(!ScriptConfirmationView.confirmEnabled(content, privacyActive: false), "UX-DR100: nothing to confirm")
        #expect(setup.folderFiles().isEmpty)
        #expect(setup.tempFiles().isEmpty)
        await setup.cleanUp()
    }

    @Test func otherSchemesAreRefusedWithAClearMessage() async throws {
        let setup = try Setup()
        try await setup.start()
        let review = try await setup.install("http://scripts.example.com/ci.md")
        #expect(review.phase == .failed(.notHTTPS(scheme: "http")))
        #expect(setup.downloader.requested.isEmpty, "never fetched")
        #expect(
            ScriptInstallError.notHTTPS(scheme: "http").detail
                == "Only https:// links can be installed; this one uses “http”.")
        await setup.cleanUp()
    }

    @Test func invalidFileShowsAnErrorAndWritesNothing() async throws {
        let setup = try Setup()
        try await setup.start()
        setup.downloader.set(Self.fileURL, .ok(Data(Self.script(extra: "\nversion: v1").utf8)))
        let review = try await setup.install()
        guard case .failed(.invalidFile(let message)) = review.phase else {
            Issue.record("expected an invalid file, got \(review.phase)")
            return
        }
        #expect(message.contains("version"))
        #expect(!ScriptInstallError.invalidFile(message).isDownloadFailure)
        #expect(setup.folderFiles().isEmpty)
        #expect(setup.tempFiles().isEmpty)
        await setup.cleanUp()
    }

    @Test func aScriptIDAlreadyInstalledIsRefused() async throws {
        let setup = try Setup()
        try setup.folder.write("mine.md", Self.script())
        try await setup.start()
        setup.downloader.set(Self.fileURL, .ok(Data(Self.script().utf8)))
        let review = try await setup.install()
        #expect(review.phase == .failed(.idInUse(id: "ci.status", fileName: "mine.md")))
        #expect(setup.folderFiles() == ["mine.md"])
        await setup.cleanUp()
    }

    // MARK: - Verification

    @Test func validSignatureIsVerified() async throws {
        let setup = try Setup()
        try await setup.start()
        let text = Self.script()
        setup.downloader.set(Self.fileURL, .ok(Data(text.utf8)))
        setup.downloader.set(Self.fileURL + ".sig", .ok(Self.sign(text)))
        let candidate = try #require(try await setup.install().candidate)
        #expect(candidate.verification == .verified)
        #expect(candidate.signatureURL?.absoluteString == Self.fileURL + ".sig")
        await setup.cleanUp()
    }

    @Test func linkSignatureURLAndRawBytesAreAccepted() async throws {
        let setup = try Setup()
        try await setup.start()
        let text = Self.script()
        let sig = "https://cdn.example.com/sigs/ci.sig"
        setup.downloader.set(Self.fileURL, .ok(Data(text.utf8)))
        setup.downloader.set(sig, .ok(try Self.key.signature(for: Data(text.utf8))))
        let candidate = try #require(try await setup.install(sig: sig).candidate)
        #expect(candidate.verification == .verified)
        #expect(!setup.downloader.requested.contains(Self.fileURL + ".sig"))
        await setup.cleanUp()
    }

    @Test func tamperedBytesUnknownKeyAndGarbageAreNotVerified() async throws {
        let text = Self.script()
        let tampered = text.replacingOccurrences(of: "status\",\"level\":\"ok", with: "status\",\"level\":\"warn")
        let cases: [(file: String, sig: Data, trusted: [Curve25519.Signing.PrivateKey])] = [
            (tampered, Self.sign(text), [Self.key]),
            (text, Self.sign(text, with: Self.otherKey), [Self.key]),
            (text, Data("not a signature".utf8), [Self.key]),
            (text, Self.sign(text), []),  // TrustedScriptKeys is empty until A84
        ]
        for item in cases {
            let setup = try Setup(trusted: item.trusted)
            try await setup.start()
            setup.downloader.set(Self.fileURL, .ok(Data(item.file.utf8)))
            setup.downloader.set(Self.fileURL + ".sig", .ok(item.sig))
            let review = try await setup.install()
            #expect(review.candidate?.verification == .badSignature)
            #expect(setup.module.installContent(for: review).verification == .badSignature)
            await setup.cleanUp()
        }
    }

    @Test func aSourceOnAnotherSiteIsNotVerified() async throws {
        let setup = try Setup()
        try await setup.start()
        let text = Self.script(extra: "\nsource: https://elsewhere.example.org/ci-status.md")
        setup.downloader.set(Self.fileURL, .ok(Data(text.utf8)))
        setup.downloader.set(Self.fileURL + ".sig", .ok(Self.sign(text)))
        #expect(try await setup.install().candidate?.verification == .otherSite)

        // Same host: verified.
        let same = Self.script(extra: "\nsource: https://SCRIPTS.example.com/ci")
        setup.downloader.set(Self.fileURL, .ok(Data(same.utf8)))
        setup.downloader.set(Self.fileURL + ".sig", .ok(Self.sign(same)))
        #expect(try await setup.install().candidate?.verification == .verified)
        await setup.cleanUp()
    }

    @Test func signatureFormats() {
        let text = Data("x".utf8)
        let raw = try! Self.key.signature(for: text)
        #expect(ScriptSignature.decode(raw) == raw)
        #expect(ScriptSignature.decode(Data((raw.base64EncodedString() + "\n").utf8)) == raw)
        #expect(ScriptSignature.decode(Data("abc".utf8)) == nil)
        #expect(ScriptSignature.verify(file: text, signature: nil, trustedKeys: []) == .unsigned)
        #expect(TrustedScriptKeys.base64.isEmpty, "TODO(A84): no key until the Script repository exists")
        let publicKey = Self.key.publicKey.rawRepresentation
        #expect(ScriptSignature.publicKey(publicKey.base64EncodedString()) == publicKey)
        #expect(ScriptSignature.publicKey("short") == nil)
    }

    @Test func fileNamesAreSanitised() {
        func name(_ url: String) -> String { ScriptInstaller.fileName(from: URL(string: url)!) }
        #expect(name("https://a.com/x/ci-status.md") == "ci-status.md")
        #expect(name("https://a.com/x/CI%20Status.MD?raw=1") == "CI-Status.md")
        #expect(name("https://a.com/x/.hidden.md") == "hidden.md")
        #expect(name("https://a.com/x/script") == "script.md")
        #expect(name("https://a.com/") == "script.md")
        #expect(name("https://a.com/x/%C3%A9t%C3%A9.md") == "t-.md")
        #expect(
            ScriptInstaller.defaultSignatureURL(for: URL(string: "https://a.com/x.md?ref=1")!)?.absoluteString
                == "https://a.com/x.md.sig?ref=1")
    }

    // MARK: - Confirm, decline, close

    @Test func confirmWritesOnceRecordsSourceAndHashAndTheScriptRuns() async throws {
        let setup = try Setup()
        try await setup.start()
        let text = Self.script()
        setup.downloader.set(Self.fileURL, .ok(Data(text.utf8)))
        setup.downloader.set(Self.fileURL + ".sig", .ok(Self.sign(text)))
        let candidate = try #require(try await setup.install().candidate)

        let target = try await setup.module.confirmInstall()
        #expect(target.lastPathComponent == "ci-status.md")
        #expect(setup.folderFiles() == ["ci-status.md"])
        #expect(try Data(contentsOf: target) == Data(text.utf8), "the exact reviewed bytes")
        #expect(setup.confirmations.writes == [.confirm("modules/ci-status.md", candidate.contentHash)])
        let source = try #require(setup.confirmations.sourceRecords["modules/ci-status.md"])
        #expect(source.url.absoluteString == Self.fileURL)
        #expect(source.signatureURL?.absoluteString == Self.fileURL + ".sig")
        #expect(setup.module.installReview == nil)
        #expect(setup.tempFiles().isEmpty, "temporary directory removed")
        let installed = try #require(setup.module.scripts.first { $0.fileName == "ci-status.md" })
        #expect(setup.module.localState(for: installed) == .confirmed)
        #expect(setup.module.isEligible(installed), "it starts running")
        await setup.cleanUp()
    }

    @Test func confirmNeverOverwritesAnExistingFile() async throws {
        let setup = try Setup()
        try setup.folder.write("ci-status.md", ScriptDiscoveryTests.script(id: "other.script"))
        try await setup.start()
        setup.downloader.set(Self.fileURL, .ok(Data(Self.script().utf8)))
        _ = try await setup.install()
        let target = try await setup.module.confirmInstall()
        #expect(target.lastPathComponent == "ci-status-2.md")
        #expect(setup.folderFiles() == ["ci-status-2.md", "ci-status.md"])
        #expect(setup.confirmations.sourceRecords.keys.sorted() == ["modules/ci-status-2.md"])
        await setup.cleanUp()
    }

    @Test func declineOrCloseLeavesNothingBehind() async throws {
        let setup = try Setup()
        try await setup.start()
        setup.downloader.set(Self.fileURL, .ok(Data(Self.script().utf8)))
        _ = try await setup.install()
        #expect(!setup.tempFiles().isEmpty)
        await setup.module.cancelInstall()
        #expect(setup.module.installReview == nil)
        #expect(setup.folderFiles().isEmpty)
        #expect(setup.tempFiles().isEmpty)
        #expect(setup.confirmations.writes.isEmpty, "a declined link records nothing")

        // A newer link replaces an open review and removes its temporary file; stopping the module cleans up too.
        _ = try await setup.install()
        _ = try await setup.install()
        #expect(setup.tempFiles().count == 2)
        await setup.module.stop()
        #expect(setup.tempFiles().isEmpty)
        setup.folder.cleanUp()
    }

    @Test func aFailedRecordRemovesTheFile() async throws {
        let setup = try Setup()
        try await setup.start()
        setup.downloader.set(Self.fileURL, .ok(Data(Self.script().utf8)))
        _ = try await setup.install()
        setup.confirmations.failure = ModuleServiceError.notAvailable
        await #expect(throws: ScriptInstallError.self) { try await setup.module.confirmInstall() }
        #expect(setup.folderFiles().isEmpty)
        #expect(setup.tempFiles().isEmpty)
        guard case .failed(.writeFailed) = setup.module.installReview?.phase else {
            Issue.record("the sheet shows the failure")
            return
        }
        await setup.cleanUp()
    }

    /// PRD FR-39: confirmations and sources stay on this Mac; another Mac that receives the file by sync (same
    /// folder, its own empty `local.toml`) shows it awaiting confirmation.
    @Test func anotherMacReceivingTheFileStaysAwaitingConfirmation() async throws {
        let setup = try Setup()
        try await setup.start()
        setup.downloader.set(Self.fileURL, .ok(Data(Self.script().utf8)))
        _ = try await setup.install()
        try await setup.module.confirmInstall()

        let otherMac = FakeModuleContext(scriptFolder: FakeScriptFolder(url: setup.folder.url))
        let module = IntegrationsModule()
        try await module.start(context: otherMac)
        let synced = try #require(module.scripts.first { $0.fileName == "ci-status.md" })
        #expect(module.localState(for: synced) == .awaitingConfirmation)
        #expect(!module.isEligible(synced))
        #expect(otherMac.fakeScriptFolder.fakeConfirmations.source(for: "modules/ci-status.md") == nil)
        await module.stop()
        await setup.cleanUp()
    }

    // MARK: - Delivery

    @Test func aLinkReceivedBeforeStartIsDeliveredAfterStartAndOpensSettings() async throws {
        let setup = try Setup()
        setup.downloader.set(Self.fileURL, .ok(Data(Self.script().utf8)))
        let intent = UserIntent()
        setup.context.fakeScriptFolder.submitInstall(
            ScriptInstallRequest(fileURL: URL(string: Self.fileURL)!, intent: intent))
        try await setup.start()
        let deadline = ContinuousClock.now + .seconds(5)
        while setup.module.installReview?.candidate == nil {
            guard ContinuousClock.now < deadline else { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(setup.context.fakeHost.openedOwnSettings == [intent], "Settings › Scripts comes forward")
        await setup.cleanUp()
    }

    // MARK: - First run, copy

    /// Flow 7 / UX-DR106: the first run of a status script shows `CHECKED JUST NOW` on its widget.
    @Test func firstRunReadsCheckedJustNow() throws {
        let frontMatter = try ScriptFrontMatter.decode(
            yaml: "id: ci.status\nname: CI\ninterval: 5m\nruntime: sh\nwidget: status\n")
        let output = ScriptOutput(widget: ScriptWidget(type: .status, level: .ok))
        let now = Date()
        let card = ScriptSurfaces.card(
            ScriptSurfaceSnapshot(
                frontMatter: frontMatter, local: .confirmed, run: ScriptRunState(phase: .ok(output, at: now))))
        #expect(card.meta?.text(now: now.addingTimeInterval(5)) == "CHECKED JUST NOW")
    }

    @Test func installStringsResolveInEveryLocale() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Integrations/Resources/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let strings = try #require(catalog?["strings"] as? [String: Any])
        var locales: Set<String> = []
        for case let entry as [String: Any] in strings.values {
            locales.formUnion((entry["localizations"] as? [String: Any])?.keys ?? [:].keys)
        }
        let keys = strings.keys.filter { $0.hasPrefix("script.install.") }
        #expect(keys.count == 11)
        for key in keys {
            let entry = try #require(strings[key] as? [String: Any])
            #expect(Set((entry["localizations"] as? [String: Any])?.keys ?? [:].keys) == locales, "\(key)")
            #expect(IntegrationsText.string(key) != key, "\(key) resolves")
        }
        for error in [
            ScriptInstallError.notHTTPS(scheme: "ftp"), .insecureRedirect, .tooLarge(limit: 262_144),
            .httpStatus(500), .idInUse(id: "a.b", fileName: "a.md"), .noFolder, .writeFailed("disk full"),
        ] {
            #expect(!error.title.hasPrefix("script."))
            #expect(!(error.detail ?? "").hasPrefix("script."))
        }
        for key in ["script.error.requires_schema", "script.format.httpsURL", "script.format.version"] {
            #expect(IntegrationsText.string(key) != key)
        }
    }
}
