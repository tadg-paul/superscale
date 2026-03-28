// swift-tools-version: 5.9
// ABOUTME: Swift package manifest for Superscale.
// ABOUTME: Defines the CLI executable and shared library targets.

import PackageDescription

let package = Package(
    name: "Superscale",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "superscale", targets: ["Superscale"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "CSystemShim",
            path: "Sources/CSystemShim"
        ),
        .executableTarget(
            name: "Superscale",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "CSystemShim",
            ],
            path: "Sources/Superscale"
        ),
        .testTarget(
            name: "SuperscaleTests",
            dependencies: ["Superscale"],
            path: "Tests/SuperscaleTests",
            exclude: ["NEXT_IDS.txt", "Resources"]
        ),
    ]
)
