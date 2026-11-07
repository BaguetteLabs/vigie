import AgentKit
import CryptoKit
import Foundation
import Testing

@testable import ClaudeAdapter

@Suite struct IntegrationPlanTests {
    static let home = URL(fileURLWithPath: "/Users/romain", isDirectory: true)
    static let settingsPath = "/Users/romain/.claude/settings.json"
    static let inputs = IntegrationInputs(cliPath: "/Users/romain/.local/bin/vigie", homeDirectory: home)
    static let command = "/Users/romain/.local/bin/vigie hook claude"

    static func adapter(_ files: [String: String]) -> ClaudeAdapter {
        ClaudeAdapter(fileReader: MemoryFiles(files: files))
    }

    static func hooks(in text: String) throws -> OrderedJSON {
        try #require(try OrderedJSON.parse(text)["hooks"])
    }

    static func commands(_ hooks: OrderedJSON, event: String) -> [String] {
        guard case .array(let groups) = hooks[event] else { return [] }
        return groups.flatMap { group -> [String] in
            guard case .array(let entries) = group["hooks"] else { return [] }
            return entries.compactMap { $0["command"]?.stringValue }
        }
    }

    static let fullyInstalled = """
        {
          "hooks": {
            "SessionStart": [{ "hooks": [{ "type": "command", "command": "\(command)" }] }],
            "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "\(command)" }] }],
            "PreToolUse": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "\(command)" }] }],
            "PostToolUse": [{ "hooks": [{ "type": "command", "command": "\(command)" }] }],
            "Notification": [{ "hooks": [{ "type": "command", "command": "\(command)" }] }],
            "Stop": [{ "hooks": [{ "type": "command", "command": "\(command)" }] }],
            "SubagentStop": [{ "hooks": [{ "type": "command", "command": "\(command)" }] }],
            "SessionEnd": [{ "hooks": [{ "type": "command", "command": "\(command)" }] }]
          }
        }
        """

