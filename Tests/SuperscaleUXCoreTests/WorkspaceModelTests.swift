// ABOUTME: Verifies the single workspace's behaviour below the window: what is sent, what is
// ABOUTME: available, which upscale model an arrival path resolves to, and what the File menu holds.

import FalGenerationKit
import Foundation
import XCTest
@testable import SuperscaleUXCore

final class WorkspaceModelTests: XCTestCase {
    private let noir = PromptPack(
        id: "image-lighting-film-noir",
        displayName: "Film Noir",
        category: "Lighting",
        body: "Relight the image with hard directional light.",
        compatibleModelIDs: [FalGenerationRequest.defaultModelID],
        requiresInput: true
    )

    // MARK: - What is sent

    // RT-87.13
    func test_theRequestCarriesThePromptAreasText_RT087_13() throws {
        var workspace = WorkspaceModel(filters: [noir], workingImage: workingImage())
        workspace.selection.choose(noir.id)
        workspace.selection.text = "Relight it, keep the rain."

        let request = try XCTUnwrap(workspace.applyRequest())

        XCTAssertEqual(request.prompt, "Relight it, keep the rain.")
    }

    // RT-87.14
    //
    // The canvas shows the upscaled rendering by default, so sending what is on screen is the
    // obvious implementation and the wrong one: AC79.2 and invariant I1 both forbid a cloud
    // filter receiving pixels produced by an upscale.
    func test_theReferenceIsTheImageAsImportedRatherThanItsUpscaledRendering_RT087_14() throws {
        let source = workingImage()
        var workspace = WorkspaceModel(filters: [noir], workingImage: source)
        workspace.selection.choose(noir.id)

        let request = try XCTUnwrap(workspace.applyRequest())

        XCTAssertEqual(request.referenceImageURLs, [source.referenceValue])
    }

    // RT-87.24
    func test_anUpscaledRenderingDoesNotBecomeTheReference_RT087_24() throws {
        let source = workingImage()
        var workspace = WorkspaceModel(filters: [noir], workingImage: source)
        workspace.upscaledRendering = WorkingImage(
            referenceValue: "data:image/png;base64,VVBTQ0FMRUQ=",
            hasWorkingImage: true
        )
        workspace.selection.choose(noir.id)

        let request = try XCTUnwrap(workspace.applyRequest())

        XCTAssertEqual(request.referenceImageURLs, [source.referenceValue])
        XCTAssertFalse(request.referenceImageURLs.contains(where: { $0.contains("VVBTQ0FMRUQ=") }))
    }

    // RT-87.12
    //
    // A window cannot be asked whether a network call happened. A fixture standing where the
    // provider would can.
    func test_choosingAFilterIssuesNoRequest_RT087_12() async {
        let service = await FixtureWorkspaceService()
        var workspace = WorkspaceModel(filters: [noir], workingImage: workingImage())

        workspace.selection.choose(noir.id)

        let requests = await service.requests
        XCTAssertTrue(requests.isEmpty)
    }

    // RT-87.17
    func test_theWorkspaceIssuesNoPricingRequest_RT087_17() async {
        let pricing = await FixturePricingProbe()
        var workspace = WorkspaceModel(filters: [noir], workingImage: workingImage())

        workspace.selection.choose(noir.id)
        _ = workspace.applyRequest()

        let calls = await pricing.calls
        XCTAssertEqual(calls, 0, "the flat rate is a constant; nothing is asked of the provider")
    }

    // RT-87.16
    func test_theCostBesideApplyIsTheDocumentedFlatRate_RT087_16() {
        XCTAssertEqual(WorkspaceModel.filterCostUSD, 0.02)
    }

    // MARK: - When applying is available

    // RT-87.26
    func test_applyingIsUnavailableWithNoWorkingImage_RT087_26() {
        var workspace = WorkspaceModel(filters: [noir], workingImage: nil)
        workspace.selection.text = "A tower at dusk."

        XCTAssertFalse(workspace.canApply)
        XCTAssertNil(workspace.applyRequest())
    }

    // RT-87.27
    func test_applyingIsUnavailableWithoutAGenerationKey_RT087_27() {
        var workspace = WorkspaceModel(
            filters: [noir],
            workingImage: workingImage(),
            isGenerationConfigured: false
        )
        workspace.selection.choose(noir.id)

        XCTAssertFalse(workspace.canApply)
        XCTAssertTrue(workspace.offersRouteToSettings)
    }

    // RT-87.28
    //
    // Section 2.8: when filters are unavailable, local upscaling works fully.
    func test_withoutAGenerationKeyLocalUpscalingIsUnaffected_RT087_28() {
        let workspace = WorkspaceModel(
            filters: [noir],
            workingImage: workingImage(),
            isGenerationConfigured: false
        )

        XCTAssertTrue(workspace.canUpscale)
    }

    // MARK: - Which upscale model an arrival path resolves to (D8)

    // RT-87.18
    func test_aDroppedImageUpscalesWithTheConfiguredDefault_RT087_18() {
        let resolved = WorkspaceModel.resolvedUpscaleModelID(
            preferred: "realesrgan-x2plus",
            arrival: .dropped,
            isKnown: { $0 == "realesrgan-x2plus" }
        )

        XCTAssertEqual(resolved, "realesrgan-x2plus")
    }

    // RT-87.19
    func test_anImageFromAFilterResultUpscalesWithTheSameModel_RT087_19() {
        let dropped = WorkspaceModel.resolvedUpscaleModelID(
            preferred: "realesrgan-x2plus",
            arrival: .dropped,
            isKnown: { _ in true }
        )
        let handed = WorkspaceModel.resolvedUpscaleModelID(
            preferred: "realesrgan-x2plus",
            arrival: .filterResult,
            isKnown: { _ in true }
        )

        XCTAssertEqual(dropped, handed, "D8 was these two paths disagreeing")
    }

