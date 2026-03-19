// ABOUTME: Tests for ContentDetector — automatic content type classification.
// ABOUTME: Validates illustration vs photo detection using colour diversity heuristic.

import XCTest
import CoreGraphics
@testable import Superscale

final class ContentDetectorTests: XCTestCase {

    private var testImagesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SuperscaleTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
            .appendingPathComponent("Tests/images")
    }

    // RT-035: Illustration labels above threshold → anime model selected
    func test_interpret_illustration_labels_selects_anime_model_RT035() {
        // Arrange: simulate VNClassifyImageRequest results with high illustration confidence
        let labels: [(identifier: String, confidence: Float)] = [
            (identifier: "illustrations", confidence: 0.85),
            (identifier: "outdoor", confidence: 0.3),
            (identifier: "nature", confidence: 0.2),
        ]

        // Act
        let result = ContentDetector.interpret(labels: labels)
        let modelName = ContentDetector.modelName(for: result.type, scale: 4)

        // Assert
        XCTAssertEqual(result.type, .illustration,
                       "High illustration confidence should classify as illustration")
        XCTAssertEqual(modelName, "realesrgan-anime-6b",
                       "Illustration content at 4× should select anime model")
    }

    // RT-036: Semi-photorealistic illustration detected as illustration
    func test_detect_semi_photorealistic_illustration_RT036() throws {
        let imageURL = testImagesDir.appendingPathComponent("remy2.jpg")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: imageURL.path),
                      "remy2.jpg not found")

        let loaded = try ImageLoader.load(from: imageURL)

        // Act
        let result = try ContentDetector.detect(image: loaded.image)
        let modelName = ContentDetector.modelName(for: result.type, scale: 4)

        // Assert
        XCTAssertEqual(result.type, .illustration,
                       "Semi-photorealistic illustration should be detected as illustration")
        XCTAssertEqual(modelName, "realesrgan-anime-6b",
                       "Illustration content at 4× should select anime model")
    }

    // RT-047: Flat sketch/illustration detected as illustration
    func test_detect_sketch_classifies_as_illustration_RT047() throws {
        let imageURL = testImagesDir.appendingPathComponent("sketch1.png")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: imageURL.path),
                      "sketch1.png not found")

        let loaded = try ImageLoader.load(from: imageURL)

        // Act
        let result = try ContentDetector.detect(image: loaded.image)
        let modelName = ContentDetector.modelName(for: result.type, scale: 4)

        // Assert
        XCTAssertEqual(result.type, .illustration,
                       "Sketch should be detected as illustration")
        XCTAssertEqual(modelName, "realesrgan-anime-6b",
                       "Illustration content at 4× should select anime model")
    }

    // RT-049: Photograph detected as photo
    func test_detect_photograph_selects_photo_model_RT049() throws {
        let imageURL = testImagesDir.appendingPathComponent("toby.jpg")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: imageURL.path),
                      "toby.jpg not found")

        let loaded = try ImageLoader.load(from: imageURL)

        // Act
        let result = try ContentDetector.detect(image: loaded.image)
        let modelName = ContentDetector.modelName(for: result.type, scale: 4)

        // Assert
        XCTAssertEqual(result.type, .photo,
                       "A photograph should be detected as photo content")
        XCTAssertEqual(modelName, "realesrgan-x4plus",
                       "Photo content at 4× should select default photo model")
    }

    // RT-050: Landscape photograph detected as photo
    func test_detect_landscape_photograph_selects_photo_model_RT050() throws {
        let imageURL = testImagesDir.appendingPathComponent("roundwood.jpg")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: imageURL.path),
                      "roundwood.jpg not found")

        let loaded = try ImageLoader.load(from: imageURL)

        // Act
        let result = try ContentDetector.detect(image: loaded.image)
        let modelName = ContentDetector.modelName(for: result.type, scale: 4)

        // Assert
        XCTAssertEqual(result.type, .photo,
                       "A landscape photograph should be detected as photo content")
        XCTAssertEqual(modelName, "realesrgan-x4plus",
                       "Photo content at 4× should select default photo model")
    }

    // Additional: illustration below threshold falls back to photo
    func test_interpret_low_illustration_confidence_falls_back_to_photo_RT035b() {
        // Arrange: illustration label present but below threshold
        let labels: [(identifier: String, confidence: Float)] = [
            (identifier: "illustrations", confidence: 0.05),
            (identifier: "outdoor", confidence: 0.8),
        ]

        // Act
        let result = ContentDetector.interpret(labels: labels)

        // Assert
        XCTAssertEqual(result.type, .photo,
                       "Low illustration confidence should fall back to photo")
    }

    // Additional: model name mapping respects scale
    func test_model_name_maps_illustration_2x_to_x2plus_RT035c() {
        // No anime 2× model exists — should fall back to general x2plus
        let modelName = ContentDetector.modelName(for: .illustration, scale: 2)
        XCTAssertEqual(modelName, "realesrgan-x2plus",
                       "Illustration at 2× should fall back to x2plus (no anime 2× variant)")
    }

    func test_model_name_maps_photo_2x_to_x2plus_RT036b() {
        let modelName = ContentDetector.modelName(for: .photo, scale: 2)
        XCTAssertEqual(modelName, "realesrgan-x2plus",
                       "Photo at 2× should select x2plus model")
    }
}
