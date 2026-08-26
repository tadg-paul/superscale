// ABOUTME: Verifies the info panel's scale sentence comes from the ceiling's decision.
// ABOUTME: The panel did its own arithmetic and named an output four times the limit.

import CoreGraphics
import Foundation
import XCTest
@testable import SuperscaleUXCore

/// What the info panel says about scale.
///
/// The author read *"Scale: 4× → 15360×8640"* off a 3840×2160 photograph with 8x requested. That
/// is 132 megapixels against a 32-megapixel ceiling, and no scale fits that picture at all, so the
/// sentence described an upscale that was never going to run while the status bar reported the
/// truth a few pixels away.
final class SizingLineTests: XCTestCase {

    private func line(
        source: CGSize?,
        selection: ScaleSelection,
        customWidth: String = "",
        customHeight: String = "",
        stretch: Bool = false,
        definesWidth: Bool = true
    ) -> String {
        SizingLine.of(
            sourceSize: source, selection: selection, customWidth: customWidth,
            customHeight: customHeight, stretch: stretch, definesWidth: definesWidth)
    }

    /// RT-108.1: a request the ceiling reduces reports what will run and what was asked for.
    func test_aReducedRequestReportsBothScales_RT108_1() {
        // 2000×2000 at 8x is 256 megapixels; 2x is 16 and fits.
        let source = CGSize(width: 2000, height: 2000)
        let reported = line(source: source, selection: .preset(8))

        let expected = ScaleReadout.of(
            sourceSize: source, selection: .preset(8), customWidth: nil, customHeight: nil,
            stretch: false)
        XCTAssertTrue(expected.wasReduced, "the fixture must be a reduced case to test one")

        XCTAssertTrue(
            reported.contains("8× requested"),
            "the requested scale is no longer visible: \(reported)")
        XCTAssertTrue(
            reported.contains("in effect"),
            "the line does not distinguish what runs from what was asked: \(reported)")
    }

    /// RT-108.2: the author's own case, asserted literally.
    ///
    /// The exact string is the contract here, because the defect *is* a sentence a human read.
    /// Asserting only that the line agrees with `UpscaleCeiling.decide` would pass against an
    /// implementation that consults the engine and then formats its answer wrongly.
    func test_theAuthorsCaseNamesNoImpossibleOutput_RT108_2() {
        let source = CGSize(width: 3840, height: 2160)
        let reported = line(source: source, selection: .preset(8))

        XCTAssertEqual(
            reported,
            "Scale: 8× requested — too large to upscale, so the image is left as it is")
        XCTAssertFalse(
            reported.contains("15360"),
            "the impossible output is still being reported: \(reported)")
        XCTAssertFalse(reported.contains("8640"), "likewise its height: \(reported)")
    }

    /// RT-108.3: a request that fits is reported unchanged, so the fix does not overcorrect.
    func test_aRequestThatFitsIsReportedPlainly_RT108_3() {
        let source = CGSize(width: 1000, height: 1000)
        let reported = line(source: source, selection: .preset(4))

        XCTAssertEqual(reported, "Scale: 4× → 4000×4000")
        XCTAssertFalse(
            reported.contains("requested"),
            "an unreduced request should not be reconciled with anything: \(reported)")
    }

    /// RT-108.4: custom dimensions the ceiling reduces report the effective pair.
    ///
    /// The same relationship AC93.1 requires of the fields themselves: what is in effect, with what
    /// was asked for still distinguishable.
    func test_reducedCustomDimensionsReportTheEffectivePair_RT108_4() {
        let source = CGSize(width: 3840, height: 2160)
        let reported = line(
            source: source, selection: .custom, customWidth: "20000", customHeight: "11250",
            stretch: true)

        XCTAssertTrue(
            reported.contains("20000×11250 requested"),
            "what was typed is no longer distinguishable: \(reported)")
        XCTAssertTrue(
            reported.contains("in effect"),
            "the effective pair is not reported: \(reported)")
        XCTAssertFalse(
            reported.hasPrefix("Custom: 20000×11250 (stretch)"),
            "the typed pair is still being reported as the outcome: \(reported)")
    }

    /// RT-108.5: with the scale cleared, the branch that is correct today stays correct.
    func test_withTheScaleClearedTheLineSaysSo_RT108_5() {
        let reported = line(source: CGSize(width: 1000, height: 1000), selection: .off)

        XCTAssertEqual(reported, "Upscaling off — select a scale to upscale this image")
        XCTAssertFalse(reported.contains("×"), "no dimensions are named with nothing running")
    }

    /// With no picture loaded there is nothing to judge against the ceiling.
    ///
    /// Not one of the criterion's numbered tests: it pins the guard that keeps the four above from
    /// depending on a source size always being present, which is the state the panel starts in.
    func test_withNoPictureTheRequestAloneIsReported() {
        XCTAssertEqual(line(source: nil, selection: .preset(4)), "Scale: 4×")
    }
}
