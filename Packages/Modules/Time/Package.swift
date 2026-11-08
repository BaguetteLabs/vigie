// swift-tools-version: 6.0
import PackageDescription

// AD-1: a module depends only on ModuleKit and VigieUI (AgentKit and Wire are for agent modules).
let package = Package(
    name: "Time",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Time", targets: ["Time"])
    ],
    dependencies: [
        .package(path: "../../ModuleKit"),
        .package(path: "../../VigieUI"),
    ],
    targets: [
        .target(
            name: "Time",
            dependencies: [
                .product(name: "ModuleKit", package: "ModuleKit"),
                .product(name: "VigieUI", package: "VigieUI"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "TimeTests",
            dependencies: ["Time"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
