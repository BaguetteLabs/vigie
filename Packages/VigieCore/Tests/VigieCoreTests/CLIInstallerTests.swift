import Darwin
import Foundation
import Testing
import Wire

@testable import VigieCore

@Suite struct CLIInstallerTests {
    /// A temp home plus a fake app bundle holding an executable `Contents/Helpers/vigie-dev`.
    struct Fixture {
        let root: URL
        var home: URL { root.appendingPathComponent("home", isDirectory: true) }

        init() throws {
            root = makeTempDirectory()
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        }

        func makeApp(_ name: String) throws -> URL {
            let helpers = root.appendingPathComponent("\(name)/Vigie Dev.app/Contents/Helpers", isDirectory: true)
            try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
            let cli = helpers.appendingPathComponent("vigie-dev")
            FileManager.default.createFile(
                atPath: cli.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
            return cli
        }

        func installer(_ cli: URL) -> CLIInstaller {
            CLIInstaller(environment: makeEnvironment(root), bundledCLIURL: cli, homeDirectory: home)
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func installsLinkAndCreatesBinDirectory() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let cli = try fixture.makeApp("Applications")
        let installer = fixture.installer(cli)
        #expect(installer.linkURL.path == fixture.home.path + "/.local/bin/vigie-dev")
        #expect(await installer.diagnose() == .missing(link: installer.linkURL))

        #expect(await installer.install() == .installed)
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: installer.linkURL.path)
        #expect(destination == cli.standardizedFileURL.path)
        let attributes = try FileManager.default.attributesOfItem(atPath: installer.binDirectory.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o755)
        #expect(await installer.diagnose() == .current(link: installer.linkURL))
    }

    @Test func secondRunIsAlreadyCurrent() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let installer = fixture.installer(try fixture.makeApp("Applications"))
        #expect(await installer.install() == .installed)
        #expect(await installer.install() == .alreadyCurrent)
    }

