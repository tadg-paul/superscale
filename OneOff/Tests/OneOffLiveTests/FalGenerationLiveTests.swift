// ABOUTME: One live run of the whole cloud filter chain — upload, grok generation, decodable image.
// ABOUTME: Costs a real 2c per run by the author's authorization; never part of any regression pack.

import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import FalGenerationKit
import SuperscaleUXCore

/// The application's cloud path, run for real, once.
///
/// #107's storage tests prove the upload; this proves everything the GUI's Apply does below the
/// view: a reference uploaded through `FalStorageClient`, a generation through
/// `FalGenerationClient` against **grok** (the MVP's flat-rate model, 2c per call), and a returned
/// image that actually decodes. Same types, same defaults, same chain as `MainView.submitFilter`.
///
/// **Cost discipline, per the author's authorization of 2026-08-25:** one grok call per run of this
/// suite. It ran once, passed, and one-offs are not repeated — there is deliberately no make
/// target for it. The only entry point is `scripts/run-live-ot.sh`, `make test-one-off` skips
/// `LiveTests`, and `make test` cannot reach this package at all, so nothing can spend money or
/// touch the network by accident.
///
/// Credentials as in `FalStorageLiveTests`: `FAL_KEY` from the environment (the wrapper sources
/// `.env`; nothing parses it), else the application's own Keychain slot, else skip.
final class FalGenerationLiveTests: XCTestCase {

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

    /// A small real photograph-like reference, generated rather than committed.
    ///
    /// A gradient rather than a flat colour: a model given a solid orange square has little to
    /// work from, and a degenerate reference makes a degenerate test.
    private func referencePNG() throws -> Data {
        let size = 256
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let colors = [
            CGColor(red: 0.9, green: 0.5, blue: 0.2, alpha: 1),
            CGColor(red: 0.1, green: 0.3, blue: 0.7, alpha: 1),
        ]
        let gradient = try XCTUnwrap(
            CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray, locations: [0, 1]))
        context.drawLinearGradient(
            gradient,
            start: .zero,
            end: CGPoint(x: size, y: size),
            options: [])
        let image = try XCTUnwrap(context.makeImage())

        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    // OT-107.4
    //
    // The one paid call. Everything the GUI's Apply does below the view, asserted in one pass so a
    // second run is never needed for a second property.
    func test_theWholeCloudFilterChainRunsLiveAndReturnsADecodableImage_OT107_4() async throws {
        let key = try liveKey()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ot107-gen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("reference.png")
        try referencePNG().write(to: file)

        // Stage 1: the reference reaches the provider's own storage.
        let storage = FalStorageClient()
        let reference = try await storage.upload(
            fileURL: file, fileName: "reference.png", apiKey: key)

        // Stage 2: grok, explicitly — the authorization is model-specific, so the test does not
        // lean on the default staying what it is today.
        let request = FalGenerationRequest(
            prompt: "A watercolour painting of a sunrise over the sea",
            modelID: "xai/grok-imagine-image",
            aspectRatio: "1:1",
            referenceImageURLs: [reference.absoluteString])

        let client = FalGenerationClient()
        let generated = try await client.generate(request, apiKey: key)

        // The provider's own address, as AC92.1 requires of the request path.
        XCTAssertTrue(
            generated.remoteURL.host?.contains("fal") == true,
            "the image lives at the provider: \(generated.remoteURL.host ?? "-")")

        // The bytes are a real picture, not merely a 200 with a body.
        XCTAssertFalse(generated.data.isEmpty, "an image came back")
        let source = try XCTUnwrap(
            CGImageSourceCreateWithData(generated.data as CFData, nil),
            "the bytes open as an image")
        let decoded = try XCTUnwrap(
            CGImageSourceCreateImageAtIndex(source, 0, nil), "and decode")
        XCTAssertGreaterThan(decoded.width, 0)
        XCTAssertGreaterThan(decoded.height, 0)

        // Warnings surface rather than vanish; an empty list is the pass, and a populated one is
        // words in the log for a human to weigh, not a failure.
        for warning in generated.warnings {
            print("OT-107.4 provider warning: \(warning)")
        }
    }
}
