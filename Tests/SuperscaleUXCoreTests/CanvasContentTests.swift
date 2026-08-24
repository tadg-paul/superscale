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
    func test_duringAnUpscaleTheBaseRemainsVisible_RT090_3() {
        let content = CanvasContent.decide(base: base, derivation: nil, isWorking: true, showsBase: false)

        XCTAssertEqual(content.image, base)
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
}
