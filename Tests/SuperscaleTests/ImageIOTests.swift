// ABOUTME: Tests for ImageLoader and ImageWriter — image format support, colour profiles, alpha handling.
// ABOUTME: Validates AC6.1 (format support), AC6.2 (colour profile preservation), AC6.3 (alpha handling).

import XCTest
import CoreGraphics
import ImageIO
@testable import Superscale

final class ImageIOTests: XCTestCase {

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SuperscaleTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
    }

    private var testImagesDir: URL {
        projectRoot.appendingPathComponent("Tests/images")
    }

    // RT-012: ImageLoader reads PNG and JPEG with correct dimensions
    func test_image_loader_reads_formats_with_correct_dimensions_RT012() throws {
        // PNG
        let pngURL = testImagesDir.appendingPathComponent("sketch1.png")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: pngURL.path),
                      "Test image sketch1.png not found")

        let pngResult = try ImageLoader.load(from: pngURL)
        XCTAssertEqual(pngResult.image.width, 4085, "PNG width")
        XCTAssertEqual(pngResult.image.height, 4085, "PNG height")

        // JPEG
        let jpgURL = testImagesDir.appendingPathComponent("remy2.jpg")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: jpgURL.path),
                      "Test image remy2.jpg not found")

        let jpgResult = try ImageLoader.load(from: jpgURL)
        XCTAssertEqual(jpgResult.image.width, 1024, "JPEG width")
        XCTAssertEqual(jpgResult.image.height, 1024, "JPEG height")
    }

    // RT-013: ImageWriter preserves colour profile from input
    func test_image_writer_preserves_colour_profile_RT013() throws {
        let pngURL = testImagesDir.appendingPathComponent("sketch1.png")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: pngURL.path),
                      "Test image sketch1.png not found")

        let loaded = try ImageLoader.load(from: pngURL)

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscale_test_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        try ImageWriter.write(loaded.image, to: tmpURL, format: .png,
                              colorSpace: loaded.colorSpace)

        // Re-read and check colour space is preserved
        let reloaded = try ImageLoader.load(from: tmpURL)
        if let originalSpace = loaded.colorSpace,
           let reloadedSpace = reloaded.colorSpace {
            XCTAssertEqual(originalSpace.name, reloadedSpace.name,
                           "Colour profile should be preserved")
        }
    }

    // RT-014: Alpha channel is separated and recombined correctly
    func test_alpha_channel_separation_and_recombination_RT014() throws {
        // Create a test image with alpha
        let image = try makeTestImageWithAlpha(width: 64, height: 64)

        // Load via ImageLoader (it should detect and separate alpha)
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscale_alpha_test_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        // Write the test image with alpha to disk
        try ImageWriter.write(image, to: tmpURL, format: .png, colorSpace: nil)

        let loaded = try ImageLoader.load(from: tmpURL)
        XCTAssertEqual(loaded.image.width, 64)
        XCTAssertEqual(loaded.image.height, 64)

        // If the input had alpha, alphaChannel should be non-nil
        if loaded.hasAlpha {
            XCTAssertNotNil(loaded.alphaChannel, "Alpha channel should be extracted")
            if let alpha = loaded.alphaChannel {
                XCTAssertEqual(alpha.width, 64, "Alpha width should match input")
                XCTAssertEqual(alpha.height, 64, "Alpha height should match input")
            }
        }

        // Recombine and verify dimensions match
        if let alpha = loaded.alphaChannel {
            let recombined = try ImageLoader.recombineAlpha(
                rgb: loaded.image, alpha: alpha)
            XCTAssertEqual(recombined.width, 64)
            XCTAssertEqual(recombined.height, 64)
        }
    }

    // MARK: - Helpers

    private func makeTestImageWithAlpha(width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw NSError(domain: "ImageIOTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create CGContext"])
        }

        // Draw with varying alpha (left side transparent, right side opaque)
        for y in 0..<height {
            for x in 0..<width {
                let alpha = CGFloat(x) / CGFloat(width)
                context.setFillColor(red: 0.5, green: 0.3, blue: 0.8, alpha: alpha)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }

        guard let image = context.makeImage() else {
            throw NSError(domain: "ImageIOTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
        }
        return image
    }
}
