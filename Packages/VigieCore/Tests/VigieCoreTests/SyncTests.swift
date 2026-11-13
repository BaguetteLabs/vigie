import Foundation
import ModuleKit
import SwiftUI
import Synchronization
import Testing
import Wire

@testable import VigieCore

/// A status provider that answers from a table (never the real iCloud Drive).
final class FakeUbiquitousStatus: UbiquitousItemStatusProviding {
    private let state = Mutex<(statuses: [String: UbiquitousItemStatus], downloads: [String])>(([:], []))

    func set(_ url: URL, _ status: UbiquitousItemStatus) {
        state.withLock { $0.statuses[url.standardizedFileURL.path] = status }
    }

    var downloads: [String] { state.withLock { $0.downloads } }

    func status(of url: URL) -> UbiquitousItemStatus {
        state.withLock { $0.statuses[url.standardizedFileURL.path] } ?? .local
    }

    func startDownloading(_ url: URL) {
        state.withLock { $0.downloads.append(url.standardizedFileURL.path) }
    }
}

/// The Notes module's `folder` setting, as Story 15.1 declares it (VigieCore cannot import the module).
let notesFolderManifest = ModuleManifest(
    id: "notes", name: "Notes", icon: "note.text",
    settings: [
        SettingDescriptor(key: "folder", label: "Folder", kind: .path(default: "~/Notes/Vigie"), scope: .local),
        SettingDescriptor(key: "token", label: "Token", kind: .secret),
    ])

/// Story 16.2: the iCloud sync toggle. A temp home with a fake iCloud Drive folder; never the real `~/Library`,
/// `~/Notes` or iCloud Drive.
@MainActor @Suite struct SyncTests {
    let fm = FileManager.default

    struct Harness {
        let environment: AppEnvironment
        let store: ConfigStore
        let watcher: ManualDirectoryWatcher
        let sync: SyncController

        var home: URL { environment.homeDirectoryURL }
        var localNotes: URL { environment.localNotesFolderURL }
        var localConfig: URL { environment.defaultConfigFolderURL }
        var root: URL { environment.iCloudSyncRootURL }
        var iCloudConfig: URL { environment.iCloudConfigFolderURL }
        var iCloudNotes: URL { environment.iCloudNotesFolderURL }
    }

