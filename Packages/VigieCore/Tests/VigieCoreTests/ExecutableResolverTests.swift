import Foundation
import ModuleKit
import Synchronization
import Testing

@testable import VigieCore

/// Records calls; answers with `output`, throws, or waits until cancelled.
final class FakeShell: ShellRunner {
    enum Behavior: Sendable {
        case output(String)
        case fail
        case hang
    }

    private let behavior: Behavior
    private let state = Mutex<(calls: [String], cancelled: Int)>(([], 0))

    init(_ behavior: Behavior) { self.behavior = behavior }

    var calls: [String] { state.withLock { $0.calls } }
    var cancelled: Int { state.withLock { $0.cancelled } }

    func run(executablePath: String, arguments: [String]) async throws -> String {
        state.withLock { $0.calls.append(executablePath) }
        switch behavior {
        case .output(let text):
            return text
        case .fail:
            throw ShellRunnerError.exited(status: 1)
        case .hang:
            do {
                try await Task.sleep(for: .seconds(3600))
            } catch {
                state.withLock { $0.cancelled += 1 }
                throw error
            }
            return ""
        }
    }
}

private func wrapped(_ path: String) -> String {
    "Last login: banner\n" + ExecutableResolverImpl.startMarker + path + ExecutableResolverImpl.endMarker
}

private func makeResolver(
    shell: FakeShell,
    environment: [String: String] = ["SHELL": "/bin/zsh", "PATH": "/usr/bin:/bin", "HOME": "/Users/test"],
    timeout: Duration = .seconds(2),
    overrides: @escaping @Sendable () -> [String: String] = { [:] }
) -> ExecutableResolverImpl {
    ExecutableResolverImpl(
        environment: environment, shellRunner: shell, timeout: timeout, overrides: overrides, log: testLogger)
}

@Suite struct ExecutableResolverTests {
    @Test func capturesLoginShellPath() async {
        let shell = FakeShell(.output(wrapped("/opt/homebrew/bin:/nonexistent:relative::/bin:/bin")))
        let resolver = makeResolver(shell: shell)
        #expect(await resolver.searchPath == ["/opt/homebrew/bin", "/nonexistent", "/bin"])
        #expect(await resolver.searchPathSource == .loginShell)
        #expect(shell.calls == ["/bin/zsh"])
    }

    @Test func resolvesRealExecutableFromCapturedPath() async {
        let resolver = makeResolver(shell: FakeShell(.output(wrapped("/nonexistent:/bin"))))
        #expect(await resolver.resolve("ls") == URL(fileURLWithPath: "/bin/ls"))
        #expect(await resolver.resolve("vigie-no-such-tool") == nil)
        #expect(await resolver.resolve("") == nil)
    }

    @Test func absolutePathsPassThroughAndRelativePathsDoNot() async {
        let resolver = makeResolver(shell: FakeShell(.output(wrapped("/bin"))))
        #expect(await resolver.resolve("/bin/ls") == URL(fileURLWithPath: "/bin/ls"))
        #expect(await resolver.resolve("/bin") == nil)  // a directory
        #expect(await resolver.resolve("bin/ls") == nil)
        #expect(await resolver.resolve("./ls") == nil)
    }

    @Test func overridesWin() async {
        let resolver = makeResolver(shell: FakeShell(.output(wrapped("/bin")))) {
            ["ls": "/usr/bin/true", "home": "~/nothing-here", "cat": "relative/cat"]
        }
        #expect(await resolver.resolve("ls") == URL(fileURLWithPath: "/usr/bin/true"))
        // An unusable override falls back to the PATH.
        #expect(await resolver.resolve("cat") == URL(fileURLWithPath: "/bin/cat"))
        #expect(await resolver.resolve("home") == nil)
    }

    @Test func overridesAreReadOnEachResolve() async {
        let table = Mutex<[String: String]>([:])
        let resolver = makeResolver(shell: FakeShell(.output(wrapped("/bin")))) { table.withLock { $0 } }
        #expect(await resolver.resolve("ls") == URL(fileURLWithPath: "/bin/ls"))
        table.withLock { $0 = ["ls": "/usr/bin/true"] }
        #expect(await resolver.resolve("ls") == URL(fileURLWithPath: "/usr/bin/true"))
    }

