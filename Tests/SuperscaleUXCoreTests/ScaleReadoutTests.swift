// ABOUTME: Verifies what the scale control shows: the scale in effect, not the one requested.
// ABOUTME: Every state here is two integers, so none of it costs a Core ML upscale to reach.

import CoreGraphics
import Foundation
import XCTest
@testable import SuperscaleUXCore

/// What the toolbar reports.
///
/// The defect: a large picture was reduced to fit memory, the status bar said so, and the 4x button
/// stayed lit. A control saying 4x while 1x runs is not a preserved choice, it is a false statement
/// about the current state — and it is the more prominent of the two things the user is looking at.
///
/// The states below only arise when the ceiling bites, which needs a source of eight megapixels and,
/// for the refusal case, over thirty-two. Through the window each would be a real upscale larger
/// than the one already rejected as too slow for this suite. As a function they are two integers.
final class ScaleReadoutTests: XCTestCase {

    /// Comfortably under the ceiling at any scale: 2 megapixels at 8x.
    private let small = CGSize(width: 500, height: 500)
    /// 4 megapixels, so 4x overruns the ceiling and 2x does not.
    private let large = CGSize(width: 2000, height: 2000)
    /// Over the ceiling before anything is done to it.
    private let enormous = CGSize(width: 6000, height: 6000)

    // MARK: - The effective scale is what reads as active

    // RT-93.1
    func test_withAReductionInForceTheEffectiveScaleIsActive_RT093_1() {
        let readout = ScaleReadout.of(
            sourceSize: large, selection: .preset(4), customWidth: nil, customHeight: nil,
            stretch: false)

        XCTAssertEqual(readout.effective, .preset(2), "what will actually run")
        XCTAssertEqual(readout.state(of: .preset(2)), .inEffect)
    }

    // RT-93.2
    func test_theRequestedScaleStaysVisibleMarkedAndChoosable_RT093_2() {
        let readout = ScaleReadout.of(
            sourceSize: large, selection: .preset(4), customWidth: nil, customHeight: nil,
            stretch: false)

        XCTAssertEqual(
            readout.state(of: .preset(4)), .requestedNotInEffect,
            "the user can still see what they asked for")
        XCTAssertTrue(
            readout.isChoosable(.preset(4)),
            "dimmed must not mean disabled, or the user is trapped at the reduced scale")
        XCTAssertTrue(readout.isChoosable(.preset(8)), "and other scales remain choosable too")
    }

    // RT-93.3
    func test_withNoReductionExactlyOneScaleIsShown_RT093_3() {
        let readout = ScaleReadout.of(
            sourceSize: small, selection: .preset(4), customWidth: nil, customHeight: nil,
            stretch: false)

        XCTAssertEqual(readout.state(of: .preset(4)), .inEffect)
        XCTAssertEqual(readout.state(of: .preset(2)), .inactive)
        XCTAssertEqual(readout.state(of: .preset(8)), .inactive)
        XCTAssertFalse(
            readout.wasReduced,
            "showing two states on every ordinary upscale would be noise")
    }

    // RT-93.11
    func test_whereNothingFitsNoScaleReadsAsActive_RT093_11() {
        let readout = ScaleReadout.of(
            sourceSize: enormous, selection: .preset(2), customWidth: nil, customHeight: nil,
            stretch: false)

        XCTAssertNil(readout.effective, "no upscale runs at all")
        for scale in [2, 4, 8] {
            XCTAssertNotEqual(
                readout.state(of: .preset(scale)), .inEffect, "scale \(scale)")
        }
        XCTAssertEqual(readout.state(of: .preset(2)), .requestedNotInEffect)
    }

    // MARK: - The custom fields obey the same rule

    // RT-93.9
    func test_aReducedCustomTargetShowsTheEffectiveDimensions_RT093_9() {
        let readout = ScaleReadout.of(
            sourceSize: CGSize(width: 1000, height: 500), selection: .custom,
            customWidth: 10000, customHeight: 5000, stretch: true)

        XCTAssertTrue(readout.wasReduced)
        let shown = try? XCTUnwrap(readout.displayedDimensions)
        XCTAssertNotNil(shown)
        XCTAssertLessThan(
            (shown?.width ?? 0) * (shown?.height ?? 0),
            CGFloat(UpscaleCeiling.maximumOutputPixels) + 1)
        XCTAssertEqual(readout.requestedDimensions?.width, 10000, "and what was typed is still known")
    }

    // MARK: - Known without running anything

    // RT-93.10
    //
    // `UpscaleDecision` is returned by `GUIUpscaleCoordinator.process`, so an implementation reading
    // the reduction from a completed run would show 4x, run, then correct itself to 2x — the
    // reported defect in miniature, and wrong for exactly as long as the user was looking at it.
    // Nothing here has run.
    func test_theReadoutDerivesTheEffectiveScaleWithNoCompletedRun_RT093_10() {
        let readout = ScaleReadout.of(
            sourceSize: large, selection: .preset(4), customWidth: nil, customHeight: nil,
            stretch: false)

        XCTAssertEqual(readout.effective, .preset(2))
        XCTAssertTrue(readout.wasReduced)
    }

    // MARK: - The transition

    // RT-93.14
    //
    // The defect is experienced as a sequence, not a state: drop a large picture and watch the
    // button stay at 4x while the status bar disagrees. There is no intermediate reading.
    func test_replacingAFittingPictureWithALargerOneMovesTheEffectiveScaleDirectly_RT093_14() {
        let before = ScaleReadout.of(
            sourceSize: small, selection: .preset(4), customWidth: nil, customHeight: nil,
            stretch: false)
        let after = ScaleReadout.of(
            sourceSize: large, selection: .preset(4), customWidth: nil, customHeight: nil,
            stretch: false)

        XCTAssertEqual(before.state(of: .preset(4)), .inEffect)
        XCTAssertEqual(
            after.state(of: .preset(4)), .requestedNotInEffect,
            "the same selection, a different picture, and the readout follows the picture")
        XCTAssertEqual(after.effective, .preset(2))
    }

    // MARK: - The selection is the user's

    // RT-93.5
    func test_theStoredSelectionIsUnchangedByAReduction_RT093_5() {
        let selection = ScaleSelection.preset(4)
        let readout = ScaleReadout.of(
            sourceSize: large, selection: selection, customWidth: nil, customHeight: nil,
            stretch: false)

        XCTAssertEqual(readout.requested, selection, "the readout reports; it does not rewrite")
    }

    // RT-93.4
    func test_afterAReductionAPictureThatFitsRunsAtTheRequestedScale_RT093_4() {
        let selection = ScaleSelection.preset(4)
        _ = ScaleReadout.of(
            sourceSize: large, selection: selection, customWidth: nil, customHeight: nil,
            stretch: false)

        // The same selection, carried forward to a smaller picture, without the user touching it.
        let afterSmaller = ScaleReadout.of(
            sourceSize: small, selection: selection, customWidth: nil, customHeight: nil,
            stretch: false)

        XCTAssertEqual(afterSmaller.effective, .preset(4))
        XCTAssertFalse(afterSmaller.wasReduced)
    }

    // MARK: - No picture yet

    // Before anything is imported there is no source size, so nothing can be judged against the
    // ceiling. The selection alone decides, which is what the toolbar showed before this issue.
    func test_withNoPictureTheSelectionAloneDecides() {
        let readout = ScaleReadout.of(
            sourceSize: nil, selection: .preset(4), customWidth: nil, customHeight: nil,
            stretch: false)

        XCTAssertEqual(readout.state(of: .preset(4)), .inEffect)
        XCTAssertFalse(readout.wasReduced)
    }
}
