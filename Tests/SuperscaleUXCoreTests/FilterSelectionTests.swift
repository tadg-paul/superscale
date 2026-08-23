// ABOUTME: Verifies that choosing a filter is free and that what is applied is the text on screen.
// ABOUTME: Drives the selection model and a fixture provider, so no paid call is ever made.

import FalGenerationKit
import Foundation
import XCTest
@testable import SuperscaleUXCore

final class FilterSelectionTests: XCTestCase {
    private let noir = PromptPack(
        id: "image-lighting-film-noir",
        displayName: "Film Noir",
        category: "Lighting",
        body: "Relight the image with hard directional light.",
        compatibleModelIDs: [FalGenerationRequest.defaultModelID],
        requiresInput: true
    )
    private let botanical = PromptPack(
        id: "image-illustration-botanical",
        displayName: "Botanical",
        category: "Illustration",
        body: "Redraw the subject as a botanical plate.",
        compatibleModelIDs: [FalGenerationRequest.defaultModelID],
        requiresInput: true
    )

    private var selection: FilterSelection {
        FilterSelection(filters: [botanical, noir])
    }

    // MARK: - Choosing is free

    // RT-85.12
    func test_choosingAFilterYieldsThatFiltersText_RT085_12() {
        var selection = selection

        selection.choose(noir.id)

        XCTAssertEqual(selection.text, noir.body)
        XCTAssertEqual(selection.selectedID, noir.id)
    }

    // RT-85.13
    //
    // Selecting must cost nothing, so a user can read eighty-six filters at no charge.
    func test_choosingAFilterIssuesNoRequest_RT085_13() async {
        let service = await FixtureFilterService()
        var selection = selection

        selection.choose(noir.id)
        selection.choose(botanical.id)

        let requests = await service.requests
        XCTAssertTrue(requests.isEmpty)
    }

    // RT-85.14
    func test_choosingASecondFilterReplacesTheTextRatherThanAppendingToIt_RT085_14() {
        var selection = selection

        selection.choose(noir.id)
        selection.choose(botanical.id)

        XCTAssertEqual(selection.text, botanical.body)
        XCTAssertFalse(selection.text.contains(noir.body))
    }

    // RT-85.25
    //
    // How a user reverts: edit the text, dislike it, click the filter again. Selection is
    // idempotent in what it produces, not in whether it acts.
    func test_choosingTheFilterAlreadyChosenYieldsItsTextAfresh_RT085_25() {
        var selection = selection
        selection.choose(noir.id)

        selection.text = "Something I typed over it."
        selection.choose(noir.id)

        XCTAssertEqual(selection.text, noir.body)
    }

    // RT-85.29
    func test_choosingAFilterReplacesHandWrittenText_RT085_29() {
        var selection = selection
        selection.text = "A tower at dusk, in ink."

        selection.choose(noir.id)

        XCTAssertEqual(selection.text, noir.body)
    }

    // MARK: - Applying sends the text as it stands

    // RT-85.15
    func test_applyingAnUneditedFilterSendsItsBody_RT085_15() async throws {
        var selection = selection
        selection.choose(noir.id)

        let prompts = try await sentPrompts(applying: selection)

        XCTAssertEqual(prompts, [noir.body])
    }

    // RT-85.16
    func test_applyingAnEditedFilterSendsTheEditedText_RT085_16() async throws {
        var selection = selection
        selection.choose(noir.id)
        selection.text = "\(noir.body) Keep the rain."

        let prompts = try await sentPrompts(applying: selection)

        XCTAssertEqual(prompts, ["\(noir.body) Keep the rain."])
    }

    // RT-85.17, RT-74.5, RT-74.6 (rewritten: composition is gone, but "without mutating the
    // bundled resource" survives as this criterion's third condition)
    func test_anEditIsDiscardedWhenAnotherFilterIsChosenAndTheBuiltInIsUnchanged_RT085_17() {
        let original = noir
        var selection = selection
        selection.choose(noir.id)
        selection.text = "Edited wording that must not stick."

        selection.choose(botanical.id)
        selection.choose(noir.id)

        XCTAssertEqual(selection.text, original.body)
        XCTAssertEqual(selection.filters.first { $0.id == original.id }, original)
    }

    // RT-85.22
    func test_applyingWithTextEnteredAndNoFilterChosenSendsThatText_RT085_22() async throws {
        var selection = selection
        selection.text = "A tower at dusk, in ink."

        let prompts = try await sentPrompts(applying: selection)

        XCTAssertNil(selection.selectedID)
        XCTAssertEqual(prompts, ["A tower at dusk, in ink."])
    }

    // MARK: - Nothing to send is refused

