// ABOUTME: Verifies what the canvas draws in every state: base, derivation, progress, curtain.
// ABOUTME: The decision is a function, so the states that would need real upscales cost nothing.

import Foundation
import XCTest
@testable import SuperscaleUXCore

final class CanvasContentTests: XCTestCase {
    private let base = RenderedImage(id: "base")
    private let upscaled = RenderedImage(id: "upscaled")
    private let filtered = RenderedImage(id: "filtered")

    // MARK: - There is always something to look at

    // RT-90.1
    func test_anImportedImageIsShownBeforeAnyOperationCompletes_RT090_1() {
        let content = CanvasContent.decide(base: base, derivation: nil, isWorking: true, showsBase: false)

        XCTAssertEqual(content.image, base)
    }

    // RT-90.2
    func test_theCanvasIsNeverEmptyWhileAnImageIsLoaded_RT090_2() {
        let states: [(RenderedImage?, Bool, Bool)] = [
            (nil, false, false),
            (nil, true, false),
            (upscaled, false, false),
            (upscaled, true, false),
            (upscaled, true, true),
            (filtered, false, true),
        ]

        for (derivation, isWorking, showsBase) in states {
            let content = CanvasContent.decide(
                base: base,
                derivation: derivation,
                isWorking: isWorking,
                showsBase: showsBase
            )
            XCTAssertNotNil(
                content.image,
                "derivation: \(String(describing: derivation)), working: \(isWorking), base: \(showsBase)"
            )
        }
    }

    // RT-90.25
    //
    // The reported defect: an image was dropped and only a ticker appeared. Present *together* is
    // the contract — the image alone means no feedback, the progress alone is the defect.
    func test_progressAndTheImageArePresentTogether_RT090_25() {
        let content = CanvasContent.decide(base: base, derivation: nil, isWorking: true, showsBase: false)

        XCTAssertEqual(content.image, base)
        XCTAssertTrue(content.showsProgress)
    }

    // MARK: - Work in flight leaves the display alone

    // RT-90.3
    //
    // A transition rather than a state, and deliberately so: this previously repeated RT-90.1's
    // exact call and assertion, leaving AC90.2's real claim — that work *starting* changes nothing
    // — tested only where no derivation was present. Falling back to the base mid-operation is the
    // plausible wrong implementation, and only this catches it.
    func test_workStartingDoesNotChangeTheImageWhenADerivationIsPresent_RT090_3() {
        let before = CanvasContent.decide(
            base: base, derivation: upscaled, isWorking: false, showsBase: false)
        let during = CanvasContent.decide(
            base: base, derivation: upscaled, isWorking: true, showsBase: false)

        XCTAssertEqual(before.image, during.image)
        XCTAssertEqual(during.image, upscaled, "not a fall back to the base")
        XCTAssertFalse(before.showsProgress)
        XCTAssertTrue(during.showsProgress)
    }

    // RT-90.4
    func test_progressIsDrawnOverTheImageRatherThanInPlaceOfIt_RT090_4() {
        let working = CanvasContent.decide(base: base, derivation: nil, isWorking: true, showsBase: false)
        let idle = CanvasContent.decide(base: base, derivation: nil, isWorking: false, showsBase: false)

        XCTAssertEqual(working.image, idle.image, "the image does not change because work started")
        XCTAssertTrue(working.showsProgress)
        XCTAssertFalse(idle.showsProgress)
    }

    // RT-90.5
    //
    // Falling back to the base mid-operation would be a regression dressed as a fix.
    func test_duringASecondUpscaleThePreviousRenderingRemains_RT090_5() {
        let content = CanvasContent.decide(base: base, derivation: upscaled, isWorking: true, showsBase: false)

        XCTAssertEqual(content.image, upscaled)
        XCTAssertTrue(content.showsProgress)
    }

    // MARK: - Turning something off falls back at once

    // RT-90.6, RT-90.7
    func test_turningTheOperationOffShowsTheBaseWithoutWaiting_RT090_6() {
        let content = CanvasContent.decide(base: base, derivation: nil, isWorking: false, showsBase: false)

        XCTAssertEqual(content.image, base)
        XCTAssertFalse(content.showsProgress, "there is nothing to build, so nothing to wait for")
    }

    // RT-90.8
    func test_turningTheOperationOffLeavesNoStaleRendering_RT090_8() {
        let content = CanvasContent.decide(base: base, derivation: nil, isWorking: false, showsBase: false)

        XCTAssertNotEqual(content.image, upscaled)
        XCTAssertNotEqual(content.image, filtered)
    }

    // MARK: - The curtain

