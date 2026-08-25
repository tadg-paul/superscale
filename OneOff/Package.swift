// swift-tools-version: 5.9
// ABOUTME: Swift package holding one-off tests, kept separate from the regression package.
// ABOUTME: The regression command addresses the main package and cannot reach these tests.

import PackageDescription

let package = Package(
    name: "SuperscaleOneOff",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: ".."),
    ],
    targets: [
        .testTarget(
            name: "OneOffTests",
            path: "Tests/OneOffTests",
            exclude: ["Fixtures"]
        ),
        // Live-provider tests sit in their own target so the layout tests above stay
        // dependency-free. They import the same client and credential storage the application
        // uses, which is what makes them proof rather than rehearsal.
        .testTarget(
            name: "OneOffLiveTests",
            dependencies: [
                .product(name: "FalGenerationKit", package: "superscale"),
                .product(name: "SuperscaleUXCore", package: "superscale"),
            ],
            path: "Tests/OneOffLiveTests"
        ),
    ]
)
