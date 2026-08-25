// ABOUTME: Verifies where the curtain divider sits for a given pointer position.
// ABOUTME: The defect it guards was a fraction taken against the window rather than the image.

import CoreGraphics
import Foundation
import XCTest
@testable import SuperscaleUXCore

/// The divider's arithmetic, isolated from the view that feeds it.
///
/// The reported defect was not bad arithmetic. `ComparisonView` divided a location local to a
/// 28-point drag handle by the width of the whole window, side panel included. Both numbers were
/// wrong and neither was visible in the expression. Pulling the mapping out into a function whose
/// only inputs are the pointer and the displayed image frame is what makes the wrongness
/// unwritable: there is no window to reach for.
final class CurtainGeometryTests: XCTestCase {

    // MARK: - One displayed frame for both sides

    // RT-90.34
    //
    // A 4x upscale is four times the width of its base. Drawn at their own sizes the divider falls
    // on different parts of the picture on each side, which reads as a fault in the upscaler.
    func test_twoImagesOfDifferentPixelSizesShareOneDisplayedFrame_RT090_34() {
        let container = CGSize(width: 800, height: 600)
        let base = CGSize(width: 400, height: 300)
        let upscaled = CGSize(width: 1600, height: 1200)

        let baseFrame = CurtainGeometry.displayedFrame(imageSize: base, in: container)
        let upscaledFrame = CurtainGeometry.displayedFrame(imageSize: upscaled, in: container)

        XCTAssertEqual(baseFrame, upscaledFrame)
    }

    // RT-90.35
    func test_aDividerFractionMapsToTheSameRelativePositionInBothImages_RT090_35() {
        let container = CGSize(width: 800, height: 600)
        let frame = CurtainGeometry.displayedFrame(
            imageSize: CGSize(width: 400, height: 300), in: container)

        let quarter = CurtainGeometry.dividerX(fraction: 0.25, in: frame)
        let threeQuarters = CurtainGeometry.dividerX(fraction: 0.75, in: frame)

        XCTAssertEqual(quarter, frame.minX + frame.width * 0.25, accuracy: 0.0001)
        XCTAssertEqual(threeQuarters, frame.minX + frame.width * 0.75, accuracy: 0.0001)
    }

    // MARK: - The pointer decides where the divider goes

    // RT-90.46
    func test_aPointerPositionMapsToTheFractionAtTheSameRelativePosition_RT090_46() {
        let frame = CGRect(x: 100, y: 0, width: 400, height: 300)

        XCTAssertEqual(
            CurtainGeometry.dividerFraction(pointerX: 300, in: frame), 0.5, accuracy: 0.0001,
            "the middle of the image is the middle of the curtain")
        XCTAssertEqual(
            CurtainGeometry.dividerFraction(pointerX: 200, in: frame), 0.25, accuracy: 0.0001)
    }

    // RT-90.47
    //
    // The defect, expressed as a test. The old expression divided by the window's width, so opening
    // the filter panel moved the divider away from the pointer; and it used canvas x rather than
    // image x, so a canvas wider than the picture moved it again.
    func test_theMappingIsUnchangedByWindowWidthPanelWidthAndCanvasAspect_RT090_47() {
        let image = CGSize(width: 400, height: 300)

        // The same canvas, reached through windows of different widths: the panel's width changes
        // where the canvas begins, never where the pointer sits inside it.
        let narrowCanvas = CurtainGeometry.displayedFrame(
            imageSize: image, in: CGSize(width: 400, height: 300))
        let wideCanvas = CurtainGeometry.displayedFrame(
            imageSize: image, in: CGSize(width: 1200, height: 900))

        XCTAssertEqual(
            CurtainGeometry.dividerFraction(
                pointerX: narrowCanvas.midX, in: narrowCanvas), 0.5, accuracy: 0.0001)
        XCTAssertEqual(
            CurtainGeometry.dividerFraction(
                pointerX: wideCanvas.midX, in: wideCanvas), 0.5, accuracy: 0.0001)

        // A canvas wider than the picture's aspect letterboxes it, so canvas x is not image x.
        let letterboxed = CurtainGeometry.displayedFrame(
            imageSize: image, in: CGSize(width: 1600, height: 300))

        XCTAssertGreaterThan(letterboxed.minX, 0, "a wider canvas leaves bars on either side")
        XCTAssertEqual(
            CurtainGeometry.dividerFraction(pointerX: letterboxed.minX, in: letterboxed),
            0.05, accuracy: 0.0001,
            "the picture's left edge is the curtain's start, not the canvas's left edge")
    }

