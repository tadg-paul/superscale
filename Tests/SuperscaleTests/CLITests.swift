// ABOUTME: End-to-end CLI tests for Superscale.
// ABOUTME: Validates command-line argument parsing and basic invocation.

import XCTest
import CoreGraphics
import ImageIO
@testable import Superscale

final class CLITests: XCTestCase {

    // RT-001
    func test_cli_version_flag_returns_zero() throws {
        let result = try runCLI(["--version"])
        XCTAssertEqual(result.exitCode, 0, "Expected exit code 0 for --version")
        let versionPattern = try NSRegularExpression(pattern: #"\d+\.\d+\.\d+"#)
        let range = NSRange(result.stdout.startIndex..., in: result.stdout)
        XCTAssertTrue(versionPattern.firstMatch(in: result.stdout, range: range) != nil,
                      "Expected semver string in output, got: \(result.stdout)")
    }

    // RT-002
    func test_cli_help_flag_returns_zero() throws {
        let result = try runCLI(["--help"])
        XCTAssertEqual(result.exitCode, 0, "Expected exit code 0 for --help")
        XCTAssertTrue(result.stdout.contains("USAGE"), "Expected usage info in output")
    }

    // RT-003
    func test_cli_list_models_returns_zero() throws {
        let result = try runCLI(["--list-models"])
        XCTAssertEqual(result.exitCode, 0, "Expected exit code 0 for --list-models")
        XCTAssertTrue(result.stdout.contains("realesrgan-x4plus"), "Expected default model in list")
    }

    // RT-004
    func test_cli_no_input_returns_error() throws {
        let result = try runCLI([])
        XCTAssertNotEqual(result.exitCode, 0, "Expected non-zero exit code with no input")
    }

    // RT-024: Batch processing — multiple input files produce multiple outputs
    func test_cli_batch_processes_multiple_files_RT024() throws {
        let modelPath = projectRoot.appendingPathComponent("models/RealESRGAN_x2plus.mlpackage")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: modelPath.path),
                      "x2plus model not found")

