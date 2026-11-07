import CryptoKit
import Foundation
import ModuleKit
import Testing
import Wire

@testable import VigieCore

@Suite struct UnifiedDiffTests {
    @Test func equalTextsRenderNothing() {
        #expect(UnifiedDiff.render(old: "a\nb\n", new: "a\nb\n", label: "f", oldExists: true).isEmpty)
    }

    @Test func newFileDiffsAgainstDevNull() {
        let text = UnifiedDiff.render(old: "", new: "{\n}\n", label: "~/x.json", oldExists: false)
        #expect(text == "--- /dev/null\n+++ ~/x.json\n@@ -0,0 +1,2 @@\n+{\n+}\n")
    }

    @Test func hunksKeepThreeLinesOfContextAndMergeNearbyChanges() {
        let old = (1...20).map { "line \($0)" }.joined(separator: "\n") + "\n"
        var lines = (1...20).map { "line \($0)" }
        lines[1] = "line 2 changed"
        lines.insert("inserted", at: 4)
        lines.remove(at: 17)  // "line 17" (shifted by the insert)
        let new = lines.joined(separator: "\n") + "\n"
        let text = UnifiedDiff.render(old: old, new: new, label: "f", oldExists: true)
        #expect(
            text == """
                --- f
                +++ f
                @@ -1,7 +1,8 @@
                 line 1
                -line 2
                +line 2 changed
                 line 3
                 line 4
                +inserted
                 line 5
                 line 6
                 line 7
                @@ -14,7 +15,6 @@
                 line 14
                 line 15
                 line 16
                -line 17
                 line 18
                 line 19
                 line 20

                """)
    }

    @Test func editsAreAMinimalScript() {
        let edits = UnifiedDiff.edits(["a", "b", "c", "a", "b", "b", "a"], ["c", "b", "a", "b", "a", "c"])
        let changes = edits.filter { if case .same = $0 { false } else { true } }
        #expect(changes.count == 5)  // Myers' classic example: D = 5
        let rebuilt = edits.compactMap { edit -> String? in
            switch edit {
            case .same(let line), .insert(let line): line
            case .delete: nil
            }
        }
        #expect(rebuilt == ["c", "b", "a", "b", "a", "c"])
    }
}

