// ABOUTME: Tests for the model manifest file (models/manifest.json).
// ABOUTME: Validates manifest schema, model entries, and required fields.

import XCTest

final class ManifestTests: XCTestCase {

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SuperscaleTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
    }

    // RT-032: manifest.json contains entries for all six models with name, sha256, url
    func test_manifest_contains_all_models_with_required_fields_RT032() throws {
        let manifestURL = projectRoot.appendingPathComponent("models/manifest.json")
        let data = try Data(contentsOf: manifestURL)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json, "manifest.json must be a JSON object")

        // Must have a release_tag field
        let releaseTag = json?["release_tag"] as? String
        XCTAssertNotNil(releaseTag, "manifest.json must contain 'release_tag'")

        // Must have a models array
        let models = json?["models"] as? [[String: Any]]
        XCTAssertNotNil(models, "manifest.json must contain 'models' array")
        XCTAssertEqual(models?.count, 7, "Expected 7 model entries")

        let expectedNames = Set([
            "realesrgan-x4plus",
            "realesrgan-x2plus",
            "realesrnet-x4plus",
            "realesrgan-anime-6b",
            "realesr-animevideov3",
            "realesr-general-x4v3",
            "realesr-general-wdn-x4v3",
        ])

        let actualNames = Set(models?.compactMap { $0["name"] as? String } ?? [])
        XCTAssertEqual(actualNames, expectedNames, "Manifest must list all seven models")

        // Each model must have required fields
        for model in models ?? [] {
            let name = model["name"] as? String ?? "<unknown>"
            XCTAssertNotNil(model["filename"] as? String,
                            "Model '\(name)' must have 'filename'")
            XCTAssertNotNil(model["sha256"] as? String,
                            "Model '\(name)' must have 'sha256'")
            XCTAssertNotNil(model["url"] as? String,
                            "Model '\(name)' must have 'url'")
            XCTAssertNotNil(model["scale"] as? Int,
                            "Model '\(name)' must have 'scale'")
        }
    }
}
