// swift-tools-version: 6.0
import PackageDescription

// AD-1: an agent adapter depends only on AgentKit (which re-exports ModuleKit and Wire).
let package = Package(
    name: "ClaudeAdapter",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ClaudeAdapter", targets: ["ClaudeAdapter"])
    ],
    dependencies: [
        .package(path: "../../AgentKit")
    ],
    targets: [
        .target(
            name: "ClaudeAdapter",
            dependencies: [
                .product(name: "AgentKit", package: "AgentKit")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ClaudeAdapterTests",
            dependencies: ["ClaudeAdapter"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
