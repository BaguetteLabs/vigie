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
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
        // AD-16: decode only (config); ConfigStore never writes TOML with it.
        .package(url: "https://github.com/mattt/swift-toml", exact: "2.1.0"),
    ],
    targets: [
        .target(
            name: "VigieCore",
            dependencies: [
                .product(name: "ModuleKit", package: "ModuleKit"),
                .product(name: "VigieUI", package: "VigieUI"),
                .product(name: "Wire", package: "Wire"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "TOML", package: "swift-toml"),
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
