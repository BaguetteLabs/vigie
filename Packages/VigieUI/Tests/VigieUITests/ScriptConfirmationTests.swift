import AppKit
import Foundation
import SwiftUI
import Testing

@testable import VigieUI

/// Story 12.3: the Script Confirmation (UX-DR87, SPEC §9.2) and the `NOT CONFIRMED` state label.
@MainActor @Suite struct ScriptConfirmationTests {
    static let content = ScriptConfirmationContent(
        fileName: "github.md", path: "/tmp/config/modules/github.md",
        documentation: "# GitHub PRs\n\nCounts **open** PRs.\nNeeds a `token`.\n\n## Setup ##\nSet the repo.",
        frontMatter: "id: github.prs\nruntime: python3", code: "print(1)", language: "python",
        fileText: "---\nid: github.prs\n---\n")

    @Test func documentationSplitsIntoHeadingsAndParagraphs() {
        #expect(
            ScriptDocumentationBlock.parse(Self.content.documentation) == [
                .heading(level: 1, text: "GitHub PRs"),
                .paragraph("Counts **open** PRs.\nNeeds a `token`."),
                .heading(level: 2, text: "Setup"),
                .paragraph("Set the repo."),
            ])
        #expect(ScriptDocumentationBlock.parse("  \n\n").isEmpty)
        // `#tag` is not a heading.
        #expect(ScriptDocumentationBlock.parse("#tag") == [.paragraph("#tag")])
        let attributed = ScriptDocumentationBlock.attributed("Counts **open** PRs.\nNext line")
        #expect(String(attributed.characters) == "Counts open PRs.\nNext line")
    }

    @Test func copyIsTheSpecWordingAndEveryKeyResolves() {
        #expect(
            ScriptConfirmationCopy.warning
                == "Scripts run as the user, with no sandbox. Only install scripts you trust.")
        #expect(ScriptStateLabel.notConfirmedText == "NOT CONFIRMED")
        #expect(ScriptConfirmationCopy.codeHeading(language: "python") == "Code · python")
        #expect(ScriptConfirmationCopy.codeHeading(language: nil) == "Code")
        for key in ScriptConfirmationCopy.keys {
            #expect(L10n.string(key) != key, "\(key) does not resolve")
        }
    }

    @Test func everyShippedLocaleHasTheConfirmationStrings() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/VigieUI/Resources/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let strings = try #require(catalog?["strings"] as? [String: Any])
        var locales: Set<String> = []
        for case let entry as [String: Any] in strings.values {
            locales.formUnion((entry["localizations"] as? [String: Any])?.keys ?? [:].keys)
        }
        #expect(locales.contains("en"))
        for key in ScriptConfirmationCopy.keys {
            let entry = try #require(strings[key] as? [String: Any], "\(key) missing")
            let localized = Set((entry["localizations"] as? [String: Any])?.keys ?? [:].keys)
            #expect(localized == locales, "\(key) is missing a locale")
        }
    }

    static func install(_ verification: ScriptConfirmationContent.Verification, author: String? = "Léa")
        -> ScriptConfirmationContent
    {
        var content = Self.content
        content.sourceURL = "https://example.com/ci.md"
        content.author = author
        content.verification = verification
        return content
    }

    /// Story 12.9 copy: SPEC §9.4 wording for the verified line and "claimed by the file" when not verified.
    @Test func linkInstallCopy() {
        #expect(ScriptConfirmationCopy.verification(.verified) == "Verified: Vigie Script repository")
        for state in [ScriptConfirmationContent.Verification.unsigned, .badSignature, .otherSite] {
            #expect(ScriptConfirmationCopy.verification(state).hasPrefix("Not verified: "))
        }
        #expect(ScriptConfirmationCopy.author("Léa", verified: true) == "Author: Léa")
        #expect(ScriptConfirmationCopy.author("Léa", verified: false) == "Author: Léa (claimed by the file)")
        #expect(ScriptConfirmationCopy.author(nil, verified: false) == "Author: not given")
        #expect(ScriptConfirmationCopy.source("https://a.com/x.md") == "Source: https://a.com/x.md")
        #expect(ScriptConfirmationCopy.close == "Close")
    }

    /// Privacy mode disables Confirm (UX-DR98); a failed download has nothing to confirm (UX-DR100).
    @Test func confirmNeedsAFileAndPrivacyOff() {
        let ready = Self.install(.verified)
        #expect(ScriptConfirmationView.confirmEnabled(ready, privacyActive: false))
        #expect(!ScriptConfirmationView.confirmEnabled(ready, privacyActive: true))
        let failed = ScriptConfirmationContent.unavailable(
            sourceURL: "https://a.com/x.md", availability: .failed(title: "Could not be downloaded", detail: "404"))
        #expect(!ScriptConfirmationView.confirmEnabled(failed, privacyActive: false))
        let downloading = ScriptConfirmationContent.unavailable(
            sourceURL: "https://a.com/x.md", availability: .downloading)
        #expect(!ScriptConfirmationView.confirmEnabled(downloading, privacyActive: false))
    }

    @Test func linkInstallStatesRenderInBothPrivacyStates() throws {
        let contents: [ScriptConfirmationContent] = [
            Self.install(.verified), Self.install(.unsigned, author: nil), Self.install(.badSignature),
            Self.install(.otherSite),
            .unavailable(sourceURL: "https://a.com/x.md", availability: .downloading),
            .unavailable(
                sourceURL: "https://a.com/x.md", availability: .failed(title: "Could not be downloaded", detail: "404")),
        ]
        for content in contents {
            for privacy in [false, true] {
                let view = ScriptConfirmationView(content: content, onConfirm: {}, onDecline: {}, onCancel: {})
                    .privacyActive(privacy)
                    .frame(width: 640, height: 640)
                #expect(ImageRenderer(content: view).cgImage != nil)
            }
        }
    }

    /// UX-DR98: in Privacy mode the author and source URL are masked like the body; the verification line stays.
    @Test func privacyMasksAuthorAndSource() {
        func strings(_ privacy: Bool) -> String {
            let view = ScriptConfirmationView(
                content: Self.install(.unsigned), onConfirm: {}, onDecline: {}, onCancel: {}
            )
            .privacyActive(privacy)
            return PrivacyTests.accessibilityStrings(view, size: CGSize(width: 640, height: 640)).joined(separator: "|")
        }
        let open = strings(false)
        #expect(open.contains("Léa (claimed by the file)"))
        #expect(open.contains("https://example.com/ci.md"))
        let masked = strings(true)
        #expect(!masked.contains("Léa"))
        #expect(!masked.contains("example.com"))
        #expect(masked.contains("Not verified: this file is not signed."))
    }

    @Test func viewsRenderInBothPrivacyStates() throws {
        for privacy in [false, true] {
            let view = ScriptConfirmationView(content: Self.content, onConfirm: {}, onDecline: {}, onCancel: {})
                .privacyActive(privacy)
                .frame(width: 640, height: 640)
            let renderer = ImageRenderer(content: view)
            #expect(renderer.cgImage != nil)
        }
        let label = ImageRenderer(content: ScriptStateLabel {}.vigieTheme(PreviewThemes.theme(.dark)))
        #expect(label.cgImage != nil)
    }
}
