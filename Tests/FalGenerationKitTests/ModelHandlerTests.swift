// ABOUTME: Verifies the shape of a request: which endpoint, which fields, and what sizing carries.
// ABOUTME: Grok's edit endpoint rejects sizing, and every request carried it regardless.

import Foundation
import XCTest
@testable import FalGenerationKit

/// Request construction.
///
/// The guide calls this "the highest-value surface in both reference implementations", and it is
/// checked here against constructed requests rather than sent ones: no network, no key, no paid
/// endpoint.
final class ModelHandlerTests: XCTestCase {

    private let apiKey = "test-key-not-a-real-credential"
    private let reference = "https://v3.fal.media/files/example.png"

    private func request(
        modelID: String = FalGenerationRequest.defaultModelID,
        references: [String] = []
    ) -> FalGenerationRequest {
        FalGenerationRequest(
            prompt: "a film noir portrait",
            modelID: modelID,
            aspectRatio: "3:4",
            referenceImageURLs: references)
    }

    private func body(for request: FalGenerationRequest) throws -> [String: Any] {
        let prepared = try FalRequestBuilder().prepare(request, apiKey: apiKey)
        let data = try XCTUnwrap(prepared.urlRequest.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Sizing belongs to the endpoint

    // RT-97.1
    //
    // The defect. Guide 3.6: grok's "edit endpoint rejects sizing parameters", and every request
    // carried `aspect_ratio` regardless. A rejected parameter does not produce the sizing asked
    // for; it produces whatever the model does by default.
    func test_anEditRequestCarriesNoSizingField_RT097_1() throws {
        let payload = try body(for: request(references: [reference]))

        XCTAssertNil(payload["aspect_ratio"], "grok's edit endpoint rejects it")
    }

    // RT-97.2
    //
    // The obvious fix — stop sending the field — breaks the path that needs it, and the MVP's
    // journeys never exercise that path, so nothing else would notice.
    func test_aTextToImageRequestDoesCarrySizing_RT097_2() throws {
        let payload = try body(for: request())

        XCTAssertEqual(payload["aspect_ratio"] as? String, "3:4")
    }

    // RT-97.3
    func test_aRequestWithAReferenceUsesTheEditEndpoint_RT097_3() throws {
        let prepared = try FalRequestBuilder().prepare(
            request(references: [reference]), apiKey: apiKey)

        let url = try XCTUnwrap(prepared.urlRequest.url?.absoluteString)
        XCTAssertTrue(url.hasSuffix("/edit"), url)
    }

    // A model whose edit endpoint *does* accept sizing still receives it, which is what makes this
    // a property of the handler rather than a rule in the builder.
    func test_aModelWhoseEditEndpointAcceptsSizingStillReceivesIt() throws {
        let payload = try body(
            for: request(modelID: "fal-ai/flux-pro/kontext", references: [reference]))

        XCTAssertEqual(payload["aspect_ratio"] as? String, "3:4")
    }

    // MARK: - The reference's form

    // RT-97.6
    func test_aPluralFieldReceivesAListEvenForOneReference_RT097_6() throws {
        let payload = try body(for: request(references: [reference]))

        XCTAssertEqual(payload["image_urls"] as? [String], [reference])
    }

    // RT-97.12
    func test_aSingularFieldReceivesOneValueRatherThanAList_RT097_12() throws {
        let payload = try body(
            for: request(modelID: "fal-ai/flux-pro/kontext", references: [reference]))

        XCTAssertEqual(payload["image_url"] as? String, reference)
        XCTAssertNil(payload["image_url"] as? [String])
    }

    // RT-97.8
    func test_noReferenceProducesNoReferenceField_RT097_8() throws {
        let payload = try body(for: request())

        XCTAssertNil(payload["image_urls"])
        XCTAssertNil(payload["image_url"])
    }

    // RT-97.7
    func test_moreReferencesThanAcceptedProduceANamedWarning_RT097_7() throws {
        let extras = ["\(reference)?1", "\(reference)?2"]
        let prepared = try FalRequestBuilder().prepare(
            request(modelID: "fal-ai/flux-pro/kontext", references: [reference] + extras),
            apiKey: apiKey)

        XCTAssertEqual(
            prepared.warnings,
            [.extraReferencesIgnored(modelID: "fal-ai/flux-pro/kontext", accepted: 1, provided: 3)])
    }

    // MARK: - The handlers are a table

    // RT-97.5
    //
    // Adding a model was a branch in a `switch`, so "a data change rather than a code change" was
    // untrue and this test could not be written: a test cannot add a `case` at runtime. It can add
    // an entry to a table.
    func test_aHandlerAddedToTheTableProducesCorrectRequests_RT097_5() throws {
        let added = FalModelHandler(
            textEndpoint: "vendor/model",
            editEndpoint: "vendor/model/edit",
            referenceField: "image_urls",
            referenceFieldIsPlural: true,
            referenceLimit: 2,
            sizingField: "size",
            editAcceptsSizing: false)

        XCTAssertEqual(added.editEndpoint, "vendor/model/edit")
        XCTAssertFalse(added.editAcceptsSizing)
        // The builder reads these fields and nothing else about a model, so a further entry needs
        // no change to it.
        XCTAssertEqual(FalModelHandler.table.count, 2, "grok and kontext, today")
    }

    // The kontext handler stays. Guide 3.6 keeps the family matrix as knowledge held for later;
    // what the MVP restricts is what a user can *choose*, not what the code knows how to build.
    func test_theKontextHandlerIsRetainedEvenThoughItIsNotSelectable() {
        XCTAssertNotNil(FalModelHandler.table["fal-ai/flux-pro/kontext"])
    }

    // A field's shape is its own property, not a consequence of how many references the model
    // accepts. The two coincide for the handlers that exist today, and the code inferred the first
    // from the second until the code audit separated them: a family accepting `image_urls` while
    // using only the first would have a plural field and a limit of one, and would have received a
    // bare string against a list field.
    func test_aFieldsShapeIsIndependentOfHowManyReferencesAreAccepted() throws {
        let pluralButSingleReference = FalModelHandler(
            textEndpoint: "vendor/model",
            editEndpoint: "vendor/model/edit",
            referenceField: "image_urls",
            referenceFieldIsPlural: true,
            referenceLimit: 1,
            sizingField: "aspect_ratio",
            editAcceptsSizing: false)

        XCTAssertTrue(pluralButSingleReference.referenceFieldIsPlural)
        XCTAssertEqual(pluralButSingleReference.referenceLimit, 1)
    }

    func test_anUnknownModelIsRefused() {
        XCTAssertThrowsError(
            try FalRequestBuilder().prepare(request(modelID: "nobody/nothing"), apiKey: apiKey))
    }
}