    private func write(_ text: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    /// A started store in a temp home: config in the default folder, notes in `~/Notes/Vigie`, and (unless
    /// `iCloudDrive` is false) an iCloud Drive folder.
    private func harness(
        config: String = "[closed]\nslots = 2\n", notes: [String: String] = ["a.vnote": "A", "notes-key.json": "{}"],
        iCloudDrive: Bool = true, prepare: ((AppEnvironment) throws -> Void)? = nil
    ) async throws -> Harness {
        let base = makeTempDirectory()
        let environment = AppEnvironment(
            flavor: .release, applicationSupportURL: base.appendingPathComponent("support", isDirectory: true),
            homeDirectoryURL: base.appendingPathComponent("home", isDirectory: true))
        try write(config, to: environment.defaultConfigFolderURL.appendingPathComponent("config.toml"))
        try write("x", to: environment.defaultConfigFolderURL.appendingPathComponent("themes/mine.toml"))
        for (name, text) in notes { try write(text, to: environment.localNotesFolderURL.appendingPathComponent(name)) }
        if iCloudDrive {
            try fm.createDirectory(at: environment.iCloudDriveFolderURL, withIntermediateDirectories: true)
        }
        try prepare?(environment)
        let watcher = ManualDirectoryWatcher()
        let store = ConfigStore(
            environment: environment, manifests: [notesFolderManifest], watcher: watcher, debounce: .zero)
        await store.start()
        return Harness(
            environment: environment, store: store, watcher: watcher, sync: SyncController(configStore: store))
    }

    private func localText(_ h: Harness) throws -> String { try read(h.environment.localConfigURL) }

    private func notesRecord(_ h: Harness) -> String? {
        if case .string(let value) = h.store.rawValue(at: SyncController.notesFolderPath, in: .local) { return value }
        return nil
    }

    // MARK: - On and off

    @Test func turningOnMovesBothFoldersAndRecordsThem() async throws {
        let h = try await harness()
        defer { h.store.stop() }
        let slots = StreamCounter(h.store.observe("closed.slots"))
        let folder = StreamCounter(h.store.observe(SyncController.notesFolderPath))
        #expect(!h.sync.isOn)

        let plan = try await h.sync.turnOn()

        #expect(!plan.adoptsConfig && !plan.adoptsNotes)
        #expect(try read(h.iCloudConfig.appendingPathComponent("config.toml")) == "[closed]\nslots = 2\n")
        #expect(try read(h.iCloudConfig.appendingPathComponent("themes/mine.toml")) == "x")
        #expect(try read(h.iCloudNotes.appendingPathComponent("a.vnote")) == "A")
        #expect(fm.fileExists(atPath: h.iCloudNotes.appendingPathComponent("notes-key.json").path))
        #expect(try fm.contentsOfDirectory(atPath: h.localNotes.path).isEmpty)
        #expect(try fm.contentsOfDirectory(atPath: h.localConfig.path).isEmpty)
        // Both locations recorded in local.toml (home abbreviated), sync on, still running from the new folder.
        let drive = "~/Library/" + "Mobile" + " Documents/com~apple~CloudDocs/Vigie"
        #expect(AppEnvironment.configFolderRecord(inLocalTOML: try localText(h)) == drive + "/config")
        #expect(notesRecord(h) == drive + "/Notes")
        #expect(h.store.value(SyncController.notesFolderPath, as: String.self) == drive + "/Notes")
        #expect(h.store.value(SyncController.icloudPath, as: Bool.self) == true)
        #expect(h.sync.isOn)
        #expect(h.store.configFolderURL.path == h.iCloudConfig.path)
        #expect(h.store.value("closed.slots", as: Int.self) == 2)
        // The Notes module hears about `folder`; config values did not change.
        #expect(await eventually { folder.count >= 1 })
        try await Task.sleep(for: .milliseconds(50))
        #expect(slots.count == 0)
        // Writes keep working in the new folder, without a restart.
        try await h.store.set("closed.slots", to: .int(3))
        #expect(try read(h.iCloudConfig.appendingPathComponent("config.toml")).contains("slots = 3"))
    }

    @Test func turningOffMovesBothBackAndRemovesTheRecords() async throws {
        let h = try await harness()
        defer { h.store.stop() }
        try await h.sync.turnOn()

        let plan = try await h.sync.turnOff()

        #expect(!plan.turnsOn)
        #expect(try read(h.localConfig.appendingPathComponent("config.toml")) == "[closed]\nslots = 2\n")
        #expect(try read(h.localNotes.appendingPathComponent("a.vnote")) == "A")
        #expect(!fm.fileExists(atPath: h.iCloudConfig.appendingPathComponent("config.toml").path))
        #expect(try fm.contentsOfDirectory(atPath: h.iCloudNotes.path).isEmpty)
        #expect(AppEnvironment.configFolderRecord(inLocalTOML: try localText(h)) == nil)
        #expect(notesRecord(h) == nil)
        #expect(h.store.value(SyncController.notesFolderPath, as: String.self) == "~/Notes/Vigie")
        #expect(h.store.value(SyncController.icloudPath, as: Bool.self) == false)
        #expect(h.store.isUsingDefaultFolder)
    }

    @Test func turningOffWaitsForDatalessFiles() async throws {
        let h = try await harness()
        defer { h.store.stop() }
        try await h.sync.turnOn()
        let status = FakeUbiquitousStatus()
        h.store.fileReader = CoordinatedFileReader(status: status)
        status.set(h.iCloudNotes.appendingPathComponent("a.vnote"), .notDownloaded)

        await #expect(throws: SyncError.notes(.downloadsPending(1))) { try await h.sync.turnOff() }

        #expect(status.downloads.contains(h.iCloudNotes.appendingPathComponent("a.vnote").standardizedFileURL.path))
        // Rolled back: config is in iCloud again and sync stays on.
        #expect(h.store.configFolderURL.path == h.iCloudConfig.path)
        #expect(h.sync.isOn)
        #expect(fm.fileExists(atPath: h.iCloudNotes.appendingPathComponent("a.vnote").path))
    }

    @Test func unavailableICloudDriveIsRefusedAndNothingMoves() async throws {
        let h = try await harness(iCloudDrive: false)
        defer { h.store.stop() }
        let model = SyncPaneModel(controller: h.sync)
        #expect(model.status == .unavailable)
        #expect(!model.canToggle)

        await #expect(throws: SyncError.iCloudDriveUnavailable) { try await h.sync.turnOn() }

        #expect(fm.fileExists(atPath: h.localConfig.appendingPathComponent("config.toml").path))
        #expect(fm.fileExists(atPath: h.localNotes.appendingPathComponent("a.vnote").path))
        #expect(!fm.fileExists(atPath: h.root.path))
        #expect(AppEnvironment.configFolderRecord(inLocalTOML: try localText(h)) == nil)
        #expect(notesRecord(h) == nil)
        #expect(!h.sync.isOn)
        #expect(SyncError.iCloudDriveUnavailable.errorDescription?.contains("iCloud Drive is off") == true)
    }

    @Test func secondMacAdoptsWhatIsAlreadyInICloud() async throws {
        let h = try await harness(notes: ["mine.vnote": "M"]) { environment in
            try self.write(
                "[closed]\nslots = 4\n", to: environment.iCloudConfigFolderURL.appendingPathComponent("config.toml"))
            try self.write("T", to: environment.iCloudNotesFolderURL.appendingPathComponent("theirs.vnote"))
        }
        defer { h.store.stop() }
        let slots = StreamCounter(h.store.observe("closed.slots"))

        let plan = try await h.sync.turnOn()

        #expect(plan.adoptsConfig && plan.adoptsNotes)
        #expect(h.store.value("closed.slots", as: Int.self) == 4)
        #expect(await eventually { slots.count >= 1 })
        // This Mac's own folders are left untouched; iCloud's are not overwritten.
        #expect(try read(h.localConfig.appendingPathComponent("config.toml")) == "[closed]\nslots = 2\n")
        #expect(try read(h.localNotes.appendingPathComponent("mine.vnote")) == "M")
        #expect(!fm.fileExists(atPath: h.iCloudNotes.appendingPathComponent("mine.vnote").path))
        #expect(try read(h.iCloudConfig.appendingPathComponent("config.toml")) == "[closed]\nslots = 4\n")
        #expect(notesRecord(h)?.hasSuffix("/Vigie/Notes") == true)
        #expect(h.sync.isOn)
    }

    @Test func aFailingNotesMoveRollsTheConfigBack() async throws {
        let h = try await harness()
        defer { h.store.stop() }
        let notesFolder = h.localNotes.path
        h.store.relocationFileSystem = ConfigRelocationFileSystem(
            copy: { from, to in
                if from.path.hasPrefix(notesFolder) { throw CocoaError(.fileWriteNoPermission) }
                try FileManager.default.copyItem(at: from, to: to)
            },
            remove: { try FileManager.default.removeItem(at: $0) })

        await #expect {
            try await h.sync.turnOn()
        } throws: { error in
            guard case SyncError.notes(.moveFailed) = error else { return false }
            return true
        }

        #expect(h.store.isUsingDefaultFolder)
        #expect(try read(h.localConfig.appendingPathComponent("config.toml")) == "[closed]\nslots = 2\n")
        #expect(try read(h.localConfig.appendingPathComponent("themes/mine.toml")) == "x")
        #expect(!fm.fileExists(atPath: h.iCloudConfig.appendingPathComponent("config.toml").path))
        #expect(!fm.fileExists(atPath: h.iCloudNotes.appendingPathComponent("a.vnote").path))
        #expect(try read(h.localNotes.appendingPathComponent("a.vnote")) == "A")
        #expect(AppEnvironment.configFolderRecord(inLocalTOML: try localText(h)) == nil)
        #expect(notesRecord(h) == nil)
        #expect(!h.sync.isOn)
    }

