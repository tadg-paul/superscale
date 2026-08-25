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

    // RT-94.14
    //
    // At the handover, the **name** changes with the work. RT-94.3 asserts that progress does not
    // lapse across the handover; this asserts that it does not merely persist under the old name,
    // which is the failure that looks identical from the outside and tells the user a provider call
    // is still running while their Neural Engine grinds through tiles.
    func test_atTheHandoverTheNameChangesWithTheWork_RT094_14() {
        let applying = CanvasWork.of(
            isUpscaling: false, isApplyingFilter: true, upscaleMessage: "")
        let handedOver = CanvasWork.of(
            isUpscaling: true, isApplyingFilter: false, upscaleMessage: "Processing tile 2 of 4")

        XCTAssertTrue(applying.isBusy)
        XCTAssertTrue(handedOver.isBusy, "progress does not lapse")
        XCTAssertNotEqual(
            applying.message, handedOver.message,
            "and the name is not the one the previous stage left behind")
        XCTAssertEqual(applying.message, CanvasWork.filterMessage)
        XCTAssertTrue(handedOver.message.lowercased().contains("tile"), handedOver.message)
    }

    /// Raising a picture to the filterable minimum is work, and it reports.
    ///
    /// It runs the same Neural Engine work as any other upscale and takes the same seconds. AC94.1
    /// covers **work of any kind** on the working image, so a new path that runs silently is the
    /// defect #94 fixed for the filter arriving somewhere else: pressing Apply on a small picture
    /// and watching nothing happen.
    func test_raisingToTheMinimumIsReportedAsWork() {
        let raising = CanvasWork.of(
            isUpscaling: true, isApplyingFilter: false,
            upscaleMessage: "Preparing for filtering…")

        XCTAssertTrue(raising.isBusy)
        XCTAssertEqual(raising.message, "Preparing for filtering…")
        XCTAssertNotEqual(
            raising.message, CanvasWork.filterMessage,
            "the provider has not been contacted yet; this is local work")
    }

    /// An upscale with nothing to say still says something.
    ///
    /// The kit reports per tile, and there is a gap between "started" and the first report. An empty
    /// message during it would read as no work at all — the defect, arriving in a smaller window.
    func test_anUpscaleWithNoReportYetStillNamesItself() {
        let starting = CanvasWork.of(
            isUpscaling: true, isApplyingFilter: false, upscaleMessage: "")

        XCTAssertTrue(starting.isBusy)
        XCTAssertFalse(starting.message.isEmpty)
    }
}
