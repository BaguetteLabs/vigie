// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VigieCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "VigieCore", targets: ["VigieCore"])
    ],
    dependencies: [
        .package(path: "../ModuleKit"),
        .package(path: "../VigieUI"),
        .package(path: "../Wire"),
    ],
    targets: [
        .target(
            name: "VigieCore",
            dependencies: [
                .product(name: "ModuleKit", package: "ModuleKit"),
                .product(name: "VigieUI", package: "VigieUI"),
                .product(name: "Wire", package: "Wire"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "VigieCoreTests",
            dependencies: ["VigieCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
