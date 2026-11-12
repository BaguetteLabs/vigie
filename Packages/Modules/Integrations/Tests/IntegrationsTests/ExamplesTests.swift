import Foundation
import Testing

@testable import Integrations

/// Story 12.7 (A85, FR-41): the bundled example scripts parse, run (the dependency-free one) and can be added.
/// The schema validation of the same files is `Scripts/check-example-scripts.sh`.
@Suite struct ExamplesTests {
    @Test func theThreeBundledExamplesParseCleanly() throws {
        let examples = IntegrationsModule.bundledExamples
        #expect(examples.map(\.fileName) == ["github-prs.md", "site-status.md", "uptime.md"])
        for example in examples {
            let parsed = ScriptMarkdown.parse(try Data(contentsOf: example.url))
            #expect(parsed.error == nil, "\(example.fileName): \(String(describing: parsed.error))")
            #expect(parsed.frontMatter != nil)
            #expect(parsed.code?.isEmpty == false)
            #expect(parsed.language == "sh")
            #expect(parsed.frontMatter?.runtime == "sh")
            #expect(parsed.documentation.isEmpty == false)
            #expect(parsed.documentation.contains("unsandboxed"))
            #expect(parsed.documentation.contains("only install scripts you trust"))
            #expect(example.definition.status == .ok)
        }
        let byID = Dictionary(uniqueKeysWithValues: examples.map { ($0.definition.moduleID ?? "", $0) })
        #expect(byID["github.prs"]?.definition.frontMatter?.widget == .number)
        #expect(byID["site.status"]?.definition.frontMatter?.widget == .status)
        #expect(byID["system.uptime"]?.definition.frontMatter?.widget == .text)
    }

    @Test func settingsAndSecretsAreDeclared() throws {
        let examples = IntegrationsModule.bundledExamples
        let github = try #require(examples.first { $0.fileName == "github-prs.md" }?.definition.frontMatter)
        #expect(github.settings.map(\.key) == ["repo", "token"])
        #expect(github.settings.last?.kind == .secret)
        let site = try #require(examples.first { $0.fileName == "site-status.md" }?.definition.frontMatter)
        #expect(site.settings.map(\.key) == ["url"])
    }

    /// Runs the uptime example for real through the runner's launcher: no network, no settings.
    @Test func uptimeExampleRunsAndPrintsValidOutput() async throws {
        let example = try #require(IntegrationsModule.bundledExamples.first { $0.fileName == "uptime.md" })
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("vigie-examples-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = scratch.appendingPathComponent("uptime.sh")
        try Data(try #require(example.definition.code).utf8).write(to: file)

        let result = try await ScriptProcessLauncher().launch(
            ScriptLaunchRequest(
                executable: URL(fileURLWithPath: "/bin/sh"), arguments: [file.path],
                environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": scratch.path, "LANG": "en_US.UTF-8"],
                workingDirectory: scratch, timeout: .seconds(10), scratchDirectory: scratch))
        #expect(result.termination == .exited(0))
        let output = try ScriptOutput.decode(json: result.stdout)
        #expect(output.widget.type == .text)
        #expect(output.widget.label == "UPTIME")
        let value = try #require(output.widget.value)
        #expect(value.range(of: #"^(\d+d \d+h|\d+h \d+m|\d+m)$"#, options: .regularExpression) != nil)
    }

    // MARK: Add example

    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vigie-examples-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @MainActor @Test func addingWritesTheFileOnceAndASecondAddIsRefused() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let modules = root.appendingPathComponent("modules", isDirectory: true)
        let context = FakeModuleContext(scriptFolder: FakeScriptFolder(url: modules))
        let module = IntegrationsModule()
        try await module.start(context: context)
        defer { Task { await module.stop() } }
        let example = try #require(IntegrationsModule.bundledExamples.first { $0.fileName == "uptime.md" })

        let url = try await module.addExample(example)
        #expect(url == modules.appendingPathComponent("uptime.md"))
        #expect(try Data(contentsOf: url) == Data(contentsOf: example.url))
        let added = try #require(module.scripts.first { $0.fileName == "uptime.md" })
        #expect(module.localState(for: added) == .awaitingConfirmation)

        // Edited by the user in between: a second add must not touch it.
        try Data("mine".utf8).write(to: url)
        await #expect(throws: ExampleAddError.exists(fileName: "uptime.md")) {
            try await module.addExample(example)
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == "mine")
    }

    @MainActor @Test func addingWithoutAFolderIsRefused() async throws {
        let module = IntegrationsModule()
        try await module.start(context: FakeModuleContext())
        defer { Task { await module.stop() } }
        let example = try #require(IntegrationsModule.bundledExamples.first)
        await #expect(throws: ExampleAddError.noFolder) { try await module.addExample(example) }
    }
}
