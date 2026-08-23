// ABOUTME: Verifies selected and generated files share one GUI upscale coordinator path.
// ABOUTME: Covers option preservation, results, and consistent local-processing failures.

import AppKit
import Foundation
import SuperscaleKit
import XCTest
@testable import SuperscaleUXCore

final class GUIUpscaleCoordinatorTests: XCTestCase {
    // RT-71.1
    func test_selectedFixtureReachesSharedCoordinatorAndYieldsResult() async throws {
        let fixture = try makeFixture(named: "selected.png", contents: Data("selected".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
        let processor = RecordingUpscaleProcessor()
        let coordinator = GUIUpscaleCoordinator(processor: processor)

        let result = try await coordinator.process(
            source: .imported(fixture),
            options: defaultOptions,
            onProgress: { _ in }
        )

        XCTAssertEqual(result.source, .imported(fixture))
        XCTAssertEqual(result.imageData, Data("selected-upscaled".utf8))
        XCTAssertEqual(processor.requests.map(\.inputURL), [fixture])
    }

    // RT-71.1
    func test_selectedFixtureRunsThroughSuperscaleProcessor() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixture = repositoryRoot.appendingPathComponent("Tests/images/icon3.png")
        let model = repositoryRoot.appendingPathComponent("models/RealESRGAN_x2plus.mlpackage")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: model.path), "2x model is not installed")
        let coordinator = GUIUpscaleCoordinator()

        let result = try await coordinator.process(
            source: .imported(fixture),
            options: GUIUpscaleOptions(
                selectedModelName: "realesrgan-x2plus",
                faceEnhance: false,
                sizing: .preset(scale: 2)
            ),
            onProgress: { _ in }
        )

        let image = try XCTUnwrap(NSBitmapImageRep(data: result.imageData))
        XCTAssertEqual(image.pixelsWide, 448)
        XCTAssertEqual(image.pixelsHigh, 414)
        XCTAssertEqual(result.resolvedModelName, "realesrgan-x2plus")
        XCTAssertFalse(result.wasAutoDetect)
    }

    // RT-71.2
    func test_modelScaleAndFaceOptionsArePreserved() async throws {
        let fixture = try makeFixture(named: "options.png", contents: Data("options".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
        let processor = RecordingUpscaleProcessor()
        let coordinator = GUIUpscaleCoordinator(processor: processor)
        let options = GUIUpscaleOptions(
            selectedModelName: "realesrgan-anime-6b",
            faceEnhance: true,
            sizing: .custom(width: 1200, height: 800, stretch: true)
        )

        _ = try await coordinator.process(
            source: .imported(fixture), options: options, onProgress: { _ in })

        XCTAssertEqual(processor.requests.first?.options, options)
    }

    // RT-71.3
    func test_generatedFixtureUsesTheSameCoordinatorAndYieldsResult() async throws {
        let fixture = try makeFixture(named: "generated.png", contents: Data("generated".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
        let processor = RecordingUpscaleProcessor()
        let coordinator = GUIUpscaleCoordinator(processor: processor)

        let result = try await coordinator.process(
            source: GUIUpscaleSource(origin: .generatedFile, url: fixture),
            options: defaultOptions,
            onProgress: { _ in }
        )

        XCTAssertEqual(result.source, GUIUpscaleSource(origin: .generatedFile, url: fixture))
        XCTAssertEqual(result.imageData, Data("generated-upscaled".utf8))
        XCTAssertEqual(processor.requests.count, 1)
    }

    // RT-71.4
    func test_selectedAndGeneratedFailuresExposeTheSameDiagnostic() async throws {
        let fixture = try makeFixture(named: "failure.png", contents: Data("failure".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
        let coordinator = GUIUpscaleCoordinator(processor: FailingUpscaleProcessor())

        let selectedError = await captureError {
            _ = try await coordinator.process(
                source: .imported(fixture), options: defaultOptions, onProgress: { _ in })
        }
        let generatedError = await captureError {
            _ = try await coordinator.process(
                source: GUIUpscaleSource(origin: .generatedFile, url: fixture),
                options: defaultOptions, onProgress: { _ in })
        }

        XCTAssertEqual(selectedError, "Fixture processing failed")
        XCTAssertEqual(generatedError, selectedError)
    }

    private var defaultOptions: GUIUpscaleOptions {
        GUIUpscaleOptions(
            selectedModelName: "auto",
            faceEnhance: false,
            sizing: .preset(scale: 4)
        )
    }

    private func makeFixture(named name: String, contents: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GUIUpscaleCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }

    private func captureError(_ operation: () async throws -> Void) async -> String {
        do {
            try await operation()
            XCTFail("Expected processing to fail")
            return ""
        } catch {
            return error.localizedDescription
        }
    }
}

private final class RecordingUpscaleProcessor: GUIUpscaleProcessing, @unchecked Sendable {
    struct Request {
        let inputURL: URL
        let options: GUIUpscaleOptions
    }

    private(set) var requests: [Request] = []

    func process(
        inputURL: URL,
        options: GUIUpscaleOptions,
        onProgress: @escaping @Sendable (PipelineProgress) -> Void
    ) throws -> GUIUpscaleProcessedImage {
        requests.append(Request(inputURL: inputURL, options: options))
        let input = try Data(contentsOf: inputURL)
        return GUIUpscaleProcessedImage(
            imageData: input + Data("-upscaled".utf8),
            preFaceImageData: nil,
            resolvedModelName: options.selectedModelName == "auto" ? "realesrgan-x4plus" : options.selectedModelName,
            wasAutoDetect: options.selectedModelName == "auto"
        )
    }
}

private struct FailingUpscaleProcessor: GUIUpscaleProcessing {
    func process(
        inputURL: URL,
        options: GUIUpscaleOptions,
        onProgress: @escaping @Sendable (PipelineProgress) -> Void
    ) throws -> GUIUpscaleProcessedImage {
        throw Failure.fixture
    }

    private enum Failure: LocalizedError {
        case fixture

        var errorDescription: String? { "Fixture processing failed" }
    }
}
