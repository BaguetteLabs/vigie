// swift-tools-version: 6.0
import PackageDescription

// AD-1: a module depends only on ModuleKit and VigieUI (AgentKit and Wire are for agent modules).
let package = Package(
    name: "Shelf",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Shelf", targets: ["Shelf"])
    ],
    dependencies: [
        .package(path: "../../ModuleKit"),
        .package(path: "../../VigieUI"),
    ],
    targets: [
        .target(
            name: "Shelf",
            dependencies: [
                .product(name: "ModuleKit", package: "ModuleKit"),
                .product(name: "VigieUI", package: "VigieUI"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ShelfTests",
            dependencies: ["Shelf"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