        let input1 = testImagesDir.appendingPathComponent("toby.jpg")
        let input2 = testImagesDir.appendingPathComponent("remy2.jpg")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: input1.path), "toby.jpg not found")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: input2.path), "remy2.jpg not found")

        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscale_batch_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let result = try runCLI([
            input1.path, input2.path,
            "-o", outputDir.path,
            "-m", "realesrgan-x2plus"
        ])

        XCTAssertEqual(result.exitCode, 0, "Batch processing should succeed. stderr: \(result.stderr)")

        let output1 = outputDir.appendingPathComponent("toby_2x.jpg")
        let output2 = outputDir.appendingPathComponent("remy2_2x.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: output1.path),
                      "First output file should exist at \(output1.path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: output2.path),
                      "Second output file should exist at \(output2.path)")
    }

    // RT-025: -o creates output directory if it doesn't exist
    func test_cli_creates_output_directory_RT025() throws {
        let modelPath = projectRoot.appendingPathComponent("models/RealESRGAN_x2plus.mlpackage")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: modelPath.path),
                      "x2plus model not found")

        let input = testImagesDir.appendingPathComponent("remy2.jpg")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: input.path), "remy2.jpg not found")

        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscale_mkdir_\(UUID().uuidString)")
            .appendingPathComponent("nested")
        defer {
            try? FileManager.default.removeItem(
                at: outputDir.deletingLastPathComponent())
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: outputDir.path),
                       "Output dir should not exist yet")

        let result = try runCLI([
            input.path,
            "-o", outputDir.path,
            "-m", "realesrgan-x2plus"
        ])

        XCTAssertEqual(result.exitCode, 0, "Should succeed. stderr: \(result.stderr)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDir.path),
                      "Output directory should be created")
    }

    // RT-026: -s 2 produces 2× output dimensions
    func test_cli_scale_flag_produces_correct_dimensions_RT026() throws {
        let modelPath = projectRoot.appendingPathComponent("models/RealESRGAN_x2plus.mlpackage")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: modelPath.path),
                      "x2plus model not found")

        let input = testImagesDir.appendingPathComponent("remy2.jpg")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: input.path), "remy2.jpg not found")

        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscale_scale_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let result = try runCLI([
            input.path,
            "-o", outputDir.path,
            "-s", "2",
            "-m", "realesrgan-x2plus"
        ])

        XCTAssertEqual(result.exitCode, 0, "Should succeed. stderr: \(result.stderr)")

        let outputPath = outputDir.appendingPathComponent("remy2_2x.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath.path),
                      "Output should exist at \(outputPath.path)")

        // Verify dimensions — input is 1024×1024, so 2× should be 2048×2048
        if let source = CGImageSourceCreateWithURL(outputPath as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            XCTAssertEqual(image.width, 2048, "Output width should be 2× input")
            XCTAssertEqual(image.height, 2048, "Output height should be 2× input")
        } else {
            XCTFail("Could not read output image")
        }
    }

    // RT-048: --help text for -m tells users about --list-models
    func test_cli_help_model_option_references_list_models_RT048() throws {
        let result = try runCLI(["--help"])
        XCTAssertEqual(result.exitCode, 0)
        // ArgumentParser may wrap help text across lines, so normalize whitespace
        let normalized = result.stdout
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        XCTAssertTrue(normalized.contains("see --list-models"),
                      "Help for -m should say 'see --list-models' — stdout: \(result.stdout)")
    }

    // RT-037: Explicit -m flag bypasses auto-detection
    func test_cli_explicit_model_bypasses_detection_RT037() throws {
        let modelPath = projectRoot.appendingPathComponent("models/RealESRNet_x4plus.mlpackage")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: modelPath.path),
                      "RealESRNet_x4plus model not found")

        let input = testImagesDir.appendingPathComponent("remy2.jpg")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: input.path), "remy2.jpg not found")

        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscale_explicit_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let result = try runCLI([
            input.path,
            "-o", outputDir.path,
            "-m", "realesrnet-x4plus"
        ])

        XCTAssertEqual(result.exitCode, 0, "Should succeed. stderr: \(result.stderr)")
        // Explicit model: should report "Using model:" not "Detected:"
        XCTAssertTrue(result.stderr.contains("Using model: realesrnet-x4plus"),
                      "Explicit model should report 'Using model:' — stderr: \(result.stderr)")
        XCTAssertFalse(result.stderr.contains("Detected:"),
                       "Explicit model should not show 'Detected:' — stderr: \(result.stderr)")
    }

    // RT-038: Auto-detection reports detected content type and model in progress output
    func test_cli_auto_detection_reports_content_type_RT038() throws {
        let modelPath = projectRoot.appendingPathComponent("models/RealESRGAN_x4plus.mlpackage")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: modelPath.path),
                      "x4plus model not found")

        let input = testImagesDir.appendingPathComponent("remy2.jpg")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: input.path), "remy2.jpg not found")

        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscale_autodetect_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        // No -m flag → auto-detection should kick in
        let result = try runCLI([
            input.path,
            "-o", outputDir.path
        ])

        XCTAssertEqual(result.exitCode, 0, "Should succeed. stderr: \(result.stderr)")
        // Auto-detection should report the detected type and chosen model
        XCTAssertTrue(result.stderr.contains("Detected:"),
                      "Auto-detection should report 'Detected:' — stderr: \(result.stderr)")
        XCTAssertTrue(result.stderr.contains("realesrgan-"),
                      "Auto-detection should include model name — stderr: \(result.stderr)")
    }

    // RT-065: --list-models includes face model with [installed] when present
    func test_cli_list_models_shows_face_model_installed_RT065() throws {
        try XCTSkipIf(!FaceModelRegistry.isInstalled, "Face model not installed")

        let result = try runCLI(["--list-models"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("gfpgan"),
                      "Face model should appear in --list-models output: \(result.stdout)")
        XCTAssertTrue(result.stdout.contains("[installed]"),
                      "Face model should show [installed] status")
    }

    // RT-066: --list-models includes face model with [not installed] and download hint when absent
    func test_cli_list_models_shows_face_model_not_installed_RT066() throws {
        try XCTSkipIf(FaceModelRegistry.isInstalled, "Face model is installed — cannot test 'not installed' path")

        let result = try runCLI(["--list-models"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("gfpgan"),
                      "Face model should appear in --list-models even when not installed: \(result.stdout)")
        XCTAssertTrue(result.stdout.contains("not installed"),
                      "Face model should show 'not installed' status")
        XCTAssertTrue(result.stdout.contains("--download-face-model"),
                      "Should hint at --download-face-model")
    }

    // RT-067: --list-models separates upscaling and face enhancement models
    func test_cli_list_models_separates_face_section_RT067() throws {
        let result = try runCLI(["--list-models"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Face enhancement:"),
                      "Should have a 'Face enhancement:' section heading: \(result.stdout)")
    }

    // RT-068: --version output matches branded format
    func test_cli_version_output_matches_branded_format_RT068() throws {
        let result = try runCLI(["--version"])
        XCTAssertEqual(result.exitCode, 0, "Expected exit code 0 for --version")
        let pattern = try NSRegularExpression(
            pattern: #"^v\d+\.\d+\.\d+ Superscale by Taḋg Paul\s*$"#)
        let range = NSRange(result.stdout.startIndex..., in: result.stdout)
        XCTAssertTrue(pattern.firstMatch(in: result.stdout, range: range) != nil,
                      "Expected 'v{semver} Superscale by Taḋg Paul', got: \(result.stdout)")
    }

    // RT-069: wdn model file exists in models directory
    func test_wdn_model_file_exists_RT069() throws {
        let modelPath = projectRoot.appendingPathComponent(
            "models/realesr-general-wdn-x4v3.mlpackage")
        XCTAssertTrue(FileManager.default.fileExists(atPath: modelPath.path),
                      "realesr-general-wdn-x4v3.mlpackage should exist in models/")
    }

    // RT-070: --list-models includes wdn model with installed status
    func test_cli_list_models_includes_wdn_model_RT070() throws {
        let modelPath = projectRoot.appendingPathComponent(
            "models/realesr-general-wdn-x4v3.mlpackage")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: modelPath.path),
                      "wdn model not installed")

        let result = try runCLI(["--list-models"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("realesr-general-wdn-x4v3"),
                      "wdn model should appear in --list-models: \(result.stdout)")
        XCTAssertTrue(result.stdout.contains("denoise"),
                      "wdn model description should mention denoise: \(result.stdout)")
    }

    // RT-059: --clear-cache empties the compiled model cache directory
    func test_cli_clear_cache_removes_compiled_models_RT059() throws {
        let modelPath = projectRoot.appendingPathComponent("models/RealESRGAN_x4plus.mlpackage")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: modelPath.path),
                      "Model not found — needed to populate cache first")

        // Populate the cache by running an upscale
        let input = testImagesDir.appendingPathComponent("remy2.jpg")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: input.path), "remy2.jpg not found")

        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscale_cache_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        _ = try runCLI([input.path, "-o", outputDir.path, "-m", "realesrgan-x4plus"])

        // Verify cache directory has content
        let cacheDir = ModelCache.cacheDirectory
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheDir.path),
                      "Cache directory should exist after a model load")

        // Run --clear-cache
        let result = try runCLI(["--clear-cache"])
        XCTAssertEqual(result.exitCode, 0, "Expected exit code 0 for --clear-cache. stderr: \(result.stderr)")

        // Cache directory should be gone or empty
        let exists = FileManager.default.fileExists(atPath: cacheDir.path)
        if exists {
            let contents = try FileManager.default.contentsOfDirectory(atPath: cacheDir.path)
            XCTAssertTrue(contents.isEmpty, "Cache directory should be empty after --clear-cache")
        }
    }

    // MARK: - Helpers

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var testImagesDir: URL {
        projectRoot.appendingPathComponent("Tests/images")
    }

    struct CLIResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    func runCLI(_ arguments: [String]) throws -> CLIResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        // Find the built binary
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
