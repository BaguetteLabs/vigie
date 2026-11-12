import Foundation
import ModuleKit
import Testing

@testable import Integrations

@Suite struct RunnerLabelTests {
    @Test func labelsComeFromTheCatalog() {
        #expect(ScriptRunLabel.waitingFirstRun == "WAITING · FIRST RUN")
        #expect(ScriptRunLabel.outcome(.timedOut(seconds: 30)) == "TIMED OUT · 30S")
        #expect(ScriptRunLabel.outcome(.timedOut(seconds: 5)) == "TIMED OUT · 5S")
        #expect(ScriptRunLabel.outcome(.failed(exitCode: 1)) == "EXIT 1")
        #expect(ScriptRunLabel.outcome(.failed(exitCode: 3)) == "EXIT 3")
        #expect(
            ScriptRunLabel.outcome(.succeeded(ScriptOutput(widget: ScriptWidget(type: .text, value: "x")))) == "EXIT 0")
        #expect(ScriptRunLabel.outcome(.invalidOutput("x")) == "INVALID OUTPUT")
        #expect(ScriptRunLabel.outcome(.runtimeNotFound("python3")) == "RUNTIME NOT FOUND")
        #expect(ScriptRunLabel.outcome(.launchFailed("x")) == "LAUNCH FAILED")
        #expect(ScriptRunLabel.state(ScriptRunState()) == "WAITING · FIRST RUN")
        let output = ScriptOutput(widget: ScriptWidget(type: .text, value: "x"))
        #expect(ScriptRunLabel.state(ScriptRunState(phase: .ok(output, at: Date()))) == nil)
    }

    @Test func everyShippedLocaleHasTheRunnerStrings() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Integrations/Resources/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let strings = try #require(catalog?["strings"] as? [String: Any])
        var locales: Set<String> = []
        for case let entry as [String: Any] in strings.values {
            locales.formUnion((entry["localizations"] as? [String: Any])?.keys ?? [:].keys)
        }
        let keys = strings.keys.filter { $0.hasPrefix("script.run.") }
        #expect(keys.count == 10)
        for key in keys {
            let entry = try #require(strings[key] as? [String: Any])
            let localized = Set((entry["localizations"] as? [String: Any])?.keys ?? [:].keys)
            #expect(localized == locales, "\(key) is missing a locale")
            #expect(IntegrationsText.string(key) != key, "\(key) does not resolve")
        }
    }

    @Test func environmentNamesAndFormats() {
        #expect(ScriptEnvironment.variableName("warn_at") == "VIGIE_SETTING_WARN_AT")
        #expect(ScriptEnvironment.variableName("token") == "VIGIE_SETTING_TOKEN")
        #expect(ScriptEnvironment.secretKey(scriptID: "github.prs", settingKey: "token") == "github.prs.token")
        #expect(ScriptEnvironment.defaultValue(.duration(default: .seconds(90), raw: "90s")) == "90s")
        #expect(ScriptEnvironment.defaultValue(.list(of: .string, default: [])) == "[]")
        #expect(ScriptEnvironment.defaultValue(.path(default: nil)) == nil)
        #expect(ScriptEnvironment.defaultValue(.secret) == nil)
        #expect(ScriptEnvironment.fileExtension(language: "python") == "py")
        #expect(ScriptEnvironment.fileExtension(language: "Swift") == "swift")
        #expect(ScriptEnvironment.fileExtension(language: "go") == "go")
        #expect(ScriptEnvironment.fileExtension(language: "c++") == nil)
        #expect(ScriptEnvironment.fileExtension(language: nil) == nil)
        // Without a captured PATH: the runtime's folder, then the system folders.
        let environment = ScriptEnvironment.build(
            settings: [], configured: { _ in nil }, secrets: [:], searchPath: [],
            runtime: URL(fileURLWithPath: "/opt/tools/bin/python3"), home: "/Users/x", language: nil)
        #expect(
            environment == [
                "PATH": "/opt/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/Users/x", "LANG": "en_US.UTF-8",
            ])
    }
}
