// ABOUTME: Verifies the failure taxonomy: what kind, and that the provider's words survive it.
// ABOUTME: A category that replaced the message would be worse than no category at all.

import Foundation
import XCTest
@testable import FalGenerationKit

/// Classifying a failure.
///
/// Three clients raised three unrelated enums, so a caller asking "is this worth retrying, or is it
/// the user's to fix" had to match on all of them.
final class FalFailureTests: XCTestCase {

    // RT-98.11, RT-98.12
    //
    // The whole point of the taxonomy: a rejected key is something the user can fix, and an
    // unreachable host is something to try again. Named cases rather than an adjective, so the
    // test asserts a classification rather than a feeling.
    func test_aRejectedCredentialAndAnUnreachableHostClassifyDifferently_RT098_11() {
        let rejected = FalFailure.fromStatus(401, diagnostic: "Invalid key.")
        let unreachable = FalFailure.unreachable(diagnostic: "The network is unavailable.")

        XCTAssertEqual(rejected.kind, .credential)
        XCTAssertEqual(unreachable.kind, .transport)

        XCTAssertTrue(rejected.isUserActionable, "a key is something the user can fix")
        XCTAssertFalse(unreachable.isUserActionable, "a network is not")

        XCTAssertTrue(unreachable.isWorthRetrying)
        XCTAssertFalse(rejected.isWorthRetrying, "the same key will be rejected again")
    }

    func test_aForbiddenResponseIsAlsoACredentialFailure() {
        XCTAssertEqual(FalFailure.fromStatus(403, diagnostic: "Forbidden.").kind, .credential)
    }

    func test_anotherFourHundredIsTheRequest() {
        for status in [400, 404, 422] {
            XCTAssertEqual(
                FalFailure.fromStatus(status, diagnostic: "Nope.").kind, .request, "\(status)")
        }
    }

    func test_aFiveHundredIsTheProvider() {
        for status in [500, 502, 503] {
            let failure = FalFailure.fromStatus(status, diagnostic: "Upstream is unwell.")
            XCTAssertEqual(failure.kind, .provider, "\(status)")
            XCTAssertTrue(failure.isWorthRetrying, "later may work")
        }
    }

    // RT-98.13
    //
    // The classification is added to the diagnostic, not substituted for it. "The model rejected
    // that aspect ratio" is what the user needs; `request` is what the caller needs.
    func test_theProvidersOwnWordsSurviveTheClassification_RT098_13() {
        let words = "The model rejected that aspect ratio."
        let failure = FalFailure.fromStatus(422, diagnostic: words)

        XCTAssertEqual(failure.diagnostic, words)
        XCTAssertEqual(failure.errorDescription, words, "and that is what a user reads")
    }
}
