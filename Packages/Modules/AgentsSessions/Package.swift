// swift-tools-version: 6.0
import PackageDescription

// AD-1: an agent module depends only on ModuleKit, VigieUI, AgentKit and Wire.
let package = Package(
    name: "AgentsSessions",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AgentsSessions", targets: ["AgentsSessions"])
    ],
    dependencies: [
        .package(path: "../../ModuleKit"),
        .package(path: "../../VigieUI"),
        .package(path: "../../AgentKit"),
        .package(path: "../../Wire"),
    ],
    targets: [
        .target(
            name: "AgentsSessions",
            dependencies: [
                .product(name: "ModuleKit", package: "ModuleKit"),
                .product(name: "VigieUI", package: "VigieUI"),
                .product(name: "AgentKit", package: "AgentKit"),
                .product(name: "Wire", package: "Wire"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AgentsSessionsTests",
            dependencies: ["AgentsSessions"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
