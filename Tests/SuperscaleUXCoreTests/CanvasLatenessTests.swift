// ABOUTME: Verifies that a rendering for a superseded base or setting is dropped, not drawn.
// ABOUTME: The fault a pure decision over four values cannot catch, because it draws what it is given.

import Foundation
import XCTest
@testable import SuperscaleUXCore

/// Lateness.
///
/// An upscale takes seconds. In those seconds the user can import another picture, lock a
/// candidate, or change the face setting. Whatever was in flight then describes a state that no
/// longer exists, and drawing it puts one picture's upscale beside another picture.
final class CanvasLatenessTests: XCTestCase {
    private let base = RenderedImage(id: "base")
    private let newBase = RenderedImage(id: "newBase")

    private func key(asset: String, faces: Bool = false) -> RenderingKey {
        RenderingKey(
            assetID: asset, modelID: "realesrgan-x4plus", sizing: "4x", facesEnhanced: faces)
    }

    // RT-90.30
    func test_anUpscaleCompletingAfterASecondImportIsNotDisplayed_RT090_30() {
        let late = StampedRendering(image: RenderedImage(id: "firstUpscale"), key: key(asset: "first"))

        let content = CanvasContent.decide(
            base: newBase, derivation: late, expecting: key(asset: "second"),
            isWorking: false, showsBase: false)

        XCTAssertEqual(content.image, newBase, "the new picture, not the old one's upscale")
        XCTAssertNil(content.comparison, "and nothing to compare it against")
    }

    // RT-90.31
    func test_anUpscaleCompletingAfterALockIsNotDisplayed_RT090_31() {
        // Lock promotes the candidate, so the base identity changes exactly as it does on import.
        let late = StampedRendering(
            image: RenderedImage(id: "preLockUpscale"), key: key(asset: "beforeLock"))

        let content = CanvasContent.decide(
            base: newBase, derivation: late, expecting: key(asset: "afterLock"),
            isWorking: false, showsBase: false)

        XCTAssertEqual(content.image, newBase)
    }

    // RT-90.32
    func test_theRenderingDisplayedMatchesTheCurrentSettingNotTheLastToFinish_RT090_32() {
        let withoutFaces = StampedRendering(
            image: RenderedImage(id: "plain"), key: key(asset: "base", faces: false))

        // Faces are on now; the plain rendering finished last and is still wrong.
        let content = CanvasContent.decide(
            base: base, derivation: withoutFaces, expecting: key(asset: "base", faces: true),
            isWorking: true, showsBase: false)

        XCTAssertEqual(content.image, base, "hold the base rather than show the wrong version")
        XCTAssertTrue(content.showsProgress)
    }

    // RT-90.33
    func test_theCanvasShowsTheNewBaseWhileTheSupersededRenderingIsStillUnderWay_RT090_33() {
        let stale = StampedRendering(
            image: RenderedImage(id: "oldUpscale"), key: key(asset: "old"))

        let content = CanvasContent.decide(
            base: newBase, derivation: stale, expecting: key(asset: "new"),
            isWorking: true, showsBase: false)

        XCTAssertEqual(content.image, newBase)
        XCTAssertTrue(content.showsProgress, "the new one is being built")
    }

    // A rendering that still matches is admitted, or none of the above would mean anything: a
    // decision that drops everything passes every test that only checks what is dropped.
    func test_aRenderingThatStillDescribesTheCurrentStateIsShown() {
        let current = key(asset: "base")
        let matching = StampedRendering(image: RenderedImage(id: "upscale"), key: current)

        let content = CanvasContent.decide(
            base: base, derivation: matching, expecting: current,
            isWorking: false, showsBase: false)

        XCTAssertEqual(content.image, RenderedImage(id: "upscale"))
        XCTAssertEqual(
            content.comparison,
            CanvasComparison(before: base, after: RenderedImage(id: "upscale")))
    }

    // With nothing awaited, nothing lands. This is the state after the scale is turned off, where
    // an upscale still in flight must not appear when it finishes.
    func test_withNothingAwaitedALateRenderingDoesNotLand() {
        let inFlight = StampedRendering(image: RenderedImage(id: "upscale"), key: key(asset: "base"))

        let content = CanvasContent.decide(
            base: base, derivation: inFlight, expecting: nil,
            isWorking: false, showsBase: false)

        XCTAssertEqual(content.image, base)
    }
}
