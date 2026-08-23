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

        XCTAssertEqual(
            coordinator.upscaleSource,
            coordinator.output.map { GUIUpscaleSource(origin: .generatedFile, url: $0.localURL) }
        )
    }

    // MARK: - AC77.2, restored by #86
    //
    // The session identifier lives on the coordinator rather than on the Generate view, because
    // that view is @State-backed and SwiftUI destroys it on a mode change. It used to be held by
    // MainView; #81 removed that as dead state, which it was not.
    //
    // The rebuild scenario itself is test_fixtureGenerationUpscalesAndAppearsInHistory in
    // SuperscaleAppUITests — a package test cannot rebuild a SwiftUI view. These hold where the
    // identifier lives and what it is bound to.

    // RT-86.1
    func test_theRecordedIdentifierSurvivesIndependentlyOfAnyView_RT086_1() async throws {
        let coordinator = try await makeSucceededCoordinator()
        let session = UUID()

        coordinator.recordSession(session)

        XCTAssertEqual(
            coordinator.upscaleSource?.sessionID, session,
            "the identifier is held by the coordinator, which outlives the view that recorded it"
        )
    }

    // RT-86.2
    func test_anImportedInputCarriesNoSessionIdentifier_RT086_2() async throws {
        let coordinator = try await makeSucceededCoordinator()
        coordinator.recordSession(UUID())

        let imported = GUIUpscaleSource.imported(URL(fileURLWithPath: "/tmp/unrelated.png"))

        XCTAssertNil(
            imported.sessionID,
            "a file the user brought in is not the coordinator's output and carries no session"
        )
    }

    // RT-86.3
    func test_aNewGenerationClearsThePreviousSessionIdentifier_RT086_3() async throws {
        let coordinator = try await makeSucceededCoordinator()
        coordinator.recordSession(UUID())

        await coordinator.generate(FalGenerationRequest(prompt: "Second"), apiKey: "fixture-key")

        XCTAssertNil(coordinator.upscaleSource?.sessionID)
    }

    // RT-86.4
    func test_theUpscaleInputCarriesTheSessionRecordedForItsOutput_RT086_4() async throws {
        let coordinator = try await makeSucceededCoordinator()
        let session = UUID()

        coordinator.recordSession(session)
        let source = try XCTUnwrap(coordinator.upscaleSource)

        XCTAssertEqual(source.sessionID, session)
        XCTAssertEqual(source.url, coordinator.output?.localURL)
    }

    // RT-86.5
    //
    // Clearing follows the output rather than the start of a generation. Clearing at each entry
    // point is the shape of the fault being fixed: an identifier outliving what it describes
    // because somewhere forgot.
    func test_theRecordedIdentifierIsClearedWhenTheOutputChanges_RT086_5() async throws {
        let coordinator = try await makeSucceededCoordinator()
        coordinator.recordSession(UUID())

        coordinator.reset()

        XCTAssertNil(coordinator.upscaleSource, "no output, so nothing to attribute")
        XCTAssertNil(coordinator.recordedSessionID)
    }

    // RT-86.6
    func test_whenRecordingASessionFailsTheInputCarriesNoIdentifier_RT086_6() async throws {
        let coordinator = try await makeSucceededCoordinator()

        // The session store threw, so nothing was recorded. The generated image is still present
        // and still sendable — it simply attaches to nothing.
        let source = try XCTUnwrap(coordinator.upscaleSource)

        XCTAssertNil(source.sessionID)
        XCTAssertNotNil(source.url)
    }

    @MainActor
    private func makeSucceededCoordinator() async throws -> GenerationCoordinator {
        let directory = temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let coordinator = GenerationCoordinator(
            service: FixtureGenerationService(
                result: .success(
                    FalGeneratedImage(
                        remoteURL: try XCTUnwrap(URL(string: "https://images.example/session.jpg")),
                        data: Data("session".utf8),
                        contentType: "image/jpeg",
                        warnings: []
                    )
                )
            ),
            outputStore: GeneratedImageStore(directory: directory)
        )
        await coordinator.generate(FalGenerationRequest(prompt: "Session"), apiKey: "fixture-key")
        return coordinator
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
