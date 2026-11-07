// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Wire",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Wire", targets: ["Wire"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Wire",
            dependencies: [],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "WireTests",
            dependencies: ["Wire"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
