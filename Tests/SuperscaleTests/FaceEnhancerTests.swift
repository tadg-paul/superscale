// ABOUTME: Tests for face enhancement — GFPGAN download, CLI flags, face detection.
// ABOUTME: Validates AC1.1–AC1.7 for the optional face enhancement feature.

import XCTest
import CoreGraphics
@testable import Superscale

final class FaceEnhancerTests: XCTestCase {

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var testImagesDir: URL {
        projectRoot.appendingPathComponent("Tests/images")
    }

    // RT-041: Without face model, upscaling succeeds and face enhancement is silently skipped
    func test_upscale_without_face_model_succeeds_silently_RT041() throws {
        // Ensure the GFPGAN model is NOT present
        try XCTSkipIf(FaceModelRegistry.isInstalled,
                      "GFPGAN model is present — cannot test missing model scenario")

        let modelPath = projectRoot.appendingPathComponent("models/RealESRGAN_x2plus.mlpackage")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: modelPath.path),
                      "x2plus model not found")

        let input = testImagesDir.appendingPathComponent("remy2.jpg")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: input.path),
                      "remy2.jpg not found")

        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscale_noface_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let result = try runCLI([
            input.path,
            "-o", outputDir.path,
            "-m", "realesrgan-x2plus"
        ])

        // Should succeed — face enhancement silently skipped when model not present
        XCTAssertEqual(result.exitCode, 0,
                       "Upscale should succeed without face model. stderr: \(result.stderr)")
        // Should NOT mention face enhancement
        XCTAssertFalse(result.stderr.contains("Face enhancement enabled"),
                       "Should not mention face enhancement when model is absent")
    }

    // RT-042: GFPGAN excluded from git, formula, and distribution
    func test_gfpgan_excluded_from_distribution_RT042() throws {
        // 1. Check .gitignore covers GFPGAN model files
        let gitignore = try String(contentsOfFile:
            projectRoot.appendingPathComponent(".gitignore").path)
        // *.mlpackage and *.pth patterns cover GFPGAN files
        XCTAssertTrue(gitignore.contains("*.mlpackage"),
                      ".gitignore should exclude *.mlpackage")
        XCTAssertTrue(gitignore.contains("*.pth"),
                      ".gitignore should exclude *.pth")

        // 2. Check formula has no GFPGAN resource
        let formula = try String(contentsOfFile:
            projectRoot.appendingPathComponent("Formula/superscale.rb").path)
        XCTAssertFalse(
            formula.lowercased().contains("gfpgan"),
            "Formula should not contain any GFPGAN references")

        // 3. Check GFPGAN model is not in git tracked files
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["ls-files", "--cached"]
        process.currentDirectoryURL = projectRoot
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let trackedFiles = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8) ?? ""
        // Exclude scripts — only flag model/weight files containing "gfpgan"
        let gfpganFiles = trackedFiles
            .components(separatedBy: "\n")
            .filter { $0.lowercased().contains("gfpgan") }
            .filter { !$0.hasPrefix("scripts/") }
        XCTAssertTrue(
            gfpganFiles.isEmpty,
            "No GFPGAN model files should be tracked in git: \(gfpganFiles)")
    }

    // RT-043: Face detection runs without error and returns face rectangles
    func test_face_detection_runs_on_image_RT043() throws {
        let photoURL = testImagesDir.appendingPathComponent("remy2.jpg")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: photoURL.path),
                      "remy2.jpg not found")

        let loaded = try ImageLoader.load(from: photoURL)

        // FaceDetector should run without error regardless of whether faces are found
        let faces = try FaceDetector.detect(in: loaded.image)

        // The result should be a valid (possibly empty) array of face rectangles
        XCTAssertNotNil(faces, "Face detection should return a result")
        // Each detected face should have valid normalized coordinates
        for face in faces {
            XCTAssertGreaterThanOrEqual(face.origin.x, 0,
                                        "Face rect x should be >= 0")
            XCTAssertGreaterThanOrEqual(face.origin.y, 0,
                                        "Face rect y should be >= 0")
            XCTAssertGreaterThan(face.size.width, 0,
                                 "Face rect width should be > 0")
            XCTAssertGreaterThan(face.size.height, 0,
                                 "Face rect height should be > 0")
        }
    }

    // RT-050: Download failure reports clear error message
    func test_download_face_model_failure_reports_clear_error_RT050() throws {
        // Skip if face model already installed — can't test download path
        try XCTSkipIf(FaceModelRegistry.isInstalled,
                      "GFPGAN model already installed")

        let result = try runCLI([
            "--download-face-model",
            "--accept-licence"
        ])

        // Should fail (model not uploaded yet) but with a clear message
        XCTAssertNotEqual(result.exitCode, 0,
                          "Download should fail when model is not available")
        XCTAssertTrue(result.stderr.contains("Download failed"),
                      "Should report 'Download failed' — stderr: \(result.stderr)")
        XCTAssertFalse(result.stderr.contains("couldn't be opened"),
                       "Should not show cryptic Foundation error — stderr: \(result.stderr)")
    }

    // RT-051: Failed download leaves no partial files behind
    func test_download_face_model_failure_leaves_no_partial_files_RT051() throws {
        try XCTSkipIf(FaceModelRegistry.isInstalled,
                      "GFPGAN model already installed")

        _ = try runCLI([
            "--download-face-model",
            "--accept-licence"
        ])

        // After a failed download, no .zip or .mlpackage should be left
        let destDir = ModelRegistry.userModelsDirectory
        if FileManager.default.fileExists(atPath: destDir.path) {
            let contents = try FileManager.default.contentsOfDirectory(atPath: destDir.path)
            let gfpganFiles = contents.filter { $0.lowercased().contains("gfpgan") }
            XCTAssertTrue(gfpganFiles.isEmpty,
                          "No partial GFPGAN files should remain after failed download: \(gfpganFiles)")
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

        let binaryPath = projectRoot
            .appendingPathComponent(".build/debug/superscale")

        process.executableURL = binaryPath
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
