// swift-tools-version: 6.0
import PackageDescription

// AD-1: a terminal adapter depends only on AgentKit (which re-exports ModuleKit and Wire).
let package = Package(
    name: "TerminalAppTerminal",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TerminalAppTerminal", targets: ["TerminalAppTerminal"])
    ],
    dependencies: [
        .package(path: "../../AgentKit")
    ],
    targets: [
        .target(
            name: "TerminalAppTerminal",
            dependencies: [
                .product(name: "AgentKit", package: "AgentKit")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "TerminalAppTerminalTests",
            dependencies: ["TerminalAppTerminal"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