    @Test func missingFileGetsAllEightHooks() async throws {
        let plan = try await Self.adapter([:]).integrationPlan(context: makeContext(), inputs: Self.inputs)
        let diff = try #require(plan.first)
        #expect(plan.count == 1)
        #expect(diff.path.path == Self.settingsPath)
        #expect(diff.baseHash == nil)
        #expect(diff.oldText == "")
        #expect(diff.summary.contains("8") && diff.summary.contains("settings.json"))
        #expect(diff.newText.hasSuffix("}\n"))
        let hooks = try Self.hooks(in: diff.newText)
        for event in ClaudeAdapter.hookEvents {
            #expect(Self.commands(hooks, event: event) == [Self.command])
        }
        // SPEC §8.3 shape, 2-space indentation, events in SPEC order.
        #expect(
            diff.newText.hasPrefix(
                """
                {
                  "hooks": {
                    "SessionStart": [
                      {
                        "hooks": [
                          {
                            "type": "command",
                            "command": "/Users/romain/.local/bin/vigie hook claude"
                """))
        guard case .object(let members) = hooks else { return }
        #expect(members.map(\.key) == ClaudeAdapter.hookEvents)
    }

    @Test func emptyFileHasBaseHash() async throws {
        let plan = try await Self.adapter([Self.settingsPath: ""]).integrationPlan(
            context: makeContext(), inputs: Self.inputs)
        let expected = SHA256.hash(data: Data()).map { String(format: "%02x", $0) }.joined()
        #expect(plan.first?.baseHash == expected)
    }

    @Test func existingHooksAndKeysArePreserved() async throws {
        let old = """
            {
              "model": "opus",
              "permissions": {
                "allow": [
                  "Bash(ls:*)"
                ],
                "deny": []
              },
              "hooks": {
                "PreToolUse": [
                  {
                    "matcher": "Bash",
                    "hooks": [
                      {
                        "type": "command",
                        "command": "~/bin/guard.sh",
                        "timeout": 5
                      }
                    ]
                  }
                ],
                "PreCompact": [
                  {
                    "hooks": [
                      {
                        "type": "command",
                        "command": "echo compact"
                      }
                    ]
                  }
                ]
              },
              "statusLine": {
                "type": "command",
                "command": "peon \\"ok\\" é"
              }
            }

            """
        let plan = try await Self.adapter([Self.settingsPath: old]).integrationPlan(
            context: makeContext(), inputs: Self.inputs)
        let diff = try #require(plan.first)
        let expected = SHA256.hash(data: Data(old.utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(diff.baseHash == expected)
        #expect(diff.oldText == old)
        // A file in Claude Code's own format (2-space JSON) keeps every original line, in order: only additions.
        let newLines = diff.newText.split(separator: "\n", omittingEmptySubsequences: false)
        var cursor = newLines.startIndex
        for line in old.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let found = newLines[cursor...].firstIndex(of: line) else {
                Issue.record("missing line: \(line)")
                return
            }
            cursor = found + 1
        }
        let root = try OrderedJSON.parse(diff.newText)
        guard case .object(let members) = root else { return }
        #expect(members.map(\.key) == ["model", "permissions", "hooks", "statusLine"])
        let hooks = try Self.hooks(in: diff.newText)
        #expect(Self.commands(hooks, event: "PreToolUse") == ["~/bin/guard.sh", Self.command])
        #expect(Self.commands(hooks, event: "PreCompact") == ["echo compact"])
        guard case .object(let events) = hooks else { return }
        #expect(
            events.map(\.key) == ["PreToolUse", "PreCompact"] + ClaudeAdapter.hookEvents.filter { $0 != "PreToolUse" })
        #expect(diff.summary.contains("8"))
    }

    @Test func idempotentWhenAlreadyInstalled() async throws {
        let plan = try await Self.adapter([Self.settingsPath: Self.fullyInstalled]).integrationPlan(
            context: makeContext(), inputs: Self.inputs)
        #expect(plan.isEmpty)
        // Applying a plan then planning again is empty too.
        let first = try #require(
            try await Self.adapter([:]).integrationPlan(context: makeContext(), inputs: Self.inputs).first)
        #expect(
            try await Self.adapter([Self.settingsPath: first.newText]).integrationPlan(
                context: makeContext(), inputs: Self.inputs
            ).isEmpty)
    }

    @Test func otherBuildsHooksAreNotOurs() async throws {
        let dev = Self.fullyInstalled.replacingOccurrences(of: "/vigie hook", with: "/vigie-dev hook")
        let plan = try await Self.adapter([Self.settingsPath: dev]).integrationPlan(
            context: makeContext(), inputs: Self.inputs)
        let hooks = try Self.hooks(in: try #require(plan.first).newText)
        #expect(
            Self.commands(hooks, event: "Stop") == ["/Users/romain/.local/bin/vigie-dev hook claude", Self.command])
        let removal = try await Self.adapter([Self.settingsPath: dev]).removalPlan(
            context: makeContext(), inputs: Self.inputs)
        #expect(removal.isEmpty)
    }

    @Test func removalKeepsForeignHooks() async throws {
        let installed = """
            {
              "hooks": {
                "PreToolUse": [
                  {
                    "matcher": "Bash",
                    "hooks": [
                      { "type": "command", "command": "~/bin/guard.sh" },
                      { "type": "command", "command": "\(Self.command)" }
                    ]
                  }
                ],
                "Stop": [
                  { "hooks": [{ "type": "command", "command": "\(Self.command)" }] }
                ],
                "SessionEnd": [
                  { "hooks": [{ "type": "command", "command": "say bye" }] },
                  { "hooks": [{ "type": "command", "command": "\(Self.command)" }] }
                ]
              },
              "model": "opus"
            }
            """
        let plan = try await Self.adapter([Self.settingsPath: installed]).removalPlan(
            context: makeContext(), inputs: Self.inputs)
        let diff = try #require(plan.first)
        #expect(diff.summary.contains("3"))
        #expect(!diff.newText.hasSuffix("\n"))
        let root = try OrderedJSON.parse(diff.newText)
        #expect(root["model"]?.stringValue == "opus")
        let hooks = try #require(root["hooks"])
        #expect(Self.commands(hooks, event: "PreToolUse") == ["~/bin/guard.sh"])
        #expect(hooks["PreToolUse"]?.description.contains("Bash") ?? false)
        #expect(hooks["Stop"] == nil)
        #expect(Self.commands(hooks, event: "SessionEnd") == ["say bye"])
        #expect(!diff.newText.contains("vigie hook"))
    }

    @Test func removalOfNothing() async throws {
        #expect(try await Self.adapter([:]).removalPlan(context: makeContext(), inputs: Self.inputs).isEmpty)
        #expect(
            try await Self.adapter([Self.settingsPath: "{\"model\": \"opus\"}"]).removalPlan(
                context: makeContext(), inputs: Self.inputs
            ).isEmpty)
    }

    @Test func installThenRemoveRestoresTheOriginal() async throws {
        let old = "{\n  \"model\": \"opus\",\n  \"hooks\": {\n    \"PreCompact\": []\n  }\n}\n"
        let install = try #require(
            try await Self.adapter([Self.settingsPath: old]).integrationPlan(
                context: makeContext(), inputs: Self.inputs
            ).first)
        let removal = try #require(
            try await Self.adapter([Self.settingsPath: install.newText]).removalPlan(
                context: makeContext(), inputs: Self.inputs
            ).first)
        #expect(removal.newText == old)
    }

    @Test(arguments: ["[1, 2]", "{\"hooks\": []}", "{\"hooks\": {\"Stop\": {}}}", "{ not json", "{\"a\": 1} trailing"])
    func refusesUnexpectedShapes(text: String) async {
        await #expect(throws: ClaudeAdapterError.invalidSettings(path: Self.settingsPath)) {
            try await Self.adapter([Self.settingsPath: text]).integrationPlan(
                context: makeContext(), inputs: Self.inputs)
        }
    }

    @Test func projectScope() async throws {
        let project = URL(fileURLWithPath: "/Users/romain/www/app", isDirectory: true)
        let context = makeContext(settings: ["hooks_scope": "project"])
        await #expect(throws: ClaudeAdapterError.noProjectDirectory) {
            try await Self.adapter([:]).integrationPlan(context: context, inputs: Self.inputs)
        }
        let inputs = IntegrationInputs(
            cliPath: Self.inputs.cliPath, homeDirectory: Self.home, projectDirectory: project)
        let plan = try await Self.adapter([:]).integrationPlan(context: context, inputs: inputs)
        #expect(plan.first?.path.path == "/Users/romain/www/app/.claude/settings.json")
    }
}

@Suite struct OrderedJSONTests {
    @Test func roundTripsJSONStringifyOutput() throws {
        let text = """
            {
              "a": 1.50,
              "b": [],
              "c": {},
              "d": [
                true,
                false,
                null,
                -2e10
              ],
              "é\\"\\\\\\n": "\\u0001 😀 /"
            }
            """
        #expect(try OrderedJSON.parse(text).serialized() == text)
    }

    @Test func decodesEscapes() throws {
        #expect(try OrderedJSON.parse(#""\ud83d\ude00 \/ \t""#) == .string("😀 / \t"))
    }

    @Test(arguments: ["", "{", "[1,]", "{\"a\" 1}", "01x", "\"\\ud83d\"", "tru", "\"a\nb\""])
    func rejectsInvalid(text: String) {
        #expect(throws: OrderedJSON.ParseError.self) { try OrderedJSON.parse(text) }
    }
}

extension OrderedJSON: CustomStringConvertible {
    public var description: String { serialized() }
}
