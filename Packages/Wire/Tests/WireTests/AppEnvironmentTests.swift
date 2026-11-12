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
        #expect(env.logSubsystem == env.bundleID)
    }

    @Test func devValues() {
        let env = make(.dev)
        #expect(env.bundleID == "fr.baguettelabs.vigie.dev")
        #expect(env.displayName == "Vigie Dev")
        #expect(env.cliName == "vigie-dev")
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
}
