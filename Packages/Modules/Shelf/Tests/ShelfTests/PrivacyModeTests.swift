import Foundation
import ModuleKit
import Testing
import VigieUI

@testable import Shelf

/// Story 21.2: with Privacy mode active and seeded file names, nothing seeded reaches the Shelf tab rows or
/// their VoiceOver labels; kind, size, times and expiry stay (AD-24).
@MainActor @Suite struct PrivacyModeTests {
    static let seedPrefix = "SEEDED-SECRET"

    static func dumped(_ value: Any) -> String {
        var out = ""
        dump(value, to: &out)
        return out
    }

    @Test func stashRowsHideFileNames() async throws {
        let h = TabHarness()
        try await h.start()
        await h.stash(makeFile("SEEDED-SECRET-1.pdf"))
        await h.stash(makeFile("SEEDED-SECRET-2.txt"))
        let raw = h.module.tabSnapshot()
        #expect(Self.dumped(raw.rows).contains(Self.seedPrefix))
        let shown = raw.privacy(true)
        #expect(!Self.dumped(shown.rows).contains(Self.seedPrefix))
        #expect(shown.rows.map(\.kind) == raw.rows.map(\.kind))
        #expect(shown.rows.map(\.sizeMode) == raw.rows.map(\.sizeMode))
        #expect(shown.rows.map(\.id) == raw.rows.map(\.id))
        #expect(shown.title == raw.title)
    }
}