    // RT-90.15, RT-90.16
    func test_theCurtainComparesTheDisplayedImageAgainstWhatItDerivesFrom_RT090_15() {
        let overUpscale = CanvasContent.decide(base: base, derivation: upscaled, isWorking: false, showsBase: false)
        let overFilter = CanvasContent.decide(base: base, derivation: filtered, isWorking: false, showsBase: false)

        XCTAssertEqual(overUpscale.comparison, CanvasComparison(before: base, after: upscaled))
        XCTAssertEqual(overFilter.comparison, CanvasComparison(before: base, after: filtered))
    }

    // RT-90.17
    //
    // Decided on whether a derivation exists rather than by comparing two images pixel by pixel,
    // which would be an absurd way to choose whether to draw a control.
    func test_withNoDerivationNoCurtainIsShown_RT090_17() {
        let content = CanvasContent.decide(base: base, derivation: nil, isWorking: false, showsBase: false)

        XCTAssertNil(content.comparison)
    }

    // RT-90.24
    func test_whileShowingTheBaseTheCurtainIsAbsent_RT090_24() {
        let content = CanvasContent.decide(base: base, derivation: upscaled, isWorking: false, showsBase: true)

        XCTAssertEqual(content.image, base)
        XCTAssertNil(content.comparison, "the base against itself is not a comparison")
    }

    // MARK: - Failure is a state, not an absence

    // RT-90.26, RT-90.27
    //
    // A failed operation is an ordinary outcome here rather than an exception: #91 adds a memory
    // cap that refuses work by design. The plausible wrong implementation leaves the spinner
    // turning forever over a picture that is never going to change.
    func test_aFailedUpscaleLeavesTheBaseAndStopsTheProgress_RT090_26() {
        let failed = CanvasContent.decide(
            base: base, derivation: nil, isWorking: false, showsBase: false)

        XCTAssertEqual(failed.image, base)
        XCTAssertFalse(failed.showsProgress)
    }

    // RT-90.28
    //
    // The transition, not a repeated state: applying a filter starts work, the filter fails, no
    // candidate is produced, and the canvas is where it began. The failure must not clear the
    // derivation on its way out, which is the plausible wrong implementation — a failure handler
    // that resets the display "to be safe" throws away a perfectly good picture.
    func test_aFailedFilterLeavesThePreviousDisplayUnchanged_RT090_28() {
        let beforeApplying = CanvasContent.decide(
            base: base, derivation: upscaled, isWorking: false, showsBase: false)
        let whileApplying = CanvasContent.decide(
            base: base, derivation: upscaled, isWorking: true, showsBase: false)
        let afterFailing = CanvasContent.decide(
            base: base, derivation: upscaled, isWorking: false, showsBase: false)

        XCTAssertEqual(whileApplying.image, beforeApplying.image, "work starting changed nothing")
        XCTAssertEqual(afterFailing.image, beforeApplying.image, "and failing changed nothing back")
        XCTAssertTrue(whileApplying.showsProgress)
        XCTAssertFalse(afterFailing.showsProgress, "the indicator stops")
    }

    // MARK: - The states the audit found unspecified

    // RT-90.40
    //
    // The one operation with nothing beneath it. Reading and decoding a file is asynchronous, so
    // between the drop and the first pixels there is no picture to draw progress over. Stated as a
    // decision rather than left to fall out, because an empty canvas here looks exactly like the
    // defect this slice removes.
    func test_whileTheImportItselfIsLoadingProgressIsShownWithNoImage_RT090_40() {
        let content = CanvasContent.decide(
            base: nil, derivation: nil, isWorking: true, showsBase: false)

        XCTAssertNil(content.image)
        XCTAssertTrue(content.showsProgress)
        XCTAssertNil(content.comparison)
    }

    // RT-90.41
    //
    // With no scale selected there is nothing awaited, so neither face setting has a rendering to
    // show and neither can land one. Expressed against the stamped form, because the face setting
    // only exists in the key: the four-value form cannot represent the difference at all.
    func test_withTheScaleOffTheFaceSettingChangesNothing_RT090_41() {
        func rendering(faces: Bool) -> StampedRendering {
            StampedRendering(
                image: RenderedImage(id: faces ? "faces" : "plain"),
                key: RenderingKey(
                    assetID: "base", modelID: "realesrgan-x4plus", sizing: "4x",
                    facesEnhanced: faces))
        }

        for faces in [false, true] {
            let content = CanvasContent.decide(
                base: base, derivation: rendering(faces: faces), expecting: nil,
                isWorking: false, showsBase: false)

            XCTAssertEqual(content.image, base, "faces: \(faces)")
            XCTAssertFalse(content.showsProgress, "nothing is rebuilt, so nothing is waited for")
            XCTAssertNil(content.comparison, "and there is nothing to compare")
        }
    }
}