    @Test func aMissingNotesFolderIsOnlyRecorded() async throws {
        let h = try await harness(notes: [:])
        defer { h.store.stop() }
        try await h.sync.turnOn()
        #expect(notesRecord(h)?.hasSuffix("/Vigie/Notes") == true)
        #expect(!fm.fileExists(atPath: h.localNotes.path))
        #expect(h.sync.isOn)
    }

    // MARK: - No secrets, no local settings

    @Test func syncedFilesHoldNoLocalSettingsAndNoSecrets() async throws {
        let h = try await harness()
        defer { h.store.stop() }
        // Every `.local` core key set on this Mac (except the two that sync itself manages).
        let managed: Set<ConfigKeyPath> = [ConfigStore.folderRecordPath, SyncController.icloudPath]
        let localKeys = CoreSettings.all.filter { $0.descriptor.scope == .local && !managed.contains($0.path) }
        #expect(!localKeys.isEmpty)
        for setting in localKeys {
            let value = try #require(h.store.resolvedValue(setting.path))
            try await h.store.set(setting.path, to: value)
        }
        // A secret setting is refused by ConfigStore (Keychain only, AD-9).
        let secret = "s3cr3t-token-value"
        let secretPath = ConfigKeyPath.module("notes", "token")
        await #expect(throws: ConfigError.secretKey(secretPath.description)) {
            try await h.store.set(secretPath, to: .string(secret))
        }