    @Test func repairsLinkAfterAppMoved() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let old = try fixture.makeApp("Downloads")
        #expect(await fixture.installer(old).install() == .installed)
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("Downloads"))

        let moved = try fixture.makeApp("Applications")
        let installer = fixture.installer(moved)
        #expect(await installer.diagnose() == .stale(link: installer.linkURL, target: old.standardizedFileURL))
        #expect(await installer.install() == .repaired(from: old.standardizedFileURL))
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: installer.linkURL.path)
        #expect(destination == moved.standardizedFileURL.path)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: installer.binDirectory.path)
        #expect(leftovers == ["vigie-dev"])
    }

    @Test func refusesToClobberRegularFile() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let installer = fixture.installer(try fixture.makeApp("Applications"))
        try FileManager.default.createDirectory(at: installer.binDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: installer.linkURL.path, contents: Data("mine".utf8))

        #expect(await installer.install() == .skippedConflict(existing: installer.linkURL))
        #expect(try Data(contentsOf: installer.linkURL) == Data("mine".utf8))
        #expect(await installer.diagnose() == .conflict(existing: installer.linkURL))
    }

    @Test func refusesToClobberForeignSymlink() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let installer = fixture.installer(try fixture.makeApp("Applications"))
        try FileManager.default.createDirectory(at: installer.binDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: installer.linkURL.path, withDestinationPath: "/usr/bin/true")

        #expect(await installer.install() == .skippedConflict(existing: installer.linkURL))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: installer.linkURL.path) == "/usr/bin/true")
    }

    @Test func replacesDanglingForeignSymlink() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let cli = try fixture.makeApp("Applications")
        let installer = fixture.installer(cli)
        try FileManager.default.createDirectory(at: installer.binDirectory, withIntermediateDirectories: true)
        let gone = fixture.root.appendingPathComponent("gone/vigie-dev")
        try FileManager.default.createSymbolicLink(atPath: installer.linkURL.path, withDestinationPath: gone.path)

        #expect(await installer.diagnose() == .stale(link: installer.linkURL, target: gone.standardizedFileURL))
        #expect(await installer.install() == .repaired(from: gone.standardizedFileURL))
        #expect(
            try FileManager.default.destinationOfSymbolicLink(atPath: installer.linkURL.path)
                == cli.standardizedFileURL.path)
    }

    @Test func failsWhenBundledCLIIsMissing() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let missing = fixture.root.appendingPathComponent("Nope.app/Contents/Helpers/vigie-dev")
        let installer = fixture.installer(missing)
        #expect(await installer.install() == .failed(.bundledCLIMissing(missing.standardizedFileURL)))
        #expect(!FileManager.default.fileExists(atPath: installer.linkURL.path))
    }

    @Test func pathHintOnlyWhenBinDirectoryIsMissingFromPath() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let installer = fixture.installer(fixture.root.appendingPathComponent("x"))
        let bin = installer.binDirectory.path
        #expect(installer.pathHint(loginShellPath: "/usr/bin:\(bin):/bin") == nil)
        #expect(installer.pathHint(loginShellPath: "/usr/bin:\(bin)/") == nil)
        #expect(installer.pathHint(loginShellPath: "$HOME/.local/bin:/bin") == nil)
        #expect(installer.pathHint(loginShellPath: nil) == nil)
        let hint = try #require(installer.pathHint(loginShellPath: "/usr/bin:/bin:/opt/homebrew/bin"))
        #expect(hint.binDirectory == installer.binDirectory)
        #expect(hint.exportLine.contains(".local/bin"))
        #expect(installer.pathHint(loginShellPath: "") != nil)
    }

    @Test func bundledCLIURLLooksInHelpers() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let cli = try fixture.makeApp("Applications")
        let bundle = try #require(
            Bundle(url: cli.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()))
        #expect(CLIInstaller.bundledCLIURL(in: bundle, cliName: "vigie-dev")?.path == cli.path)
        #expect(CLIInstaller.bundledCLIURL(in: bundle, cliName: "vigie") == nil)
    }
}

@Suite struct SecondInstanceTests {
    @MainActor @Test func sendsAppExpandThenTerminates() async throws {
        let root = URL(fileURLWithPath: "/tmp/vsi-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = AppEnvironment(flavor: .dev, applicationSupportURL: root, configFolderOverride: root)
        let path = environment.socketURL.path
        #expect(path.hasPrefix(root.path))
        let listener = try listen(at: path)
        defer { close(listener) }

        let terminated = Counter()
        let sent = await SecondInstance.notifyRunningInstanceAndQuit(
            environment: environment, terminate: { terminated.increment() }
        ).value
        #expect(sent)
        #expect(terminated.count == 1)

        let client = accept(listener, nil, nil)
        #expect(client >= 0)
        defer { close(client) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while true {
            let count = read(client, &buffer, buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer[0..<count])
        }
        let envelope = try Envelope.decodeLine(data)
        #expect(envelope.topic == Topic.appExpand)
        #expect(envelope.payload == .object([:]))
    }

    @MainActor @Test func terminatesWithoutSpoolingWhenNoInstanceListens() async throws {
        let root = URL(fileURLWithPath: "/tmp/vsi-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = AppEnvironment(flavor: .dev, applicationSupportURL: root, configFolderOverride: root)
        let terminated = Counter()
        let sent = await SecondInstance.notifyRunningInstanceAndQuit(
            environment: environment, terminate: { terminated.increment() }
        ).value
        #expect(!sent)
        #expect(terminated.count == 1)
        #expect(!FileManager.default.fileExists(atPath: environment.spoolURL.path))
    }

    private func listen(at path: String) throws -> Int32 {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8) + [0]) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, Darwin.listen(fd, 4) == 0 else {
            close(fd)
            throw POSIXError(.EADDRINUSE)
        }
        return fd
    }
}
