// ABOUTME: Verifies that a generation key is checked against the provider, free of charge.
// ABOUTME: The badge in Settings reported storage, so a typo saved and showed a green tick.

import Foundation
import XCTest
@testable import FalGenerationKit

/// What the provider says about a key, and what it costs to ask.
///
/// Every response here is stubbed. No test reaches the network, and none can reach a paid endpoint:
/// RT-95.16 asserts that as a property of the request rather than trusting it.
final class CredentialVerifierTests: XCTestCase {

    private let apiKey = "test-key-not-a-real-credential"

    /// Answers with a fixed status, and keeps what it was asked.
    private actor StubTransport: FalHTTPTransport {
        private let statusCode: Int
        private let failure: (any Error)?
        private(set) var requests: [URLRequest] = []

        init(statusCode: Int = 200, failure: (any Error)? = nil) {
            self.statusCode = statusCode
            self.failure = failure
        }

        func send(_ request: URLRequest) async throws -> FalHTTPResponse {
            requests.append(request)
            if let failure { throw failure }
            return FalHTTPResponse(statusCode: statusCode, headers: [:], body: Data("{}".utf8))
        }

        func recorded() -> [URLRequest] { requests }
    }

    private struct Unreachable: Error {}

    private func verifier(_ transport: some FalHTTPTransport) -> FalCredentialVerifier {
        FalCredentialVerifier(
            transport: transport,
            baseURL: URL(string: "https://api.fal.ai") ?? URL(fileURLWithPath: "/"))
    }

    // MARK: - The four answers

    // RT-95.6
    func test_aKeyTheProviderAcceptsReadsAsWorking_RT095_6() async {
        let verdict = await verifier(StubTransport(statusCode: 200)).verifyGenerationKey(apiKey)

        XCTAssertEqual(verdict, .accepted)
    }

    // RT-95.7
    //
    // With a reason. "Rejected" alone leaves the user choosing between a typo, an expired key and a
    // key belonging to another account.
    func test_aKeyTheProviderRejectsReadsAsRejectedWithAReason_RT095_7() async {
        for status in [401, 403] {
            let verdict = await verifier(StubTransport(statusCode: status))
                .verifyGenerationKey(apiKey)

            guard case let .rejected(reason) = verdict else {
                return XCTFail("\(status) produced \(verdict)")
            }
            XCTAssertFalse(reason.isEmpty, "a rejection says why")
        }
    }

    // RT-95.8
    //
    // The one that matters most. Reporting an unreachable provider as a rejection has the user
    // delete a key that works.
    func test_anUnreachableProviderIsNotAnAnswerAboutTheKey_RT095_8() async {
        let thrown = await verifier(StubTransport(failure: Unreachable()))
            .verifyGenerationKey(apiKey)
        XCTAssertEqual(thrown, .unreachable, "a transport failure")

        let serverFault = await verifier(StubTransport(statusCode: 503))
            .verifyGenerationKey(apiKey)
        XCTAssertEqual(serverFault, .unreachable, "the provider's own outage")

        // A rate limit is the provider declining to answer, not declining the key.
        let throttled = await verifier(StubTransport(statusCode: 429))
            .verifyGenerationKey(apiKey)
        XCTAssertEqual(throttled, .unreachable)
    }

    func test_anEmptyKeyIsRejectedWithoutAskingAnybody() async {
        let transport = StubTransport(statusCode: 200)

        let verdict = await verifier(transport).verifyGenerationKey("   ")

        guard case .rejected = verdict else { return XCTFail("\(verdict)") }
        let recorded = await transport.recorded()
        XCTAssertTrue(recorded.isEmpty, "nothing to ask about")
    }

    // MARK: - What the check costs

    // RT-95.16
    //
    // The client most obviously to hand is `FalGenerationClient`, whose calls generate images at 2c
    // each. Verifying by generating would charge a user for checking whether they typed their key
    // correctly, and charge them twice if they had not.
    func test_verificationIssuesNoGenerationRequest_RT095_16() async throws {
        let transport = StubTransport(statusCode: 200)

        _ = await verifier(transport).verifyGenerationKey(apiKey)

        let recorded = await transport.recorded()
        let request = try XCTUnwrap(recorded.first)
        let url = try XCTUnwrap(request.url?.absoluteString)

        XCTAssertEqual(request.httpMethod ?? "GET", "GET", "a read, not a submission")
        XCTAssertNil(request.httpBody, "nothing is submitted")
        XCTAssertTrue(url.contains("/models"), url)
        XCTAssertFalse(url.contains("grok"), "no model is invoked: \(url)")
        XCTAssertFalse(url.contains("queue"), "no job is queued: \(url)")
        XCTAssertEqual(recorded.count, 1, "one call, not a poll loop")
    }

    /// The secret travels in the header and nowhere else — not in the URL, where it would reach
    /// every proxy log between here and the provider.
    func test_theKeyTravelsInTheHeaderOnly() async throws {
        let transport = StubTransport(statusCode: 200)

        _ = await verifier(transport).verifyGenerationKey(apiKey)

        let recorded = await transport.recorded()
        let request = try XCTUnwrap(recorded.first)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"), "Key \(apiKey)")
        XCTAssertFalse(request.url?.absoluteString.contains(apiKey) ?? true)
    }

    func test_surroundingWhitespaceIsTrimmedBeforeAsking() async throws {
        let transport = StubTransport(statusCode: 200)

        _ = await verifier(transport).verifyGenerationKey("  \(apiKey)\n")

        let recorded = await transport.recorded()
        let request = try XCTUnwrap(recorded.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Key \(apiKey)")
    }
}