        try await h.sync.turnOn()

        let synced = try ConfigDocument.parse(read(h.iCloudConfig.appendingPathComponent("config.toml")))
        for setting in localKeys + [
            CoreSetting(path: SyncController.notesFolderPath, descriptor: notesFolderManifest.settings[0])
        ] {
            #expect(synced.value(at: setting.path) == nil, "\(setting.path)")
        }
        #expect(synced.value(at: ConfigStore.folderRecordPath) == nil)
        #expect(synced.value(at: SyncController.icloudPath) == nil)
        // Nothing under the iCloud root holds the secret, a local.toml, or a `.local` table.
        let walker = try #require(fm.enumerator(at: h.root, includingPropertiesForKeys: nil))
        while let url = walker.nextObject() as? URL {
            #expect(url.lastPathComponent != "local.toml")
            if let text = try? read(url) {
                #expect(!text.contains(secret))
                #expect(!text.contains("[display]") && !text.contains("[virtual_notch]") && !text.contains("[privacy]"))
            }
        }
        let rootPath = h.root.standardizedFileURL.path + "/"
        #expect(!h.store.localURL.standardizedFileURL.path.hasPrefix(rootPath))
        #expect(!h.environment.localConfigURL.standardizedFileURL.path.hasPrefix(rootPath))
        // The local values are still in effect, from local.toml.
        let local = try ConfigDocument.parse(localText(h))
        for setting in localKeys { #expect(local.value(at: setting.path) != nil, "\(setting.path)") }
    }

    // MARK: - Dataless reads