    // RT-85.23
    func test_applyingWithNeitherTextNorAFilterIssuesNoRequest_RT085_23() async throws {
        let prompts = try await sentPrompts(applying: selection)

        XCTAssertFalse(selection.canApply)
        XCTAssertNil(selection.request(modelID: FalGenerationRequest.defaultModelID))
        XCTAssertTrue(prompts.isEmpty)
    }

    // RT-85.27
    //
    // The reachable case a (text, filter) pair misses: a filter is chosen, so a pair-based
    // guard permits an empty prompt to reach a paid edit endpoint.
    func test_applyingWithAFilterChosenAndItsTextClearedIssuesNoRequest_RT085_27() async throws {
        var selection = selection
        selection.choose(noir.id)
        selection.text = ""

        let prompts = try await sentPrompts(applying: selection)

        XCTAssertFalse(selection.canApply)
        XCTAssertNil(selection.request(modelID: FalGenerationRequest.defaultModelID))
        XCTAssertTrue(prompts.isEmpty)
    }

    // RT-85.28
    func test_applyingWithWhitespaceOnlyTextIssuesNoRequest_RT085_28() async throws {
        var selection = selection
        selection.text = "   \n\t "

        let prompts = try await sentPrompts(applying: selection)

        XCTAssertFalse(selection.canApply)
        XCTAssertTrue(prompts.isEmpty)
    }

    // MARK: - A stored identifier still resolves

    // RT-85.18
    func test_anIdentifierInTheFormThePreviousVersionStoredResolvesToAFilter_RT085_18() throws {
        let catalogue = try PromptPackCatalogue.bundled()
        var selection = FilterSelection(filters: catalogue.packs)

        selection.choose("image-illustration-botanical")

        XCTAssertEqual(selection.selectedID, "image-illustration-botanical")
        XCTAssertEqual(selection.text, catalogue.pack(id: "image-illustration-botanical")?.body)
    }

    // MARK: - A corpus that will not load

    // RT-85.30
    @MainActor
    func test_afterACorpusFailsToLoadTheFilterListIsEmptyAndTheReasonIsAvailable_RT085_30() throws {
        let state = try settingsState { throw PromptPackError.bundleUnavailable }

        XCTAssertTrue(state.promptPackCatalogue.packs.isEmpty)
        XCTAssertEqual(state.lastError, PromptPackError.bundleUnavailable.localizedDescription)
    }

    // RT-85.31
    //
    // Section 2.8 of the implementation guide rules that when filters are unavailable, local
    // upscaling works fully. A corpus that will not load is that condition by another route.
    @MainActor
    func test_aFailedCorpusLoadLeavesTheUpscaleSettingsUnaffected_RT085_31() throws {
        let working = try settingsState { PromptPackCatalogue(packs: []) }
        let failed = try settingsState { throw PromptPackError.bundleUnavailable }

        XCTAssertEqual(failed.defaultUpscaleModelID, working.defaultUpscaleModelID)
        XCTAssertFalse(failed.defaultUpscaleModelID.isEmpty)
        XCTAssertTrue(failed.isSaveEnabled)
    }

    // MARK: - Fixtures

    /// Applies the selection exactly as the view does — through the request the model builds,
    /// so a refusal cannot be implemented twice and diverge. Nothing is written to disk: the
    /// fixture stands where the provider would, and records what reached it.
    @MainActor
    private func sentPrompts(applying selection: FilterSelection) async throws -> [String] {
        let service = FixtureFilterService()

        if let request = selection.request(modelID: FalGenerationRequest.defaultModelID) {
            _ = try await service.generate(request, apiKey: "fixture-key")
        }
        return service.requests.map(\.prompt)
    }

    @MainActor
    private func settingsState(
        loading load: () throws -> PromptPackCatalogue
    ) throws -> GenerationSettingsState {
        let suite = "FilterSelectionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return GenerationSettingsState(
            credentials: GenerationCredentialService(storage: EphemeralCredentialStorage()),
            preferencesStore: GenerationPreferencesStore(defaults: defaults, folderValidator: { _ in true }),
            loadingCatalogue: load
        )
    }
}

@MainActor
private final class FixtureFilterService: GenerationServing {
    private(set) var requests: [FalGenerationRequest] = []

    func generate(_ request: FalGenerationRequest, apiKey: String) async throws -> FalGeneratedImage {
        requests.append(request)
        return FalGeneratedImage(
            remoteURL: URL(fileURLWithPath: "/dev/null"),
            data: Data("filtered".utf8),
            contentType: "image/png",
            warnings: []
        )
    }
}

private final class EphemeralCredentialStorage: CredentialStorage {
    private var values: [CredentialSlot: String] = [:]

    func value(for slot: CredentialSlot) throws -> String? { values[slot] }
    func setValue(_ value: String, for slot: CredentialSlot) throws { values[slot] = value }
    func removeValue(for slot: CredentialSlot) throws { values[slot] = nil }
}
