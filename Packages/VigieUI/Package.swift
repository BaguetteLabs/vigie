// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VigieUI",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "VigieUI", targets: ["VigieUI"]),
    ],
    dependencies: [
        .package(path: "../ModuleKit"),
    ],
    targets: [
        .target(
            name: "VigieUI",
            dependencies: [
                .product(name: "ModuleKit", package: "ModuleKit"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "VigieUITests",
            dependencies: ["VigieUI"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
