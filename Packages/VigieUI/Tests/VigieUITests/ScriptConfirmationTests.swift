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
