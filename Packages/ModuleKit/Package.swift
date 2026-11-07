// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ModuleKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ModuleKit", targets: ["ModuleKit"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ModuleKit",
            dependencies: [],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ModuleKitTests",
            dependencies: ["ModuleKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
