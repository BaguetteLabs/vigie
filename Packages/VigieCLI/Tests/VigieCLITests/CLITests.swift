import Testing

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
}
