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

    // RT-050: Non-TTY download attempt reports clear error message
    func test_download_face_model_failure_reports_clear_error_RT050() throws {
        // Arrange: redirect stdin from /dev/null to simulate non-TTY
        let result = try runCLI(
            ["--download-face-model"],
            stdin: FileHandle.nullDevice
        )

        // Assert: non-zero exit with clear, actionable error
        XCTAssertNotEqual(result.exitCode, 0,
                          "Non-TTY --download-face-model should fail")
        XCTAssertTrue(result.stderr.contains("interactive terminal"),
                      "Should mention interactive terminal — stderr: \(result.stderr)")
        XCTAssertFalse(result.stderr.contains("couldn't be opened"),
                       "Should not show cryptic Foundation error — stderr: \(result.stderr)")
    }

    // RT-051: Non-TTY download attempt leaves no partial files behind
    func test_download_face_model_failure_leaves_no_partial_files_RT051() throws {
        try XCTSkipIf(FaceModelRegistry.isInstalled,
                      "GFPGAN model already installed — cannot test partial file cleanup")

        _ = try runCLI(
            ["--download-face-model"],
            stdin: FileHandle.nullDevice
        )

        // After a failed download, no .zip or .mlpackage should be left
        let destDir = ModelRegistry.userModelsDirectory
        if FileManager.default.fileExists(atPath: destDir.path) {
            let contents = try FileManager.default.contentsOfDirectory(atPath: destDir.path)
            let gfpganFiles = contents.filter { $0.lowercased().contains("gfpgan") }
            XCTAssertTrue(gfpganFiles.isEmpty,
                          "No partial GFPGAN files should remain after failed download: \(gfpganFiles)")
        }
    }

    // RT-052: Face enhancement modifies face regions when model is present
    func test_face_enhancement_modifies_face_regions_RT052() throws {
        try XCTSkipIf(!FaceModelRegistry.isInstalled,
                      "GFPGAN model not installed — cannot test face enhancement")

        let photoURL = testImagesDir.appendingPathComponent("remy2.jpg")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: photoURL.path),
                      "remy2.jpg not found")

        let loaded = try ImageLoader.load(from: photoURL)

        // Detect faces in the original image
        let faces = try FaceDetector.detect(in: loaded.image)
        try XCTSkipIf(faces.isEmpty, "No faces detected in remy2.jpg")

        // Run face enhancement
        let enhancer = try FaceEnhancer()
        let enhanced = try enhancer.enhance(
            image: loaded.image, faceRects: faces)

        // The enhanced image should have the same dimensions
        XCTAssertEqual(enhanced.width, loaded.image.width,
                       "Enhanced image width should match input")
        XCTAssertEqual(enhanced.height, loaded.image.height,
                       "Enhanced image height should match input")

        // Extract pixels from the face region in both images — they should differ
        let faceRect = FaceDetector.expandRect(
            faces[0], by: 1.5,
            imageWidth: loaded.image.width,
            imageHeight: loaded.image.height)

        let originalPixels = extractPixels(from: loaded.image, in: faceRect)
        let enhancedPixels = extractPixels(from: enhanced, in: faceRect)

        // At least some pixels should differ (face was enhanced)
        var diffCount = 0
        let pixelCount = min(originalPixels.count, enhancedPixels.count)
        for i in 0..<pixelCount {
            if originalPixels[i] != enhancedPixels[i] {
                diffCount += 1
            }
        }

        XCTAssertGreaterThan(diffCount, pixelCount / 10,
                             "Face region should be visibly modified by enhancement " +
                             "(only \(diffCount)/\(pixelCount) pixels differ)")
    }

    /// Extract raw pixel bytes from a region of an image.
    private func extractPixels(from image: CGImage, in rect: CGRect) -> [UInt8] {
        let x = Int(rect.origin.x)
        let y = Int(rect.origin.y)
        let w = min(Int(rect.width), image.width - x)
        let h = min(Int(rect.height), image.height - y)

        guard w > 0, h > 0,
              let cropped = image.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else {
            return []
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = w * 4
        var data = [UInt8](repeating: 0, count: h * bytesPerRow)

        guard let ctx = CGContext(
            data: &data,
            width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return []
        }
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))

        return data
    }

    // RT-053: Non-TTY invocation of --download-face-model fails with interactive terminal error
    func test_download_face_model_non_tty_fails_with_terminal_error_RT053() throws {
        // Arrange: redirect stdin from /dev/null to simulate non-TTY
        let result = try runCLI(
            ["--download-face-model"],
            stdin: FileHandle.nullDevice
        )

        // Assert: non-zero exit and clear error about interactive terminal
        XCTAssertNotEqual(result.exitCode, 0,
                          "Non-TTY --download-face-model should fail")
        XCTAssertTrue(result.stderr.contains("interactive terminal"),
                      "Error should mention interactive terminal — stderr: \(result.stderr)")
    }

    // RT-054: --accept-licence flag is removed (unknown flag error)
    func test_accept_licence_flag_removed_RT054() throws {
        let result = try runCLI(["--accept-licence"])

        // Assert: ArgumentParser rejects unknown flag
        XCTAssertNotEqual(result.exitCode, 0,
                          "--accept-licence should be rejected as unknown flag")
        // ArgumentParser reports unknown options in stderr
        let combined = result.stderr + result.stdout
        XCTAssertTrue(combined.lowercased().contains("unknown option") ||
                      combined.lowercased().contains("unexpected argument"),
                      "--accept-licence should be reported as unknown — output: \(combined)")
    }

    // MARK: - Helpers

    struct CLIResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    func runCLI(
        _ arguments: [String],
        stdin: FileHandle? = nil
    ) throws -> CLIResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        let binaryPath = projectRoot
            .appendingPathComponent(".build/debug/superscale")

        process.executableURL = binaryPath
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        if let stdin = stdin {
            process.standardInput = stdin
        }

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
