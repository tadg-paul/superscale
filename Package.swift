// swift-tools-version: 5.9
// ABOUTME: Swift package manifest for Superscale.
// ABOUTME: Defines the SuperscaleKit library, CLI executable, and test targets.

import PackageDescription

let package = Package(
    name: "Superscale",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "SuperscaleKit", targets: ["SuperscaleKit"]),
        .executable(name: "superscale", targets: ["Superscale"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "SuperscaleKit",
            path: "Sources/SuperscaleKit"
        ),
        .target(
            name: "CSystemShim",
            path: "Sources/CSystemShim"
        ),
        .executableTarget(
            name: "Superscale",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "CSystemShim",
                "SuperscaleKit",
            ],
            path: "Sources/Superscale"
        ),
        .testTarget(
            name: "SuperscaleTests",
            dependencies: ["SuperscaleKit"],
            path: "Tests/SuperscaleTests",
            exclude: ["NEXT_IDS.txt", "Resources"]
        ),
    ]
)
