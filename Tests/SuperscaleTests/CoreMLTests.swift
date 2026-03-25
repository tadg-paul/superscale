// ABOUTME: Tests for CoreML model loading and inference.
// ABOUTME: Validates that converted .mlpackage models produce correctly-sized output.

import XCTest
import CoreGraphics
@testable import Superscale

final class CoreMLTests: XCTestCase {

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SuperscaleTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
    }

    private var defaultModelURL: URL {
        projectRoot.appendingPathComponent("models/RealESRGAN_x4plus.mlpackage")
    }

    private var modelAvailable: Bool {
        FileManager.default.fileExists(atPath: defaultModelURL.path)
    }

    // RT-010: Load x4plus model, feed test image → output has correct dimensions
    func test_coreml_inference_produces_upscaled_output_RT010() throws {
        try XCTSkipIf(!modelAvailable,
                      "Model not available at \(defaultModelURL.path). Run 'make convert-models' first.")

        let inference = try CoreMLInference(modelURL: defaultModelURL)
        let inputImage = try makeTestImage(width: 64, height: 64)

        let output = try inference.upscale(inputImage)

        // The model operates at its fixed tile size (512×512 → 2048×2048 for 4×).
        // Vision resizes the 64×64 input to match the model's expected input shape.
        // Output dimensions are determined by the model, not the input size.
        XCTAssertGreaterThan(output.width, 0, "Output image must have non-zero width")
        XCTAssertGreaterThan(output.height, 0, "Output image must have non-zero height")

        // For the default 4× model with 512×512 tile size, output should be 2048×2048
        let expectedOutputSize = 512 * 4  // tile_size × scale
        XCTAssertEqual(output.width, expectedOutputSize,
                       "Expected output width \(expectedOutputSize), got \(output.width)")
        XCTAssertEqual(output.height, expectedOutputSize,
                       "Expected output height \(expectedOutputSize), got \(output.height)")
    }

    // RT-011: Inference of 1024×1024 image completes within 30 seconds on Apple Silicon
    func test_coreml_inference_performance_RT011() throws {
        try XCTSkipIf(!modelAvailable,
                      "Model not available at \(defaultModelURL.path). Run 'make convert-models' first.")

        let inference = try CoreMLInference(modelURL: defaultModelURL)
        let inputImage = try makeTestImage(width: 1024, height: 1024)

        let start = CFAbsoluteTimeGetCurrent()
        let output = try inference.upscale(inputImage)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertGreaterThan(output.width, 0, "Output image must be valid")
        XCTAssertLessThan(elapsed, 30.0,
                          "Inference took \(String(format: "%.1f", elapsed))s — exceeds 30s target")

        // Log the timing for benchmarking (visible in test output)
        print("CoreML inference: \(String(format: "%.2f", elapsed))s for 1024×1024 input")
    }

    // RT-057: Subsequent model loads use cache and complete in under 1 second
    func test_coreml_cached_load_is_fast_RT057() throws {
        try XCTSkipIf(!modelAvailable,
                      "Model not available at \(defaultModelURL.path). Run 'make convert-models' first.")

        // Ensure clean state
        try? ModelCache.clearCache()

        // First load: compiles and caches
        _ = try CoreMLInference(modelURL: defaultModelURL)

        // Second load: should use cache and be fast
        let start = CFAbsoluteTimeGetCurrent()
        _ = try CoreMLInference(modelURL: defaultModelURL)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertLessThan(elapsed, 1.0,
                          "Cached model load took \(String(format: "%.2f", elapsed))s — should be under 1s")
    }

    // RT-058: Stale cache key triggers recompilation
    func test_coreml_stale_cache_key_triggers_recompile_RT058() throws {
        try XCTSkipIf(!modelAvailable,
                      "Model not available at \(defaultModelURL.path). Run 'make convert-models' first.")

        // Ensure clean state and populate cache
        try? ModelCache.clearCache()
        _ = try CoreMLInference(modelURL: defaultModelURL)

        // Tamper with the cache key
        let modelName = defaultModelURL.deletingPathExtension().lastPathComponent
        let cacheKeyFile = ModelCache.cacheDirectory
            .appendingPathComponent("\(modelName).cachekey")
        try "tampered".write(to: cacheKeyFile, atomically: true, encoding: .utf8)

        // Reload — should recompile and update the key
        _ = try CoreMLInference(modelURL: defaultModelURL)

        let updatedKey = try String(contentsOf: cacheKeyFile, encoding: .utf8)
        XCTAssertNotEqual(updatedKey, "tampered",
                          "Cache key should have been updated after recompilation")
    }

    // RT-060: Compiled model is stored at expected cache path
    func test_coreml_cache_stores_at_expected_path_RT060() throws {
        try XCTSkipIf(!modelAvailable,
                      "Model not available at \(defaultModelURL.path). Run 'make convert-models' first.")

        try? ModelCache.clearCache()
        _ = try CoreMLInference(modelURL: defaultModelURL)

        let modelName = defaultModelURL.deletingPathExtension().lastPathComponent
        let cachedModelPath = ModelCache.cacheDirectory
            .appendingPathComponent("\(modelName).mlmodelc")

        XCTAssertTrue(FileManager.default.fileExists(atPath: cachedModelPath.path),
                      "Compiled model should exist at \(cachedModelPath.path)")
    }

    // RT-061: Cached inference output is pixel-identical to fresh compile
    func test_coreml_cached_output_matches_fresh_RT061() throws {
        try XCTSkipIf(!modelAvailable,
                      "Model not available at \(defaultModelURL.path). Run 'make convert-models' first.")

        let inputImage = try makeTestImage(width: 64, height: 64)

        // Fresh compile
        try? ModelCache.clearCache()
        let fresh = try CoreMLInference(modelURL: defaultModelURL)
        let freshOutput = try fresh.upscale(inputImage)

        // Cached load
        let cached = try CoreMLInference(modelURL: defaultModelURL)
        let cachedOutput = try cached.upscale(inputImage)

        XCTAssertEqual(freshOutput.width, cachedOutput.width,
                       "Output width should match")
        XCTAssertEqual(freshOutput.height, cachedOutput.height,
                       "Output height should match")

        // Compare pixel data
        guard let freshData = freshOutput.dataProvider?.data as Data?,
              let cachedData = cachedOutput.dataProvider?.data as Data? else {
            XCTFail("Could not extract pixel data from output images")
            return
        }
        XCTAssertEqual(freshData, cachedData,
                       "Cached model output should be pixel-identical to fresh compile")
    }

    // MARK: - Helpers

    /// Create a synthetic test image with a simple colour pattern.
    private func makeTestImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw NSError(domain: "CoreMLTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create CGContext"])
        }

        // Draw a gradient pattern for visual verification
        for y in 0..<height {
            for x in 0..<width {
                let r = CGFloat(x) / CGFloat(width)
                let g = CGFloat(y) / CGFloat(height)
                let b = CGFloat((x + y) % 256) / 255.0
                context.setFillColor(red: r, green: g, blue: b, alpha: 1.0)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }

        guard let image = context.makeImage() else {
            throw NSError(domain: "CoreMLTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
        }
        return image
    }
}
