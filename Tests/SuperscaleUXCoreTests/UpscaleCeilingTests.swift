// ABOUTME: Verifies the ceiling that stops a large upscale exhausting memory and killing the app.
// ABOUTME: Bounds the output by area, because that is what the stitching buffer scales with.

import CoreGraphics
import Foundation
import SuperscaleKit
import XCTest
@testable import SuperscaleUXCore

/// The ceiling.
///
/// `Tiler.stitch` holds roughly 36 bytes per output pixel, all resident. The documented caps were
/// expressed as a long edge, which says nothing about area: 8192 × 8192 is 67 megapixels and about
/// 2.4 GB, while 8192 × 1000 is 8 megapixels and about 300 MB. The old rule treated those two
/// alike, and a 2000-pixel-wide picture at 4x fell into the gap between "warn" and "refuse" —
/// permitted, and fatal.
final class UpscaleCeilingTests: XCTestCase {

    private let source = CGSize(width: 2000, height: 2000)

    // MARK: - Presets

    // RT-91.1
    func test_anOutputAboveTheCeilingIsReducedToTheLargestScaleThatFits_RT091_1() {
        let decision = UpscaleCeiling.decide(
            sourceSize: source, requested: .preset(scale: 4))

        XCTAssertTrue(decision.wasReduced)
        XCTAssertLessThanOrEqual(
            decision.outputSize.width * decision.outputSize.height,
            CGFloat(UpscaleCeiling.maximumOutputPixels))
        XCTAssertEqual(decision.sizing, .preset(scale: 2), "the largest preset that fits")
    }

    // RT-91.5
    //
    // The reported case. Asserted as a sizing rather than by performing the upscale: a test that
    // reproduces a 2.3 GB allocation by allocating 2.3 GB is not a test.
    func test_theReportedCaseYieldsASizingThatFits_RT091_5() {
        let decision = UpscaleCeiling.decide(
            sourceSize: CGSize(width: 2000, height: 1500), requested: .preset(scale: 4))

        let outputPixels = decision.outputSize.width * decision.outputSize.height
        XCTAssertLessThanOrEqual(outputPixels, CGFloat(UpscaleCeiling.maximumOutputPixels))
        XCTAssertTrue(decision.wasReduced)
    }

    // RT-91.3
    func test_anOutputThatFitsIsUnreduced_RT091_3() {
        let decision = UpscaleCeiling.decide(
            sourceSize: CGSize(width: 800, height: 600), requested: .preset(scale: 4))

        XCTAssertFalse(decision.wasReduced)
        XCTAssertEqual(decision.sizing, .preset(scale: 4), "what was asked for is what runs")
        XCTAssertEqual(decision.outputSize, CGSize(width: 3200, height: 2400))
    }

    // RT-91.2
    func test_theDecisionReportsWhatWasAskedForAndWhatIsUsed_RT091_2() {
        let decision = UpscaleCeiling.decide(
            sourceSize: source, requested: .preset(scale: 8))

        XCTAssertTrue(decision.wasReduced)
        XCTAssertEqual(decision.requested, .preset(scale: 8), "the request is carried, not lost")
        XCTAssertNotEqual(decision.sizing, decision.requested)
        // The selection the user made is theirs. AC82.8 holds that it changes only when they change
        // it, so a reduction reports itself rather than quietly rewriting the control.
        XCTAssertEqual(decision.requested, .preset(scale: 8))
    }

    // MARK: - The unit

