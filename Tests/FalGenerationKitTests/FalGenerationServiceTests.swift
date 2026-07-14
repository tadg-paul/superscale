// ABOUTME: Verifies FAL request construction, model handling, and response processing.
// ABOUTME: Uses deterministic transport fixtures so tests never call paid provider APIs.

import Foundation
import XCTest
@testable import FalGenerationKit

final class FalGenerationServiceTests: XCTestCase {
    // RT-72.1
    func test_textToImageRequestUsesConfiguredEndpointAndAuthentication() throws {
        let request = FalGenerationRequest(prompt: "A lighthouse in winter")
        let prepared = try FalRequestBuilder().prepare(request, apiKey: "fal-test-key")

        XCTAssertEqual(prepared.urlRequest.url?.absoluteString, "https://fal.run/xai/grok-imagine-image")
        XCTAssertEqual(prepared.urlRequest.httpMethod, "POST")
        XCTAssertEqual(prepared.urlRequest.value(forHTTPHeaderField: "Authorization"), "Key fal-test-key")
        XCTAssertEqual(prepared.urlRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(prepared.urlRequest.httpBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["prompt"] as? String, "A lighthouse in winter")
        XCTAssertEqual(payload["num_images"] as? Int, 1)
    }

    // RT-72.2
    func test_successfulResponseDownloadsFirstGeneratedImage() async throws {
        let transport = FixtureFalTransport(responses: [
            .json(statusCode: 200, body: #"{"images":[{"url":"https://images.example/generated.png"}]}"#),
            .init(statusCode: 200, headers: ["Content-Type": "image/png"], body: Data([0x89, 0x50, 0x4e, 0x47])),
        ])
        let client = FalGenerationClient(transport: transport)

        let image = try await client.generate(
            FalGenerationRequest(prompt: "A lighthouse in winter"),
            apiKey: "fal-test-key"
        )

        XCTAssertEqual(image.remoteURL.absoluteString, "https://images.example/generated.png")
        XCTAssertEqual(image.data, Data([0x89, 0x50, 0x4e, 0x47]))
        XCTAssertEqual(image.contentType, "image/png")
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].url?.absoluteString, "https://images.example/generated.png")
        XCTAssertEqual(requests[1].httpMethod, "GET")
    }

    // RT-72.3
    func test_grokRequestsRepresentOneTwoAndThreeReferenceImages() throws {
        for count in 1...3 {
            let references = (1...count).map { "data:image/png;base64,reference-\($0)" }
            let prepared = try FalRequestBuilder().prepare(
                FalGenerationRequest(prompt: "Restyle", referenceImageURLs: references),
                apiKey: "fal-test-key"
            )

            XCTAssertEqual(prepared.urlRequest.url?.absoluteString, "https://fal.run/xai/grok-imagine-image/edit")
            let payload = try payload(from: prepared.urlRequest)
            XCTAssertEqual(payload["image_urls"] as? [String], references)
            XCTAssertTrue(prepared.warnings.isEmpty)
        }

        XCTAssertThrowsError(
            try FalRequestBuilder().prepare(
                FalGenerationRequest(
                    prompt: "Too many",
                    referenceImageURLs: ["one", "two", "three", "four"]
                ),
                apiKey: "fal-test-key"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("at most three"))
        }
    }

    // RT-72.4
    func test_modelHandlersSelectEditEndpointAndWarnWhenExtraReferencesAreIgnored() throws {
        let grok = try FalRequestBuilder().prepare(
            FalGenerationRequest(prompt: "Edit", referenceImageURLs: ["https://images.example/one.png"]),
            apiKey: "fal-test-key"
        )
        XCTAssertEqual(grok.urlRequest.url?.path, "/xai/grok-imagine-image/edit")

        let kontext = try FalRequestBuilder().prepare(
            FalGenerationRequest(
                prompt: "Edit",
                modelID: "fal-ai/flux-pro/kontext",
                referenceImageURLs: [
                    "https://images.example/one.png",
                    "https://images.example/two.png",
                ]
            ),
            apiKey: "fal-test-key"
        )
        let payload = try payload(from: kontext.urlRequest)
        XCTAssertEqual(payload["image_url"] as? String, "https://images.example/one.png")
        XCTAssertNil(payload["image_urls"])
        XCTAssertEqual(kontext.warnings, [.extraReferencesIgnored(modelID: "fal-ai/flux-pro/kontext", accepted: 1, provided: 2)])
    }

