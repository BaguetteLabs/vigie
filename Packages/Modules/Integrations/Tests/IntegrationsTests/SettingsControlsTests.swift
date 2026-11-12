import Foundation
import ModuleKit
import Testing
import VigieUI

@testable import Integrations

/// Story 12.6: the generated controls of a script's declared settings: one VigieUI control kind per setting type,
/// with min, max, step and options kept, numbers clamped, paths shown with `~`, nil resetting to the default.
@MainActor @Suite struct SettingsControlsTests {
    func setting(_ yaml: String) throws -> ScriptSetting {
        let data = runnerScript(settings: [yaml])
        let definition = runnerDefinition(data)
        return try #require(definition.frontMatter?.settings.first)
    }

    @Test func eachTypeMapsToItsControl() throws {
        #expect(
            try setting("{ key: on, type: bool, label: On, default: true }").kind.settingKind == .bool(default: true))
        #expect(
            try setting("{ key: n, type: int, label: N, default: 5, min: 1, max: 9, step: 2 }").kind.settingKind
                == .int(default: 5, min: 1, max: 9, step: 2))
        #expect(
            try setting("{ key: x, type: double, label: X, default: 0.5, min: 0, max: 1 }").kind.settingKind
                == .double(default: 0.5, min: 0, max: 1, step: nil))
        #expect(try setting("{ key: s, type: string, label: S }").kind.settingKind == .string(default: ""))
        #expect(try setting("{ key: t, type: secret, label: T }").kind.settingKind == .secret)
        #expect(
            try setting("{ key: e, type: enum, label: E, options: [a, b], default: b }").kind.settingKind
                == .enumeration(options: ["a", "b"], default: "b"))
        #expect(
            try setting(#"{ key: d, type: duration, label: D, default: "1h30m" }"#).kind.settingKind
                == .duration(default: .seconds(5400)))
        #expect(try setting("{ key: p, type: path, label: P, default: ~/x }").kind.settingKind == .path(default: "~/x"))
        #expect(
            try setting("{ key: l, type: list, label: L, of: path, default: [a] }").kind.settingKind
                == .list(of: .path, default: ["a"]))
    }

    @Test func numbersAreClampedToMinAndMax() throws {
        let int = try setting("{ key: n, type: int, label: N, default: 5, min: 1, max: 9 }").kind
        #expect(ScriptSettingRows.settingValue(.int(50), kind: int) as? Int == 9)
        #expect(ScriptSettingRows.settingValue(.int(-3), kind: int) as? Int == 1)
        #expect(ScriptSettingRows.settingValue(.int(4), kind: int) as? Int == 4)
        let double = try setting("{ key: x, type: double, label: X, default: 0.5, min: 0, max: 1 }").kind
        #expect(ScriptSettingRows.settingValue(.double(1.5), kind: double) as? Double == 1)
        #expect(ScriptSettingRows.settingValue(.int(-2), kind: double) as? Double == 0)
        let open = try setting("{ key: m, type: int, label: M }").kind
        #expect(ScriptSettingRows.settingValue(.int(1_000), kind: open) as? Int == 1_000)
        // nil and an emptied path reset to the front-matter default.
        #expect(ScriptSettingRows.settingValue(nil, kind: open) == nil)
        let path = try setting("{ key: p, type: path, label: P }").kind
        #expect(ScriptSettingRows.settingValue(SettingControlValue.none, kind: path) == nil)
    }

    @Test func rowsReadAndWriteThroughTheStoreWithLabelsAsWritten() async throws {
        let data = runnerScript(
            id: "test.rows",
            settings: [
                #"{ key: mode, type: enum, label: "Mode (fast/slow)", help: "Pick one", options: [fast, slow], default: fast }"#,
                #"{ key: folder, type: path, label: Folder }"#,
                #"{ key: every, type: duration, label: Every, default: 5m }"#,
            ])
        let frontMatter = try #require(runnerDefinition(data).frontMatter)
        let store = MemoryScriptSettings()
        store.register(frontMatter.id, settings: frontMatter.settings.map(\.descriptor))
        let rows = frontMatter.settings.map {
            ScriptSettingRows.row(for: $0, scriptID: frontMatter.id, store: store, secrets: nil)
        }
        #expect(String(localized: rows[0].label) == "Mode (fast/slow)")
        #expect(rows[0].help.map { String(localized: $0) } == "Pick one")
        guard case .enumeration(let options, _) = rows[0].kind else {
            Issue.record("expected an enum")
            return
        }
        #expect(options == ["fast", "slow"])
        // Unset: the control shows the declared default.
        #expect(rows[0].currentValue == .string("fast"))
        #expect(rows[2].currentValue == .duration(.seconds(300)))

        try await rows[0].binding.set(.string("slow"))
        #expect(rows[0].currentValue == .string("slow"))
        try await rows[2].binding.set(.duration(.seconds(90)))
        #expect(store.values[.init(id: "test.rows", key: "every")] as? Duration == .seconds(90))

        // A configured path (a file URL) shows with `~`.
        let home = FileManager.default.homeDirectoryForCurrentUser
        store.edit(home.appendingPathComponent("Reports"), id: "test.rows", key: "folder")
        #expect(rows[1].currentValue == .string("~/Reports"))

        try await rows[0].binding.set(nil)
        #expect(rows[0].currentValue == .string("fast"))
    }
}
