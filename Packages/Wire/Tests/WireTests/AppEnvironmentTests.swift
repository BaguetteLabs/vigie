import Foundation
import Testing

@testable import Wire

@Suite(.serialized) struct AppEnvironmentTests {
    let root = URL(fileURLWithPath: "/tmp/vt/Support", isDirectory: true)
    let home = URL(fileURLWithPath: "/tmp/vt/home", isDirectory: true)
    let sockName = "vigie" + "." + "sock"

    func make(_ flavor: AppEnvironment.Flavor, override: URL? = nil) -> AppEnvironment {
        AppEnvironment(
            flavor: flavor, applicationSupportURL: root, configFolderOverride: override,
            homeDirectoryURL: home, tempDirectoryProvider: { nil })
    }

    @Test func releaseValues() {
        let env = make(.release)
        #expect(env.bundleID == "fr.baguettelabs.vigie")
        #expect(env.displayName == "Vigie")
        #expect(env.cliName == "vigie")
        #expect(env.urlScheme == "vigie")
        #expect(env.logSubsystem == env.bundleID)
    }

    @Test func devValues() {
        let env = make(.dev)
        #expect(env.bundleID == "fr.baguettelabs.vigie.dev")
        #expect(env.displayName == "Vigie Dev")
        #expect(env.cliName == "vigie-dev")
        #expect(env.urlScheme == "vigie-dev")
        #expect(env.logSubsystem == "fr.baguettelabs.vigie.dev")
    }

    @Test func defaultApplicationSupportDiffersPerFlavor() {
        let rel = AppEnvironment(flavor: .release).applicationSupportURL
        let dev = AppEnvironment(flavor: .dev).applicationSupportURL
        #expect(rel.lastPathComponent == "Vigie")
        #expect(dev.lastPathComponent == "Vigie Dev")
        #expect(rel.deletingLastPathComponent() == dev.deletingLastPathComponent())
    }

    @Test(arguments: [AppEnvironment.Flavor.release, .dev])
    func allURLsSitUnderRoot(flavor: AppEnvironment.Flavor) {
        let env = make(flavor)
        #expect(env.applicationSupportURL == root)
        #expect(env.socketURL == root.appendingPathComponent(sockName))
        #expect(env.spoolURL == root.appendingPathComponent("spool.jsonl"))
        #expect(env.spoolReplayingURL == root.appendingPathComponent("spool.replaying.jsonl"))
        #expect(env.instanceLockURL == root.appendingPathComponent("instance.lock"))
        #expect(env.localConfigURL == root.appendingPathComponent("local.toml"))
        #expect(env.dropsDirectory == root.appendingPathComponent("drops", isDirectory: true))
    }

    @Test func configFolderDefaultsToReleaseOneForBothFlavors() {
        #expect(make(.release).defaultConfigFolderURL == make(.dev).defaultConfigFolderURL)
        #expect(make(.dev).defaultConfigFolderURL.path.hasSuffix("/home/.config/" + "vi" + "gie"))
        #expect(make(.dev).configFolderURL == make(.dev).defaultConfigFolderURL)
    }

    @Test func configOverrideViaInit() {
        let custom = URL(fileURLWithPath: "/tmp/vt/custom", isDirectory: true)
        let env = make(.dev, override: custom)
        #expect(env.configFolderURL == custom)
        #expect(env.defaultConfigFolderURL == make(.dev).defaultConfigFolderURL)
        // Script modules follow the config folder in effect (SPEC §9.1, Story 12.2).
        #expect(env.scriptModulesFolderURL == custom.appendingPathComponent("modules", isDirectory: true))
    }

    @Test func configOverrideViaEnvironmentVariableInDevOnly() {
        let name = AppEnvironment.configDirVariable
        let previous = getenv(name).map { String(cString: $0) }
        setenv(name, "/tmp/vt/from-env", 1)
        defer {
            if let previous { setenv(name, previous, 1) } else { unsetenv(name) }
        }
        #expect(make(.dev).configFolderURL.path == "/tmp/vt/from-env")
        #expect(make(.release).configFolderOverride == nil)
        let explicit = URL(fileURLWithPath: "/tmp/vt/explicit", isDirectory: true)
        #expect(make(.dev, override: explicit).configFolderURL == explicit)
    }

