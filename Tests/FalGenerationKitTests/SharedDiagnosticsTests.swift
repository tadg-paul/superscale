// ABOUTME: Verifies that all three clients read a provider failure through the same parser.
// ABOUTME: Pricing reimplemented a smaller one with no nesting, no request id and no redaction.

import Foundation
import XCTest
@testable import FalGenerationKit

/// One parser, three clients.
///
/// The strongest form of "the same parser" that can be asserted from outside is that identical
/// bodies produce identical diagnostics whichever client made the call. Asserted that way rather
/// than by inspecting which function each client calls, which is a claim about source.
///
/// Every response here is stubbed and the keys are strings these tests invent. No test reaches the
/// network, and none reaches a paid endpoint.
final class SharedDiagnosticsTests: XCTestCase {

    private let generationKey = "fal-generation-INVENTED-FOR-THIS-TEST"
    private let accountKey = "fal-account-INVENTED-FOR-THIS-TEST"

    private let baseURL = URL(string: "https://api.example.invalid") ?? URL(fileURLWithPath: "/")

    /// Answers every request with the same failing body.
    private struct FailingBodyTransport: FalHTTPTransport {
        let statusCode: Int
        let body: Data

        func send(_ request: URLRequest) async throws -> FalHTTPResponse {
            FalHTTPResponse(statusCode: statusCode, headers: [:], body: body)
        }
    }

