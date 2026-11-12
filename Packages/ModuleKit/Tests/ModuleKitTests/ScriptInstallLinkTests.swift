import Foundation
import Testing

@testable import ModuleKit

/// Story 12.9: `vigie://install?url=<URL>[&sig=<URL>]` parsing (AD-18, AD-20; `vigie-dev` in dev builds, AD-17).
@Suite struct ScriptInstallLinkTests {
    static func parse(_ link: String, scheme: String = "vigie") -> Result<
        ScriptInstallRequest, ScriptInstallRequest.LinkProblem
    > {
        ScriptInstallRequest.parse(link: URL(string: link)!, scheme: scheme)
    }

    @Test func goodLinkWithAndWithoutSignature() throws {
        let file = "https%3A%2F%2Fexample.com%2Fscripts%2Fci.md%3Fref%3Dmain"
        let plain = try Self.parse("vigie://install?url=\(file)").get()
        #expect(plain.fileURL.absoluteString == "https://example.com/scripts/ci.md?ref=main")
        #expect(plain.signatureURL == nil)
        let signed = try Self.parse("vigie://install?url=\(file)&sig=https://cdn.example.com/ci.md.sig").get()
        #expect(signed.signatureURL?.absoluteString == "https://cdn.example.com/ci.md.sig")
        // Also without `//`, with a trailing slash, and any letter case of the scheme and action.
        #expect((try? Self.parse("vigie:install?url=https://a.com/x.md").get()) != nil)
        #expect((try? Self.parse("VIGIE://Install/?url=https://a.com/x.md").get()) != nil)
    }

    @Test func devSchemeIsItsOwn() throws {
        let link = "vigie-dev://install?url=https://a.com/x.md"
        #expect((try? Self.parse(link, scheme: "vigie-dev").get()) != nil)
        #expect(Self.parse(link, scheme: "vigie") == .failure(.otherScheme("vigie-dev")))
        #expect(
            Self.parse("vigie://install?url=https://a.com/x.md", scheme: "vigie-dev") == .failure(.otherScheme("vigie"))
        )
    }

    @Test func missingOrUnreadableURL() {
        #expect(Self.parse("vigie://install") == .failure(.missingFileURL))
        #expect(Self.parse("vigie://install?url=") == .failure(.missingFileURL))
        #expect(Self.parse("vigie://install?sig=https://a.com/x.sig") == .failure(.missingFileURL))
        #expect(Self.parse("vigie://install?url=just-a-name") == .failure(.unreadableFileURL("just-a-name")))
    }

    @Test func wrongHostOrPath() {
        #expect(Self.parse("vigie://open?url=https://a.com/x.md") == .failure(.unknownAction("open")))
        #expect(Self.parse("vigie://install/more?url=https://a.com/x.md") == .failure(.unknownAction("install/more")))
        #expect(Self.parse("vigie://?url=https://a.com/x.md") == .failure(.unknownAction("")))
    }

    /// An `http` file URL still parses: the module refuses it with a visible message (AC: "refused with a clear
    /// message"), so it must reach the module.
    @Test func otherFileSchemesReachTheModule() throws {
        let request = try Self.parse("vigie://install?url=http://a.com/x.md&sig=nope").get()
        #expect(request.fileURL.scheme == "http")
        #expect(request.signatureURL == nil, "a sig that is not a URL is dropped")
    }

    @MainActor @Test func defaultsDoNothing() async {
        var count = 0
        for await _ in NoScriptFolder().installRequests() { count += 1 }
        #expect(count == 0)
        #expect(NoScriptConfirmations().source(for: "modules/a.md") == nil)
        await #expect(throws: ModuleServiceError.notAvailable) {
            try await NoScriptConfirmations().recordSource(
                "modules/a.md",
                ScriptSourceRecord(url: URL(string: "https://a.com")!, signatureURL: nil, installedAt: .now))
        }
    }
}
