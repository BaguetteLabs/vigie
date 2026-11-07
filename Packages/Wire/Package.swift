// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Wire",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Wire", targets: ["Wire"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Wire",
            dependencies: [],
            resources: [.process("Resources")],
            // Debug = dev flavor, Release = release flavor (AD-17). Single source of truth;
            // App/project.yml sets the same condition for the Debug app configuration.
            swiftSettings: [.define("VIGIE_DEV", .when(configuration: .debug))]
        ),
        .testTarget(
            name: "WireTests",
            dependencies: ["Wire"],
            swiftSettings: [.define("VIGIE_DEV", .when(configuration: .debug))]
        ),
    ],
    swiftLanguageModes: [.v6]
)
