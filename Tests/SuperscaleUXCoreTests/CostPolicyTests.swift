// ABOUTME: Verifies generation cost confirmation policy and non-fatal account states.
// ABOUTME: Covers exact threshold boundaries and unavailable estimate handling.

import XCTest
@testable import SuperscaleUXCore

final class CostPolicyTests: XCTestCase {
    // RT-76.5
    func test_costPolicyCoversThresholdBoundariesAndUnavailableEstimate() {
        let policy = GenerationCostPolicy(threshold: 0.05, confirmWhenUnavailable: true)

        XCTAssertEqual(policy.decision(for: 0.049), .proceed)
        XCTAssertEqual(policy.decision(for: 0.05), .proceed)
        XCTAssertEqual(policy.decision(for: 0.051), .requireConfirmation)
        XCTAssertEqual(policy.decision(for: nil), .requireConfirmation)
        XCTAssertEqual(
            GenerationCostPolicy(threshold: 0.05, confirmWhenUnavailable: false).decision(for: nil),
            .proceed
        )
    }

    // RT-76.7
    func test_accountFailureDoesNotDisableConfiguredGeneration() {
        let availability = GenerationAvailability(generationKeyConfigured: true, accountState: .failed("unauthorized"))

        XCTAssertTrue(availability.canGenerate)
        XCTAssertEqual(availability.accountState, .failed("unauthorized"))
    }
}
