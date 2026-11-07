// swift-tools-version: 6.0
import PackageDescription

// AD-1: a terminal adapter depends only on AgentKit (which re-exports ModuleKit and Wire).
let package = Package(
    name: "ITermTerminal",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ITermTerminal", targets: ["ITermTerminal"])
    ],
    dependencies: [
        .package(path: "../../AgentKit")
    ],
    targets: [
        .target(
            name: "ITermTerminal",
            dependencies: [
                .product(name: "AgentKit", package: "AgentKit")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ITermTerminalTests",
            dependencies: ["ITermTerminal"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
