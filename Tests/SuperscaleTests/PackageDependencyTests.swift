// ABOUTME: Regression tests for Swift package product and target boundaries.
// ABOUTME: Uses SwiftPM's resolved package description to protect CLI isolation.

import Foundation
import XCTest

final class PackageDependencyTests: XCTestCase {
    // RT-70.1: The CLI remains isolated from GUI-only modules.
    func test_cli_target_excludes_gui_only_modules_RT70_1() throws {
        let package = try loadPackageDescription()
        let cli = try XCTUnwrap(target(named: "Superscale", in: package))
        let dependencies = dependencyNames(in: cli)

        XCTAssertTrue(dependencies.contains("SuperscaleKit"))
        XCTAssertFalse(dependencies.contains("FalGenerationKit"))
        XCTAssertFalse(dependencies.contains("SuperscaleUXCore"))
    }

    // RT-70.3: GUI-only library and test targets are available to SwiftPM.
    func test_package_exposes_gui_module_and_test_targets_RT70_3() throws {
        let package = try loadPackageDescription()
        let targetNames = try XCTUnwrap(package["targets"] as? [[String: Any]])
            .compactMap { $0["name"] as? String }
        let productNames = try XCTUnwrap(package["products"] as? [[String: Any]])
            .compactMap { $0["name"] as? String }

        XCTAssertTrue(productNames.contains("FalGenerationKit"))
        XCTAssertTrue(productNames.contains("SuperscaleUXCore"))
        XCTAssertTrue(targetNames.contains("FalGenerationKit"))
        XCTAssertTrue(targetNames.contains("SuperscaleUXCore"))
        XCTAssertTrue(targetNames.contains("FalGenerationKitTests"))
        XCTAssertTrue(targetNames.contains("SuperscaleUXCoreTests"))
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func loadPackageDescription() throws -> [String: Any] {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "package", "dump-package"]
        process.currentDirectoryURL = projectRoot
        process.standardOutput = output
        process.standardError = errors

        try process.run()
        process.waitUntilExit()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errorData, encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, errorText)

        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: outputData) as? [String: Any]
        )
    }

    private func target(
        named name: String,
        in package: [String: Any]
    ) -> [String: Any]? {
        let targets = package["targets"] as? [[String: Any]]
        return targets?.first { $0["name"] as? String == name }
    }

    private func dependencyNames(in target: [String: Any]) -> Set<String> {
        let dependencies = target["dependencies"] as? [[String: Any]] ?? []
        let names = dependencies.compactMap { dependency -> String? in
            if let byName = dependency["byName"] as? [Any] {
                return byName.first as? String
            }
            if let product = dependency["product"] as? [Any] {
                return product.first as? String
            }
            return nil
        }
        return Set(names)
    }
}
