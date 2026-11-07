#if DEBUG
    import Foundation
    import ModuleKit
    import Observation
    import SwiftUI

    /// A debug-only module that exercises the host (Stories 2.5, 2.8): its state cycles `ambient → active`
    /// every 5 s, it renders a short/wide compact view and offers two left-wing items: `sample` (priority 50,
    /// short/wide) and `sample.icon` (priority 60, icon only), so overflow and size fallback are exercisable.
    @MainActor @Observable
    public final class DevSampleModule: NotchModule {
        public nonisolated static let staticManifest = ModuleManifest(
            id: "dev.sample",
            name: LocalizedStringResource("vigiecore.devSample.name", bundle: .atURL(Bundle.module.bundleURL)),
            icon: "testtube.2",
            defaultEnabled: false
        )

        public nonisolated static var descriptor: ModuleDescriptor {
            ModuleDescriptor(manifest: staticManifest) { DevSampleModule() }
        }

        public let manifest = DevSampleModule.staticManifest
        public private(set) var state: ModuleState = .hidden

        public init() {}

        public func start(context: any ModuleContext) async throws {
            state = .ambient
            _ = context.scheduler.every(.seconds(5)) { [weak self] in
                await self?.toggle()
            }
        }

        public func stop() async {
            state = .hidden
        }

        func toggle() {
            state = state == .active ? .ambient : .active
        }

        public func compactView(size: CompactSize) -> AnyView? {
            switch size {
            case .icon: nil
            case .short, .wide: AnyView(Text("vigiecore.devSample.compact", bundle: .module))
            }
        }

        public func leftWingItems() -> [LeftWingItem] {
            [
                LeftWingItem(id: "sample", priority: 50) { [weak self] size in
                    self?.compactView(size: size)
                },
                LeftWingItem(id: "sample.icon", priority: 60) { size in
                    size == .icon ? AnyView(Image(systemName: "testtube.2")) : nil
                },
            ]
        }
    }
#endif
