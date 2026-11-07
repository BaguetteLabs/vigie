// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AgentKit", targets: ["AgentKit"])
    ],
    dependencies: [
        .package(path: "../ModuleKit"),
        .package(path: "../Wire"),
    ],
    targets: [
        .target(
            name: "AgentKit",
            dependencies: [
                .product(name: "ModuleKit", package: "ModuleKit"),
                .product(name: "Wire", package: "Wire"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AgentKitTests",
            dependencies: ["AgentKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
