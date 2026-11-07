// swift-tools-version: 6.0
// Throwaway spike (Story 1.5). Not part of the shipped packages.
import PackageDescription

let package = Package(
    name: "warp-focus",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "warp-focus",
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ApplicationServices")]
        )
    ]
)
