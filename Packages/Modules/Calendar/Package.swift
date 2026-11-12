// swift-tools-version: 6.0
import PackageDescription

// AD-1: a module depends only on ModuleKit and VigieUI (AgentKit and Wire are for agent modules).
let package = Package(
    name: "Calendar",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Calendar", targets: ["Calendar"])
    ],
    dependencies: [
        .package(path: "../../ModuleKit"),
        .package(path: "../../VigieUI"),
    ],
    targets: [
        .target(
            name: "Calendar",
            dependencies: [
                .product(name: "ModuleKit", package: "ModuleKit"),
                .product(name: "VigieUI", package: "VigieUI"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "CalendarTests",
            dependencies: ["Calendar"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
