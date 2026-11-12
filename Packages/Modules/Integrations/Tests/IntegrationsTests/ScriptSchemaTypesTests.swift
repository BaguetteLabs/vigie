import Foundation
import ModuleKit
import Testing

@testable import Integrations

/// Story 12.1: the Codable types follow `schemas/script-module.schema.json` (same enums, keys, reserved setting
/// keys, versions and defaults), parse durations with the config grammar, read YAML front matter and report
/// readable errors.
@Suite struct ScriptSchemaTypesTests {
    // MARK: - Schema parity

    /// The published schema, read as plain JSON (no JSON Schema library, AD-16).
    nonisolated(unsafe) static let schema: [String: Any] = {
        var url = URL(filePath: #filePath)
        while !FileManager.default.fileExists(atPath: url.appending(path: "schemas").path(percentEncoded: false)) {
            url.deleteLastPathComponent()
        }
        let data = try! Data(contentsOf: url.appending(path: "schemas/script-module.schema.json"))
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }()

    static func node(_ pointer: String) -> [String: Any] {
        var node: Any = schema
        for part in pointer.split(separator: "/") where part != "#" {
            if let index = Int(part), let array = node as? [Any] {
                node = array[index]
            } else {
                node = (node as! [String: Any])[String(part)]!
            }
        }
        return node as! [String: Any]
    }

    static func strings(_ pointer: String, _ key: String) -> [String] { node(pointer)[key] as! [String] }
    static func properties(_ pointer: String) -> Set<String> {
        Set((node(pointer)["properties"] as! [String: Any]).keys)
    }

    @Test func enumsMatchTheSchema() {
        #expect(
            Self.strings("#/$defs/frontMatter/properties/widget", "enum") == ScriptWidgetType.allCases.map(\.rawValue))
        #expect(
            Self.strings("#/$defs/frontMatter/properties/surfaces/items", "enum")
                == ScriptSurface.allCases.map(\.rawValue))
        #expect(
            Self.strings("#/$defs/output/properties/state", "enum") == ScriptOutput.StateName.allCases.map(\.rawValue))
        #expect(Self.strings("#/$defs/level", "enum") == ScriptLevel.allCases.map(\.rawValue))
        #expect(
            Self.strings("#/$defs/settingList/properties/of", "enum")
                == ScriptSetting.ListElement.allCases.map(\.rawValue))
        #expect(Self.node("#/$defs/schemaVersion")["enum"] as! [Int] == Array(ScriptSchemaVersion.supported))
        #expect(Self.node("#/$defs/frontMatter/properties/icon")["default"] as! String == ScriptFrontMatter.defaultIcon)
        #expect(
            Self.strings("#/$defs/frontMatter/properties/surfaces", "default")
                == ScriptFrontMatter.defaultSurfaces.map(\.rawValue))
        #expect(
            Self.node("#/$defs/output/properties/state")["default"] as! String
                == ScriptOutput.StateName(ScriptOutput.defaultState).rawValue)
    }

    @Test func settingTypesMatchTheSchema() {
        let branches = Self.node("#/$defs/setting")["oneOf"] as! [[String: String]]
        var schemaTypes: [String] = []
        for branch in branches {
            let pointer = branch["$ref"]!
            let type = (Self.node(pointer + "/properties/type")["const"]) as! String
            schemaTypes.append(type)
            let name = ScriptSetting.TypeName(rawValue: type)!
            #expect(Self.properties(pointer) == ScriptSetting.keys(for: name), "keys of \(type)")
        }
        #expect(schemaTypes == ScriptSetting.TypeName.allCases.map(\.rawValue))
    }

    @Test func keysMatchTheSchema() {
        #expect(Self.properties("#/$defs/frontMatter") == ScriptFrontMatter.keys)
        #expect(Self.node("#/$defs/frontMatter")["additionalProperties"] as? Bool == false)
        #expect(Self.node("#/$defs/output")["additionalProperties"] as? Bool == true)
        #expect(Self.properties("#/$defs/output") == ["schema", "state", "widget", "action", "notify"])
        let reserved = Self.node("#/$defs/settingKey")["pattern"] as! String
        for key in ScriptSetting.reservedKeys { #expect(reserved.contains(key)) }
        #expect(reserved.contains("(enabled|side|priority|surfaces|notify)"))
        #expect(ScriptSetting.reservedKeys.count == 5)
    }

    // MARK: - Defaults

    static func fixture<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        let url = ScriptSchemaFixtureTests.root.appending(path: "valid/\(name).json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object["document"]!))
    }

    @Test func frontMatterDefaults() throws {
        let minimal = try Self.fixture(ScriptFrontMatter.self, "fm-minimal")
        #expect(
            minimal
                == ScriptFrontMatter(
                    schema: .absent, id: "dev.minimal", name: "Minimal", icon: "terminal", interval: .seconds(300),
                    runtime: "bash", widget: .text, surfaces: [.home], priority: nil, settings: []))
        #expect(minimal.schema.rawValue == 1, "a file without schema is version 1")
        #expect(ScriptSchemaVersion.current.rawValue == 2, "new files write schema 2 (Story 12.8)")
    }

    /// Story 12.8 (schema part, done with 12.9): schema 2 adds `author`, `source` (HTTPS) and `version`; a schema 1
    /// file (explicit or without `schema`) cannot use them, so an older Vigie refuses a v2 file by its version.
    @Test func schemaTwoProvenanceKeys() throws {
        let v2 = try Self.fixture(ScriptFrontMatter.self, "fm-v2-provenance")
        #expect(v2.schema == .provenance)
        #expect(v2.author == "Léa Martin")
        #expect(v2.source?.host() == "github.com")
        #expect(v2.version == "1.2.0")
        let v1 = try Self.fixture(ScriptFrontMatter.self, "fm-v1-explicit")
        #expect(v1.schema == .absent)
        #expect(v1.author == nil && v1.source == nil && v1.version == nil)
        #expect(Self.node("#/$defs/schemaVersion")["default"] as? Int == ScriptSchemaVersion.absent.rawValue)

        let yaml = "id: dev.a\nname: A\ninterval: 5m\nruntime: sh\nwidget: text\nauthor: Léa\n"
        #expect(throws: ScriptSchemaError(path: "author", reason: .requiresSchema(2))) {
            try ScriptFrontMatter.decode(yaml: yaml)
        }
        let message = ScriptSchemaError(path: "author", reason: .requiresSchema(2)).message
        #expect(message.hasPrefix("author: needs schema: 2"))
        let decoded = try ScriptFrontMatter.decode(yaml: "schema: 2\n" + yaml + "version: \"1.0\"\n")
        #expect(decoded.author == "Léa" && decoded.version == "1.0")
        for good in ["1", "1.2", "1.2.3", "1.2.3-rc.1", "1.0+build.7"] { #expect(ScriptFrontMatter.isVersion(good)) }
        for bad in ["v1", "1.2.3.4", "1.", "", "1.0 beta"] { #expect(!ScriptFrontMatter.isVersion(bad), "\(bad)") }
        #expect(ScriptFrontMatter.httpsURL("https://example.com") != nil)
        for bad in ["http://example.com", "https://", "https://a b", "ftp://x", "HTTPS://example.com"] {
            #expect(ScriptFrontMatter.httpsURL(bad) == nil, "\(bad)")
        }
    }

    @Test func specExampleDecodes() throws {
        let spec = try Self.fixture(ScriptFrontMatter.self, "fm-spec-example")
        #expect(spec.id == "github.prs")
        #expect(spec.icon == "arrow.triangle.pull")
        #expect(spec.interval == .seconds(300))
        #expect(spec.runtime == "python3")
        #expect(spec.widget == .number)
        #expect(spec.surfaces == [.home, .side, .page])
        #expect(spec.priority == 5)
        #expect(
            spec.settings == [
                ScriptSetting(key: "token", label: "GitHub token", kind: .secret),
                ScriptSetting(key: "repo", label: "Repository (owner/name)", kind: .string(default: "")),
                ScriptSetting(
                    key: "warn_at", label: "Warn when open PRs ≥", kind: .int(default: 5, min: nil, max: nil, step: nil)
                ),
            ])
    }

    @Test func settingDefaultsAndOptions() throws {
        let settings = try Self.fixture(ScriptFrontMatter.self, "fm-all-settings").settings
        let kinds = Dictionary(uniqueKeysWithValues: settings.map { ($0.key, $0.kind) })
        #expect(kinds["verbose"] == .bool(default: true))
        #expect(kinds["quiet"] == .bool(default: false))
        #expect(kinds["retries"] == .int(default: 2, min: 0, max: 5, step: 1))
        #expect(kinds["count"] == .int(default: 0, min: nil, max: nil, step: nil))
        #expect(kinds["threshold"] == .double(default: 0.5, min: 0, max: 1.5, step: 0.1))
        #expect(kinds["ratio"] == .double(default: 2, min: nil, max: nil, step: nil))
        #expect(kinds["url"] == .string(default: "https://vigie.app"))
        #expect(kinds["api_key"] == .secret)
        #expect(kinds["method"] == .enumeration(options: ["GET", "HEAD"], default: "HEAD"))
        #expect(kinds["timeout"] == .duration(default: .seconds(10), raw: "10s"))
        #expect(kinds["grace"] == .duration(default: .zero, raw: "0s"))
        #expect(kinds["log_file"] == .path(default: "~/Library/Logs/site.log"))
        #expect(kinds["cert"] == .path(default: nil))
        #expect(kinds["hosts"] == .list(of: .string, default: ["vigie.app", "example.com"]))
        #expect(kinds["watch_dirs"] == .list(of: .path, default: []))
        #expect(kinds["tags"] == .list(of: .string, default: []))
        #expect(settings.first { $0.key == "verbose" }?.help == "Log every request.")
        #expect(settings.first { $0.key == "quiet" }?.help == nil)
    }

    @Test func outputDefaultsAndSpecExample() throws {
        let minimal = try Self.fixture(ScriptOutput.self, "out-status-minimal")
        #expect(
            minimal == ScriptOutput(schema: .absent, state: .ambient, widget: ScriptWidget(type: .status, level: .ok)))

        let spec = try Self.fixture(ScriptOutput.self, "out-spec-example")
        #expect(spec.state == .active)
        #expect(
            spec.widget
                == ScriptWidget(
                    type: .number, value: "3", label: "OPEN PRS", detail: "2 awaiting review", level: .warn))
        #expect(spec.action == .open("https://github.com/me/project/pulls"))
        #expect(spec.action?.url == URL(string: "https://github.com/me/project/pulls"))
    }

    @Test func outputIgnoresNotifyAndUnknownKeys() throws {
        let output = try Self.fixture(ScriptOutput.self, "out-text-ignored-keys")
        #expect(output.state == .hidden)
        #expect(output.widget == ScriptWidget(type: .text, value: "Fri 14:00 · release/0.3", label: "NEXT RELEASE"))
        #expect(output.action == .copy("release/0.3"))
        #expect(
            try Self.fixture(ScriptOutput.self, "out-status-full").action
                == .run(["open", "-a", "Safari", "https://vigie.app"]))
    }

    @Test func numericValuesKeepTheirPrintedForm() throws {
        #expect(try Self.fixture(ScriptOutput.self, "out-number-numeric-value").widget.value == "42")
        #expect(try Self.fixture(ScriptOutput.self, "out-number-fraction").widget.value == "2.5")
    }

    // MARK: - Durations (config grammar)

    @Test(arguments: [
        ("150ms", Duration.milliseconds(150)), ("90s", .seconds(90)), ("5m", .seconds(300)), ("1h30m", .seconds(5400)),
        ("7d", .seconds(604_800)), ("1.5m", .seconds(90)), (".5h", .seconds(1800)), ("1.m", .seconds(60)),
        ("0s", .zero),
    ])
    func durationGrammar(_ text: String, _ expected: Duration) {
        #expect(ScriptDuration.parse(text) == expected)
    }

    @Test(arguments: ["", "5", "5M", "5min", "1h 30m", "1.5.2m", "m", "-5m", " 5m", "5m "])
    func durationRejects(_ text: String) {
        #expect(ScriptDuration.parse(text) == nil)
    }

    @Test func intervalIsAboveZero() {
        #expect(ScriptDuration.parseInterval("0s") == nil)
        #expect(ScriptDuration.parseInterval("0h0m") == nil)
        #expect(ScriptDuration.parseInterval("0h10m") == .seconds(600))
        #expect(ScriptDuration.format(.seconds(5400)) == "1h30m")
        #expect(ScriptDuration.format(.milliseconds(150)) == "150ms")
    }

    // MARK: - YAML front matter (Yams)

    @Test func specExampleAsYAML() throws {
        let yaml = """
            id: github.prs
            name: GitHub PRs
            icon: arrow.triangle.pull
            interval: 5m
            runtime: python3
            widget: number                    # status | number | text
            surfaces: [home, side, page]
            priority: 5
            settings:
              - { key: token,   type: secret, label: "GitHub token" }
              - { key: repo,    type: string, label: "Repository (owner/name)" }
              - { key: warn_at, type: int,    label: "Warn when open PRs ≥", default: 5 }
            """
        #expect(try ScriptFrontMatter.decode(yaml: yaml) == Self.fixture(ScriptFrontMatter.self, "fm-spec-example"))
    }

    @Test func yamlErrorsNameTheKey() {
        let yaml = "id: a\nname: A\ninterval: 1m\nruntime: sh\nwidget: chart\n"
        #expect(
            throws: ScriptSchemaError(
                path: "widget", reason: .unknownValue("chart", allowed: ["status", "number", "text"]))
        ) {
            try ScriptFrontMatter.decode(yaml: yaml)
        }
        let nested =
            "id: a\nname: A\ninterval: 1m\nruntime: sh\nwidget: text\nsettings:\n  - { key: side, type: bool, label: S }\n"
        #expect(throws: ScriptSchemaError(path: "settings[0].key", reason: .reservedKey("side"))) {
            try ScriptFrontMatter.decode(yaml: nested)
        }
    }

    // MARK: - Messages

    @Test func messagesAreReadable() {
        let unknown = ScriptSchemaError(
            path: "widget.type", reason: .unknownValue("chart", allowed: ["status", "number", "text"]))
        #expect(unknown.message == "widget.type: unknown value “chart” (expected one of: status, number, text).")
        #expect(ScriptSchemaError(path: "intervall", reason: .unknownKey).message == "intervall: unknown key.")
        #expect(
            ScriptSchemaError(path: "schema", reason: .unsupportedSchema(2, supported: 1)).message
                == "schema: schema version 2 is not supported by this version of Vigie (it reads up to 1).")
        #expect(
            ScriptSchemaError(path: "interval", reason: .invalidFormat("5", .interval)).message
                == "interval: “5” is not a duration above zero such as 30s, 5m or 1h30m.")
        #expect(
            ScriptSchemaError(path: "", reason: .wrongType(expected: .object)).message
                == "the document: expected an object.")
    }
}
