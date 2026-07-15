// ABOUTME: Verifies fixture-backed generation state, reference limits, and output handoff.
// ABOUTME: Exercises the Generate workspace coordinator without paid provider calls.

import FalGenerationKit
import Foundation
import XCTest
@testable import SuperscaleUXCore

@MainActor
final class GenerationCoordinatorTests: XCTestCase {
    // RT-75.1, RT-75.2
    func test_referenceSelectionAcceptsAtMostThreeImages() throws {
        let selection = GenerationReferenceSelection()
        let urls = (1...4).map { URL(fileURLWithPath: "/tmp/reference-\($0).png") }

        for url in urls.prefix(3) {
            try selection.add(url)
        }
        XCTAssertEqual(selection.urls, Array(urls.prefix(3)))
        XCTAssertThrowsError(try selection.add(urls[3]))
    }

    // RT-75.3
    func test_generationProgressesToDownloadedOutput() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = FixtureGenerationService(
            result: .success(
                FalGeneratedImage(
                    remoteURL: try XCTUnwrap(URL(string: "https://images.example/output.png")),
                    data: Data("generated-image".utf8),
                    contentType: "image/png",
                    warnings: []
                )
            )
        )
        let coordinator = GenerationCoordinator(
            service: service,
            outputStore: GeneratedImageStore(directory: directory)
        )

        await coordinator.generate(
            FalGenerationRequest(prompt: "A lighthouse"),
            apiKey: "fixture-key"
        )

        guard case let .succeeded(output) = coordinator.phase else {
            return XCTFail("Expected generated output")
        }
        XCTAssertEqual(try Data(contentsOf: output.localURL), Data("generated-image".utf8))
        XCTAssertEqual(output.remoteURL.absoluteString, "https://images.example/output.png")
        XCTAssertEqual(service.requests.map(\.prompt), ["A lighthouse"])
    }

    // RT-75.4
    func test_generationRepresentsProviderDownloadAndCancellationFailures() async {
        for (error, expectedPhase) in [
            (FalGenerationError.providerFailure(statusCode: 500, diagnostic: "fixture"), "failed"),
            (FalGenerationError.downloadFailure("fixture"), "failed"),
            (CancellationError(), "cancelled"),
        ] as [(Error, String)] {
            let coordinator = GenerationCoordinator(
                service: FixtureGenerationService(result: .failure(error)),
                outputStore: GeneratedImageStore(directory: temporaryDirectory())
            )

            await coordinator.generate(FalGenerationRequest(prompt: "Fixture"), apiKey: "fixture-key")

            switch (coordinator.phase, expectedPhase) {
            case (.failed, "failed"), (.cancelled, "cancelled"):
                break
            default:
                XCTFail("Expected \(expectedPhase), got \(coordinator.phase)")
            }
        }
    }

    // RT-75.6
    func test_successfulOutputExposesGeneratedFileForSharedUpscaleHandoff() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinator = GenerationCoordinator(
            service: FixtureGenerationService(
                result: .success(
                    FalGeneratedImage(
                        remoteURL: try XCTUnwrap(URL(string: "https://images.example/handoff.jpg")),
                        data: Data("handoff".utf8),
                        contentType: "image/jpeg",
                        warnings: []
                    )
                )
            ),
            outputStore: GeneratedImageStore(directory: directory)
        )

        await coordinator.generate(FalGenerationRequest(prompt: "Handoff"), apiKey: "fixture-key")

        XCTAssertEqual(coordinator.upscaleSource, coordinator.output.map { .generatedFile($0.localURL) })
    }

    private func temporaryDirectory() -> URL {
        projectRoot
            .appendingPathComponent(".agent/tmp/package-tests", isDirectory: true)
            .appendingPathComponent("GenerationCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

@MainActor
private final class FixtureGenerationService: GenerationServing {
    private(set) var requests: [FalGenerationRequest] = []
    let result: Result<FalGeneratedImage, Error>

    init(result: Result<FalGeneratedImage, Error>) {
        self.result = result
    }

    func generate(_ request: FalGenerationRequest, apiKey: String) async throws -> FalGeneratedImage {
        requests.append(request)
        return try result.get()
    }
}
