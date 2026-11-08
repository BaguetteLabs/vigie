// swift-tools-version: 6.0
import PackageDescription

// AD-1: an agent module depends only on ModuleKit, VigieUI, AgentKit and Wire (here ModuleKit, VigieUI and AgentKit),
// plus GRDB from the AD-16 allowlist.
// AD-11: `agents.usage` owns the only SQLite database (GRDB 7.12.x).
let package = Package(
    name: "AgentsUsage",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AgentsUsage", targets: ["AgentsUsage"])
    ],
    dependencies: [
        .package(path: "../../ModuleKit"),
        .package(path: "../../VigieUI"),
        .package(path: "../../AgentKit"),
        .package(url: "https://github.com/groue/GRDB.swift", .upToNextMinor(from: "7.12.0")),
    ],
    targets: [
        .target(
            name: "AgentsUsage",
            dependencies: [
                .product(name: "ModuleKit", package: "ModuleKit"),
                .product(name: "VigieUI", package: "VigieUI"),
                .product(name: "AgentKit", package: "AgentKit"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AgentsUsageTests",
            dependencies: ["AgentsUsage"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
