import Testing

@testable import VigieUI

/// Story 7.9: the order arithmetic behind the Usage tab's drag and Move up / Move down.
@Suite struct UsageProviderOrderTests {
    @Test func dropMovesOntoTargetAndKeepsOthers() {
        #expect(UsageProviderOrder.moving("c", onto: "a", in: ["a", "b", "c"]) == ["c", "a", "b"])
        #expect(UsageProviderOrder.moving("a", onto: "c", in: ["a", "b", "c"]) == ["b", "c", "a"])
        #expect(UsageProviderOrder.moving("a", onto: "a", in: ["a", "b"]) == ["a", "b"])
    }

    @Test func boundsAndMerge() {
        #expect(UsageProviderOrder.moving("a", by: -1, in: ["a", "b"]) == ["a", "b"])
        #expect(UsageProviderOrder.moving("b", by: 1, in: ["a", "b"]) == ["a", "b"])
        #expect(UsageProviderOrder.merged(shown: ["b"], current: ["a", "b"], existing: ["z"]) == ["b", "a", "z"])
    }
}
