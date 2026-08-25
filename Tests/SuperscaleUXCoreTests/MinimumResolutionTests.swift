// ABOUTME: Verifies the 1024 long-edge floor: who is raised, who is not, and who cannot reach it.
// ABOUTME: Documented in the guide since it was written, and never enforced until now.

import CoreGraphics
import Foundation
import XCTest
@testable import SuperscaleUXCore

/// The floor beneath which a filter has too little to work with.
///
/// Guide 2.5 states it plainly and slice 7 was unstarted, so an undersized picture was sent as it
/// was and the provider did its own thing with it — which the author saw as grok returning
/// 1024 x 1024 for anything whose short edge fell below that.
final class MinimumResolutionTests: XCTestCase {

    // RT-96.1
    func test_anUndersizedPictureIsRaisedToTheMinimum_RT096_1() {
        let decision = MinimumResolution.decide(sourceSize: CGSize(width: 240, height: 320))

        XCTAssertTrue(decision.wasRaised)
        XCTAssertGreaterThanOrEqual(
            max(decision.resultingSize.width, decision.resultingSize.height),
            MinimumResolution.longEdge)
        XCTAssertFalse(decision.stillBelowMinimum)
    }

    // RT-96.2
    func test_aPictureAlreadyAtOrAboveTheMinimumIsUntouched_RT096_2() {
        for size in [CGSize(width: 1024, height: 768), CGSize(width: 2000, height: 1500)] {
            let decision = MinimumResolution.decide(sourceSize: size)

            XCTAssertFalse(decision.wasRaised, "\(size)")
            XCTAssertEqual(decision.resultingSize, size)
        }
    }

    // The least upscale that clears the floor, not the largest available: raising further spends
    // time on pixels the provider does not want.
    func test_theSmallestSufficientScaleIsChosen() {
        // 600 x 400 at 2x is 1200, which clears 1024.
        let decision = MinimumResolution.decide(sourceSize: CGSize(width: 600, height: 400))

        XCTAssertEqual(decision.scale, 2)
    }

    // RT-96.17
    //
    // The control offers 2x, 4x and 8x, so a 50-pixel picture reaches 400 and no further. The
    // criterion first said such a picture "is raised to it", which is impossible; the AC audit
    // caught it. Raising as far as possible and saying so matches the posture the memory ceiling
    // takes in the other direction.
    func test_aPictureTooSmallToReachTheFloorIsRaisedAsFarAsItGoesAndReported_RT096_17() {
        let decision = MinimumResolution.decide(sourceSize: CGSize(width: 50, height: 50))

        XCTAssertEqual(decision.scale, 8, "as far as the control goes")
        XCTAssertEqual(decision.resultingSize, CGSize(width: 400, height: 400))
        XCTAssertTrue(decision.stillBelowMinimum, "and the user is told the provider may alter it")
    }

    // The floor is the long edge, so orientation does not change the answer.
    func test_theFloorIsTheLongEdgeWhicheverWayThePictureIsTurned() {
        let portrait = MinimumResolution.decide(sourceSize: CGSize(width: 400, height: 900))
        let landscape = MinimumResolution.decide(sourceSize: CGSize(width: 900, height: 400))

        XCTAssertEqual(portrait.scale, landscape.scale)
        XCTAssertEqual(portrait.wasRaised, landscape.wasRaised)
    }

    // A picture exactly at the floor is not raised: the criterion is "at or above".
    func test_aPictureExactlyAtTheFloorIsNotRaised() {
        let decision = MinimumResolution.decide(sourceSize: CGSize(width: 1024, height: 200))

        XCTAssertFalse(decision.wasRaised)
    }

    func test_aDegenerateSizeIsNotClaimedToBeRaisable() {
        let decision = MinimumResolution.decide(sourceSize: .zero)

        XCTAssertFalse(decision.wasRaised)
        XCTAssertTrue(decision.stillBelowMinimum)
    }
}
