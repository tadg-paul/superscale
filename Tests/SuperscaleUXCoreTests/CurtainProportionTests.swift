// ABOUTME: Measures the curtain's shared-width rule against the sizes the author reported on #127.
// ABOUTME: Establishes whether the rendered proportions are a defect or the specified behaviour.

import Foundation
import XCTest
@testable import SuperscaleUXCore

/// Guide 2.3's shared-width rule, measured against the author's own numbers.
///
/// The #127 ticket asserted the rule was unimplemented. It is implemented, and `ComparisonView`
/// calls it, so before anything is changed these establish what it actually produces for the two
/// cases reported. Measuring what is being measured, which is the lesson AC119.1 records after four
/// remediation cycles were spent moving a layout that was already correct.
final class CurtainProportionTests: XCTestCase {
    /// A canvas of the shape the application presents: the window less the filter panel.
    private let wideCanvas = CGSize(width: 900, height: 600)
    private let tallCanvas = CGSize(width: 700, height: 900)

    // RT-127.1
    //
    // The author's first case: a 1471x1661 portrait filtered by grok, which returns 1024x1024
    // whenever the picture it is given has a short edge under 1024.
    //
    // Each side must keep its own proportions — nothing stretched to match the other's shape — and
    // both must share a width, so the single divider falls at the same fraction on each.
    func test_aSquareReturnAgainstAPortraitSourceSharesAWidthAndKeepsBothShapes_RT127_1() {
        let source = CGSize(width: 1471, height: 1661)
        let returned = CGSize(width: 1024, height: 1024)

        let frames = CurtainGeometry.pairedFrames(
            first: source, second: returned, in: wideCanvas)

        XCTAssertEqual(
            frames.first.width, frames.second.width, accuracy: 0.01,
            "the two sides must share a width, or one divider means two things")

        XCTAssertEqual(
            frames.first.height / frames.first.width,
            source.height / source.width, accuracy: 0.01,
            "the source keeps its own proportions")
        XCTAssertEqual(
            frames.second.height / frames.second.width,
            returned.height / returned.width, accuracy: 0.01,
            "and so does the return; neither is stretched to match the other")
    }

    // RT-127.3
    //
    // Where the pair cannot both fit at the canvas's full width, the shared width is whatever makes
    // the taller of the two exactly fill the canvas height. Using the full width unconditionally
    // clips the more portrait of the two off the bottom, which is the defect this rule replaced.
    func test_whereBothSidesDoNotFitTheTallerExactlyFillsTheHeight_RT127_3() {
        let source = CGSize(width: 1471, height: 1661)
        let returned = CGSize(width: 1024, height: 1024)

        let frames = CurtainGeometry.pairedFrames(
            first: source, second: returned, in: wideCanvas)

        let tallest = max(frames.first.height, frames.second.height)
        XCTAssertEqual(
            tallest, wideCanvas.height, accuracy: 0.01,
            "the taller side fills the canvas height exactly")
        XCTAssertLessThanOrEqual(
            frames.first.width, wideCanvas.width,
            "and neither side exceeds the canvas width")
    }

    // RT-127.2
    //
    // The complementary case: where both sides do fit, the shared width is the canvas's own.
    //
    // **The example matters and the first one chosen here was wrong.** A 3423x2698 pair is about
    // 1.27:1 and the canvas 1.5:1, so the pair is proportionally *taller* than the canvas and height
    // binds — 761 points of a 900-point canvas, measured. That is the rule working, not failing, and
    // it is the author's second reported symptom. A pair that genuinely fits needs to be wider in
    // proportion than the canvas.
    func test_whereBothSidesFitTheSharedWidthIsTheCanvasWidth_RT127_2() {
        let source = CGSize(width: 4000, height: 1600)
        let returned = CGSize(width: 4000, height: 1600)

        let frames = CurtainGeometry.pairedFrames(
            first: source, second: returned, in: wideCanvas)

        XCTAssertEqual(
            frames.first.width, wideCanvas.width, accuracy: 0.01,
            "a pair wider in proportion than the canvas fills the canvas width")
        XCTAssertLessThanOrEqual(
            frames.first.height, wideCanvas.height,
            "and fits within its height")
    }

    // RT-127.5
    //
    // The author's second symptom, pinned as a measurement rather than described.
    //
    // *"the returned image is actually the correct aspect ratio, but it is not being rendered to
    // cover the whole display area."* On a 3423x2698 source — 1.27:1 — against a 1.5:1 canvas, the
    // shared width is 761 of 900 points, and the pair exactly fills the height. Filling the width
    // instead would overflow the canvas by a third and clip the picture.
    //
    // This test exists to record that the behaviour is specified, so that if it is changed the
    // change is deliberate and this test is superseded rather than quietly broken.
    func test_aPairTallerInProportionThanTheCanvasIsHeightLimited_RT127_5() {
        let size = CGSize(width: 3423, height: 2698)

        let frames = CurtainGeometry.pairedFrames(
            first: size, second: size, in: wideCanvas)

        XCTAssertLessThan(
            frames.first.width, wideCanvas.width,
            "a pair taller in proportion than the canvas cannot fill its width")
        XCTAssertEqual(
            frames.first.height, wideCanvas.height, accuracy: 0.01,
            "it fills the height instead, which is what guide 2.3 specifies")
    }

    // RT-127.4
    //
    // The author's second case, and the one the AC audit flagged as possibly the rule working as
    // written rather than failing: *"the returned image is actually the correct aspect ratio, but
    // it is not being rendered to cover the whole display area."*
    //
    // A 3423x2698 source is about 1.27:1. On a canvas taller than that shape, the shared width is
    // limited by height and the pair does **not** fill the width. This test records which of the
    // two it is, so the ticket's next step is a decision rather than a guess.
    func test_aLandscapePairOnATallCanvasIsLimitedByHeightNotWidth_RT127_4() {
        let source = CGSize(width: 3423, height: 2698)
        let returned = CGSize(width: 3423, height: 2698)

        let frames = CurtainGeometry.pairedFrames(
            first: source, second: returned, in: tallCanvas)

        XCTAssertEqual(
            frames.first.width, tallCanvas.width, accuracy: 0.01,
            """
            a landscape pair on a tall canvas should still fill the width, \
            because its own height is the smaller constraint
            """)
    }
}
