// swift-tools-version: 6.0
// SPIKE (Story 1.4): debug runner for the hook socket path. Not part of the app or CI.
import PackageDescription

let package = Package(
    name: "hook-listener",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../../Packages/Wire"),
        .package(path: "../../Packages/VigieCore"),
    ],
    targets: [
        .executableTarget(
            name: "hook-listener",
            dependencies: [
                .product(name: "Wire", package: "Wire"),
                .product(name: "VigieCore", package: "VigieCore"),
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