    // RT-91.4
    //
    // The defect, as a test. A long-edge cap treats these two alike; they differ by a factor of
    // eight in memory.
    func test_theCeilingIsAreaSoEqualAreasAreTreatedAlike_RT091_4() {
        let wideShort = UpscaleCeiling.decide(
            sourceSize: CGSize(width: 4000, height: 500), requested: .preset(scale: 2))
        let tallNarrow = UpscaleCeiling.decide(
            sourceSize: CGSize(width: 500, height: 4000), requested: .preset(scale: 2))

        XCTAssertEqual(wideShort.wasReduced, tallNarrow.wasReduced)
        XCTAssertEqual(wideShort.sizing, tallNarrow.sizing)

        // And a picture of the same long edge but far greater area is not treated the same.
        let square = UpscaleCeiling.decide(
            sourceSize: CGSize(width: 4000, height: 4000), requested: .preset(scale: 2))
        XCTAssertNotEqual(
            square.sizing, wideShort.sizing,
            "the same long edge, eight times the area, and a different answer")
    }

    // MARK: - Custom targets

    // RT-91.8
    func test_aCustomTargetAboveTheCeilingIsReducedProportionally_RT091_8() {
        let decision = UpscaleCeiling.decide(
            sourceSize: CGSize(width: 1000, height: 500),
            requested: .custom(width: 10000, height: 5000, stretch: true))

        XCTAssertTrue(decision.wasReduced)
        XCTAssertLessThanOrEqual(
            decision.outputSize.width * decision.outputSize.height,
            CGFloat(UpscaleCeiling.maximumOutputPixels))
        XCTAssertEqual(
            decision.outputSize.width / decision.outputSize.height, 2.0, accuracy: 0.01,
            "the requested proportions survive the reduction")
    }

    // RT-91.9
    //
    // With stretch off the target is fitted to the source's aspect, so the output differs from what
    // was typed. The ceiling binds what is produced, not what was asked for.
    func test_theCeilingBindsTheOutputRatherThanTheRequest_RT091_9() {
        let decision = UpscaleCeiling.decide(
            sourceSize: CGSize(width: 1000, height: 1000),
            requested: .custom(width: 9000, height: 2000, stretch: false))

        // Fitted to a square source, 9000 × 2000 becomes 2000 × 2000: four megapixels, which fits.
        XCTAssertFalse(decision.wasReduced, "the fitted output fits, whatever the typed width said")
        XCTAssertEqual(decision.outputSize, CGSize(width: 2000, height: 2000))
    }

    // MARK: - Nothing fits

    // RT-91.7
    func test_aPictureThatFitsAtNoScaleIsLeftAlone_RT091_7() {
        let decision = UpscaleCeiling.decide(
            sourceSize: CGSize(width: 8000, height: 8000), requested: .preset(scale: 2))

        XCTAssertTrue(decision.wasReduced)
        XCTAssertNil(decision.sizing, "no upscale is performed")
        XCTAssertEqual(decision.outputSize, CGSize(width: 8000, height: 8000), "as it is")
    }

    // MARK: - The wiring

    /// Records what it was asked to produce, and produces nothing.
    private final class RecordingProcessor: GUIUpscaleProcessing, @unchecked Sendable {
        private let lock = NSLock()
        private var received: GUIUpscaleOptions?

        var requestedSizing: GUIUpscaleSizing? {
            lock.lock()
            defer { lock.unlock() }
            return received?.sizing
        }

        func process(
            inputURL: URL,
            options: GUIUpscaleOptions,
            onProgress: @escaping @Sendable (PipelineProgress) -> Void
        ) async throws -> GUIUpscaleProcessedImage {
            lock.lock()
            received = options
            lock.unlock()
            return GUIUpscaleProcessedImage(
                imageData: Data(), preFaceImageData: nil, resolvedModelName: "stub",
                wasAutoDetect: false)
        }
    }

