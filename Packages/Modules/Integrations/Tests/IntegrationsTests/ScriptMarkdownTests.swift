import Foundation
import Testing

@testable import Integrations

/// Story 12.2: a script file splits into front matter, exactly one fenced code block and documentation.
@Suite struct ScriptMarkdownTests {
    static let frontMatter = """
        ---
        id: github.prs
        name: GitHub PRs
        interval: 5m
        runtime: python3
        widget: number
        ---
        """

    static func parse(_ text: String) -> ScriptMarkdown { ScriptMarkdown.parse(Data(text.utf8)) }

    @Test func oneBlockKeepsCodeLanguageAndDocumentation() throws {
        let parsed = Self.parse(
            Self.frontMatter + """

                Counts open PRs.

                ```python title="main"
                import os
                    print(1)
                ```

                Needs a token.
                """)
        #expect(parsed.error == nil)
        #expect(parsed.frontMatter?.id == "github.prs")
        #expect(parsed.code == "import os\n    print(1)")
        #expect(parsed.language == "python")
        #expect(parsed.documentation == "Counts open PRs.\n\n\nNeeds a token.")
    }

    @Test func tildeFenceWithoutLanguage() {
        let parsed = Self.parse(Self.frontMatter + "\n~~~\necho hi\n~~~\n")
        #expect(parsed.error == nil)
        #expect(parsed.code == "echo hi")
        #expect(parsed.language == nil)
        #expect(parsed.documentation.isEmpty)
    }

    @Test func longerFenceHoldsShorterOnesAndIndentIsStripped() {
        let parsed = Self.parse(Self.frontMatter + "\n  ````sh\n  ```\n  inner\n  ```\n  ````\n")
        #expect(parsed.error == nil)
        #expect(parsed.code == "```\ninner\n```")
        #expect(parsed.language == "sh")
    }

    @Test func zeroBlocksIsAnError() {
        let parsed = Self.parse(Self.frontMatter + "\nOnly words.\n\n    indented code is documentation\n")
        #expect(parsed.error == .noCodeBlock)
        #expect(parsed.frontMatter != nil)
        #expect(parsed.code == nil)
        #expect(parsed.documentation.hasPrefix("Only words."))
    }

    @Test func twoBlocksIsAnError() {
        let parsed = Self.parse(Self.frontMatter + "\n```sh\na\n```\n\n```sh\nb\n```\n")
        #expect(parsed.error == .severalCodeBlocks(count: 2))
        #expect(parsed.code == nil)
        #expect(parsed.frontMatter?.id == "github.prs")
    }

    @Test func unclosedFenceIsAnError() {
        // Front matter is lines 1-7, a blank line 8, the fence line 9.
        let parsed = Self.parse(Self.frontMatter + "\n\n```sh\necho\n")
        #expect(parsed.error == .codeBlockUnclosed(line: 9))
    }

    @Test func frontMatterMustOpenAndClose() {
        #expect(Self.parse("# Title\n```sh\na\n```\n").error == .frontMatterMissing)
        #expect(Self.parse("---\nid: a\n```sh\na\n```\n").error == .frontMatterUnclosed)
        #expect(ScriptMarkdown.parse(Data([0xFF, 0xFE, 0x00])).error == .notText)
    }

    @Test func invalidYAMLNamesTheFileLine() {
        let parsed = Self.parse("---\nid: a\nname: [unclosed\n---\n```sh\na\n```\n")
        guard case .invalidYAML(let line?) = parsed.error else {
            Issue.record(
                "expected a YAML error with a line: \(String(describing: parsed.error))"
            )
            return
        }
        #expect(line >= 3)
        #expect(parsed.error?.message.contains("not valid YAML") == true)
    }

    @Test func emptyFrontMatterIsAnError() {
        let parsed = Self.parse("---\n---\n```sh\na\n```\n")
        #expect(
            parsed.error == .schema(ScriptSchemaError(path: "", reason: .wrongType(expected: .object))),
            "\(String(describing: parsed.error))")
        #expect(parsed.frontMatter == nil)
    }

    @Test func schemaErrorKeepsItsKeyPath() {
        let parsed = Self.parse(
            "---\nid: a.b\nname: A\ninterval: 5m\nruntime: sh\nwidget: chart\n---\n```sh\na\n```\n")
        guard case .schema(let error) = parsed.error else {
            Issue.record("expected a schema error")
            return
        }
        #expect(error.path == "widget")
        #expect(parsed.error?.keyPath == "widget")
        #expect(parsed.error?.message(fileName: "a.md").hasPrefix("a.md: widget: ") == true)
    }

    /// AD-18: host-owned keys are rejected by the 12.1 schema at `settings[n].key` and surface as this error.
    @Test(arguments: ["enabled", "side", "priority", "surfaces", "notify"])
    func hostOwnedSettingKeyErrorsTheFile(_ key: String) {
        let parsed = Self.parse(
            Self.frontMatter.replacingOccurrences(
                of: "widget: number\n", with: "widget: number\nsettings:\n  - { key: \(key), type: int, label: X }\n")
                + "\n```sh\na\n```\n")
        #expect(parsed.error == .schema(ScriptSchemaError(path: "settings[0].key", reason: .reservedKey(key))))
        #expect(parsed.error?.keyPath == "settings[0].key")
    }

    @Test func crlfAndByteOrderMarkAreAccepted() {
        let text =
            "\u{FEFF}" + (Self.frontMatter + "\n```sh\necho\n```\nDoc\n").replacingOccurrences(of: "\n", with: "\r\n")
        let parsed = Self.parse(text)
        #expect(parsed.error == nil)
        #expect(parsed.code == "echo")
        #expect(parsed.documentation == "Doc")
    }
}