    @Test func coordinatedReaderDownloadsDatalessFilesAndReadsLocalOnes() async throws {
        let folder = makeTempDirectory()
        let file = folder.appendingPathComponent("config.toml")
        try write("a = 1\n", to: file)
        let status = FakeUbiquitousStatus()
        let reader = CoordinatedFileReader(status: status)

        status.set(file, .notDownloaded)
        #expect(try await reader.read(file) == nil)
        #expect(await reader.readResult(file) == .pending)
        #expect(status.downloads.count == 2)
        #expect(status.downloads.allSatisfy { $0 == file.standardizedFileURL.path })

        status.set(file, .downloaded)
        #expect(try await reader.read(file) == Data("a = 1\n".utf8))
        status.set(file, .local)
        #expect(await reader.readResult(file) == .data(Data("a = 1\n".utf8)))
        #expect(await reader.readResult(folder.appendingPathComponent("missing.toml")) == .missing)
        await #expect(throws: CocoaError.self) { try await reader.read(folder.appendingPathComponent("missing.toml")) }
        #expect(status.downloads.count == 2)
    }

    @Test func systemStatusTreatsAnOldPlaceholderAsDataless() throws {
        let folder = makeTempDirectory()
        try write("", to: folder.appendingPathComponent(".config.toml.icloud"))
        #expect(SystemUbiquitousItemStatus().status(of: folder.appendingPathComponent("config.toml")) == .notDownloaded)
        try write("a = 1\n", to: folder.appendingPathComponent("plain.toml"))
        #expect(SystemUbiquitousItemStatus().status(of: folder.appendingPathComponent("plain.toml")) == .local)
    }

    @Test func configStoreKeepsTheLastValuesWhileADownloadIsPending() async throws {
        let fixture = ConfigFixture()
        let (store, watcher) = try await fixture.makeStore(config: "[closed]\nslots = 2\n")
        defer { store.stop() }
        let status = FakeUbiquitousStatus()
        store.fileReader = CoordinatedFileReader(status: status)
        store.pendingRetryInterval = .seconds(60)
        let slots = StreamCounter(store.observe("closed.slots"))

        // A newer version arrives as a dataless file: not read, a download is requested, values stay.
        try fixture.writeConfig("[closed]\nslots = 3\n")
        status.set(fixture.configURL, .notDownloaded)
        await store.fireAndSettle(watcher)
        #expect(store.value("closed.slots", as: Int.self) == 2)
        #expect(store.problems.isEmpty)
        #expect(status.downloads.contains(fixture.configURL.standardizedFileURL.path))
        #expect(slots.count == 0)

        // The download lands: the watcher's reload applies it.
        status.set(fixture.configURL, .downloaded)
        await store.fireAndSettle(watcher)
        #expect(store.value("closed.slots", as: Int.self) == 3)
        #expect(await eventually { slots.count == 1 })
    }

