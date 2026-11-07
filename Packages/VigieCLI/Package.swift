// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VigieCLI",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "vigie", targets: ["vigie"]),
    ],
    dependencies: [
        .package(path: "../Wire"),
    ],
    targets: [
        // Testable command logic; the executable target stays a thin entry point.
        .target(
            name: "VigieCLI",
            dependencies: [
                .product(name: "Wire", package: "Wire"),
            ],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "vigie",
            dependencies: ["VigieCLI"]
        ),
        .testTarget(
            name: "VigieCLITests",
            dependencies: ["VigieCLI"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
