// ABOUTME: End-to-end CLI tests for Superscale.
// ABOUTME: Validates command-line argument parsing and basic invocation.

import XCTest
import CoreGraphics
import ImageIO
@testable import SuperscaleKit

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

    // MARK: - Target resolution tests (#38)

    // RT-071: --scale accepts float and produces output at specified scale
    func test_cli_float_scale_produces_correct_dimensions_RT071() throws {
        let modelPath = projectRoot.appendingPathComponent("models/RealESRGAN_x4plus.mlpackage")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: modelPath.path),
                      "x4plus model not found")

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscale_rt071_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let inputURL = tmpDir.appendingPathComponent("test_100x100.png")
        try createTestImage(width: 100, height: 100, at: inputURL)

        let result = try runCLI([
            inputURL.path, "-o", tmpDir.path,
            "-s", "2.4", "-m", "realesrgan-x4plus"
        ])

        XCTAssertEqual(result.exitCode, 0, "Should succeed. stderr: \(result.stderr)")

        let outputPath = tmpDir.appendingPathComponent("test_100x100_2.4x.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath.path),
                      "Output should exist at \(outputPath.path)")

        if let source = CGImageSourceCreateWithURL(outputPath as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            XCTAssertEqual(image.width, 240, "Output width should be 100 × 2.4 = 240")
            XCTAssertEqual(image.height, 240, "Output height should be 100 × 2.4 = 240")
        } else {
            XCTFail("Could not read output image")
        }
    }

    // RT-072: --width alone scales proportionally
    func test_cli_width_scales_proportionally_RT072() throws {
        let modelPath = projectRoot.appendingPathComponent("models/RealESRGAN_x4plus.mlpackage")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: modelPath.path),
                      "x4plus model not found")

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscale_rt072_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let inputURL = tmpDir.appendingPathComponent("test_100x200.png")
        try createTestImage(width: 100, height: 200, at: inputURL)

        let result = try runCLI([
            inputURL.path, "-o", tmpDir.path,
            "--width", "800", "-m", "realesrgan-x4plus"
        ])

        XCTAssertEqual(result.exitCode, 0, "Should succeed. stderr: \(result.stderr)")

        // Find output file (filename uses model native scale since --width not --scale)
        let outputs = try FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("test_100x200_") }
        XCTAssertEqual(outputs.count, 1, "Should produce one output file")

        if let outputURL = outputs.first,
           let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            XCTAssertEqual(image.width, 800, "Output width should match --width 800")
            XCTAssertEqual(image.height, 1600,
                           "Output height should scale proportionally: 200 × (800/100) = 1600")
        } else {
            XCTFail("Could not read output image")
        }
    }

    // RT-073: --height alone scales proportionally
    func test_cli_height_scales_proportionally_RT073() throws {
        let modelPath = projectRoot.appendingPathComponent("models/RealESRGAN_x4plus.mlpackage")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: modelPath.path),
                      "x4plus model not found")

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscale_rt073_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let inputURL = tmpDir.appendingPathComponent("test_100x200.png")
        try createTestImage(width: 100, height: 200, at: inputURL)

        let result = try runCLI([
            inputURL.path, "-o", tmpDir.path,
            "--height", "800", "-m", "realesrgan-x4plus"
        ])

        XCTAssertEqual(result.exitCode, 0, "Should succeed. stderr: \(result.stderr)")

        let outputs = try FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("test_100x200_") }
        XCTAssertEqual(outputs.count, 1, "Should produce one output file")

        if let outputURL = outputs.first,
           let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            XCTAssertEqual(image.width, 400,
                           "Output width should scale proportionally: 100 × (800/200) = 400")
            XCTAssertEqual(image.height, 800, "Output height should match --height 800")
        } else {
            XCTFail("Could not read output image")
        }
    }

    // RT-074: --width and --height together preserves aspect ratio (fit bounding box)
    func test_cli_width_height_preserves_aspect_ratio_RT074() throws {
        let modelPath = projectRoot.appendingPathComponent("models/RealESRGAN_x4plus.mlpackage")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: modelPath.path),
                      "x4plus model not found")

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscale_rt074_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        // 100×200 image with --width 2000 --height 2000 → fit = min(20, 10) = 10× → 1000×2000
        let inputURL = tmpDir.appendingPathComponent("test_100x200.png")
        try createTestImage(width: 100, height: 200, at: inputURL)

        let result = try runCLI([
            inputURL.path, "-o", tmpDir.path,
            "--width", "2000", "--height", "2000", "-m", "realesrgan-x4plus"
        ])

        XCTAssertEqual(result.exitCode, 0, "Should succeed. stderr: \(result.stderr)")

        let outputs = try FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("test_100x200_") }
        XCTAssertEqual(outputs.count, 1, "Should produce one output file")

        if let outputURL = outputs.first,
           let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            XCTAssertEqual(image.width, 1000,
                           "Width should fit bounding box: min(2000/100, 2000/200)=10 → 100×10=1000")
            XCTAssertEqual(image.height, 2000,
                           "Height should fit bounding box: 200×10=2000")
        } else {
            XCTFail("Could not read output image")
        }
    }

    // RT-075: --stretch produces exact dimensions ignoring aspect ratio
    func test_cli_stretch_produces_exact_dimensions_RT075() throws {
        let modelPath = projectRoot.appendingPathComponent("models/RealESRGAN_x4plus.mlpackage")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: modelPath.path),
                      "x4plus model not found")

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscale_rt075_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let inputURL = tmpDir.appendingPathComponent("test_100x200.png")
        try createTestImage(width: 100, height: 200, at: inputURL)

        let result = try runCLI([
            inputURL.path, "-o", tmpDir.path,
            "--width", "2000", "--height", "2000", "--stretch",
            "-m", "realesrgan-x4plus"
        ])

        XCTAssertEqual(result.exitCode, 0, "Should succeed. stderr: \(result.stderr)")

        let outputs = try FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("test_100x200_") }
        XCTAssertEqual(outputs.count, 1, "Should produce one output file")

        if let outputURL = outputs.first,
           let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            XCTAssertEqual(image.width, 2000,
                           "Width should be exactly 2000 with --stretch")
            XCTAssertEqual(image.height, 2000,
                           "Height should be exactly 2000 with --stretch")
        } else {
            XCTFail("Could not read output image")
        }
    }

    // RT-076: --scale and --width together produces validation error
    func test_cli_scale_and_width_mutual_exclusion_RT076() throws {
        let result = try runCLI(["test.png", "-s", "2", "--width", "800"])
        XCTAssertNotEqual(result.exitCode, 0,
                          "Should fail when both --scale and --width specified")
        let combined = result.stdout + result.stderr
        XCTAssertTrue(combined.lowercased().contains("cannot") ||
                      combined.lowercased().contains("error"),
                      "Should emit an error message: \(combined)")
    }

    // RT-077: Warning emitted when target exceeds model's native scale
    func test_cli_beyond_native_scale_emits_warning_RT077() throws {
        let modelPath = projectRoot.appendingPathComponent("models/RealESRGAN_x4plus.mlpackage")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: modelPath.path),
                      "x4plus model not found")

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscale_rt077_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let inputURL = tmpDir.appendingPathComponent("test_100x100.png")
        try createTestImage(width: 100, height: 100, at: inputURL)

        let result = try runCLI([
            inputURL.path, "-o", tmpDir.path,
            "-s", "6", "-m", "realesrgan-x4plus"
        ])

        XCTAssertEqual(result.exitCode, 0, "Should still succeed. stderr: \(result.stderr)")
        XCTAssertTrue(result.stderr.contains("exceeds"),
                      "Should warn about exceeding native scale: \(result.stderr)")

        // Output should still be produced at 600×600
        let outputPath = tmpDir.appendingPathComponent("test_100x100_6x.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath.path),
                      "Output should still be produced")
        if let source = CGImageSourceCreateWithURL(outputPath as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            XCTAssertEqual(image.width, 600, "Output should be 100 × 6 = 600")
            XCTAssertEqual(image.height, 600, "Output should be 100 × 6 = 600")
        }
    }

    // RT-078: --stretch without both --width and --height produces validation error
    func test_cli_stretch_without_both_dimensions_RT078() throws {
        let result = try runCLI(["test.png", "--stretch", "--width", "800"])
        XCTAssertNotEqual(result.exitCode, 0,
                          "Should fail when --stretch used without both dimensions")
        let combined = result.stdout + result.stderr
        XCTAssertTrue(combined.lowercased().contains("stretch") ||
                      combined.lowercased().contains("error"),
                      "Should mention --stretch in error: \(combined)")
    }

    // MARK: - Test image helper

    private func createTestImage(width: Int, height: Int, at url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw NSError(domain: "test", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot create CGContext"])
        }
        // Draw a gradient pattern so the image has some content
        for y in 0..<height {
            for x in 0..<width {
                let r = CGFloat(x) / CGFloat(width)
                let g = CGFloat(y) / CGFloat(height)
                ctx.setFillColor(red: r, green: g, blue: 0.5, alpha: 1.0)
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        guard let image = ctx.makeImage() else {
            throw NSError(domain: "test", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot make CGImage"])
        }
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ) else {
            throw NSError(domain: "test", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot create image destination"])
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "test", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot write image"])
        }
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

    // MARK: - Help text expansion tests (#39)

    // RT-079: Help text has all required sections in the specified order; -h == --help
    func test_cli_help_has_sections_in_order_RT079() throws {
        let result = try runCLI(["--help"])
        XCTAssertEqual(result.exitCode, 0, "Expected exit code 0 for --help")

        let sections = [
            "NAME", "USAGE", "DESCRIPTION", "ARGUMENTS", "OPTIONS",
            "EXAMPLES", "MODELS", "MODEL DETAILS",
            "FACE ENHANCEMENT", "REQUIREMENTS", "LICENSE", "SEE ALSO"
        ]

        var searchStart = result.stdout.startIndex
        for section in sections {
            if let range = result.stdout.range(of: section, range: searchStart..<result.stdout.endIndex) {
                searchStart = range.upperBound
            } else {
                XCTFail("Section '\(section)' not found after previous sections in help output.\nOutput:\n\(result.stdout)")
                return
            }
        }

        // AC41.5: Section heading is "MODELS", not "INSTALLED MODELS"
        XCTAssertFalse(result.stdout.contains("INSTALLED MODELS"),
                       "Section should be 'MODELS' not 'INSTALLED MODELS'")

        // AC39.6: -h produces same output as --help
        let shortResult = try runCLI(["-h"])
        XCTAssertEqual(shortResult.exitCode, 0, "Expected exit code 0 for -h")
        XCTAssertEqual(result.stdout, shortResult.stdout,
                       "-h and --help should produce identical output")
    }

    // RT-080: Piped help output contains no ANSI escape sequences
    func test_cli_help_piped_has_no_ansi_RT080() throws {
        let result = try runCLI(["--help"])
        XCTAssertEqual(result.exitCode, 0)
        // ESC character is \u{1B}; ANSI sequences start with ESC[
        XCTAssertFalse(result.stdout.contains("\u{1B}["),
                       "Piped help should not contain ANSI escape sequences")
    }

    // RT-081: Pager env vars are respected without breaking output
    func test_cli_help_respects_pager_env_vars_RT081() throws {
        // When piped (as in tests), pager is not invoked — but env vars must not
        // break the output. Verify help works with MANPAGER and PAGER set.
        let result1 = try runCLI(["--help"], environment: ["MANPAGER": "cat"])
        XCTAssertEqual(result1.exitCode, 0)
        XCTAssertTrue(result1.stdout.contains("NAME"),
                      "Help should work with MANPAGER set")

        let result2 = try runCLI(["--help"], environment: ["PAGER": "cat", "MANPAGER": ""])
        XCTAssertEqual(result2.exitCode, 0)
        XCTAssertTrue(result2.stdout.contains("NAME"),
                      "Help should work with PAGER set")

        // Both should produce identical content
        XCTAssertEqual(result1.stdout, result2.stdout,
                       "MANPAGER and PAGER should produce the same help content when piped")
    }

    // RT-082: Help output lists all registered model names (static, no install status)
    func test_cli_help_lists_all_models_RT082() throws {
        let result = try runCLI(["--help"])
        XCTAssertEqual(result.exitCode, 0)

        let models = [
            "realesrgan-x4plus", "realesrgan-x2plus", "realesrnet-x4plus",
            "realesrgan-anime-6b", "realesr-animevideov3",
            "realesr-general-x4v3", "realesr-general-wdn-x4v3"
        ]

        for model in models {
            XCTAssertTrue(result.stdout.contains(model),
                          "Help should list model: \(model)")
        }

        // AC41.5: Static help text — no runtime installation status
        XCTAssertFalse(result.stdout.contains("[installed]"),
                       "Static help should not contain '[installed]' status")
        XCTAssertFalse(result.stdout.contains("[not installed]"),
                       "Static help should not contain '[not installed]' status")
    }

    // RT-083: Piped help completes within timeout, no pager, no ANSI
    func test_cli_help_piped_does_not_block_RT083() throws {
        let result = try runCLI(["--help"], timeout: 5.0)
        XCTAssertEqual(result.exitCode, 0,
                       "Help should complete within 5s timeout when piped")
        XCTAssertFalse(result.stdout.isEmpty,
                       "Help output should not be empty")
        // AC41.3: Piped output must contain no ANSI escape sequences
        XCTAssertFalse(result.stdout.contains("\u{1B}["),
                       "Piped help should contain no ANSI escape sequences")
    }

    // RT-090: NO_COLOR suppresses ANSI escape codes in help output
    func test_cli_help_no_color_suppresses_ansi_RT090() throws {
        let result = try runCLI(["--help"], environment: ["NO_COLOR": "1"])
        XCTAssertEqual(result.exitCode, 0, "Expected exit code 0 for --help with NO_COLOR")
        XCTAssertFalse(result.stdout.isEmpty, "Help output should not be empty")
        XCTAssertFalse(result.stdout.contains("\u{1B}["),
                       "Help with NO_COLOR should contain no ANSI escape sequences")
        XCTAssertTrue(result.stdout.contains("NAME"),
                      "Help with NO_COLOR should still contain content")
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
        let timedOut: Bool
    }

    func runCLI(
        _ arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) throws -> CLIResult {
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

        if let env = environment {
            var processEnv = ProcessInfo.processInfo.environment
            for (key, value) in env {
                if value.isEmpty {
                    processEnv.removeValue(forKey: key)
                } else {
                    processEnv[key] = value
                }
            }
            process.environment = processEnv
        }

        try process.run()

        var didTimeout = false
        if let timeout = timeout {
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if process.isRunning {
                process.terminate()
                didTimeout = true
            }
        } else {
            process.waitUntilExit()
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return CLIResult(
            exitCode: didTimeout ? -1 : process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            timedOut: didTimeout
        )
    }
}
