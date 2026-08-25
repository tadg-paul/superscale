// ABOUTME: Verifies that the canvas reports every kind of work, and names the one under way.
// ABOUTME: A provider call is work too; the canvas previously watched only the local upscale.

import CoreGraphics
import Foundation
import XCTest
@testable import SuperscaleUXCore

/// What the canvas says is happening.
///
/// The defect: pressing Apply started a paid provider call that ran for tens of seconds while the
/// canvas showed nothing. The application knew — the status dot and the filter panel both consulted
/// the coordinator — and the one surface the user was looking at did not ask.
final class CanvasWorkTests: XCTestCase {

    // MARK: - Every kind of work shows

    // RT-94.1
    func test_whileAFilterIsBeingAppliedTheCanvasShowsProgress_RT094_1() {
        let work = CanvasWork.of(isUpscaling: false, isApplyingFilter: true, upscaleMessage: "")

        XCTAssertTrue(work.isBusy)
    }

    // RT-94.2
    func test_whileAnUpscaleRunsTheCanvasShowsProgress_RT094_2() {
        let work = CanvasWork.of(
            isUpscaling: true, isApplyingFilter: false, upscaleMessage: "Processing tile 2 of 4")

        XCTAssertTrue(work.isBusy)
    }

    // RT-94.3, RT-94.14
    //
    // A filter completing and its upscale starting are two operations. The canvas going quiet
    // between them reads as "finished" when it is not, and the name must follow the work rather
    // than latch to whichever started first.
    func test_progressIsContinuousAcrossTheHandoverAndTheNameFollows_RT094_3() {
        let applying = CanvasWork.of(
            isUpscaling: false, isApplyingFilter: true, upscaleMessage: "")
        let both = CanvasWork.of(
            isUpscaling: true, isApplyingFilter: true, upscaleMessage: "Loading...")
        let upscaling = CanvasWork.of(
            isUpscaling: true, isApplyingFilter: false, upscaleMessage: "Processing tile 1 of 4")

        XCTAssertTrue(applying.isBusy)
        XCTAssertTrue(both.isBusy)
        XCTAssertTrue(upscaling.isBusy, "no gap at any point in the sequence")

        XCTAssertNotEqual(
            applying.message, upscaling.message,
            "the name follows the work rather than latching to the first")
    }

    // RT-94.4
    func test_withNothingRunningNoProgressIsShown_RT094_4() {
        let work = CanvasWork.of(isUpscaling: false, isApplyingFilter: false, upscaleMessage: "")

        XCTAssertFalse(work.isBusy)
    }

    // RT-94.15
    //
    // Applying is cancellable, and it is the operation a user is most likely to abandon because it
    // costs money. An indicator that never stops would be the opposite defect.
    func test_aCancelledFilterStopsTheProgress_RT094_15() {
        let during = CanvasWork.of(isUpscaling: false, isApplyingFilter: true, upscaleMessage: "")
        let afterCancel = CanvasWork.of(
            isUpscaling: false, isApplyingFilter: false, upscaleMessage: "")

        XCTAssertTrue(during.isBusy)
        XCTAssertFalse(afterCancel.isBusy)
    }

    // MARK: - Naming the work

    // RT-94.5
    func test_anApplyingFilterAndARunningUpscaleAreDistinguishable_RT094_5() {
        let applying = CanvasWork.of(
            isUpscaling: false, isApplyingFilter: true, upscaleMessage: "")
        let upscaling = CanvasWork.of(
            isUpscaling: true, isApplyingFilter: false, upscaleMessage: "Processing tile 2 of 4")

        XCTAssertNotEqual(applying.message, upscaling.message)
        XCTAssertFalse(applying.message.isEmpty, "silence is what the defect looked like")
    }

    // RT-94.6
    //
    // `UpscaleProgressReader` maps kit phases to text, and a cloud call has no tiles. Borrowing the
    // upscale's vocabulary would report tile counts for something that does not tile.
    func test_aProviderCallDoesNotBorrowTheUpscalesVocabulary_RT094_6() {
        let applying = CanvasWork.of(
            isUpscaling: false, isApplyingFilter: true, upscaleMessage: "Processing tile 2 of 4")

        XCTAssertFalse(
            applying.message.lowercased().contains("tile"),
            "a provider call has no tiles, whatever the upscale's last message said")
    }

    // While both are somehow in flight, the provider call is the one named: it is the slower, the
    // one that costs money, and the one the user is waiting on.
    func test_withBothInFlightTheProviderCallIsNamed() {
        let both = CanvasWork.of(
            isUpscaling: true, isApplyingFilter: true, upscaleMessage: "Processing tile 2 of 4")

        XCTAssertFalse(both.message.lowercased().contains("tile"))
    }
}