    private func body(_ json: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: json)
    }

    // MARK: - The diagnostic each client produces for one body

    private func generationDiagnostic(
        _ payload: Data, statusCode: Int = 500
    ) async -> String {
        let client = FalGenerationClient(
            transport: FailingBodyTransport(statusCode: statusCode, body: payload),
            baseURL: baseURL)
        do {
            _ = try await client.generate(
                FalGenerationRequest(prompt: "a portrait", aspectRatio: "1:1"),
                apiKey: generationKey,
                otherSecrets: [accountKey])
            return "no failure"
        } catch let failure as FalGenerationError {
            guard case let .providerFailure(_, diagnostic) = failure else {
                return failure.localizedDescription
            }
            return diagnostic
        } catch {
            return error.localizedDescription
        }
    }

    private func pricingDiagnostic(
        _ payload: Data, statusCode: Int = 500
    ) async -> String {
        let client = FalPricingClient(
            transport: FailingBodyTransport(statusCode: statusCode, body: payload),
            baseURL: baseURL)
        do {
            _ = try await client.pricing(
                modelID: "xai/grok-imagine-image",
                apiKey: generationKey,
                otherSecrets: [accountKey])
            return "no failure"
        } catch let failure as FalPricingError {
            guard case let .httpFailure(_, diagnostic) = failure else {
                return failure.localizedDescription
            }
            return diagnostic
        } catch {
            return error.localizedDescription
        }
    }

    private func accountDiagnostic(
        _ payload: Data, statusCode: Int = 500
    ) async -> String {
        let client = FalAccountClient(
            transport: FailingBodyTransport(statusCode: statusCode, body: payload),
            baseURL: baseURL)
        do {
            _ = try await client.summary(
                accountKey: accountKey, otherSecrets: [generationKey])
            return "no failure"
        } catch let failure as FalAccountError {
            guard case let .httpFailure(_, diagnostic) = failure else {
                return failure.localizedDescription
            }
            return diagnostic
        } catch {
            return error.localizedDescription
        }
    }

    // RT-98.1
    //
    // Pricing did its own smaller version — `message` or `detail`, no nesting, no request
    // identifier, no redaction — so an identical body produced a different, and less safe,
    // diagnostic depending on which call happened to fail.
    func test_identicalBodiesProduceIdenticalDiagnosticsOnEveryClient_RT098_1() async throws {
        let payload = try body([
            "message": "The model rejected that aspect ratio.",
            "request_id": "req-98-1",
        ])

        let generation = await generationDiagnostic(payload)
        let pricing = await pricingDiagnostic(payload)
        let account = await accountDiagnostic(payload)

        XCTAssertEqual(generation, pricing)
        XCTAssertEqual(pricing, account)
        XCTAssertTrue(generation.contains("rejected that aspect ratio"), generation)
    }

    // RT-98.2
    func test_aNestedErrorMessageIsReadOnEveryClient_RT098_2() async throws {
        let payload = try body(["error": ["message": "Upstream is unavailable."]])

        for diagnostic in [
            await generationDiagnostic(payload),
            await pricingDiagnostic(payload),
            await accountDiagnostic(payload),
        ] {
            XCTAssertTrue(diagnostic.contains("Upstream is unavailable"), diagnostic)
        }
    }

    // RT-98.3
    func test_aRequestIdentifierIsAttachedOnEveryClient_RT098_3() async throws {
        let payload = try body(["message": "Nope.", "request_id": "req-98-3"])

        for diagnostic in [
            await generationDiagnostic(payload),
            await pricingDiagnostic(payload),
            await accountDiagnostic(payload),
        ] {
            XCTAssertTrue(diagnostic.contains("req-98-3"), diagnostic)
        }
    }

    // RT-98.10
    //
    // The live defect. Redaction was on the generation client only, so a pricing failure carrying a
    // key in its echoed payload surfaced it while the identical failure from a generation call did
    // not.
    func test_redactionHappensOnEveryClient_RT098_10() async throws {
        let payload = try body([
            "message": "Rejected key \(generationKey) for account \(accountKey).",
        ])

        for diagnostic in [
            await generationDiagnostic(payload),
            await pricingDiagnostic(payload),
            await accountDiagnostic(payload),
        ] {
            XCTAssertFalse(diagnostic.contains(generationKey), diagnostic)
            XCTAssertFalse(diagnostic.contains(accountKey), diagnostic)
            XCTAssertTrue(diagnostic.contains("[REDACTED]"), diagnostic)
        }
    }

    // RT-98.16, at the client rather than at the redactor
    //
    // Redaction removes only what it is handed. A call passing its own key alone leaves the *other*
    // credential echoed in a body untouched, and this application holds both — so the client, not
    // just the redactor, has to be given both.
    func test_eachClientRedactsTheCredentialTheCallDidNotUse_RT098_16() async throws {
        let generation = await generationDiagnostic(
            try body(["message": "Your account key \(accountKey) is suspended."]))
        XCTAssertFalse(generation.contains(accountKey), generation)

        let account = await accountDiagnostic(
            try body(["message": "Your generation key \(generationKey) is suspended."]))
        XCTAssertFalse(account.contains(generationKey), account)
    }

    // RT-98.12
    //
    // The classification a caller acts on: a rejected credential is the user's to fix, an
    // unreachable host is worth retrying, and telling them apart must not require knowing which
    // client raised the failure.
    func test_aRejectedCredentialAndAnUnreachableHostClassifyDifferently_RT098_12() async throws {
        let payload = try body(["message": "Unauthorized."])

        let rejected = FalFailure.fromStatus(
            401, diagnostic: await generationDiagnostic(payload, statusCode: 401))
        let unreachable = FalFailure.unreachable(diagnostic: "The host could not be reached.")

        XCTAssertEqual(rejected.kind, .credential)
        XCTAssertTrue(rejected.isUserActionable, "the user can fix a bad key")
        XCTAssertFalse(rejected.isWorthRetrying, "retrying the same key will fail the same way")

        XCTAssertEqual(unreachable.kind, .transport)
        XCTAssertFalse(unreachable.isUserActionable)
        XCTAssertTrue(unreachable.isWorthRetrying)
    }

    /// A validation failure reported as a list is read the same way whichever client saw it.
    func test_aDetailListIsReadOnEveryClient() async throws {
        let payload = try body([
            "detail": [
                ["msg": "aspect_ratio is not supported"],
                ["msg": "image_urls must contain at least one entry"],
            ]
        ])

        for diagnostic in [
            await generationDiagnostic(payload, statusCode: 422),
            await pricingDiagnostic(payload, statusCode: 422),
            await accountDiagnostic(payload, statusCode: 422),
        ] {
            XCTAssertTrue(diagnostic.contains("aspect_ratio is not supported"), diagnostic)
            XCTAssertTrue(diagnostic.contains("at least one entry"), diagnostic)
        }
    }
}