    // RT-72.5
    func test_providerAndDownloadFailuresAreReported() async throws {
        let providerClient = FalGenerationClient(transport: FixtureFalTransport(responses: [
            .json(statusCode: 422, body: #"{"detail":"prompt is required"}"#),
        ]))
        await assertThrowsDescription(
            try await providerClient.generate(FalGenerationRequest(prompt: "Bad request"), apiKey: "secret"),
            contains: ["FAL", "422", "prompt is required"]
        )

        let malformedClient = FalGenerationClient(transport: FixtureFalTransport(responses: [
            .json(statusCode: 200, body: #"{"images":[]}"#),
        ]))
        await assertThrowsDescription(
            try await malformedClient.generate(FalGenerationRequest(prompt: "No image"), apiKey: "secret"),
            contains: ["FAL", "image"]
        )

        let downloadClient = FalGenerationClient(transport: FixtureFalTransport(responses: [
            .json(statusCode: 200, body: #"{"images":[{"url":"https://images.example/missing.png"}]}"#),
            .init(statusCode: 404, headers: [:], body: Data("missing".utf8)),
        ]))
        await assertThrowsDescription(
            try await downloadClient.generate(FalGenerationRequest(prompt: "Missing image"), apiKey: "secret"),
            contains: ["download", "404"]
        )
    }

    // RT-72.6
    func test_diagnosticsRedactCredentialsAndRetainActionableContext() async throws {
        let key = "fal-super-secret"
        let transport = FixtureFalTransport(responses: [
            .json(statusCode: 401, body: #"{"message":"Key fal-super-secret is invalid","request_id":"req-123"}"#),
        ])
        let client = FalGenerationClient(transport: transport)

        do {
            _ = try await client.generate(FalGenerationRequest(prompt: "Denied"), apiKey: key)
            XCTFail("Expected provider authentication failure")
        } catch {
            let diagnostic = error.localizedDescription
            XCTAssertFalse(diagnostic.contains(key))
            XCTAssertTrue(diagnostic.contains("[REDACTED]"))
            XCTAssertTrue(diagnostic.contains("401"))
            XCTAssertTrue(diagnostic.contains("req-123"))
        }


        let failingClient = FalGenerationClient(
            transport: FailingFalTransport(message: "Connection failed for \(key)")
        )
        do {
            _ = try await failingClient.generate(FalGenerationRequest(prompt: "Offline"), apiKey: key)
            XCTFail("Expected transport failure")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains(key))
            XCTAssertTrue(error.localizedDescription.contains("[REDACTED]"))
            XCTAssertTrue(error.localizedDescription.contains("Connection failed"))
        }
    }

    // RT-72.7
    func test_mvpRegistryExposesOnlyFalModelsWithGrokAsDefault() {
        let registry = GenerationModelRegistry.mvp

        XCTAssertEqual(registry.defaultModel.id, "xai/grok-imagine-image")
        XCTAssertFalse(registry.selectableModels.isEmpty)
        XCTAssertTrue(registry.selectableModels.allSatisfy { $0.provider == .fal })
        XCTAssertEqual(registry.selectableModels.map(\.id), ["xai/grok-imagine-image"])
    }

    private func payload(from request: URLRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private func assertThrowsDescription<T>(
        _ expression: @autoclosure () async throws -> T,
        contains fragments: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected operation to throw", file: file, line: line)
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
}

private struct FailingFalTransport: FalHTTPTransport {
    let message: String

    func send(_ request: URLRequest) async throws -> FalHTTPResponse {
        throw Failure(message: message)
    }

    private struct Failure: LocalizedError {
        let message: String

        var errorDescription: String? { message }
    }
}

private actor FixtureFalTransport: FalHTTPTransport {
    private var responses: [FalHTTPResponse]
    private var requests: [URLRequest] = []

    init(responses: [FalHTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> FalHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw FixtureError.missingResponse
        }
        return responses.removeFirst()
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }

    enum FixtureError: Error {
        case missingResponse
    }
}

private extension FalHTTPResponse {
    static func json(statusCode: Int, body: String) -> FalHTTPResponse {
        FalHTTPResponse(
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"],
            body: Data(body.utf8)
        )
    }
}