    @Test func overrideExpandsTilde() async throws {
        let home = makeTempDirectory()
        let tool = home.appendingPathComponent("tool")
        try Data("#!/bin/sh\n".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let resolver = makeResolver(
            shell: FakeShell(.output(wrapped("/bin"))), environment: ["SHELL": "/bin/zsh", "HOME": home.path]
        ) { ["tool": "~/tool"] }
        #expect(await resolver.resolve("tool")?.path == tool.path)
    }

    @Test func capturesOnceAcrossManyResolves() async {
        let shell = FakeShell(.output(wrapped("/bin:/usr/bin")))
        let resolver = makeResolver(shell: shell)
        await withTaskGroup(of: URL?.self) { group in
            for name in ["ls", "cat", "true", "env", "nope"] {
                for _ in 0..<10 { group.addTask { await resolver.resolve(name) } }
            }
            for await _ in group {}
        }
        #expect(shell.calls.count == 1)
        await resolver.prime()
        #expect(shell.calls.count == 2)
        #expect(await resolver.resolve("ls") != nil)
        #expect(shell.calls.count == 2)
    }

    @Test func timeoutFallsBackAndTerminatesShell() async {
        let shell = FakeShell(.hang)
        let resolver = makeResolver(
            shell: shell, environment: ["SHELL": "/bin/zsh", "PATH": "/custom/bin:/usr/bin"],
            timeout: .milliseconds(50))
        let clock = ContinuousClock()
        let start = clock.now
        await resolver.prime()
        #expect(clock.now - start < .seconds(1))
        #expect(await resolver.searchPathSource == .fallback)
        #expect(
            await resolver.searchPath == ["/custom/bin", "/usr/bin", "/opt/homebrew/bin", "/usr/local/bin", "/bin"])
        #expect(await eventually { shell.cancelled == 1 })
        #expect(await resolver.resolve("ls") == URL(fileURLWithPath: "/bin/ls"))
    }

    @Test func failingShellFallsBack() async {
        let resolver = makeResolver(shell: FakeShell(.fail), environment: ["SHELL": "/bin/zsh"])
        #expect(await resolver.searchPathSource == .fallback)
        #expect(await resolver.searchPath == ExecutableResolverImpl.fallbackEntries)
    }

    @Test func outputWithoutMarkersFallsBack() async {
        let resolver = makeResolver(shell: FakeShell(.output("/opt/homebrew/bin:/bin")))
        #expect(await resolver.searchPathSource == .fallback)
    }

    @Test(arguments: [
        ("/bin/zsh", "/bin/zsh"),
        ("/bin/bash", "/bin/bash"),
        ("zsh", "/bin/zsh"),
        ("", "/bin/zsh"),
        ("/nonexistent/fish", "/bin/zsh"),
    ])
    func shellMustBeAbsolute(shellEnv: String, expected: String) async {
        let shell = FakeShell(.output(wrapped("/bin")))
        _ = await makeResolver(shell: shell, environment: ["SHELL": shellEnv]).searchPath
        #expect(shell.calls == [expected])
    }

    @Test func contextFactoryHandsOutTheSharedResolver() async {
        let root = makeTempDirectory()
        let resolver = makeResolver(shell: FakeShell(.output(wrapped("/bin"))))
        let factory = await CoreModuleContextFactory(
            environment: makeEnvironment(root), eventBus: InProcessEventBus(), executables: resolver)
        let context = await factory.makeContext(
            for: ModuleManifest(id: "dev.sample", name: "Sample", icon: "star"), tracker: RegistrationTracker())
        #expect(await context.executables.resolve("ls") == URL(fileURLWithPath: "/bin/ls"))
        #expect((context.executables as? ExecutableResolverImpl) === resolver)
    }
}

@Suite struct SystemShellRunnerTests {
    @Test func returnsStdout() async throws {
        let output = try await SystemShellRunner().run(
            executablePath: "/bin/sh", arguments: ["-c", "printf 'a:b'"])
        #expect(output == "a:b")
    }

    @Test func nonZeroExitThrows() async {
        await #expect(throws: ShellRunnerError.exited(status: 3)) {
            try await SystemShellRunner().run(executablePath: "/bin/sh", arguments: ["-c", "exit 3"])
        }
    }

    @Test func rejectsRelativeExecutable() async {
        await #expect(throws: ShellRunnerError.notAbsolute("sh")) {
            try await SystemShellRunner().run(executablePath: "sh", arguments: [])
        }
    }

    @Test func cancellationTerminatesProcess() async {
        let clock = ContinuousClock()
        let start = clock.now
        let task = Task {
            try await SystemShellRunner().run(executablePath: "/bin/sleep", arguments: ["10"])
        }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(clock.now - start < .seconds(5))
    }

    @Test func realLoginShellCapture() async {
        // `/bin/sh -l` reads /etc/profile (path_helper), so the captured PATH holds the system directories.
        let resolver = ExecutableResolverImpl(
            environment: ["SHELL": "/bin/sh", "PATH": "/usr/bin:/bin"], timeout: .seconds(10), log: testLogger)
        #expect(await resolver.searchPathSource == .loginShell)
        #expect(await resolver.searchPath.contains("/bin"))
        #expect(await resolver.resolve("sh") != nil)
    }
}
