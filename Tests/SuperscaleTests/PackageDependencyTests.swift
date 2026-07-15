// ABOUTME: Regression tests for Swift package product and target boundaries.
// ABOUTME: Uses SwiftPM's generated build graph to protect CLI isolation.

import Foundation
import XCTest

final class PackageDependencyTests: XCTestCase {
    // RT-70.1, RT-78.2: The CLI remains isolated from GUI-only modules.
    func test_cli_target_excludes_gui_only_modules_RT70_1() throws {
        let dependencyMap = try loadTargetDependencyMap()
        let dependencies = Set(try XCTUnwrap(dependencyMap["Superscale"]))

        XCTAssertTrue(dependencies.contains("SuperscaleKit"))
        XCTAssertFalse(dependencies.contains("FalGenerationKit"))
        XCTAssertFalse(dependencies.contains("SuperscaleUXCore"))
    }

    // RT-70.3: GUI-only library and test targets are available to SwiftPM.
    func test_package_exposes_gui_module_and_test_targets_RT70_3() throws {
        let dependencyMap = try loadTargetDependencyMap()

        XCTAssertNotNil(dependencyMap["FalGenerationKit"])
        XCTAssertNotNil(dependencyMap["SuperscaleUXCore"])
        XCTAssertEqual(dependencyMap["FalGenerationKitTests"], ["FalGenerationKit"])
        XCTAssertTrue(
            try XCTUnwrap(dependencyMap["SuperscaleUXCoreTests"])
                .contains("SuperscaleUXCore")
        )
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func loadTargetDependencyMap() throws -> [String: [String]] {
        let buildDirectory = projectRoot.appendingPathComponent(".build")
        let platformDirectories = try FileManager.default.contentsOfDirectory(
            at: buildDirectory,
            includingPropertiesForKeys: nil
        )

        for platformDirectory in platformDirectories {
            let description = platformDirectory
                .appendingPathComponent("debug")
                .appendingPathComponent("description.json")
            guard FileManager.default.fileExists(atPath: description.path) else {
                continue
            }

            let data = try Data(contentsOf: description)
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            return try XCTUnwrap(object["targetDependencyMap"] as? [String: [String]])
        }

        throw XCTSkip("SwiftPM debug build description is unavailable")
    }
}
