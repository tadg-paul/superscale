// ABOUTME: Verifies that a provider's error is read in every shape and carries no credential out.
// ABOUTME: The keys here are strings the tests invent; no real credential proves credentials are removed.

import Foundation
import XCTest
@testable import FalGenerationKit

/// Reading a provider failure.
///
/// Two things matter and they pull against each other: say what the provider said, and never say a
/// key. The second is why truncation and redaction have an order.
final class DiagnosticRedactorTests: XCTestCase {

    private let generationKey = "fal-generation-INVENTED-FOR-THIS-TEST"
    private let accountKey = "fal-account-INVENTED-FOR-THIS-TEST"

    private var allSecrets: [String] { [generationKey, accountKey] }

    private func diagnostic(for json: Any, secrets: [String]? = nil) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: json)
        return FalDiagnosticRedactor.providerDiagnostic(
            from: data, secrets: secrets ?? allSecrets)
    }

    // MARK: - Every envelope

    func test_aTopLevelMessageIsRead() throws {
        let text = try diagnostic(for: ["message": "The model rejected that aspect ratio."])

        XCTAssertTrue(text.contains("rejected that aspect ratio"), text)
    }

    func test_aNestedErrorMessageIsRead() throws {
        let text = try diagnostic(for: ["error": ["message": "Upstream is unavailable."]])

        XCTAssertTrue(text.contains("Upstream is unavailable"), text)
    }

    func test_aRequestIdentifierIsAttached() throws {
        let text = try diagnostic(for: ["message": "Nope.", "request_id": "req-123"])

        XCTAssertTrue(text.contains("req-123"), text)
    }

    // MARK: - `detail`, in both shapes

    // RT-98.6
    func test_aDetailStringStillProducesThatString_RT098_6() throws {
        let text = try diagnostic(for: ["detail": "Body too large."])

        XCTAssertTrue(text.contains("Body too large"), text)
    }

    // RT-98.4
    //
    // FastAPI runs the platform host and reports validation failures as a list. Against a list the
    // parser fell through to a generic sentence, discarding the only part that said what was wrong.
    func test_aDetailListOfOneProducesThatEntrysMessage_RT098_4() throws {
        let text = try diagnostic(
            for: ["detail": [["loc": ["body", "aspect_ratio"], "msg": "unsupported value"]]])

        XCTAssertTrue(text.contains("unsupported value"), text)
        XCTAssertFalse(text.contains("The provider rejected the request."), text)
    }

    // RT-98.5
    func test_aDetailListOfSeveralProducesAllOfThem_RT098_5() throws {
        let text = try diagnostic(
            for: ["detail": [["msg": "first problem"], ["msg": "second problem"]]])

        XCTAssertTrue(text.contains("first problem"), text)
        XCTAssertTrue(text.contains("second problem"), text)
    }

    // MARK: - No credential leaves

    // RT-98.7
    func test_aKeyEchoedInAMessageIsRedacted_RT098_7() throws {
        let text = try diagnostic(for: ["message": "Bad key: \(generationKey)"])

        XCTAssertFalse(text.contains(generationKey), text)
        XCTAssertTrue(text.contains("[REDACTED]"), text)
    }

    // RT-98.8
    func test_aKeyEchoedInADetailListEntryIsRedacted_RT098_8() throws {
        let text = try diagnostic(for: ["detail": [["msg": "rejected \(generationKey)"]]])

        XCTAssertFalse(text.contains(generationKey), text)
    }

    // RT-98.16
    //
    // The redactor removes only what it is handed. Passing the key the failing call used would
    // leave the other one — and this application holds two.
    func test_aGenerationFailureRedactsAnEchoedAccountKey_RT098_16() throws {
        let text = try diagnostic(for: ["message": "saw \(accountKey)"])

        XCTAssertFalse(text.contains(accountKey), text)
    }

    // RT-98.9
    func test_aKeyEchoedInAnUnparseableBodyIsRedacted_RT098_9() {
        let body = Data("<html>oops \(generationKey)</html>".utf8)
        let text = FalDiagnosticRedactor.providerDiagnostic(from: body, secrets: allSecrets)

        XCTAssertFalse(text.contains(generationKey), text)
    }

    // RT-98.17
    //
    // Truncation used to happen first, so a key straddling the limit left a fragment behind: the
    // whole key was genuinely absent and a test looking for the whole key would have passed.
    func test_aSecretStraddlingTheTruncationBoundaryLeavesNoFragment_RT098_17() {
        let limit = FalDiagnosticRedactor.unparseableBodyLimit
        // Place the key so that it begins a few characters before the cut and ends after it.
        let padding = String(repeating: "x", count: limit - 5)
        let body = Data("\(padding)\(generationKey) trailing".utf8)

        let text = FalDiagnosticRedactor.providerDiagnostic(from: body, secrets: allSecrets)

        let head = String(generationKey.prefix(8))
        XCTAssertFalse(text.contains(head), "a fragment of the key survived: \(text.suffix(40))")
    }

    // An unreadable body is still bounded, so an echoed payload cannot flood a diagnostic.
    func test_anUnparseableBodyIsBounded() {
        let body = Data(String(repeating: "y", count: 5_000).utf8)
        let text = FalDiagnosticRedactor.providerDiagnostic(from: body, secrets: allSecrets)

        XCTAssertLessThanOrEqual(text.count, FalDiagnosticRedactor.unparseableBodyLimit)
    }

    func test_anEmptyBodyProducesAPlainSentence() {
        let text = FalDiagnosticRedactor.providerDiagnostic(from: Data(), secrets: allSecrets)

        XCTAssertEqual(text, "The provider rejected the request.")
    }
}
