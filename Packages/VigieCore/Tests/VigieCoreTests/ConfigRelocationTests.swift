import Foundation
import ModuleKit
import SwiftUI
import Testing
import Wire

@testable import VigieCore

/// Story 16.1: choosing the config folder (move or adopt, the `local.toml` record, live reload, the watcher and the
/// script folder following it), and writes through a symlinked folder in a git checkout. Temp folders only.
@MainActor @Suite struct ConfigRelocationTests {
    let fm = FileManager.default

    private func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    private func root(_ fixture: ConfigFixture) -> URL { fixture.support.deletingLastPathComponent() }

    private func write(_ text: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// A store in a temp home, so the default folder (under `<home>`) is a temp folder too.
    private func homeStore(config: String) async throws -> (ConfigStore, ManualDirectoryWatcher, AppEnvironment) {
        let base = makeTempDirectory()
        let home = base.appendingPathComponent("home", isDirectory: true)
        let custom = base.appendingPathComponent("custom", isDirectory: true)
        try write(config, to: custom.appendingPathComponent("config.toml"))
        let environment = AppEnvironment(
            flavor: .dev, applicationSupportURL: base.appendingPathComponent("support", isDirectory: true),
            configFolderOverride: custom, homeDirectoryURL: home)
        let watcher = ManualDirectoryWatcher()
        let store = ConfigStore(environment: environment, watcher: watcher, debounce: .zero)
        await store.start()
        return (store, watcher, environment)
    }

    /// Indices of lines that differ between two texts with the same number of lines (nil when the counts differ).
    private func differingLines(_ before: String, _ after: String) -> [Int]? {
        let old = before.components(separatedBy: "\n")
        let new = after.components(separatedBy: "\n")
        guard old.count == new.count else { return nil }
        return old.indices.filter { old[$0] != new[$0] }
    }

    static let multiSection = """
        # Vigie config, kept in my dotfiles
        [general]
        hide_in_fullscreen = true   # keep it out of the way
        hover_delay = "150ms"

        # Notch
        [closed]
        slots = 3        # three per side
        peek = true

        [appearance]
        theme = "chrome-hologram"
        mode = "system"  # follow macOS

        """

    // MARK: - Move

    @Test func moveToAnEmptyFolderMovesTheFilesAndRecordsTheLocation() async throws {
        let fixture = ConfigFixture()
        try write("x", to: fixture.configFolder.appendingPathComponent("themes/mine.toml"))
        try write("---\nid: a\n---\n", to: fixture.configFolder.appendingPathComponent("modules/a.md"))
        let (store, _) = try await fixture.makeStore(config: "[closed]\nslots = 2\n")
        defer { store.stop() }
        let observed = StreamCounter(store.observe("closed.slots"))
        let target = root(fixture).appendingPathComponent("dotfiles/vigie", isDirectory: true)

        let outcome = try await store.relocate(to: target)

        #expect(outcome == .moved)
        #expect(try read(target.appendingPathComponent("config.toml")) == "[closed]\nslots = 2\n")
        #expect(try read(target.appendingPathComponent("themes/mine.toml")) == "x")
        #expect(fm.fileExists(atPath: target.appendingPathComponent("modules/a.md").path))
        #expect(try fm.contentsOfDirectory(atPath: fixture.configFolder.path).isEmpty)
        #expect(store.configURL.path == target.appendingPathComponent("config.toml").path)
        #expect(store.configFolderURL.path == target.path)
        #expect(store.location.folder.path == target.path)
        #expect(store.value("closed.slots", as: Int.self) == 2)
        // Recorded in local.toml, and read back by AppEnvironment at the next launch.
        let local = try read(fixture.localURL)
        #expect(AppEnvironment.configFolderRecord(inLocalTOML: local) == target.path)
        #expect(!fm.fileExists(atPath: fixture.configFolder.appendingPathComponent("config.toml").path))
        let relaunched = AppEnvironment(flavor: .release, applicationSupportURL: fixture.support)
        #expect(relaunched.configFolderURL.standardizedFileURL.path == target.path)
        #expect(relaunched.configFolderSource == .localRecord)
        // Values did not change: observers stay silent.
        try await Task.sleep(for: .milliseconds(50))
        #expect(observed.count == 0)
    }

    @Test func recordIsTildeAbbreviatedAndUseDefaultRemovesIt() async throws {
        let (store, _, environment) = try await homeStore(config: "[closed]\nslots = 2\n")
        defer { store.stop() }
        #expect(!store.isUsingDefaultFolder)
        let dotfiles = environment.homeDirectoryURL.appendingPathComponent("dotfiles/vigie", isDirectory: true)

        try await store.relocate(to: dotfiles)
        #expect(
            AppEnvironment.configFolderRecord(inLocalTOML: try read(environment.localConfigURL)) == "~/dotfiles/vigie")

        #expect(try await store.relocate(to: environment.defaultConfigFolderURL) == .moved)
        #expect(store.isUsingDefaultFolder)
        #expect(AppEnvironment.configFolderRecord(inLocalTOML: try read(environment.localConfigURL)) == nil)
        #expect(
            try read(environment.defaultConfigFolderURL.appendingPathComponent("config.toml"))
                == "[closed]\nslots = 2\n")
    }

    // MARK: - Adopt

    @Test func adoptReloadsNotifiesChangedKeysAndLeavesTheOldFolder() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(config: "[closed]\nslots = 2\npeek = false\n")
        defer { store.stop() }
        let before = try Data(contentsOf: fixture.configURL)
        let slots = StreamCounter(store.observe("closed.slots"))
        let peek = StreamCounter(store.observe("closed.peek"))
        let target = root(fixture).appendingPathComponent("repo", isDirectory: true)
        try write("[closed]\nslots = 4\npeek = false\n", to: target.appendingPathComponent("config.toml"))
        #expect(try store.planRelocation(to: target).adopts)

        #expect(try await store.relocate(to: target) == .adopted)

        #expect(store.value("closed.slots", as: Int.self) == 4)
        #expect(await eventually { slots.count == 1 })
        #expect(peek.count == 0)
        #expect(try Data(contentsOf: fixture.configURL) == before)
        #expect(AppEnvironment.configFolderRecord(inLocalTOML: try read(fixture.localURL)) == target.path)
    }

    // MARK: - Refusals

    @Test func refusalsChangeNothing() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(config: "[closed]\nslots = 2\n")
        defer { store.stop() }
        try write("[modules.\"x\"]\n", to: fixture.configFolder.appendingPathComponent("modules/x.md"))
        let base = root(fixture)
        let file = base.appendingPathComponent("plain.txt")
        try write("x", to: file)
        let readOnly = base.appendingPathComponent("readonly", isDirectory: true)
        try fm.createDirectory(at: readOnly, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: readOnly.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: readOnly.path) }
        let crowded = base.appendingPathComponent("crowded", isDirectory: true)
        try fm.createDirectory(at: crowded.appendingPathComponent("modules"), withIntermediateDirectories: true)
        let localBefore = try Data(contentsOf: fixture.localURL)

        let cases: [(URL, ConfigRelocationError)] = [
            (fixture.configFolder, .sameFolder),
            (fixture.configFolder.appendingPathComponent("sub", isDirectory: true), .insideCurrentFolder),
            (base, .containsCurrentFolder),
            (fixture.support, .applicationSupport),
            (fixture.support.appendingPathComponent("inner", isDirectory: true), .applicationSupport),
            (file, .notAFolder),
            (readOnly, .notWritable),
            (readOnly.appendingPathComponent("new", isDirectory: true), .notWritable),
            (crowded, .conflict("modules")),
        ]
        for (target, expected) in cases {
            await #expect(throws: expected) { try await store.relocate(to: target) }
            #expect(ConfigRelocationError.sameFolder.errorDescription?.hasPrefix("settings.") == false)
        }
        #expect(store.configFolderURL == fixture.configFolder)
        #expect(try Data(contentsOf: fixture.localURL) == localBefore)
        #expect(try read(fixture.configURL) == "[closed]\nslots = 2\n")
        #expect(!fm.fileExists(atPath: readOnly.appendingPathComponent("new").path))
    }

    // MARK: - Rollback

    @Test func aFailingCopyRollsBackAndChangesNothing() async throws {
        let fixture = ConfigFixture()
        try write("x", to: fixture.configFolder.appendingPathComponent("themes/mine.toml"))
        try write("y", to: fixture.configFolder.appendingPathComponent("modules/a.md"))
        let (store, watcher) = try await fixture.makeStore(config: "[closed]\nslots = 2\n")
        defer { store.stop() }
        let watchedBefore = watcher.watchedDirectories
        let localBefore = try Data(contentsOf: fixture.localURL)
        // `config.toml` and `themes` copy; `modules` fails midway (after a partial copy).
        store.relocationFileSystem = ConfigRelocationFileSystem(
            copy: { from, to in
                if from.lastPathComponent == "modules" {
                    try FileManager.default.createDirectory(at: to, withIntermediateDirectories: true)
                    throw CocoaError(.fileWriteOutOfSpace)
                }
                try FileManager.default.copyItem(at: from, to: to)
            },
            remove: { try FileManager.default.removeItem(at: $0) })
        let target = root(fixture).appendingPathComponent("new", isDirectory: true)

        await #expect {
            try await store.relocate(to: target)
        } throws: { error in
            if case .moveFailed = error as? ConfigRelocationError { return true }
            return false
        }

        #expect(!fm.fileExists(atPath: target.path), "partial copies and the created folder are removed")
        #expect(try read(fixture.configURL) == "[closed]\nslots = 2\n")
        #expect(try read(fixture.configFolder.appendingPathComponent("themes/mine.toml")) == "x")
        #expect(try read(fixture.configFolder.appendingPathComponent("modules/a.md")) == "y")
        #expect(store.configFolderURL == fixture.configFolder)
        #expect(store.configURL == fixture.configURL)
        #expect(try Data(contentsOf: fixture.localURL) == localBefore)
        #expect(watcher.watchedDirectories == watchedBefore)
    }

    @Test func aFailingCopyIntoAnExistingFolderKeepsTheFolder() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(config: "[closed]\nslots = 2\n")
        defer { store.stop() }
        store.relocationFileSystem = ConfigRelocationFileSystem(
            copy: { _, _ in throw CocoaError(.fileWriteNoPermission) }, remove: { _ in })
        let target = root(fixture).appendingPathComponent("existing", isDirectory: true)
        try write("keep", to: target.appendingPathComponent("README"))

        await #expect(throws: ConfigRelocationError.self) { try await store.relocate(to: target) }
        #expect(try fm.contentsOfDirectory(atPath: target.path) == ["README"])
        #expect(store.configFolderURL == fixture.configFolder)
    }

    // MARK: - Watcher

    @Test func theWatcherFollowsTheNewFolder() async throws {
        let fixture = ConfigFixture()
        let (store, watcher) = try await fixture.makeStore(config: "[closed]\nslots = 2\n")
        defer { store.stop() }
        let target = root(fixture).appendingPathComponent("new", isDirectory: true)
        try await store.relocate(to: target)
        let watched = Set(watcher.watchedDirectories.map(\.path))
        #expect(watched == [target.path, fixture.support.path])

        // A write in the new folder reloads.
        try fixture.atomicReplace(target.appendingPathComponent("config.toml"), with: "[closed]\nslots = 1\n")
        watcher.fire(target)
        await store.waitForScheduledReload()
        #expect(store.value("closed.slots", as: Int.self) == 1)

        // The old folder is no longer watched or read.
        try fixture.writeConfig("[closed]\nslots = 4\n")
        watcher.fire(fixture.configFolder)
        await store.waitForScheduledReload()
        await store.reload()
        #expect(store.value("closed.slots", as: Int.self) == 1)
    }

    @Test func aSymlinkedConfigFileWatchesItsTargetFolder() async throws {
        let fixture = ConfigFixture()
        let dotfiles = root(fixture).appendingPathComponent("dotfiles", isDirectory: true)
        try write("[closed]\nslots = 2\n", to: dotfiles.appendingPathComponent("vigie.toml"))
        try fm.createDirectory(at: fixture.configFolder, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            at: fixture.configURL, withDestinationURL: dotfiles.appendingPathComponent("vigie.toml"))
        let (store, watcher) = try await fixture.makeStore()
        defer { store.stop() }
        let watched = Set(watcher.watchedDirectories.map { $0.resolvingSymlinksInPath().path })
        #expect(watched.contains(dotfiles.resolvingSymlinksInPath().path))
        #expect(watched.contains(fixture.configFolder.resolvingSymlinksInPath().path))
    }

    // MARK: - Symlink and git checkout

    @Test func aSymlinkedFolderInAGitCheckoutGetsAOneLineAtomicWrite() async throws {
        let base = makeTempDirectory()
        let repo = base.appendingPathComponent("dotfiles", isDirectory: true)
        try fm.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let real = repo.appendingPathComponent("vigie", isDirectory: true)
        try write(Self.multiSection, to: real.appendingPathComponent("config.toml"))
        let link = base.appendingPathComponent("config-link", isDirectory: true)
        try fm.createSymbolicLink(at: link, withDestinationURL: real)
        let environment = AppEnvironment(
            flavor: .dev, applicationSupportURL: base.appendingPathComponent("support", isDirectory: true),
            configFolderOverride: link)
        let store = ConfigStore(environment: environment, watcher: ManualDirectoryWatcher(), debounce: .zero)
        await store.start()
        defer { store.stop() }

        try await store.set("closed.slots", to: .int(2))

        #expect(try fm.destinationOfSymbolicLink(atPath: link.path) == real.path, "the symlink itself is kept")
        let after = try read(real.appendingPathComponent("config.toml"))
        let changed = try #require(differingLines(Self.multiSection, after))
        #expect(changed.count == 1)
        #expect(after.components(separatedBy: "\n")[changed[0]] == "slots = 2        # three per side")
        // No temp file left next to it, nothing written beside the link.
        #expect(try fm.contentsOfDirectory(atPath: real.path) == ["config.toml"])
        #expect(Set(try fm.contentsOfDirectory(atPath: base.path)) == ["dotfiles", "config-link", "support"])
    }

    @Test func gitStyleDiffOfOneEditIsOneLine() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(config: Self.multiSection)
        defer { store.stop() }
        for (key, value) in [
            ("appearance.mode", ConfigResolvedValue.string("dark")),
            ("general.hide_in_fullscreen", .bool(false)),
        ] {
            let before = try read(fixture.configURL)
            try await store.set(ConfigKeyPath(stringLiteral: key), to: value)
            let changed = try #require(differingLines(before, try read(fixture.configURL)))
            #expect(changed.count == 1, "\(key)")
        }
    }

    @Test func relocatingToASymlinkedCheckoutAdoptsIt() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(config: "[closed]\nslots = 2\n")
        defer { store.stop() }
        let real = root(fixture).appendingPathComponent("repo/vigie", isDirectory: true)
        try write(Self.multiSection, to: real.appendingPathComponent("config.toml"))
        let link = root(fixture).appendingPathComponent("link", isDirectory: true)
        try fm.createSymbolicLink(at: link, withDestinationURL: real)

        #expect(try await store.relocate(to: link) == .adopted)
        try await store.set("closed.slots", to: .int(4))
        let changed = try #require(
            differingLines(Self.multiSection, try read(real.appendingPathComponent("config.toml"))))
        #expect(changed.count == 1)
        #expect(try fm.destinationOfSymbolicLink(atPath: link.path) == real.path)
    }

    // MARK: - Script folder

    @Test func theScriptFolderFollowsARelocationAndRescans() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(config: "[closed]\nslots = 2\n")
        defer { store.stop() }
        try write("y", to: fixture.configFolder.appendingPathComponent("modules/a.md"))
        let factory = CoreModuleContextFactory(
            environment: fixture.environment, eventBus: InProcessEventBus(), configStore: store)
        let tracker = RegistrationTracker()
        let context = factory.makeContext(
            for: ModuleManifest(id: "integrations", name: "Integrations", icon: "puzzlepiece.extension"),
            tracker: tracker)
        let service = context.scriptFolder
        #expect(service.url?.path == fixture.environment.scriptModulesFolderURL.path)
        let changes = StreamCounter(service.changes())
        let target = root(fixture).appendingPathComponent("new", isDirectory: true)

        try await store.relocate(to: target)

        #expect(service.url?.path == target.appendingPathComponent("modules").path)
        #expect(await eventually { changes.count >= 1 })
        #expect(fm.fileExists(atPath: try #require(service.url).appendingPathComponent("a.md").path))
        tracker.cancelAll()
    }

    @Test func aRetargetedScriptWatchWatchesTheNewModulesFolder() async throws {
        let location = ConfigFolderLocation(folder: makeTempDirectory())
        let watcher = ManualDirectoryWatcher()
        let tracker = RegistrationTracker()
        let service = CoreScriptFolder(
            url: nil, builtInModuleIDs: [], tracker: tracker, folderLocation: location, makeWatcher: { watcher })
        let counter = StreamCounter(service.changes())
        let next = makeTempDirectory()
        location.set(next)
        #expect(await eventually { counter.count == 1 })
        #expect(watcher.watchedDirectories == [AppEnvironment.scriptModulesFolderURL(in: next).standardizedFileURL])
        tracker.cancelAll()
    }

    // MARK: - Settings › General › Config folder

    @Test func settingsRowMovesAfterConfirmation() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(config: "[closed]\nslots = 2\n")
        defer { store.stop() }
        let model = ConfigFolderModel(configStore: store)
        let target = root(fixture).appendingPathComponent("chosen", isDirectory: true)
        var startedAt: URL?
        model.chooseFolder = { start in
            startedAt = start
            return target
        }
        var revealed: [URL] = []
        model.reveal = { revealed.append($0) }
        #expect(model.canUseDefault)

        await model.change()
        #expect(startedAt == fixture.configFolder)
        #expect(model.pending?.adopts == false)
        #expect(model.confirmationText == SettingsText.string("settings.configFolder.confirm.move"))
        #expect(model.confirmationText?.contains("config.toml") == true)
        await model.confirm()
        #expect(model.pending == nil)
        #expect(model.error == nil)
        #expect(store.configFolderURL.path == target.path)
        #expect(model.displayPath == target.path)
        model.revealInFinder()
        #expect(revealed.map(\.path) == [target.path])
    }

    @Test func settingsRowExplainsAdoptAndShowsErrorsInline() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(config: "[closed]\nslots = 2\n")
        defer { store.stop() }
        let model = ConfigFolderModel(configStore: store)
        let target = root(fixture).appendingPathComponent("repo", isDirectory: true)
        try write("[closed]\nslots = 3\n", to: target.appendingPathComponent("config.toml"))

        model.chooseFolder = { _ in target }
        await model.change()
        #expect(model.confirmationText == SettingsText.string("settings.configFolder.confirm.adopt"))
        #expect(model.confirmationText?.contains("already has a config.toml") == true)
        model.cancel()
        #expect(model.pending == nil)
        #expect(store.configFolderURL == fixture.configFolder)

        model.chooseFolder = { _ in fixture.support }
        await model.change()
        #expect(model.pending == nil)
        #expect(model.error == ConfigRelocationError.applicationSupport.errorDescription)

        model.chooseFolder = { _ in nil }
        await model.change()
        #expect(model.pending == nil)
    }

    @Test func settingsRowRendersOffscreen() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(config: "[closed]\nslots = 2\n")
        defer { store.stop() }
        let model = ConfigFolderModel(configStore: store)
        model.chooseFolder = { _ in fixture.support }
        await model.change()
        let (window, view) = hostOffscreen(
            Form { ConfigFolderSection(model: model) }.formStyle(.grouped), size: CGSize(width: 560, height: 260))
        defer { window.close() }
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        #expect(rep.pixelsWide > 0)
    }

    @Test func catalogStringsResolve() {
        let keys = [
            "settings.section.configFolder", "settings.configFolder.label", "settings.configFolder.change",
            "settings.configFolder.reveal", "settings.configFolder.useDefault", "settings.configFolder.cancel",
            "settings.configFolder.choose.prompt", "settings.configFolder.confirm.adopt",
            "settings.configFolder.confirm.move", "settings.configFolder.confirm.adoptButton",
            "settings.configFolder.confirm.moveButton", "settings.configFolder.recordMissing",
        ]
        for key in keys { #expect(SettingsText.string(key) != key, "\(key)") }
        let errors: [ConfigRelocationError] = [
            .sameFolder, .insideCurrentFolder, .containsCurrentFolder, .applicationSupport, .notAFolder,
            .notWritable, .conflict("modules"), .moveFailed("x"), .recordFailed("x"),
        ]
        for error in errors {
            let text = error.errorDescription
            #expect(text?.hasPrefix("settings.") == false, "\(error)")
            #expect(text?.contains("%@") == false, "\(error)")
        }
        #expect(String(localized: CoreSettings.label("config.config.folder")) == "Config folder")
    }
}
