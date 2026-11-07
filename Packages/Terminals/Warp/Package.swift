// swift-tools-version: 6.0
import PackageDescription

// AD-1: a terminal adapter depends only on AgentKit (which re-exports ModuleKit and Wire).
let package = Package(
    name: "WarpTerminal",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "WarpTerminal", targets: ["WarpTerminal"])
    ],
    dependencies: [
        .package(path: "../../AgentKit")
    ],
    targets: [
        .target(
            name: "WarpTerminal",
            dependencies: [
                .product(name: "AgentKit", package: "AgentKit")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "WarpTerminalTests",
            dependencies: ["WarpTerminal"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
