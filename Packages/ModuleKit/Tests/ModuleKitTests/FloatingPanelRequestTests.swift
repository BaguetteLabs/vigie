import SwiftUI
import Testing

@_spi(Host) @testable import ModuleKit

/// Story 15.3: the floating panel API is additive; a host that does not implement it refuses.
@MainActor @Suite struct FloatingPanelRequestTests {
    struct BareHost: HostControl {
        func requestPeek() {}
        func expand(focus: UserIntent?) {}
        func openOwnTab(focus: UserIntent?) {}
        func registerDynamicModule(_ module: any NotchModule) throws -> RegistrationToken { RegistrationToken {} }
    }

    @Test func theDefaultHostRefusesAndDismissIsANoOp() {
        let request = FloatingPanelRequest(id: "notes.panel", content: { AnyView(EmptyView()) })
        #expect(request.size == nil)
        #expect(!BareHost().presentFloatingPanel(request, focus: UserIntent()))
        BareHost().dismissFloatingPanel()
    }
}
