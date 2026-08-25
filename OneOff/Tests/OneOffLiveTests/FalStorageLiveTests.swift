// ABOUTME: One-off tests that exercise the real FAL storage API with the user's own credential.
// ABOUTME: Exists because every regression test stubs the transport, so the wire format was believed, not proven.

import Foundation
import XCTest
@testable import FalGenerationKit
import SuperscaleUXCore

/// The live storage exchange, proven rather than rehearsed.
///
/// #107: the first real GUI attempt at the cloud path failed at the initiate exchange with
/// "Invalid storage type", because `storage_type=gcs` had never been sent to anything but a stub.
/// The stubs verify we send what we believe the protocol is; these verify the belief.
///
/// **Credential:** `FAL_KEY` from the environment where set, otherwise the same Keychain slot the
/// application reads (`org.tigoss.superscale.generation` / `fal-generation`) — so a green run
/// proves the key the user typed into Settings, end to end. Where neither exists the tests skip
/// with a message rather than failing, because absence of a secret is not a defect. The credential
/// never appears in any assertion message, log or artefact.
///
/// **Cost and residue:** each run uploads one picture of a few hundred bytes to FAL's CDN. FAL
/// expires uploads at its own discretion (the no-cache rule exists because of that); nothing here
/// needs cleanup and nothing can perform it.
final class FalStorageLiveTests: XCTestCase {

    private func liveKey() throws -> String {
        if let fromEnvironment = ProcessInfo.processInfo.environment["FAL_KEY"],
            !fromEnvironment.isEmpty
        {
            return fromEnvironment
        }
        let service = GenerationCredentialService(storage: KeychainCredentialStorage())
        if let stored = try? service.generationKey(), !stored.isEmpty {
            return stored
        }
        throw XCTSkip("No FAL credential: set FAL_KEY or store a key in the application's Settings.")
    }

    /// A tiny valid PNG, generated rather than committed, so the upload is real but negligible.
    private func probePNG() throws -> Data {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.9, green: 0.4, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try XCTUnwrap(context.makeImage())

        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    // OT-107.1
    //
    // The initiate exchange against the real endpoint: the storage type we send is one the
    // provider accepts, and the response carries both URLs the client's parser expects. This is
    // the exact exchange that failed for the author on 2026-08-25.
    func test_aLiveInitiateReturnsTheProvidersOwnDestination_OT107_1() async throws {
        let key = try liveKey()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ot107-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("ot-107-1.png")
        try probePNG().write(to: file)

        let client = FalStorageClient()
        let url = try await client.upload(fileURL: file, fileName: "ot-107-1.png", apiKey: key)

        XCTAssertEqual(url.scheme, "https", "the provider issued a real address")
        XCTAssertTrue(
            url.host?.contains("fal.media") == true,
            "and it is the provider's own CDN, not something composed locally: \(url.host ?? "-")")
    }

    // OT-107.2
    //
    // The full round trip: what comes back from the returned URL is byte-for-byte what was sent.
    // An initiate that succeeds while the PUT quietly mangles the body would pass OT-107.1 and
    // hand the model a corrupted reference.
    func test_aLiveRoundTripReturnsTheBytesThatWereSent_OT107_2() async throws {
        let key = try liveKey()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ot107-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let sent = try probePNG()
        let file = directory.appendingPathComponent("ot-107-2.png")
        try sent.write(to: file)

        let client = FalStorageClient()
        let url = try await client.upload(fileURL: file, fileName: "ot-107-2.png", apiKey: key)

        let (received, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(received, sent, "the CDN serves the picture that was uploaded")
    }

    // OT-107.3
    //
    // The failure shape. The defect reached the author as a *usable sentence* only because the
    // parser read FAL's error body; this pins that the live error for a bad storage type is still
    // the shape the parser expects, so the diagnostic the user reads stays faithful. Driven
    // through the client itself with a bad base URL query — not possible, so driven raw.
    func test_theLiveErrorShapeForABadStorageTypeIsStillParseable_OT107_3() async throws {
        let key = try liveKey()

        var components = try XCTUnwrap(
            URLComponents(string: "https://rest.fal.ai/storage/upload/initiate"))
        components.queryItems = [URLQueryItem(name: "storage_type", value: "gcs")]
        var request = URLRequest(url: try XCTUnwrap(components.url))
        request.httpMethod = "POST"
        request.setValue("Key \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["file_name": "probe.png", "content_type": "image/png"])

        let (body, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        XCTAssertGreaterThanOrEqual(status, 400, "the rejected value is still rejected")

        let parsed = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: body) as? [String: Any],
            "the error body is still JSON")
        let detail = try XCTUnwrap(parsed["detail"], "and still carries a detail field")
        XCTAssertFalse("\(detail)".isEmpty, "with words in it a user could be shown")
    }
}
