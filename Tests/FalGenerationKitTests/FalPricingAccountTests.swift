// ABOUTME: Verifies FAL pricing and account clients against deterministic HTTP fixtures.
// ABOUTME: Covers successful parsing, malformed data, and account authorization failures.

import Foundation
import XCTest
@testable import FalGenerationKit

final class FalPricingAccountTests: XCTestCase {
    // RT-76.1
    func test_pricingClientReturnsUnitPriceAndHistoricalEstimate() async throws {
        let transport = PricingFixtureTransport(responses: [
            .json(200, #"{"prices":[{"unit_price":0.02,"unit":"image","currency":"USD"}]}"#),
            .json(200, #"{"total_cost":0.0185,"currency":"USD"}"#),
        ])
        let client = FalPricingClient(
            transport: transport,
            baseURL: try XCTUnwrap(URL(string: "https://api.example"))
        )

        let pricing = try await client.pricing(modelID: "xai/grok-imagine-image", apiKey: "generation-key")

        XCTAssertEqual(pricing.unitPrice.amount, 0.02)
        XCTAssertEqual(pricing.unitPrice.unit, "image")
        XCTAssertEqual(pricing.estimatedCost, 0.0185)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.path }, ["/v1/models/pricing", "/v1/models/pricing/estimate"])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Key generation-key" })
    }

    // RT-76.2
    func test_pricingClientRejectsUnavailableAndMalformedResponses() async throws {
        let fixtures: [[FalHTTPResponse]] = [
            [.json(200, #"{"prices":[]}"#)],
            [.json(200, #"{"prices":"invalid"}"#)],
            [.json(503, #"{"message":"pricing unavailable"}"#)],
        ]

        for responses in fixtures {
            let client = FalPricingClient(
                transport: PricingFixtureTransport(responses: responses),
                baseURL: try XCTUnwrap(URL(string: "https://api.example"))
            )
            do {
                _ = try await client.pricing(modelID: "model", apiKey: "key")
                XCTFail("Expected pricing to be unavailable")
            } catch {
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }
        }
    }

    // RT-76.3
    func test_accountClientReturnsBalanceUsageAndBillingEvents() async throws {
        let transport = PricingFixtureTransport(responses: [
            .json(200, #"{"username":"tester","credits":{"current_balance":12.5,"currency":"USD"}}"#),
            .json(200, #"{"time_series":[{"bucket":"today","results":[{"endpoint_id":"model","unit":"image","quantity":2,"unit_price":0.02,"cost":0.04,"currency":"USD"}]}],"has_more":false}"#),
            .json(200, #"{"billing_events":[{"request_id":"req-1","endpoint_id":"model","timestamp":"2026-07-15T00:00:00Z","output_units":1,"unit_price":0.02,"cost_estimate_nano_usd":20000000}],"has_more":false}"#),
        ])
        let client = FalAccountClient(
            transport: transport,
            baseURL: try XCTUnwrap(URL(string: "https://api.example"))
        )

        let summary = try await client.summary(accountKey: "admin-key")

        XCTAssertEqual(summary.balance, 12.5)
        XCTAssertEqual(summary.recentUsageCost, 0.04)
        XCTAssertEqual(summary.billingEvents.first?.requestID, "req-1")
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.path }, [
            "/v1/account/billing", "/v1/models/usage", "/v1/models/billing-events",
        ])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Key admin-key" })
    }

    // RT-76.4
    func test_accountClientDistinguishesMissingUnauthorizedAndScopeErrors() async throws {
        let client = FalAccountClient(
            transport: PricingFixtureTransport(responses: []),
            baseURL: try XCTUnwrap(URL(string: "https://api.example"))
        )
        await assertFailure(client: client, key: "", contains: "required")

        for (status, fragment) in [(401, "unauthorized"), (403, "Admin scope")] {
            let failing = FalAccountClient(
                transport: PricingFixtureTransport(responses: [.json(status, #"{"message":"denied"}"#)]),
                baseURL: try XCTUnwrap(URL(string: "https://api.example"))
            )
            await assertFailure(client: failing, key: "admin-key", contains: fragment)
        }
    }

    private func assertFailure(client: FalAccountClient, key: String, contains fragment: String) async {
        do {
            _ = try await client.summary(accountKey: key)
            XCTFail("Expected account request to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains(fragment))
        }
    }
}

private actor PricingFixtureTransport: FalHTTPTransport {
    private var responses: [FalHTTPResponse]
    private var requests: [URLRequest] = []

    init(responses: [FalHTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> FalHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw FixtureError.missingResponse }
        return responses.removeFirst()
    }

    func recordedRequests() -> [URLRequest] { requests }

    enum FixtureError: Error { case missingResponse }
}

private extension FalHTTPResponse {
    static func json(_ statusCode: Int, _ body: String) -> FalHTTPResponse {
        FalHTTPResponse(statusCode: statusCode, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
    }
}
