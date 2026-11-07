import Testing

@testable import AgentKit

@Suite struct AppleScriptSupportTests {
    @Test func literalEscapesQuotesAndBackslashes() {
        #expect(AppleScriptText.literal("/dev/ttys003") == "\"/dev/ttys003\"")
        #expect(AppleScriptText.literal("a\"b\\c") == "\"a\\\"b\\\\c\"")
    }

    @Test func permissionDeniedNumbers() {
        #expect(AppleScriptError(number: -1743, message: "").isPermissionDenied)
        #expect(AppleScriptError(number: -1744, message: "").isPermissionDenied)
        #expect(!AppleScriptError(number: -1728, message: "").isPermissionDenied)
    }

    @Test func nsAppleScriptRunnerReturnsTextAndThrowsNumberedErrors() async throws {
        let runner = NSAppleScriptRunner()
        #expect(try await runner.run(source: "return \"ok\"") == "ok")
        await #expect(throws: AppleScriptError.self) { try await runner.run(source: "error \"boom\" number 42") }
        do {
            _ = try await runner.run(source: "error \"boom\" number 42")
        } catch let error as AppleScriptError {
            #expect(error.number == 42)
            #expect(error.message == "boom")
        }
    }
}
