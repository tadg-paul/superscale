// ABOUTME: Tests for the Pipeline — end-to-end upscaling orchestration.
// ABOUTME: Validates pipeline output, progress reporting, error handling, and small image padding.

import XCTest
import CoreGraphics
import ImageIO
@testable import SuperscaleKit

final class PipelineTests: XCTestCase {

    private var testImagesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SuperscaleTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
            .appendingPathComponent("Tests/images")
    }

    private var modelsDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("models")
    }

    // RT-021: Full pipeline produces correctly scaled output
    func test_pipeline_produces_correctly_scaled_output_RT021() throws {
        let inputURL = testImagesDir.appendingPathComponent("remy2.jpg")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: inputURL.path),
                      "Test image remy2.jpg not found")

        let modelURL = modelsDir.appendingPathComponent("RealESRGAN_x2plus.mlpackage")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: modelURL.path),
                      "x2plus model not found — run make convert-models")

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscale_pipeline_test_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let pipeline = try Pipeline(modelName: "realesrgan-x2plus")
        try pipeline.process(input: inputURL, output: outputURL)

        // Verify output exists and has correct dimensions (1024×2 = 2048)
        let result = try ImageLoader.load(from: outputURL)
        XCTAssertEqual(result.image.width, 2048, "Output width should be 2× input")
        XCTAssertEqual(result.image.height, 2048, "Output height should be 2× input")
    }

    // RT-022: Pipeline reports progress on stderr during multi-tile processing
    func test_pipeline_reports_progress_RT022() throws {
        let inputURL = testImagesDir.appendingPathComponent("remy2.jpg")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: inputURL.path),
                      "Test image remy2.jpg not found")

        let modelURL = modelsDir.appendingPathComponent("RealESRGAN_x2plus.mlpackage")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: modelURL.path),
                      "x2plus model not found — run make convert-models")

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscale_progress_test_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        // Capture progress messages
        var progressMessages: [String] = []
        let pipeline = try Pipeline(modelName: "realesrgan-x2plus", tileSize: 256)
        pipeline.onProgress = { message in
            progressMessages.append(message)
        }

        try pipeline.process(input: inputURL, output: outputURL)

        // With 1024×1024 input and 256 tile size, should get multiple tiles
        XCTAssertGreaterThan(progressMessages.count, 0,
                             "Should report progress during processing")
        // At least one message should mention tile processing
        let hasTileMessage = progressMessages.contains { $0.contains("tile") || $0.contains("Tile") }
        XCTAssertTrue(hasTileMessage, "Progress should mention tile processing")
    }

    // RT-023: Pipeline errors on non-existent input path
    func test_pipeline_errors_on_invalid_input_RT023() throws {
        let badURL = URL(fileURLWithPath: "/nonexistent/path/image.png")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscale_error_test_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let pipeline = try Pipeline(modelName: "realesrgan-x2plus")

        XCTAssertThrowsError(try pipeline.process(input: badURL, output: outputURL)) { error in
            let description = String(describing: error)
            XCTAssertTrue(
                description.lowercased().contains("read") ||
                description.lowercased().contains("not found") ||
                description.lowercased().contains("cannot"),
                "Error should describe the problem: \(description)")
        }
    }

    // MARK: - Small image upscaling tests (#42)

    // RT-087: Opaque image smaller than tile size preserves full content
    func test_pipeline_small_opaque_image_preserves_content_RT087() throws {
        let modelURL = modelsDir.appendingPathComponent("RealESRGAN_x4plus.mlpackage")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: modelURL.path),
                      "x4plus model not found")

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscale_rt087_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Arrange: 100×50 opaque image, left half red, right half blue.
        // This non-square aspect ratio (2:1) makes .scaleFill stretching
        // detectable: without padding, the blue right half is lost entirely
        // because the stretch maps the full image to 512×512 and only the
        // top-left fraction of the output survives the crop.
        let inputURL = tmpDir.appendingPathComponent("small_100x50.png")
        try createSplitColourImage(width: 100, height: 50, at: inputURL,
                                   leftRed: true, rightBlue: true, withAlpha: false)

        let outputURL = tmpDir.appendingPathComponent("small_100x50_4x.png")

        // Act
        let pipeline = try Pipeline(modelName: "realesrgan-x4plus")
        try pipeline.process(input: inputURL, output: outputURL)

        // Assert: correct dimensions (100×4=400, 50×4=200)
        let result = try ImageLoader.load(from: outputURL)
        XCTAssertEqual(result.image.width, 400,
                       "Output width should be 100×4=400, got \(result.image.width)")
        XCTAssertEqual(result.image.height, 200,
                       "Output height should be 50×4=200, got \(result.image.height)")

        // Assert: right edge still has blue content (not red from stretching).
        // Without the padding fix, .scaleFill stretches the entire 100×50 image
        // to 512×512, and the visible 400×200 crop only captures the leftmost
        // ~20% of the stretched content — all red, with blue completely lost.
        let rightEdge = samplePixel(result.image, x: 380, y: 100)
        XCTAssertNotNil(rightEdge, "Should sample right-edge pixel")
        if let px = rightEdge {
            XCTAssertGreaterThan(px.b, px.r,
                                 "Right edge should be blue, not red (stretch distortion detected). " +
                                 "R=\(px.r) G=\(px.g) B=\(px.b)")
        }

        // Also verify left edge is still red
        let leftEdge = samplePixel(result.image, x: 20, y: 100)
        XCTAssertNotNil(leftEdge, "Should sample left-edge pixel")
        if let px = leftEdge {
            XCTAssertGreaterThan(px.r, px.b,
                                 "Left edge should be red, not blue. " +
                                 "R=\(px.r) G=\(px.g) B=\(px.b)")
        }
    }

    // RT-088: Transparent image smaller than tile size has aligned RGB and alpha
    func test_pipeline_small_transparent_image_aligned_channels_RT088() throws {
        let modelURL = modelsDir.appendingPathComponent("RealESRGAN_x4plus.mlpackage")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: modelURL.path),
                      "x4plus model not found")

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscale_rt088_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Arrange: 100×50 RGBA image.
        // Top half: transparent (alpha=0).
        // Bottom half: opaque bright blue (0, 0, 255, 255).
        // Without the padding fix, .scaleFill stretches the 100×50 image to
        // 512×512. The visible crop shows only the top-left ~20×5 pixels of
        // the original, which is entirely in the transparent region. The
        // RGB content from that region is black/garbage. After recombination
        // with the correctly-resized alpha (bottom half opaque), the result
        // is opaque black where it should be opaque blue.
        let inputURL = tmpDir.appendingPathComponent("small_alpha_100x50.png")
        try createTopTransparentBottomBlueImage(width: 100, height: 50, at: inputURL)

        let outputURL = tmpDir.appendingPathComponent("small_alpha_100x50_4x.png")

        // Act
        let pipeline = try Pipeline(modelName: "realesrgan-x4plus")
        try pipeline.process(input: inputURL, output: outputURL)

        // Assert: correct dimensions
        let result = try ImageLoader.load(from: outputURL)
        XCTAssertEqual(result.image.width, 400,
                       "Output width should be 100×4=400, got \(result.image.width)")
        XCTAssertEqual(result.image.height, 200,
                       "Output height should be 50×4=200, got \(result.image.height)")

        // Assert: bottom area is opaque blue (not opaque black from stretch artefact).
        // Sample in the centre of the bottom half — should be opaque with blue dominant.
        let bottomCentre = samplePixelRGBA(result.image, x: 200, y: 150)
        XCTAssertNotNil(bottomCentre, "Should sample bottom-centre pixel")
        if let px = bottomCentre {
            XCTAssertGreaterThan(px.a, 200,
                                 "Bottom pixel should be opaque, got alpha=\(px.a)")
            XCTAssertGreaterThan(px.b, 50,
                                 "Bottom pixel should have blue content, got B=\(px.b). " +
                                 "R=\(px.r) G=\(px.g) B=\(px.b) A=\(px.a)")
        }

        // Assert: top area is transparent
        let topCentre = samplePixelRGBA(result.image, x: 200, y: 20)
        XCTAssertNotNil(topCentre, "Should sample top-centre pixel")
        if let px = topCentre {
            XCTAssertLessThan(px.a, 50,
                              "Top pixel should be transparent, got alpha=\(px.a)")
        }
    }

    // RT-089: Large image (multi-tile) produces identical output dimensions
    func test_pipeline_large_image_unchanged_RT089() throws {
        let inputURL = testImagesDir.appendingPathComponent("remy2.jpg")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: inputURL.path),
                      "Test image remy2.jpg not found")

        let modelURL = modelsDir.appendingPathComponent("RealESRGAN_x4plus.mlpackage")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: modelURL.path),
                      "x4plus model not found")

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscale_rt089_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        // Act: 1024×1024 input with default 512 tile size → multi-tile processing
        let pipeline = try Pipeline(modelName: "realesrgan-x4plus")
        try pipeline.process(input: inputURL, output: outputURL)

        // Assert: dimensions correct (1024×4 = 4096)
        let result = try ImageLoader.load(from: outputURL)
        XCTAssertEqual(result.image.width, 4096,
                       "Large image output width should be 1024×4=4096, got \(result.image.width)")
        XCTAssertEqual(result.image.height, 4096,
                       "Large image output height should be 1024×4=4096, got \(result.image.height)")
    }

    // MARK: - Test image helpers

    /// Create an opaque image with left half one colour, right half another.
    private func createSplitColourImage(
        width: Int, height: Int, at url: URL,
        leftRed: Bool, rightBlue: Bool, withAlpha: Bool
    ) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let alphaInfo: CGImageAlphaInfo = withAlpha ? .premultipliedLast : .noneSkipLast
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: alphaInfo.rawValue
        ) else {
            throw NSError(domain: "test", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot create CGContext"])
        }

        // Left half: red
        ctx.setFillColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))

        // Right half: blue
        ctx.setFillColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0)
        ctx.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))

        try writeImage(from: ctx, to: url)
    }

    /// Create an RGBA image: top half transparent, bottom half opaque blue.
    private func createTopTransparentBottomBlueImage(
        width: Int, height: Int, at url: URL
    ) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "test", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot create CGContext"])
        }

        // Clear to fully transparent
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))

        // Bottom half: opaque blue.
        // CGContext origin is bottom-left, so "bottom half" in image coords
        // (y increasing downward) is the top half in CGContext coords.
        ctx.setFillColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))

        try writeImage(from: ctx, to: url)
    }

    private func writeImage(from ctx: CGContext, to url: URL) throws {
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

    private struct RGBPixel {
        let r: UInt8
        let g: UInt8
        let b: UInt8
    }

    private struct RGBAPixel {
        let r: UInt8
        let g: UInt8
        let b: UInt8
        let a: UInt8
    }

    private func samplePixel(_ image: CGImage, x: Int, y: Int) -> RGBPixel? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(
            x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        guard let data = ctx.data else { return nil }
        let ptr = data.assumingMemoryBound(to: UInt8.self)
        return RGBPixel(r: ptr[0], g: ptr[1], b: ptr[2])
    }

    private func samplePixelRGBA(_ image: CGImage, x: Int, y: Int) -> RGBAPixel? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(
            x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        guard let data = ctx.data else { return nil }
        let ptr = data.assumingMemoryBound(to: UInt8.self)
        return RGBAPixel(r: ptr[0], g: ptr[1], b: ptr[2], a: ptr[3])
    }
}
