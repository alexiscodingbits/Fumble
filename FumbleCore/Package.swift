// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FumbleCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FumbleCore", targets: ["FumbleCore"]),
        .library(name: "FumbleUI", targets: ["FumbleUI"]),
        .executable(name: "fumble-cli", targets: ["fumble-cli"]),
        .executable(name: "FumbleApp", targets: ["FumbleApp"]),
    ],
    targets: [
        // PURE model + analysis. Imports Foundation ONLY — no AppKit, no SwiftUI, no CoreGraphics.
        .target(name: "FumbleCore"),
        // PURE presentation logic (formatting, view state). Foundation/Observation only — no SwiftUI.
        .target(name: "FumbleUI", dependencies: ["FumbleCore"]),
        // Debug/inspection CLI. Dumps today's stats as text or JSON.
        .executableTarget(name: "fumble-cli", dependencies: ["FumbleCore"]),
        // The ONLY target importing SwiftUI/AppKit/CoreGraphics.
        .executableTarget(
            name: "FumbleApp",
            dependencies: ["FumbleCore", "FumbleUI"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "FumbleCoreTests", dependencies: ["FumbleCore"]),
        .testTarget(name: "FumbleUITests", dependencies: ["FumbleUI", "FumbleCore"]),
    ]
)