    // RT-87.20
    func test_aModelChosenInTheToolbarOverridesTheDefault_RT087_20() {
        let resolved = WorkspaceModel.resolvedUpscaleModelID(
            preferred: "realesrgan-x2plus",
            arrival: .dropped,
            chosenInToolbar: "realesrgan-anime-6b",
            isKnown: { _ in true }
        )

        XCTAssertEqual(resolved, "realesrgan-anime-6b")
    }

    // RT-87.34
    func test_aStoredDefaultNamingNoRealModelFallsBackToAutomatic_RT087_34() {
        let resolved = WorkspaceModel.resolvedUpscaleModelID(
            preferred: "realesrgan-removed-in-a-later-version",
            arrival: .dropped,
            isKnown: { _ in false }
        )

        XCTAssertEqual(resolved, "auto")
    }

    // MARK: - Cancellation

    // RT-87.29, RT-87.30
    func test_cancellingAnApplicationLeavesNoCandidate_RT087_29() async throws {
        let directory = temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let coordinator = await GenerationCoordinator(
            service: SlowWorkspaceService(),
            outputStore: GeneratedImageStore(directory: directory)
        )

        await coordinator.start(FalGenerationRequest(prompt: "Relight"), apiKey: "fixture-key")
        await coordinator.cancel()

        let phase = await coordinator.phase
        XCTAssertEqual(phase, .cancelled)
        let output = await coordinator.output
        XCTAssertNil(output, "a cancelled application leaves the working image as it was")
    }

    // MARK: - Recent sessions

    // RT-87.21
    func test_recentSessionsAreListedMostRecentFirst_RT087_21() {
        let sessions = [
            session(prompt: "Oldest", secondsAgo: 300),
            session(prompt: "Newest", secondsAgo: 10),
            session(prompt: "Middle", secondsAgo: 100),
        ]

        let recents = WorkspaceModel.recentSessions(from: sessions)

        XCTAssertEqual(recents.map(\.prompt), ["Newest", "Middle", "Oldest"])
    }

    // RT-87.32
    func test_atMostTenSessionsAreListed_RT087_32() {
        let sessions = (1...25).map { session(prompt: "Session \($0)", secondsAgo: Double($0)) }

        let recents = WorkspaceModel.recentSessions(from: sessions)

        XCTAssertEqual(recents.count, 10)
        XCTAssertEqual(recents.first?.prompt, "Session 1", "the most recent is the least seconds ago")
    }

    // RT-87.33
    func test_aSessionWhoseImageIsMissingIsReported_RT087_33() throws {
        let missing = session(prompt: "Gone", secondsAgo: 5, assetPath: "/nowhere/deleted.png")

        XCTAssertThrowsError(try WorkspaceModel.workingImage(for: missing)) { error in
            XCTAssertTrue(
                error.localizedDescription.localizedCaseInsensitiveContains("no longer"),
                "the reason should say the image is gone, got '\(error.localizedDescription)'"
            )
        }
    }

    // MARK: - A catalogue that will not load

    // RT-87.31
    func test_aFailedCatalogueLeavesThePanelAReasonToShow_RT087_31() {
        let workspace = WorkspaceModel(
            filters: [],
            workingImage: workingImage(),
            catalogueFailure: "Prompt-pack resource 'image-design-broken' is invalid: frontmatter is malformed."
        )

        XCTAssertTrue(workspace.filters.isEmpty)
        XCTAssertEqual(
            workspace.catalogueFailure,
            "Prompt-pack resource 'image-design-broken' is invalid: frontmatter is malformed."
        )
    }

    // MARK: - Fixtures

    private func workingImage() -> WorkingImage {
        WorkingImage(referenceValue: "data:image/png;base64,U09VUkNF", hasWorkingImage: true)
    }

    private func session(
        prompt: String,
        secondsAgo: Double,
        assetPath: String? = nil
    ) -> GenerationSessionRecord {
        GenerationSessionRecord(
            id: UUID(),
            prompt: prompt,
            modelID: FalGenerationRequest.defaultModelID,
            estimatedCost: nil,
            referencePaths: [],
            timestamp: Date(timeIntervalSince1970: 1_000_000 - secondsAgo),
            status: .generated,
            safeDiagnostic: nil,
            generatedAssetPath: assetPath,
            upscaledAssetPath: nil,
            metadataPath: "/nowhere/metadata.json"
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceModelTests-\(UUID().uuidString)", isDirectory: true)
    }
}

@MainActor
private final class FixtureWorkspaceService: GenerationServing {
    private(set) var requests: [FalGenerationRequest] = []

    func uploadReference(_ data: Data, fileName: String, apiKey: String) async throws -> URL {
        URL(string: "https://v3.fal.media/files/fixture/\(fileName)")
            ?? URL(fileURLWithPath: fileName)
    }

    func generate(_ request: FalGenerationRequest, apiKey: String) async throws -> FalGeneratedImage {
        requests.append(request)
        return FalGeneratedImage(
            remoteURL: URL(fileURLWithPath: "/dev/null"),
            data: Data(),
            contentType: "image/png",
            warnings: []
        )
    }
}

@MainActor
private final class FixturePricingProbe {
    private(set) var calls = 0

    func refresh() { calls += 1 }
}

@MainActor
private final class SlowWorkspaceService: GenerationServing {
    /// Immediate, because what this fixture is slow at is generating.
    func uploadReference(_ data: Data, fileName: String, apiKey: String) async throws -> URL {
        URL(fileURLWithPath: fileName)
    }

    func generate(_ request: FalGenerationRequest, apiKey: String) async throws -> FalGeneratedImage {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        throw CancellationError()
    }
}
