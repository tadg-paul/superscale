// ABOUTME: Tests for ModelRegistry — model metadata, path resolution, and status.
// ABOUTME: Validates the model catalogue and --list-models CLI output with status indicators.

import XCTest
@testable import SuperscaleKit

final class ModelRegistryTests: XCTestCase {

    // RT-006: --list-models shows model names with installed/available labels
    func test_cli_list_models_shows_status_labels_RT006() throws {
        let result = try runCLI(["--list-models"])
        XCTAssertEqual(result.exitCode, 0, "Expected exit code 0 for --list-models")

        // All six models must appear in the output
        let expectedModels = [
            "realesrgan-x4plus",
            "realesrgan-x2plus",
            "realesrnet-x4plus",
            "realesrgan-anime-6b",
            "realesr-animevideov3",
            "realesr-general-x4v3",
        ]
        for name in expectedModels {
            XCTAssertTrue(result.stdout.contains(name),
                          "Expected model '\(name)' in --list-models output")
        }

        // Each model line must have a status indicator
        let lines = result.stdout.components(separatedBy: "\n")
        let modelLines = lines.filter { line in
            expectedModels.contains { line.contains($0) }
        }
        XCTAssertEqual(modelLines.count, 6, "Expected exactly 6 model lines")

        for line in modelLines {
            XCTAssertTrue(
                line.contains("[installed]") || line.contains("[not installed]"),
                "Expected status indicator in line: \(line)"
            )
        }
    }

    // RT-019: ModelRegistry contains correct metadata for all models
    func test_model_registry_contains_all_models_with_metadata_RT019() {
        let models = ModelRegistry.models
        XCTAssertEqual(models.count, 7, "Expected exactly 7 models in registry")

        // Every model must have non-empty name, displayName, filename
        for model in models {
            XCTAssertFalse(model.name.isEmpty, "Model name must not be empty")
            XCTAssertFalse(model.displayName.isEmpty, "Display name must not be empty")
            XCTAssertFalse(model.filename.isEmpty, "Filename must not be empty")
            XCTAssertTrue(model.filename.hasSuffix(".mlpackage"),
                          "Filename must end with .mlpackage: \(model.filename)")
            XCTAssertTrue([2, 4].contains(model.scale),
                          "Scale must be 2 or 4, got \(model.scale) for \(model.name)")
            XCTAssertGreaterThan(model.tileSize, 0, "Tile size must be positive")
        }

        // Exactly one default
        let defaults = models.filter { $0.isDefault }
        XCTAssertEqual(defaults.count, 1, "Expected exactly one default model")
    }

    // RT-020: Given a CLI model name, ModelRegistry locates the .mlpackage URL
    func test_model_registry_resolves_model_url_RT020() {
        // Known model should resolve
        let url = ModelRegistry.modelURL(for: "realesrgan-x4plus")
        // URL should be non-nil if models have been converted (may be nil in CI)
        // But the method itself must exist and return a URL type
        if let url = url {
            XCTAssertTrue(url.path.hasSuffix("RealESRGAN_x4plus.mlpackage"),
                          "Expected URL to end with correct filename, got: \(url.path)")
        }

        // Unknown model should return nil
        let unknown = ModelRegistry.modelURL(for: "nonexistent-model")
        XCTAssertNil(unknown, "Unknown model name should return nil")
    }

    // RT-046: All six models present after build (download-models provisions them)
    func test_all_models_present_after_build_RT046() {
        let modelsDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("models")

        let expectedModels = [
            "RealESRGAN_x4plus.mlpackage",
            "RealESRGAN_x2plus.mlpackage",
            "RealESRNet_x4plus.mlpackage",
            "RealESRGAN_x4plus_anime_6B.mlpackage",
            "realesr-animevideov3.mlpackage",
            "realesr-general-x4v3.mlpackage",
        ]

        for filename in expectedModels {
            let modelPath = modelsDir.appendingPathComponent(filename)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: modelPath.path),
                "Model \(filename) should be present in models/ directory " +
                "(run 'make download-models' or 'make build')")
        }
    }

    // MARK: - Helpers

    struct CLIResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    func runCLI(_ arguments: [String]) throws -> CLIResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        let buildDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SuperscaleTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
            .appendingPathComponent(".build/debug/superscale")

        process.executableURL = buildDir
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return CLIResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
