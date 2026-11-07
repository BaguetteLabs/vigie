// swift-tools-version: 6.0
import PackageDescription

// AD-1: a terminal adapter depends only on AgentKit (which re-exports ModuleKit and Wire).
let package = Package(
    name: "GenericTerminal",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "GenericTerminal", targets: ["GenericTerminal"])
    ],
    dependencies: [
        .package(path: "../../AgentKit")
    ],
    targets: [
        .target(
            name: "GenericTerminal",
            dependencies: [
                .product(name: "AgentKit", package: "AgentKit")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "GenericTerminalTests",
            dependencies: ["GenericTerminal"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
