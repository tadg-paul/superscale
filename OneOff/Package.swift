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
    ]
)
