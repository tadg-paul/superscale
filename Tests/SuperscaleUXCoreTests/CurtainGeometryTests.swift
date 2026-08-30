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

    // MARK: - Two pictures that are not the same shape

    // RT-96.8, RT-96.9
    //
    // Grok squares anything whose short edge is under 1024, so a 3:4 original comes back 1:1. Fit
    // both into one rectangle and one of them is stretched, which is what the author saw.
    func test_sidesOfDifferingAspectEachKeepTheirOwnRatio_RT096_8() {
        let container = CGSize(width: 800, height: 900)
        let original = CGSize(width: 600, height: 800)      // 3:4
        let returned = CGSize(width: 1024, height: 1024)    // 1:1

        let frames = CurtainGeometry.pairedFrames(
            first: original, second: returned, in: container)

        XCTAssertEqual(
            frames.first.width / frames.first.height, 600.0 / 800.0, accuracy: 0.001,
            "the original is still 3:4")
        XCTAssertEqual(
            frames.second.width / frames.second.height, 1.0, accuracy: 0.001,
            "and the return is still square")
    }

    // RT-96.16
    func test_sidesOfDifferingAspectShareAWidthAndDifferInHeight_RT096_16() {
        let frames = CurtainGeometry.pairedFrames(
            first: CGSize(width: 600, height: 800),
            second: CGSize(width: 1024, height: 1024),
            in: CGSize(width: 800, height: 900))

        XCTAssertEqual(frames.first.width, frames.second.width, accuracy: 0.001)
        XCTAssertNotEqual(frames.first.height, frames.second.height, accuracy: 0.001)
    }

    // RT-96.10
    //
    // Most comparisons have matching shapes and must not be disturbed to accommodate those that do
    // not. Stated as the property rather than as "unchanged from before", which is a claim about
    // history that no test can see.
    func test_twoSidesOfEqualAspectProduceIdenticalFrames_RT096_10() {
        let frames = CurtainGeometry.pairedFrames(
            first: CGSize(width: 400, height: 300),
            second: CGSize(width: 1600, height: 1200),
            in: CGSize(width: 800, height: 600))

        XCTAssertEqual(frames.first, frames.second)
    }

    // RT-96.18
    //
    // The obvious choice of shared width — the container's — clips the more portrait of the two off
    // the bottom, which reads as a new defect rather than an incomplete fix.
    func test_aPortraitSideIsNotClippedInAWideCanvas_RT096_18() {
        let container = CGSize(width: 1600, height: 400)
        let frames = CurtainGeometry.pairedFrames(
            first: CGSize(width: 300, height: 900),
            second: CGSize(width: 900, height: 900),
            in: container)

        XCTAssertLessThanOrEqual(frames.first.height, container.height + 0.001)
        XCTAssertLessThanOrEqual(frames.second.height, container.height + 0.001)
        XCTAssertGreaterThan(frames.first.height, 0)
    }

    // RT-96.11, RT-96.12
    //
    // One vertical divider, two pictures. Sharing a width is what lets it mean the same thing on
    // both: at 50% it is at the horizontal midpoint of each.
    func test_aDividerAtHalfIsAtTheMidpointOfEachSide_RT096_11() {
        let frames = CurtainGeometry.pairedFrames(
            first: CGSize(width: 600, height: 800),
            second: CGSize(width: 1024, height: 1024),
            in: CGSize(width: 800, height: 900))

        XCTAssertEqual(
            CurtainGeometry.dividerX(fraction: 0.5, in: frames.first),
            CurtainGeometry.dividerX(fraction: 0.5, in: frames.second),
            accuracy: 0.001,
            "one line, one position, whatever the shapes")
    }

    // RT-96.9
    //
    // The reported case, with its own test rather than folded into RT-96.8. A 3:4 photograph goes to
    // grok, a 1024x1024 square comes back, and what the author saw was their own picture stretched
    // to square beside it.
    func test_aSquareReturnBesideAPortraitOriginalLeavesTheOriginalAtItsOwnRatio_RT096_9() {
        let original = CGSize(width: 768, height: 1024)
        let returned = CGSize(width: 1024, height: 1024)

        let frames = CurtainGeometry.pairedFrames(
            first: original, second: returned, in: CGSize(width: 900, height: 1200))

        XCTAssertEqual(
            frames.first.width / frames.first.height,
            original.width / original.height,
            accuracy: 0.001,
            "the original keeps 3:4")
        XCTAssertEqual(
            frames.second.width / frames.second.height,
            1.0,
            accuracy: 0.001,
            "the return keeps 1:1")
        XCTAssertNotEqual(
            frames.first.height, frames.second.height, accuracy: 0.001,
            "different shapes occupy different heights; that is the honest presentation")
    }

    // RT-96.12
    //
    // RT-96.11 checks one fraction at one pair of shapes. The mapping has to hold across the range
    // and across aspects, or a divider that is right at the midpoint drifts everywhere else.
    func test_theDividerMapsToTheSameFractionOfWidthAcrossAspectsAndPositions_RT096_12() {
        let pairs: [(CGSize, CGSize)] = [
            (CGSize(width: 768, height: 1024), CGSize(width: 1024, height: 1024)),
            (CGSize(width: 1920, height: 1080), CGSize(width: 1024, height: 1024)),
            (CGSize(width: 500, height: 500), CGSize(width: 100, height: 400)),
        ]

        for (first, second) in pairs {
            let frames = CurtainGeometry.pairedFrames(
                first: first, second: second, in: CGSize(width: 1000, height: 800))

            for fraction in [0.05, 0.25, 0.5, 0.75, 0.95] as [CGFloat] {
                XCTAssertEqual(
                    CurtainGeometry.dividerX(fraction: fraction, in: frames.first),
                    CurtainGeometry.dividerX(fraction: fraction, in: frames.second),
                    accuracy: 0.001,
                    "\(fraction) across \(first) and \(second)")
            }
        }
    }

    // RT-96.13
    //
    // AC90.14 is unaffected by any of this: the divider sits where the pointer is. UT-90.1 failed on
    // exactly that — "the mouse pointer does not align with the curtain" — so the round trip is
    // asserted rather than assumed, at the paired frames this issue introduces.
    func test_theDividerStillSitsWhereThePointerIs_RT096_13() {
        let frames = CurtainGeometry.pairedFrames(
            first: CGSize(width: 768, height: 1024),
            second: CGSize(width: 1024, height: 1024),
            in: CGSize(width: 900, height: 1200))
        let frame = frames.first

        // Within the clamped band, a pointer position must survive the round trip to a fraction and
        // back. Outside it, the clamp is the point and the divider stops.
        for pointerX in [frame.minX + frame.width * 0.1,
                         frame.midX,
                         frame.minX + frame.width * 0.9] {
            let fraction = CurtainGeometry.dividerFraction(pointerX: pointerX, in: frame)

            XCTAssertEqual(
                CurtainGeometry.dividerX(fraction: fraction, in: frame),
                pointerX,
                accuracy: 0.001,
                "the divider is where the pointer is")
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

    // MARK: - #136: the divider is reachable, and scroll moves it

    // RT-136.1
    //
    // AC136.1's geometry half. The drag gesture used to sit on the drawn circle itself, so the
    // reachable target and the paint were one 28-point thing over a photograph that also accepts a
    // drag --- the author's *"I always end up grabbing the image and moving it instead."*
    //
    // A **usable** margin rather than any margin, which is why the threshold is 44 rather than
    // "greater than 28": one point larger would satisfy a looser assertion and change nothing for
    // the user. 44 is the target size the platform's own guidance asks for.
    func test_theHandleIsReachableBeyondWhatIsDrawn_RT136_1() {
        XCTAssertGreaterThan(
            CurtainGeometry.handleHitDiameter, CurtainGeometry.handleDiameter,
            "the reachable handle is no larger than the drawn one, which is the defect")
        XCTAssertGreaterThanOrEqual(
            CurtainGeometry.handleHitDiameter, 44,
            "a margin too small to help is not a fix")
        XCTAssertEqual(
            CurtainGeometry.handleDiameter, 28,
            "the paint is unchanged: #66 established that this handle's drawn size is load-bearing")
    }

    // RT-136.4
    //
    // AC136.3. Scrolling and dragging must not come to disagree about where the divider belongs, so
    // the scroll mapping is asserted against the pointer mapping rather than against a number of
    // its own.
    func test_aScrollLandsWhereTheSamePointerWould_RT136_4() {
        let frame = CGRect(x: 100, y: 0, width: 400, height: 300)
        let start: CGFloat = 0.5
        let startX = CurtainGeometry.dividerX(fraction: start, in: frame)

        let scrolled = CurtainGeometry.dividerFraction(
            scrolledFrom: start, byX: 40, y: 0, in: frame)

        XCTAssertEqual(
            scrolled,
            CurtainGeometry.dividerFraction(pointerX: startX + 40, in: frame),
            accuracy: 0.0001,
            "a scroll of 40 points puts the divider somewhere a drag to that point would not")
    }

    // RT-136.8
    //
    // AC136.4. A scroll accumulates with no natural end --- a trackpad flick keeps delivering events
    // after the fingers have left --- so this is the criterion most likely to break in use. The
    // clamp is reached through `dividerFraction`, so it is the same clamp a drag observes.
    func test_theDividerStaysWithinItsBoundsHoweverFarAScrollContinues_RT136_8() {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 300)

        var fraction: CGFloat = 0.5
        for _ in 0..<200 {
            fraction = CurtainGeometry.dividerFraction(
                scrolledFrom: fraction, byX: 50, y: 0, in: frame)
        }
        XCTAssertEqual(fraction, CurtainGeometry.maximumFraction, accuracy: 0.0001,
                       "scrolling right ran the divider past its bound")

        for _ in 0..<400 {
            fraction = CurtainGeometry.dividerFraction(
                scrolledFrom: fraction, byX: -50, y: 0, in: frame)
        }
        XCTAssertEqual(fraction, CurtainGeometry.minimumFraction, accuracy: 0.0001,
                       "and scrolling left ran it past the other")
    }

    // RT-136.9
    //
    // AC136.7. Direction is a coin flip an implementation can lose silently, and macOS has already
    // applied the user's natural-scrolling preference to the delta before it arrives --- so
    // following the reported sign *is* following the preference, and negating it would fight the
    // setting for half of all users.
    func test_theDividerFollowsTheReportedSign_RT136_9() {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 300)

        XCTAssertGreaterThan(
            CurtainGeometry.dividerFraction(scrolledFrom: 0.5, byX: 30, y: 0, in: frame), 0.5,
            "a positive delta moved the divider the wrong way")
        XCTAssertLessThan(
            CurtainGeometry.dividerFraction(scrolledFrom: 0.5, byX: -30, y: 0, in: frame), 0.5,
            "and a negative delta moved it the wrong way too")
    }

    // RT-136.10
    //
    // AC136.2's dominant-axis clause, and the case that motivated it. A trackpad reports
    // `scrollingDeltaX` on a sideways swipe; **an ordinary wheel mouse reports only
    // `scrollingDeltaY`**. Written against X alone, the feature would look right on a laptop and do
    // nothing on a desk.
    func test_aVerticalOnlyScrollMovesTheDivider_RT136_10() {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 300)

        XCTAssertGreaterThan(
            CurtainGeometry.dividerFraction(scrolledFrom: 0.5, byX: 0, y: 30, in: frame), 0.5,
            "a wheel mouse, which has no horizontal axis, cannot move the divider at all")

        // And the dominant axis wins where both are present, so a slightly-off sideways swipe on a
        // trackpad does not fight itself.
        XCTAssertEqual(
            CurtainGeometry.dividerFraction(scrolledFrom: 0.5, byX: 40, y: 5, in: frame),
            CurtainGeometry.dividerFraction(scrolledFrom: 0.5, byX: 40, y: 0, in: frame),
            accuracy: 0.0001,
            "a small perpendicular component changed the result")
    }

    // A zero-width frame has no curtain to move, and a scroll arriving during layout must not
    // produce a NaN the view then tries to draw. The same guard `dividerFraction` carries.
    func test_aScrollAgainstAZeroWidthFrameChangesNothing() {
        XCTAssertEqual(
            CurtainGeometry.dividerFraction(scrolledFrom: 0.42, byX: 100, y: 0, in: .zero), 0.42,
            accuracy: 0.0001)
    }
}
