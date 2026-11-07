// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VigieUI",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "VigieUI", targets: ["VigieUI"]),
        .executable(name: "themegen", targets: ["themegen"]),
        .executable(name: "contrastcheck", targets: ["contrastcheck"]),
    ],
    dependencies: [
        .package(path: "../ModuleKit"),
        // AD-16: decode only (themes, config); never writes TOML.
        .package(url: "https://github.com/mattt/swift-toml", exact: "2.1.0"),
        // AD-16: YAML front matter. Used only by the theme generator, never linked into VigieUI.
        .package(url: "https://github.com/jpsim/Yams", from: "6.2.2"),
    ],
    targets: [
        .target(
            name: "VigieUI",
            dependencies: [
                .product(name: "ModuleKit", package: "ModuleKit"),
                .product(name: "TOML", package: "swift-toml"),
            ],
            resources: [
                .process("Resources/Localizable.xcstrings"),
                .copy("Resources/Themes"),
            ]
        ),
        // Generator logic (AD-14): DESIGN.md frontmatter -> Themes/*.toml, using VigieUI's token types.
        .target(
            name: "ThemeGenKit",
            dependencies: [
                "VigieUI",
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .executableTarget(
            name: "themegen",
            dependencies: ["ThemeGenKit"]
        ),
        // Story 2.15: CI contrast check of the DESIGN contrast pairs (`Scripts/check-contrast.sh`).
        .executableTarget(
            name: "contrastcheck",
            dependencies: ["VigieUI"]
        ),
        .testTarget(
            name: "VigieUITests",
            dependencies: ["VigieUI"]
        ),
        .testTarget(
            name: "ThemeGenKitTests",
            dependencies: ["ThemeGenKit", "VigieUI"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
