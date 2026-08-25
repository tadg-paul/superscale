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
    ///
    /// - Parameter size: the edge length in pixels. RT-92.3 needs two pictures whose *byte* sizes
    ///   differ by an order of magnitude, to show that the request body's size does not follow.
    private func pngData(size: Int = 8) throws -> Data {
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

    // MARK: - AC92.1: the body carries a URL, never bytes

    // RT-92.1, RT-92.2
    //
    // The reference was a `data:` URL — a whole photograph base64-encoded into the JSON. Asserted
    // as *the generation request's* body rather than the upload's, because that is where the bytes
    // used to be and where the criterion says they must not be.
    func test_theGenerationBodyCarriesTheProvidersURLAndNoPayload_RT092_1() async throws {
        let transport = RecordingTransport()
        let reference = try await FalStorageClient(transport: transport)
            .upload(try pngData(), fileName: "toby.png", apiKey: apiKey)

        let prepared = try FalRequestBuilder().prepare(
            FalGenerationRequest(
                prompt: "a film noir portrait",
                aspectRatio: "1:1",
                referenceImageURLs: [reference.absoluteString]),
            apiKey: apiKey)

        // Decoded rather than string-matched: `JSONSerialization` escapes forward slashes, so a
        // body genuinely containing the URL does not contain its unescaped text.
        let data = try XCTUnwrap(prepared.urlRequest.httpBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(
            payload["image_urls"] as? [String], [reference.absoluteString],
            "the URL the upload returned")

        let body = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(body.contains("data:"), "no data URL: \(body.prefix(200))")
        XCTAssertFalse(body.contains("base64"), "and no payload")
    }

    // RT-92.3
    //
    // The body's size is independent of the reference's size. A `data:` URL grew the request by a
    // third of the file, so a large photograph produced a large body — and the two pictures here
    // differ in bytes by an order of magnitude while the bodies differ by nothing.
    func test_theBodysSizeIsIndependentOfTheReferencesSize_RT092_3() async throws {
        func bodyLength(forPixels size: Int) async throws -> Int {
            let transport = RecordingTransport()
            let reference = try await FalStorageClient(transport: transport)
                .upload(try pngData(size: size), fileName: "toby.png", apiKey: apiKey)
            let prepared = try FalRequestBuilder().prepare(
                FalGenerationRequest(
                    prompt: "a film noir portrait",
                    aspectRatio: "1:1",
                    referenceImageURLs: [reference.absoluteString]),
                apiKey: apiKey)
            return prepared.urlRequest.httpBody?.count ?? 0
        }

        let small = try await bodyLength(forPixels: 8)
        let large = try await bodyLength(forPixels: 256)

        XCTAssertEqual(
            small, large,
            "the body says where the picture is, not what it contains")
    }

    // RT-92.8
    //
    // The no-reuse guarantee is structural — the absence of a cache — so the test for it is
    // behavioural. The stub issues a different URL per upload, and two applies of the same base
    // must send two different ones. An implementation that cached would fail this in a way an
    // internals check would not.
    func test_twoAppliesOfTheSameBaseSendTwoDifferentURLs_RT092_8() async throws {
        let transport = RecordingTransport()
        let client = FalStorageClient(transport: transport)
        let bytes = try pngData()

        let first = try await client.upload(bytes, fileName: "toby.png", apiKey: apiKey)
        let second = try await client.upload(bytes, fileName: "toby.png", apiKey: apiKey)

        XCTAssertNotEqual(first, second, "each apply uploads afresh")
    }

    // MARK: - AC92.5: an upload that fails is reported, and nothing partial survives

    /// Fails at whichever exchange it is told to.
    private actor FailingTransport: FalHTTPTransport {
        enum Stage { case initiate, transfer }
        let failing: Stage
        private(set) var requests: [URLRequest] = []

        init(failing: Stage) { self.failing = failing }

        func send(_ request: URLRequest) async throws -> FalHTTPResponse {
            requests.append(request)
            let isInitiate = request.url?.path.contains("initiate") == true
            if (isInitiate && failing == .initiate) || (!isInitiate && failing == .transfer) {
                return FalHTTPResponse(
                    statusCode: 500, headers: [:],
                    body: Data("{\"message\":\"Storage is unavailable.\"}".utf8))
            }
            let body = """
                {"upload_url":"https://upload.example/put/1",
                 "file_url":"https://v3.fal.media/files/1.png"}
                """
            return FalHTTPResponse(statusCode: 200, headers: [:], body: Data(body.utf8))
        }

        func recorded() -> [URLRequest] { requests }
    }

    // RT-92.11
    func test_anInitiateFailureIsReportedInPlainLanguage_RT092_11() async throws {
        let client = FalStorageClient(transport: FailingTransport(failing: .initiate))

        do {
            _ = try await client.upload(try pngData(), fileName: "toby.png", apiKey: apiKey)
            XCTFail("an initiate failure should not produce a reference")
        } catch {
            let described = error.localizedDescription
            XCTAssertFalse(described.isEmpty, "it says something")
            XCTAssertFalse(described.contains(apiKey), "and not the key")
        }
    }

    // RT-92.12
    func test_aByteTransferFailureIsReportedTheSameWay_RT092_12() async throws {
        let client = FalStorageClient(transport: FailingTransport(failing: .transfer))

        do {
            _ = try await client.upload(try pngData(), fileName: "toby.png", apiKey: apiKey)
            XCTFail("a transfer failure should not produce a reference")
        } catch {
            let described = error.localizedDescription
            XCTAssertFalse(described.isEmpty)
            XCTAssertFalse(described.contains(apiKey))
        }
    }

    // RT-92.13
    //
    // Neither failure leaves a partial reference behind for the generation request to use. The
    // dangerous shape is the transfer failure: the initiate exchange has already returned a
    // `file_url`, so an implementation returning it before the bytes arrive would send the provider
    // a URL with nothing behind it.
    func test_neitherFailureLeavesAPartialReferenceBehind_RT092_13() async throws {
        for stage in [FailingTransport.Stage.initiate, .transfer] {
            let transport = FailingTransport(failing: stage)
            let client = FalStorageClient(transport: transport)

            let reference = try? await client.upload(
                try pngData(), fileName: "toby.png", apiKey: apiKey)

            XCTAssertNil(reference, "\(stage): no URL escapes a failed upload")
        }
    }

    // MARK: - AC92.6: the credential appears only in a header

    // RT-92.15, RT-92.16
    //
    // Across *every* request the upload makes, not only the first. RT-92.14 checks the initiate
    // exchange's header; this checks that no URL and no body anywhere in the exchange carries the
    // token, and that a failure's diagnostic does not either.
    func test_noRequestURLOrBodyAnywhereContainsTheToken_RT092_15() async throws {
        let transport = RecordingTransport()
        let client = FalStorageClient(transport: transport)

        _ = try await client.upload(try pngData(), fileName: "toby.png", apiKey: apiKey)

        let recorded = await transport.recorded()
        XCTAssertEqual(recorded.count, 2, "initiate, then transfer")
        for request in recorded {
            XCTAssertFalse(
                request.url?.absoluteString.contains(apiKey) ?? false,
                request.url?.absoluteString ?? "")
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            XCTAssertFalse(body.contains(apiKey), body.prefix(200).description)
        }
    }
}
