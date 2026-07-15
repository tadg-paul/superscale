// ABOUTME: Verifies pricing and account state orchestration independently from SwiftUI.
// ABOUTME: Ensures cloud-status failures remain visible and non-fatal to generation.

import FalGenerationKit
import Foundation
import XCTest
@testable import SuperscaleUXCore

final class GenerationCloudStatusTests: XCTestCase {
    @MainActor
    func test_pricingCoordinatorRepresentsAvailableAndUnavailableStates() async {
        let expected = FalPricing(
            unitPrice: FalUnitPrice(amount: 0.02, unit: "image", currency: "USD"),
            estimatedCost: 0.02,
            currency: "USD"
        )
        let available = GenerationPricingCoordinator(service: PricingFixture(result: .success(expected)))

        await available.refresh(modelID: "xai/grok-imagine-image", apiKey: "generation-key")
        XCTAssertEqual(available.state, .available(expected))

        let unavailable = GenerationPricingCoordinator(
            service: PricingFixture(result: .failure(FixtureError(message: "Pricing unavailable")))
        )
        await unavailable.refresh(modelID: "xai/grok-imagine-image", apiKey: "generation-key")
        XCTAssertEqual(unavailable.state, .unavailable("Pricing unavailable"))
    }

    @MainActor
    func test_accountCoordinatorPreservesBalanceUsageAndBillingEvents() async {
        let event = FalBillingEvent(
            requestID: "request-1",
            endpointID: "xai/grok-imagine-image",
            timestamp: "2026-07-15T00:00:00Z",
            outputUnits: 1,
            unitPrice: 0.02,
            costEstimateNanoUSD: 20_000_000
        )
        let expected = FalAccountSummary(
            username: "tester",
            balance: 10,
            currency: "USD",
            recentUsageCost: 0.04,
            billingEvents: [event]
        )
        let coordinator = GenerationAccountCoordinator(service: AccountFixture(result: .success(expected)))

        await coordinator.refresh(accountKey: "admin-key")

        XCTAssertEqual(coordinator.state, .available(expected))
    }

    @MainActor
    func test_missingCredentialsProduceActionableStatesWithoutRequests() async {
        let pricing = GenerationPricingCoordinator(service: PricingFixture(result: .failure(FixtureError(message: "unused"))))
        let account = GenerationAccountCoordinator(service: AccountFixture(result: .failure(FixtureError(message: "unused"))))

        await pricing.refresh(modelID: "xai/grok-imagine-image", apiKey: "")
        await account.refresh(accountKey: "")

        XCTAssertEqual(pricing.state, .unavailable("Add a FAL generation key in Settings to check pricing."))
        XCTAssertEqual(account.state, .unavailable("Add a FAL account/admin key in Settings to load account details."))
    }
}

private struct PricingFixture: GenerationPricingServing {
    let result: Result<FalPricing, Error>

    func pricing(modelID: String, apiKey: String) async throws -> FalPricing {
        try result.get()
    }
}

private struct AccountFixture: GenerationAccountServing {
    let result: Result<FalAccountSummary, Error>

    func summary(accountKey: String) async throws -> FalAccountSummary {
        try result.get()
    }
}

private struct FixtureError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