    @Test func aPendingDownloadIsRetriedWithoutAWatcherEvent() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(config: "[closed]\nslots = 2\n")
        defer { store.stop() }
        let status = FakeUbiquitousStatus()
        store.fileReader = CoordinatedFileReader(status: status)
        store.pendingRetryInterval = .milliseconds(20)
        try fixture.writeConfig("[closed]\nslots = 4\n")
        status.set(fixture.configURL, .notDownloaded)
        await store.reload()
        #expect(store.value("closed.slots", as: Int.self) == 2)
        status.set(fixture.configURL, .downloaded)
        #expect(await eventually { store.value("closed.slots", as: Int.self) == 4 })
    }

    // MARK: - Settings › Sync

    @Test func paneConfirmsBeforeTurningOnAndOff() async throws {
        let h = try await harness()
        defer { h.store.stop() }
        let model = SyncPaneModel(controller: h.sync)
        var revealed: [URL] = []
        model.reveal = { revealed.append($0) }
        #expect(model.status == .off)
        #expect(model.statusText == SettingsText.string("settings.sync.status.off"))

        model.request(true)
        #expect(model.pending?.turnsOn == true)
        #expect(model.confirmationText == SettingsText.string("settings.sync.confirm.on"))
        #expect(model.confirmationText?.contains("iCloud Drive › Vigie") == true)
        #expect(!h.sync.isOn)
        model.cancel()
        #expect(model.pending == nil)

        model.request(true)
        await model.confirm()
        #expect(model.error == nil)
        #expect(h.sync.isOn)
        let drive = "~/Library/" + "Mobile" + " Documents/com~apple~CloudDocs/Vigie"
        #expect(model.status == .on(drive))
        #expect(model.statusText == "ON · " + drive)
        model.revealInFinder()
        #expect(revealed.map(\.path) == [h.root.path])

        model.request(false)
        #expect(model.confirmationText == SettingsText.string("settings.sync.confirm.off"))
        #expect(model.confirmationText?.contains("back to this Mac") == true)
        await model.confirm()
        #expect(!h.sync.isOn)
        #expect(model.status == .off)
    }

    @Test func paneShowsAdoptAndErrorsInline() async throws {
        let h = try await harness { environment in
            try self.write(
                "[closed]\nslots = 4\n", to: environment.iCloudConfigFolderURL.appendingPathComponent("config.toml"))
        }
        defer { h.store.stop() }
        let model = SyncPaneModel(controller: h.sync)
        model.request(true)
        #expect(model.confirmationText?.hasSuffix(SettingsText.string("settings.sync.confirm.adopt")) == true)
        // iCloud Drive turned off meanwhile: the confirmation fails inline, nothing moves.
        try fm.removeItem(at: h.environment.iCloudDriveFolderURL)
        await model.confirm()
        #expect(model.error == SyncError.iCloudDriveUnavailable.errorDescription)
        #expect(model.status == .unavailable)
        #expect(!h.sync.isOn)
    }

    @Test func paneRendersInAllThreeStates() async throws {
        let on = try await harness()
        defer { on.store.stop() }
        try await on.sync.turnOn()
        let off = try await harness()
        defer { off.store.stop() }
        let unavailable = try await harness(iCloudDrive: false)
        defer { unavailable.store.stop() }
        for (name, h) in [("on", on), ("off", off), ("unavailable", unavailable)] {
            let model = SyncPaneModel(controller: h.sync)
            if name == "off" { model.request(true) }
            let (window, view) = hostOffscreen(
                Form { SyncSection(model: model) }.formStyle(.grouped), size: CGSize(width: 560, height: 300))
            defer { window.close() }
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            #expect(rep.pixelsWide > 0, "\(name)")
            if let dir = ProcessInfo.processInfo.environment["VIGIE_SETTINGS_SNAPSHOT_DIR"],
                let png = rep.representation(using: .png, properties: [:])
            {
                try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("settings-sync-\(name).png"))
            }
        }
    }

    @Test func syncCatalogKeysResolve() {
        let keys = [
            "settings.sync.status.off", "settings.sync.status.on", "settings.sync.status.unavailable",
            "settings.sync.confirm.on", "settings.sync.confirm.adopt", "settings.sync.confirm.off",
            "settings.sync.confirm.onButton", "settings.sync.confirm.offButton", "settings.sync.cancel",
            "settings.sync.reveal", "settings.sync.note", "settings.sync.error.unavailable",
            "settings.sync.error.config", "settings.sync.error.notes", "settings.sync.error.record",
            "settings.userFolder.error.sameFolder", "settings.userFolder.error.insideCurrent",
            "settings.userFolder.error.containsCurrent", "settings.userFolder.error.notAFolder",
            "settings.userFolder.error.notWritable", "settings.userFolder.error.downloadsPending",
            "settings.userFolder.error.moveFailed", "settings.userFolder.error.recordFailed",
        ]
        for key in keys { #expect(SettingsText.string(key) != key, "\(key)") }
        #expect(SettingsText.string("settings.sync.status.unavailable") == "UNAVAILABLE · iCloud Drive is off")
        #expect(SyncError.notes(.downloadsPending(2)).errorDescription?.contains("2 files") == true)
        #expect(SyncError.config(.notWritable).errorDescription?.hasPrefix("Config folder: ") == true)
    }
}
