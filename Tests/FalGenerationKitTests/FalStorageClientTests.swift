// ABOUTME: Verifies that a reference is uploaded rather than inlined, and never cached.
// ABOUTME: Every request here is inspected rather than sent; nothing reaches the network.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FalGenerationKit

/// Uploading a reference.
///
/// Applying a filter previously posted the whole photograph inside the request as a base64 data
/// URI, built in a SwiftUI view — a third again in size on the paid operation a user repeats most.
final class FalStorageClientTests: XCTestCase {

    private let apiKey = "fal-INVENTED-FOR-THIS-TEST"

    /// Records every request and answers with a script.
    private actor RecordingTransport: FalHTTPTransport {
        private(set) var requests: [URLRequest] = []
        private var uploadCount = 0

        func send(_ request: URLRequest) async throws -> FalHTTPResponse {
            requests.append(request)
            if request.url?.path.contains("initiate") == true {
                uploadCount += 1
                // A different destination each time, so reuse is visible from outside.
                let body = """
                    {"upload_url":"https://upload.example/put/\(uploadCount)",
                     "file_url":"https://v3.fal.media/files/\(uploadCount).png"}
                    """
                return FalHTTPResponse(statusCode: 200, headers: [:], body: Data(body.utf8))
            }
            return FalHTTPResponse(statusCode: 200, headers: [:], body: Data())
        }

        func recorded() -> [URLRequest] { requests }
    }

    /// A real PNG, so the content check has content to read.
    private func pngData() throws -> Data {
        let size = 8
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let image = try XCTUnwrap(context.makeImage())

        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    // MARK: - Two exchanges, the provider's address

    // RT-92.4
    func test_theInitiateRequestCarriesTheNameAndContentTypeAsJSON_RT092_4() async throws {
        let transport = RecordingTransport()
        let client = FalStorageClient(
            transport: transport, baseURL: URL(fileURLWithPath: "/")) // unused; requests inspected

        _ = try? await client.upload(try pngData(), fileName: "toby.png", apiKey: apiKey)

        let recorded = await transport.recorded()
        let initiate = try XCTUnwrap(recorded.first)
        let body = try XCTUnwrap(initiate.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(json["file_name"] as? String, "toby.png")
        XCTAssertEqual(json["content_type"] as? String, UTType.png.identifier)
        XCTAssertEqual(initiate.httpMethod, "POST")
    }

    // RT-92.5
    func test_theBytesGoToTheAddressTheProviderGave_RT092_5() async throws {
        let transport = RecordingTransport()
        let client = FalStorageClient(transport: transport)

        _ = try await client.upload(try pngData(), fileName: "toby.png", apiKey: apiKey)

        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 2, "one to ask, one to put")
        XCTAssertEqual(requests[1].httpMethod, "PUT")
        XCTAssertEqual(requests[1].url?.absoluteString, "https://upload.example/put/1")
    }

    // RT-92.6
    func test_theReturnedURLIsTheProvidersOwn_RT092_6() async throws {
        let client = FalStorageClient(transport: RecordingTransport())

        let url = try await client.upload(try pngData(), fileName: "toby.png", apiKey: apiKey)

        XCTAssertEqual(url.absoluteString, "https://v3.fal.media/files/1.png")
    }

    // MARK: - Never reused

    // RT-92.7, RT-92.8
    //
    // The FAL reference calls this a hard rule: CDN URLs expire at the provider's discretion. The
    // client has nowhere to cache — and this proves it from outside, which an internals check
    // could not.
    func test_twoAppliesUploadTwiceAndSendDifferentURLs_RT092_7() async throws {
        let transport = RecordingTransport()
        let client = FalStorageClient(transport: transport)
        let data = try pngData()

        let first = try await client.upload(data, fileName: "toby.png", apiKey: apiKey)
        let second = try await client.upload(data, fileName: "toby.png", apiKey: apiKey)

        XCTAssertNotEqual(first, second, "a cache would return the first URL again")
        let recorded = await transport.recorded()
        XCTAssertEqual(recorded.count, 4, "two exchanges, twice")
    }

    // MARK: - Content, not naming

    // RT-92.9
    func test_aPNGNamedJpgIsUploadedAsAPNG_RT092_9() async throws {
        let transport = RecordingTransport()
        let client = FalStorageClient(transport: transport)

        _ = try await client.upload(try pngData(), fileName: "toby.jpg", apiKey: apiKey)

        let recorded = await transport.recorded()
        let initiate = try XCTUnwrap(recorded.first)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(initiate.httpBody)) as? [String: Any])

        XCTAssertEqual(json["content_type"] as? String, UTType.png.identifier)
        XCTAssertEqual(json["file_name"] as? String, "toby.jpg", "the name is passed as given")
    }

    // RT-92.10
    func test_contentMatchingNoSupportedTypeIsRefusedBeforeAnyUpload_RT092_10() async {
        let transport = RecordingTransport()
        let client = FalStorageClient(transport: transport)

        do {
            _ = try await client.upload(
                Data("not an image at all".utf8), fileName: "notes.png", apiKey: apiKey)
            XCTFail("an unsupported file should be refused")
        } catch let error as FalStorageError {
            XCTAssertEqual(error, .unsupportedContent)
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        let sent = await transport.recorded()
        XCTAssertTrue(sent.isEmpty, "refused before spending any bandwidth")
    }

    // MARK: - The credential

    // RT-92.14, RT-92.15
    func test_theKeyIsInTheHeaderAndNowhereElse_RT092_14() async throws {
        let transport = RecordingTransport()
        let client = FalStorageClient(transport: transport)

        _ = try await client.upload(try pngData(), fileName: "toby.png", apiKey: apiKey)

        let recorded = await transport.recorded()
        let initiate = try XCTUnwrap(recorded.first)
        XCTAssertEqual(
            initiate.value(forHTTPHeaderField: "Authorization"), "Key \(apiKey)")

        let url = try XCTUnwrap(initiate.url?.absoluteString)
        XCTAssertFalse(url.contains(apiKey), url)
        let body = String(data: initiate.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertFalse(body.contains(apiKey), body)
    }

    // The signed upload address carries no credential of ours, so the second exchange sends none.
    func test_theTransferCarriesNoCredential() async throws {
        let transport = RecordingTransport()
        let client = FalStorageClient(transport: transport)

        _ = try await client.upload(try pngData(), fileName: "toby.png", apiKey: apiKey)

        let recorded = await transport.recorded()
        let put = recorded[1]
        XCTAssertNil(put.value(forHTTPHeaderField: "Authorization"))
    }
}
