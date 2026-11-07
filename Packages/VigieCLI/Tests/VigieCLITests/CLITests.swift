import Testing
import Wire

@testable import VigieCLI

@Suite struct CLITests {
    @Test func usageResolvesFromCatalog() {
        #expect(!CLI.usage.isEmpty)
        #expect(CLI.usage != "cli.usage")
    }

    @Test func noArgumentsPrintsUsageAndExitsZero() {
        var lines: [String] = []
        let status = CLI.run(arguments: []) { lines.append($0) }
        #expect(status == 0)
        #expect(lines == [CLI.usage])
    }

    @Test func versionPrintsCliNameAndBundleID() {
        var lines: [String] = []
        let status = CLI.run(arguments: ["version"]) { lines.append($0) }
        let env = AppEnvironment.current
        #expect(status == 0)
        #expect(lines == ["\(env.cliName) \(env.bundleID)"])
    }
}