    // RT-91.10
    //
    // Nine tests over a function would all stay green against an upscale path that computed its own
    // dimensions and never called it, and the crash would remain. That is the fault #90 is
    // repairing in the curtain: defensible arithmetic behind a caller feeding it the wrong numbers,
    // unnoticed for five months. So this asserts what the processor was *asked* for.
    func test_theCoordinatorAsksForAnOutputWithinTheCeiling_RT091_10() async throws {
        let processor = RecordingProcessor()
        let coordinator = GUIUpscaleCoordinator(processor: processor)

        let result = try await coordinator.process(
            source: .imported(URL(fileURLWithPath: "/tmp/large.png")),
            options: GUIUpscaleOptions(
                selectedModelName: "realesrgan-x4plus", faceEnhance: false,
                sizing: .preset(scale: 4)),
            sourceSize: source,
            onProgress: { _ in })

        XCTAssertEqual(
            processor.requestedSizing, .preset(scale: 2),
            "the processor is asked for what fits, not for what was requested")
        XCTAssertEqual(result.reduction?.requested, .preset(scale: 4), "and the request is reported")
        XCTAssertEqual(result.reduction?.wasReduced, true)
    }

    // The refusal, at the seam rather than in the arithmetic: a picture that fits at no scale
    // reaches the processor not at all.
    func test_aPictureThatFitsAtNoScaleNeverReachesTheProcessor() async {
        let processor = RecordingProcessor()
        let coordinator = GUIUpscaleCoordinator(processor: processor)

        do {
            _ = try await coordinator.process(
                source: .imported(URL(fileURLWithPath: "/tmp/enormous.png")),
                options: GUIUpscaleOptions(
                    selectedModelName: "realesrgan-x4plus", faceEnhance: false,
                    sizing: .preset(scale: 2)),
                sourceSize: CGSize(width: 8000, height: 8000),
                onProgress: { _ in })
            XCTFail("the upscale should be refused rather than attempted")
        } catch let error as UpscaleCeilingError {
            XCTAssertNotNil(error.errorDescription, "the refusal explains itself in plain language")
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        XCTAssertNil(processor.requestedSizing, "nothing was allocated")
    }

    // MARK: - Degenerate requests are not refusals

    // Raised by the code audit as B1. A custom selection with nothing typed reached the coordinator
    // as `sizing: nil`, which it read as "nothing fits" — so a user who clicked custom and typed
    // nothing was told their picture was too large to upscale for want of memory. False, and
    // exactly the sort of message that produces a bug report about the thing just fixed.
    func test_aCustomTargetWithNothingTypedIsNotAMemoryRefusal() {
        let decision = UpscaleCeiling.decide(
            sourceSize: CGSize(width: 800, height: 600),
            requested: .custom(width: nil, height: nil, stretch: false))

        XCTAssertFalse(decision.wasReduced)
        XCTAssertNotNil(decision.sizing, "not a refusal; the empty fields are validation's business")
    }

    // Raised by the code audit as B2. The ladder is [8, 4, 2]; a request below the smallest rung
    // found no rung and reported a refusal for something that trivially fits.
    func test_aRequestBelowTheSmallestPresetIsNotARefusal() {
        let decision = UpscaleCeiling.decide(
            sourceSize: CGSize(width: 800, height: 600), requested: .preset(scale: 1))

        XCTAssertFalse(decision.wasReduced)
        XCTAssertEqual(decision.sizing, .preset(scale: 1))
        XCTAssertEqual(decision.outputSize, CGSize(width: 800, height: 600))
    }

    // MARK: - The floor is a different question

    // RT-91.6
    //
    // The minimum long edge is what a filter needs to have something to work with; the ceiling is
    // what memory allows. A floor expressed as an edge and a ceiling expressed as an area answer
    // different questions and do not interfere.
    func test_theMinimumLongEdgeIsUnaffectedByTheCeiling_RT091_6() {
        let tiny = CGSize(width: 300, height: 400)
        let decision = UpscaleCeiling.decide(
            sourceSize: tiny, requested: .preset(scale: 4))

        XCTAssertFalse(decision.wasReduced, "1200 × 1600 is under two megapixels")
        XCTAssertEqual(decision.sizing, .preset(scale: 4))
        XCTAssertGreaterThanOrEqual(
            max(decision.outputSize.width, decision.outputSize.height), 1024,
            "raising a small picture to the filterable minimum is never blocked by the ceiling")
    }
}
