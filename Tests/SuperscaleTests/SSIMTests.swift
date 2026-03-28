// ABOUTME: Tests for SSIM computation and quality regression against PyTorch references.
// ABOUTME: Covers RT-062 (reference existence), RT-063 (SSIM correctness), RT-064 (quality gate).

import XCTest
import CoreGraphics
@testable import Superscale

final class SSIMTests: XCTestCase {

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SuperscaleTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
    }

    private var testImagesDir: URL {
        projectRoot.appendingPathComponent("Tests/images")
    }

    private var referencesDir: URL {
        projectRoot.appendingPathComponent("Tests/SuperscaleTests/Resources/references")
    }

    private var defaultModelURL: URL {
        projectRoot.appendingPathComponent("models/RealESRGAN_x4plus.mlpackage")
    }

    /// Test image filenames for SSIM comparison.
    private let testImages = [
        "remy1.png", "remy2.jpg", "toby.jpg",
        "vance-wilson.jpg", "icon.png", "icon2.png", "icon3.png",
    ]

    // MARK: - RT-062: Reference images exist with correct dimensions

    func test_reference_images_exist_with_correct_dimensions_RT062() throws {
        let fm = FileManager.default

        // Skip if no reference images have been generated yet.
        let refExists = testImages.contains { filename in
            let stem = (filename as NSString).deletingPathExtension
            return fm.fileExists(
                atPath: referencesDir.appendingPathComponent("\(stem)_ref.png").path)
        }
        try XCTSkipIf(
            !refExists,
            "Reference images not generated — run scripts/generate_references.py first")

        for filename in testImages {
            let stem = (filename as NSString).deletingPathExtension
            let refPath = referencesDir.appendingPathComponent("\(stem)_ref.png")

            XCTAssertTrue(
                fm.fileExists(atPath: refPath.path),
                "Reference image missing: \(stem)_ref.png")

            // Load input to get expected dimensions.
            let inputURL = testImagesDir.appendingPathComponent(filename)
            let inputImage = try ImageLoader.load(from: inputURL).image
            let expectedWidth = inputImage.width * 4
            let expectedHeight = inputImage.height * 4

            let refImage = try ImageLoader.load(from: refPath).image
            XCTAssertEqual(
                refImage.width, expectedWidth,
                "\(stem)_ref.png width: expected \(expectedWidth), got \(refImage.width)")
            XCTAssertEqual(
                refImage.height, expectedHeight,
                "\(stem)_ref.png height: expected \(expectedHeight), got \(refImage.height)")
        }
    }

    // MARK: - RT-063: SSIM computation correctness

    func test_ssim_identical_images_equals_one_RT063a() throws {
        let image = try makeTestImage(width: 64, height: 64, red: 128, green: 200, blue: 50)
        let score = try SSIM.compute(between: image, and: image)
        XCTAssertEqual(score, 1.0, accuracy: 0.001,
                       "SSIM of identical images should be 1.0")
    }

    func test_ssim_completely_different_images_is_low_RT063b() throws {
        let black = try makeTestImage(width: 64, height: 64, red: 0, green: 0, blue: 0)
        let white = try makeTestImage(width: 64, height: 64, red: 255, green: 255, blue: 255)
        let score = try SSIM.compute(between: black, and: white)
        XCTAssertLessThan(score, 0.1,
                          "SSIM of black vs white should be very low, got \(score)")
    }

    func test_ssim_similar_images_in_midrange_RT063c() throws {
        // Create two images that are similar but not identical.
        let imageA = try makeTestImage(width: 64, height: 64, red: 128, green: 128, blue: 128)
        let imageB = try makeTestImage(width: 64, height: 64, red: 140, green: 140, blue: 140)
        let score = try SSIM.compute(between: imageA, and: imageB)
        XCTAssertGreaterThan(score, 0.5,
                             "SSIM of similar images should be above 0.5, got \(score)")
        XCTAssertLessThan(score, 1.0,
                          "SSIM of non-identical images should be below 1.0, got \(score)")
    }

    // MARK: - RT-064: CoreML output achieves SSIM ≥ 0.90 against PyTorch reference
    // Slow test (~2.5 min) — excluded from `make test`, run via `make test-ssim`.
    // The "SSIM_RT064" suffix allows `swift test --filter SSIM_RT064` targeting.

    func test_coreml_output_ssim_against_pytorch_reference_SSIM_RT064() throws {
        let fm = FileManager.default

        try XCTSkipIf(
            !fm.fileExists(atPath: referencesDir.path),
            "Reference images not generated — run scripts/generate_references.py first")
        try XCTSkipIf(
            !fm.fileExists(atPath: defaultModelURL.path),
            "Default model not available — run make build first")

        let pipeline = try Pipeline(modelName: "realesrgan-x4plus", faceEnhance: false)
        let threshold: Float = 0.90

        for filename in testImages {
            let stem = (filename as NSString).deletingPathExtension
            let inputURL = testImagesDir.appendingPathComponent(filename)
            let refPath = referencesDir.appendingPathComponent("\(stem)_ref.png")

            try XCTSkipIf(
                !fm.fileExists(atPath: refPath.path),
                "Reference image missing: \(stem)_ref.png")

            // Upscale via CoreML.
            let outputURL = fm.temporaryDirectory
                .appendingPathComponent("ssim_test_\(stem)_\(UUID().uuidString).png")
            defer { try? fm.removeItem(at: outputURL) }

            try pipeline.process(input: inputURL, output: outputURL)

            // Load both images and compute SSIM.
            let coremlImage = try ImageLoader.load(from: outputURL).image
            let refImage = try ImageLoader.load(from: refPath).image

            let score = try SSIM.compute(between: coremlImage, and: refImage)
            XCTAssertGreaterThanOrEqual(
                score, threshold,
                "\(filename): SSIM \(score) is below threshold \(threshold)")
        }
    }

    // MARK: - Helpers

    /// Create a solid-colour test image.
    private func makeTestImage(
        width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8
    ) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        for i in 0..<(width * height) {
            pixels[i * 4] = red
            pixels[i * 4 + 1] = green
            pixels[i * 4 + 2] = blue
            pixels[i * 4 + 3] = 255
        }

        guard let context = CGContext(
            data: &pixels,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw ImageIOError.contextCreationFailed
        }
        return image
    }
}
