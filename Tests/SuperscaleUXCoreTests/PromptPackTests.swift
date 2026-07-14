// ABOUTME: Verifies bundled prompt-pack loading, validation, composition, and selection state.
// ABOUTME: Protects prompt bodies and stable metadata without launching the GUI.

import XCTest
@testable import SuperscaleUXCore

final class PromptPackTests: XCTestCase {
    // RT-74.1, RT-74.2
    func test_bundledPromptPacksLoadWithStableMetadataAndFalCompatibility() throws {
        let catalogue = try PromptPackCatalogue.bundled()
        let architectural = try XCTUnwrap(catalogue.pack(id: "image-design-architectural-drawing"))

        XCTAssertEqual(catalogue.packs.count, 86)
        XCTAssertEqual(architectural.displayName, "Architectural Drawing")
        XCTAssertEqual(architectural.category, "Design")
        XCTAssertTrue(architectural.body.hasPrefix("Transform the input image into an architectural drawing."))
        XCTAssertEqual(architectural.compatibleModelIDs, ["xai/grok-imagine-image"])
        XCTAssertEqual(catalogue.packs.map(\.id), catalogue.packs.map(\.id).sorted())
    }

    // RT-74.3, RT-74.4
    func test_loaderRejectsMissingBodiesDuplicateIDsMalformedMetadataAndUnsupportedModels() throws {
        let valid = descriptor(id: "image-design-example", resourceName: "example")
        let loader = PromptPackLoader(supportedModelIDs: ["xai/grok-imagine-image"])

        assertLoadError(loader, descriptors: [valid], bodies: [:], contains: ["example", "body"])
        assertLoadError(loader, descriptors: [valid, valid], bodies: ["example": "Body"], contains: ["duplicate", valid.id])
        assertLoadError(
            loader,
            descriptors: [descriptor(id: "bad id", resourceName: "bad-metadata")],
            bodies: ["bad-metadata": "Body"],
            contains: ["bad-metadata", "metadata"]
        )
        assertLoadError(
            loader,
            descriptors: [
                descriptor(
                    id: "image-design-future",
                    resourceName: "future-model",
                    modelIDs: ["future/provider-model"]
                ),
            ],
            bodies: ["future-model": "Body"],
            contains: ["future-model", "unsupported model"]
        )
    }

    // RT-74.4
    func test_loaderDiagnosticsDoNotExposePromptBodies() {
        let secretBody = "private prompt wording that must not enter diagnostics"
        let loader = PromptPackLoader(supportedModelIDs: ["xai/grok-imagine-image"])

        do {
            _ = try loader.load(
                descriptors: [descriptor(id: "bad id", resourceName: "safe-resource-name")],
                bodyProvider: { _ in secretBody }
            )
            XCTFail("Expected malformed metadata to be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("safe-resource-name"))
            XCTAssertFalse(error.localizedDescription.contains(secretBody))
        }
    }

    // RT-74.5, RT-74.6
    func test_promptCompositionSupportsPackUserAndCombinedInputsWithoutMutation() {
        let pack = PromptPack(
            id: "image-design-example",
            displayName: "Example",
            category: "Design",
            body: "Apply the bundled treatment.",
            compatibleModelIDs: ["xai/grok-imagine-image"]
        )
        let original = pack

        XCTAssertEqual(PromptComposer.compose(pack: pack, userPrompt: ""), "Apply the bundled treatment.")
        XCTAssertEqual(PromptComposer.compose(pack: nil, userPrompt: "Draw a tower."), "Draw a tower.")
        XCTAssertEqual(
            PromptComposer.compose(pack: pack, userPrompt: "Draw a tower."),
            "Apply the bundled treatment.\n\nDraw a tower."
        )
        XCTAssertEqual(PromptComposer.compose(pack: pack, userPrompt: "Second use."), "Apply the bundled treatment.\n\nSecond use.")
        XCTAssertEqual(pack, original)
    }

    // RT-74.7
    @MainActor
    func test_selectionStateReferencesBundledPacksWithoutAnEditingSurface() throws {
        let catalogue = try PromptPackCatalogue.bundled()
        let selection = PromptPackSelection(catalogue: catalogue)
        let selectedID = "image-illustration-botanical"

        selection.select(packID: selectedID)

        XCTAssertEqual(selection.selectedPack?.id, selectedID)
        XCTAssertEqual(selection.selectedPack, catalogue.pack(id: selectedID))
    }

    private func descriptor(
        id: String,
        resourceName: String,
        modelIDs: [String] = ["xai/grok-imagine-image"]
    ) -> PromptPackDescriptor {
        PromptPackDescriptor(
            id: id,
            displayName: "Example",
            category: "Design",
            resourceName: resourceName,
            compatibleModelIDs: modelIDs
        )
    }

    private func assertLoadError(
        _ loader: PromptPackLoader,
        descriptors: [PromptPackDescriptor],
        bodies: [String: String],
        contains fragments: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try loader.load(descriptors: descriptors) { resourceName in
                guard let body = bodies[resourceName] else { throw PromptBodyFixtureError.missing }
                return body
            }
            XCTFail("Expected prompt-pack loading to fail", file: file, line: line)
        } catch {
            for fragment in fragments {
                XCTAssertTrue(
                    error.localizedDescription.localizedCaseInsensitiveContains(fragment),
                    "Expected diagnostic to contain '\(fragment)', got '\(error.localizedDescription)'",
                    file: file,
                    line: line
                )
            }
        }
    }

    private enum PromptBodyFixtureError: Error {
        case missing
    }
}