@MainActor @Suite struct IntegrationInstallerTests {
    let root = makeTempDirectory()
    var target: URL { root.appendingPathComponent(".claude/settings.json") }
    nonisolated static let date = Date(timeIntervalSince1970: 1_800_000_000)

    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func write(_ text: String, mode: Int? = nil) throws {
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: target)
        if let mode { try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: target.path) }
    }

    func read() throws -> String { try String(contentsOf: target, encoding: .utf8) }

    func diff(old: String?, new: String) -> ConfigDiff {
        ConfigDiff(
            path: target, baseHash: old.map(Self.hash), oldText: old ?? "", newText: new, summary: "Add 1 hook")
    }

    func installer(store: ConfigStore? = nil, activity: (any ActivityLog)? = nil) -> CoreIntegrationInstaller {
        CoreIntegrationInstaller(
            environment: makeEnvironment(root), homeDirectory: root, configStore: store, activity: activity,
            now: { Self.date })
    }

    func folderEntries() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: target.deletingLastPathComponent().path).sorted()
    }

    @Test func cliPathIsTheLocalBinLink() {
        #expect(installer().cliPath == root.appendingPathComponent(".local/bin/vigie-dev").path)
    }

    @Test func freshFileIsCreatedWithoutBackup() async throws {
        let new = "{\n  \"hooks\": {}\n}\n"
        let installer = installer()
        let preview = try await installer.preview([diff(old: nil, new: new)], adapterID: "claude", action: .install)
        #expect(!preview.stale)
        #expect(preview.files.first?.unifiedDiff.hasPrefix("--- /dev/null\n") == true)
        let result = try await installer.apply(preview)
        #expect(try read() == new)
        #expect(result.appliedPaths == [target])
        #expect(result.backupPaths.isEmpty)
        #expect(try folderEntries() == ["settings.json"])  // no temp file left behind
        let mode = try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func existingFileGetsTimestampedBackupAndKeepsItsMode() async throws {
        let old = "{\n  \"model\": \"opus\",\n  \"hooks\": {\"Stop\": [{\"hooks\": [{\"command\": \"mine\"}]}]}\n}\n"
        let new =
            "{\n  \"model\": \"opus\",\n  \"hooks\": {\"Stop\": [{\"hooks\": [{\"command\": \"mine\"}]}, {}]}\n}\n"
        try write(old, mode: 0o600)
        let installer = installer()
        let preview = try await installer.preview([diff(old: old, new: new)], adapterID: "claude", action: .install)
        #expect(!preview.stale)
        #expect(preview.files.first?.unifiedDiff.contains("-  \"hooks\"") == true)
        let result = try await installer.apply(preview)
        #expect(try read() == new)
        let stamp = CoreIntegrationInstaller.stamp(Self.date)
        let backup = URL(fileURLWithPath: target.path + ".vigie-backup-\(stamp)")
        #expect(result.backupPaths == [backup])
        #expect(try String(contentsOf: backup, encoding: .utf8) == old)
        #expect(try folderEntries() == ["settings.json", "settings.json.vigie-backup-\(stamp)"])
        for url in [target, backup] {
            let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
            #expect(mode == 0o600)
        }
        #expect(stamp.wholeMatch(of: /\d{8}-\d{6}/) != nil)
    }

    @Test func secondBackupInTheSameSecondGetsASuffix() async throws {
        try write("a\n")
        let installer = installer()
        _ = try await installer.apply(
            try await installer.preview([diff(old: "a\n", new: "b\n")], adapterID: "claude", action: .install))
        let result = try await installer.apply(
            try await installer.preview([diff(old: "b\n", new: "a\n")], adapterID: "claude", action: .remove))
        let stamp = CoreIntegrationInstaller.stamp(Self.date)
        #expect(result.backupPaths.map(\.lastPathComponent) == ["settings.json.vigie-backup-\(stamp)-2"])
    }

    @Test func hashMismatchMarksThePreviewStale() async throws {
        try write("edited by the user\n")
        let preview = try await installer().preview(
            [diff(old: "original\n", new: "new\n")], adapterID: "claude", action: .install)
        #expect(preview.stale)
        // A file the plan saw as absent that now exists is stale too.
        let appeared = try await installer().preview(
            [diff(old: nil, new: "new\n")], adapterID: "claude", action: .install)
        #expect(appeared.stale)
        await #expect(throws: IntegrationError.stalePreview) { try await installer().apply(preview) }
    }

    @Test func concurrentChangeAfterPreviewIsRefusedAndNothingIsWritten() async throws {
        try write("original\n")
        let installer = installer()
        let preview = try await installer.preview(
            [diff(old: "original\n", new: "new\n")], adapterID: "claude", action: .install)
        #expect(!preview.stale)
        try write("edited meanwhile\n")
        await #expect(throws: IntegrationError.targetChanged(paths: [target])) { try await installer.apply(preview) }
        #expect(try read() == "edited meanwhile\n")
        #expect(try folderEntries() == ["settings.json"])
    }

    @Test func symlinkedTargetEditsTheDestinationAndKeepsTheLink() async throws {
        let real = root.appendingPathComponent("dotfiles/claude-settings.json")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old\n".utf8).write(to: real)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: real)
        let installer = installer()
        _ = try await installer.apply(
            try await installer.preview([diff(old: "old\n", new: "new\n")], adapterID: "claude", action: .install))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: target.path) == real.path)
        #expect(try String(contentsOf: real, encoding: .utf8) == "new\n")
    }

    @Test func installIsRecordedInLocalTomlAndRemovalClearsIt() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore()
        defer { store.stop() }
        let activity = RecordingActivityLog()
        try write("{}\n")
        let installer = installer(store: store, activity: activity)
        let result = try await installer.apply(
            try await installer.preview(
                [diff(old: "{}\n", new: "{\"hooks\":{}}\n")], adapterID: "claude", action: .install))
        let backup = try #require(result.backupPaths.first)
        let local = try String(contentsOf: fixture.localURL, encoding: .utf8)
        #expect(local.contains("[integrations.claude]"))
        #expect(local.contains("installed_at = \"\(WireDate.string(from: Self.date))\""))
        #expect(local.contains("target = \"\(target.path)\""))
        #expect(local.contains("backup = \"\(backup.path)\""))
        #expect(local.contains("cli_path = \"\(root.appendingPathComponent(".local/bin/vigie-dev").path)\""))
        #expect(store.problems.isEmpty)
        #expect(activity.entries.map(\.kind) == ["integration.install"])
        #expect(activity.entries.first?.adapter == "claude")
        #expect(activity.entries.first?.detail["backup"] == backup.path)

        _ = try await installer.apply(
            try await installer.preview(
                [diff(old: "{\"hooks\":{}}\n", new: "{}\n")], adapterID: "claude", action: .remove))
        let after = try String(contentsOf: fixture.localURL, encoding: .utf8)
        for key in CoreSettings.integrationKeys { #expect(!after.contains("\(key) =")) }
        #expect(activity.entries.map(\.kind) == ["integration.install", "integration.remove"])
    }

    @Test func integrationTableIsNotAnUnknownKeyBeforeRegistration() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(local: "[integrations.claude]\ninstalled_at = \"x\"\n")
        defer { store.stop() }
        #expect(store.problems.isEmpty)
    }
}
