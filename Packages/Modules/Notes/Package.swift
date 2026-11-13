// swift-tools-version: 6.0
import PackageDescription

// AD-1: a module depends only on ModuleKit and VigieUI (AgentKit and Wire are for agent modules).
let package = Package(
    name: "Notes",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Notes", targets: ["Notes"])
    ],
    dependencies: [
        .package(path: "../../ModuleKit"),
        .package(path: "../../VigieUI"),
    ],
    targets: [
        .target(
            name: "Notes",
            dependencies: [
                .product(name: "ModuleKit", package: "ModuleKit"),
                .product(name: "VigieUI", package: "VigieUI"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "NotesTests",
            dependencies: ["Notes", .product(name: "VigieUI", package: "VigieUI")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