    // MARK: - Config folder record (Story 16.1)

    /// A temp support folder holding `local.toml` with `text`, and a temp home.
    func recordFixture(_ text: String?) throws -> (support: URL, home: URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "vigie-env-\(UUID().uuidString)", isDirectory: true)
        let support = base.appendingPathComponent("Support", isDirectory: true)
        let home = base.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        if let text {
            try text.write(to: support.appendingPathComponent("local.toml"), atomically: true, encoding: .utf8)
        }
        return (support, home)
    }

    func makeRecorded(_ support: URL, _ home: URL) -> AppEnvironment {
        AppEnvironment(
            flavor: .release, applicationSupportURL: support, homeDirectoryURL: home, tempDirectoryProvider: { nil })
    }

    @Test func recordedFolderInLocalTOMLIsUsedAtLaunch() throws {
        let (support, home) = try recordFixture(
            "# header\n[display]\ndisplay = \"main\"\n\n[config]\nfolder = \"~/dotfiles/vigie\"\n")
        let folder = home.appendingPathComponent("dotfiles/vigie", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let env = makeRecorded(support, home)
        #expect(env.configFolderURL.standardizedFileURL == folder.standardizedFileURL)
        #expect(env.configFolderSource == .localRecord)
        #expect(env.configFolderRecordProblem == nil)
        #expect(env.scriptModulesFolderURL.standardizedFileURL.path == folder.appendingPathComponent("modules").path)
        #expect(env.abbreviatingHome(folder) == "~/dotfiles/vigie")
    }

    @Test func missingRecordedFolderFallsBackToDefaultWithAProblem() throws {
        let (support, home) = try recordFixture("[config]\nfolder = \"/nonexistent/vigie-\(UUID().uuidString)\"\n")
        let env = makeRecorded(support, home)
        #expect(env.configFolderURL == env.defaultConfigFolderURL)
        #expect(env.configFolderSource == .defaultFolder)
        #expect(env.configFolderRecordProblem?.contains("missing") == true)
    }

    @Test func relativeRecordedPathIsAProblem() throws {
        let (support, home) = try recordFixture("[config]\nfolder = \"dotfiles\"\n")
        let env = makeRecorded(support, home)
        #expect(env.configFolderURL == env.defaultConfigFolderURL)
        #expect(env.configFolderRecordProblem != nil)
    }

    @Test func noRecordMeansDefault() throws {
        for text in [nil, "", "[config]\nfolder = \"\"\n", "[other]\nfolder = \"/tmp\"\n"] {
            let (support, home) = try recordFixture(text)
            let env = makeRecorded(support, home)
            #expect(env.configFolderSource == .defaultFolder)
            #expect(env.configFolderRecordProblem == nil)
        }
    }

    @Test func explicitOverrideWinsOverTheRecord() throws {
        let (support, home) = try recordFixture("[config]\nfolder = \"~\"\n")
        let explicit = URL(fileURLWithPath: "/tmp/vt/explicit", isDirectory: true)
        let env = AppEnvironment(
            flavor: .release, applicationSupportURL: support, configFolderOverride: explicit, homeDirectoryURL: home)
        #expect(env.configFolderURL == explicit)
        #expect(env.configFolderSource == .explicitOverride)
    }

    @Test func recordParserReadsTheTwoStringForms() {
        #expect(AppEnvironment.configFolderRecord(inLocalTOML: "[config]\nfolder = '/a b/c' # x\n") == "/a b/c")
        #expect(AppEnvironment.configFolderRecord(inLocalTOML: "[ config ]\n  folder=\"/a\\\\b\\\"c\"\n") == "/a\\b\"c")
        #expect(AppEnvironment.configFolderRecord(inLocalTOML: "config.folder = \"/root\"\n") == "/root")
        #expect(AppEnvironment.configFolderRecord(inLocalTOML: "[config.sub]\nfolder = \"/no\"\n") == nil)
        #expect(AppEnvironment.configFolderRecord(inLocalTOML: "[config]\nfolder = 3\n") == nil)
    }

    @Test func socketStaysInApplicationSupportAtLimit() {
        // Build a root whose socket path is exactly 100 bytes.
        let suffix = "/" + sockName
        let base = "/" + String(repeating: "a", count: 100 - suffix.utf8.count - 1)
        let url = URL(fileURLWithPath: base, isDirectory: true)
        let socket = AppEnvironment.socketURL(
            applicationSupportURL: url, bundleID: "x.y", tempDirectory: { URL(fileURLWithPath: "/fake/") })
        #expect(socket.path.utf8.count == 100)
        #expect(socket.deletingLastPathComponent().path == base)
    }

    @Test func socketFallsBackToDarwinTempDirAboveLimit() {
        let long = URL(fileURLWithPath: "/" + String(repeating: "a", count: 101), isDirectory: true)
        let socket = AppEnvironment.socketURL(
            applicationSupportURL: long, bundleID: "fr.baguettelabs.vigie.dev",
            tempDirectory: { URL(fileURLWithPath: "/fake/T/", isDirectory: true) })
        #expect(socket.path == "/fake/T/fr.baguettelabs.vigie.dev/" + sockName)
    }

    @Test func environmentUsesFallbackWhenRootIsLong() {
        let long = URL(fileURLWithPath: "/" + String(repeating: "b", count: 120), isDirectory: true)
        let env = AppEnvironment(
            flavor: .dev, applicationSupportURL: long, configFolderOverride: nil,
            homeDirectoryURL: home, tempDirectoryProvider: { URL(fileURLWithPath: "/fake/T/") })
        #expect(env.socketURL.path == "/fake/T/fr.baguettelabs.vigie.dev/" + sockName)
        #expect(env.spoolURL.deletingLastPathComponent() == long)
    }

    @Test func darwinTempDirectoryComesFromConfstr() {
        let url = AppEnvironment.darwinUserTempDirectory()
        #expect(url != nil)
        #expect(url?.path.hasPrefix("/var/folders/") == true || url?.path.hasPrefix("/private/var/folders/") == true)
    }

    @Test func currentMatchesCompileFlag() {
        #if VIGIE_DEV
            #expect(AppEnvironment.current.bundleID == "fr.baguettelabs.vigie.dev")
        #else
            #expect(AppEnvironment.current.bundleID == "fr.baguettelabs.vigie")
        #endif
    }

    @Test func iCloudLocationsForReleaseAndDev() throws {
        let release = make(.release)
        let drive = "/tmp/vt/home/Library/" + "Mobile" + " Documents/com~apple~CloudDocs"
        #expect(release.iCloudDriveFolderURL.path == drive)
        #expect(release.iCloudSyncRootURL.path == drive + "/Vigie")
        #expect(release.iCloudConfigFolderURL.path == drive + "/Vigie/config")
        #expect(release.iCloudNotesFolderURL.path == drive + "/Vigie/Notes")
        #expect(release.localNotesFolderURL.path == "/tmp/vt/home/Notes/Vigie")
        let dev = make(.dev)
        #expect(dev.iCloudSyncRootURL.path == drive + "/Vigie Dev")
        #expect(dev.iCloudConfigFolderURL.path == drive + "/Vigie Dev/config")
        #expect(dev.iCloudNotesFolderURL.path == drive + "/Vigie Dev/Notes")
        #expect(dev.localNotesFolderURL.path == "/tmp/vt/home/Notes/Vigie Dev")
    }

    @Test func iCloudDriveAvailabilityFollowsTheFolder() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let env = AppEnvironment(
            flavor: .release, applicationSupportURL: root, homeDirectoryURL: home, tempDirectoryProvider: { nil })
        #expect(!env.isICloudDriveAvailable)
        try FileManager.default.createDirectory(
            at: env.iCloudDriveFolderURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: env.iCloudDriveFolderURL)
        #expect(!env.isICloudDriveAvailable)
        try FileManager.default.removeItem(at: env.iCloudDriveFolderURL)
        try FileManager.default.createDirectory(at: env.iCloudDriveFolderURL, withIntermediateDirectories: true)
        #expect(env.isICloudDriveAvailable)
    }
}
