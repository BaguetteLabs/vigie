// swift-tools-version: 6.0
import PackageDescription

// AD-1: a module depends only on ModuleKit and VigieUI (AgentKit and Wire are for agent modules).
// AD-16: Yams 6.2.x parses script front matter (AD-18); no JSON Schema library, the Codable types in
// `Sources/Integrations/Schema` are checked against `schemas/script-module.schema.json` by fixtures (Story 12.1).
let package = Package(
    name: "Integrations",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Integrations", targets: ["Integrations"])
    ],
    dependencies: [
        .package(path: "../../ModuleKit"),
        .package(path: "../../VigieUI"),
        .package(url: "https://github.com/jpsim/Yams", from: "6.2.2"),
    ],
    targets: [
        .target(
            name: "Integrations",
            dependencies: [
                .product(name: "ModuleKit", package: "ModuleKit"),
                .product(name: "VigieUI", package: "VigieUI"),
                .product(name: "Yams", package: "Yams"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "IntegrationsTests",
            dependencies: ["Integrations"],
            exclude: ["Fixtures"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