    // RT-90.50
    func test_aPointerBeyondEitherEndLeavesTheDividerAtItsBounds_RT090_50() {
        let frame = CGRect(x: 100, y: 0, width: 400, height: 300)

        XCTAssertEqual(
            CurtainGeometry.dividerFraction(pointerX: -900, in: frame), 0.05, accuracy: 0.0001)
        XCTAssertEqual(
            CurtainGeometry.dividerFraction(pointerX: 9000, in: frame), 0.95, accuracy: 0.0001)
    }

    // RT-90.51
    //
    // What this proves: replacing the picture with one four times larger in pixels does not move
    // the divider, because the mapping never sees pixel dimensions — only the frame the picture is
    // displayed in. What it does not prove is the interactive case, where `ComparisonView` scales
    // and pans the image layers: the divider is drawn outside that transform, and RT-90.48 is what
    // holds it. Recorded rather than implied, because a test that quietly proves less than its name
    // suggests is worse than no test.
    func test_theMappingIsUnchangedWhenTheDisplayedPictureIsItsUpscale_RT090_51() {
        let container = CGSize(width: 800, height: 600)
        let base = CurtainGeometry.displayedFrame(
            imageSize: CGSize(width: 400, height: 300), in: container)
        let upscaled = CurtainGeometry.displayedFrame(
            imageSize: CGSize(width: 1600, height: 1200), in: container)

        for pointerX in stride(from: base.minX, through: base.maxX, by: 40) {
            XCTAssertEqual(
                CurtainGeometry.dividerFraction(pointerX: pointerX, in: base),
                CurtainGeometry.dividerFraction(pointerX: pointerX, in: upscaled),
                accuracy: 0.0001,
                "pointer at \(pointerX)")
        }
    }

    // MARK: - Whose scroll is it

    // RT-94.17
    //
    // The picture was panned from an `NSEvent` monitor that never asked where the pointer was, so
    // scrolling the filter category strip moved the photograph. The decision is a containment test
    // and it holds at any window size, which is the part a single-size check would miss.
    func test_aLocationInsideThePictureBelongsToItAndOneOutsideDoesNot_RT094_17() {
        for container in [CGSize(width: 400, height: 300), CGSize(width: 1600, height: 900)] {
            let frame = CurtainGeometry.displayedFrame(
                imageSize: CGSize(width: 400, height: 300), in: container)

            XCTAssertTrue(
                CurtainGeometry.scrollBelongsToPicture(
                    at: CGPoint(x: frame.midX, y: frame.midY), in: frame),
                "the middle of the picture, at \(container)")
            XCTAssertFalse(
                CurtainGeometry.scrollBelongsToPicture(
                    at: CGPoint(x: frame.maxX + 40, y: frame.midY), in: frame),
                "beyond its right edge, at \(container)")
            XCTAssertFalse(
                CurtainGeometry.scrollBelongsToPicture(
                    at: CGPoint(x: frame.midX, y: frame.minY - 40), in: frame),
                "above it, at \(container)")
        }
    }

    // With no picture there is nothing to pan, so no location belongs to it.
    func test_withNoPictureNoScrollBelongsToIt() {
        XCTAssertFalse(
            CurtainGeometry.scrollBelongsToPicture(at: CGPoint(x: 10, y: 10), in: .zero))
    }

    // MARK: - Degenerate inputs

    // A zero-width container has no curtain to divide. Guarded because a window can be zero-sized
    // during layout and a division by zero would produce a NaN the view would then try to draw.
    func test_aZeroSizedContainerYieldsNoDivisionByZero() {
        let frame = CurtainGeometry.displayedFrame(
            imageSize: CGSize(width: 400, height: 300), in: .zero)

        XCTAssertEqual(frame, .zero)
        XCTAssertFalse(CurtainGeometry.dividerFraction(pointerX: 10, in: frame).isNaN)
    }
}
