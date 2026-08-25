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
    // RT-90.23
    //
    // Turning the scale off during an upscale. The run is cancelled at the stage — #87's slice 3
    // put cancellation inside the tile loop, so the work actually stops rather than merely ceasing
    // to be observed — and this asserts the second half: a completion that arrives anyway is **not
    // admitted**.
    //
    // Both halves are needed and neither implies the other. Cancellation that does not stop the
    // work wastes a Neural Engine for a minute; a stop that does not guard the result puts an
    // upscale on a canvas whose scale the user has just turned off.
    func test_turningTheScaleOffRefusesALateCompletion_RT090_23() {
        let base = RenderedImage(id: "base")
        let key = RenderingKey(
            assetID: "base", modelID: "realesrgan-x4plus", sizing: "4x", facesEnhanced: false)
        let inFlight = StampedRendering(image: RenderedImage(id: "upscaled"), key: key)

        // While the scale is selected, the rendering is what the canvas awaits.
        let running = CanvasContent.decide(
            base: base, derivation: inFlight, expecting: key, isWorking: true, showsBase: false)
        XCTAssertEqual(running.image, inFlight.image)

        // The scale is turned off: nothing is awaited. A completion arriving now describes a state
        // the user has left.
        let afterTurningOff = CanvasContent.decide(
            base: base, derivation: inFlight, expecting: nil, isWorking: false, showsBase: false)

        XCTAssertEqual(afterTurningOff.image, base, "the canvas falls back to the base at once")
        XCTAssertNil(afterTurningOff.comparison, "and there is nothing to compare it against")
        XCTAssertFalse(afterTurningOff.showsProgress)
    }

    // RT-90.9
    //
    // Toggling face enhancement leaves the previous rendering on screen while the new one builds.
    // Clearing it is what emptied the canvas the moment anything was adjusted, and falling back to
    // the base mid-operation is a regression dressed as a fix: the user asked for a change to what
    // they were looking at, not for it to be taken away while they waited.
    func test_togglingFacesLeavesThePreviousRenderingUpWhileTheNewOneBuilds_RT090_9() {
        let base = RenderedImage(id: "base")
        let plainKey = RenderingKey(
            assetID: "base", modelID: "realesrgan-x4plus", sizing: "4x", facesEnhanced: false)
        let plain = StampedRendering(image: RenderedImage(id: "plain"), key: plainKey)

        let onScreen = CanvasContent.decide(
            base: base, derivation: plain, expecting: plainKey, isWorking: false, showsBase: false)
        XCTAssertEqual(onScreen.image, plain.image)

        // Faces are switched on. The new rendering does not exist yet, and the state the canvas
        // still holds is the old one — which is exactly what should stay up.
        let building = CanvasContent.decide(
            base: base, derivation: plain, expecting: plainKey, isWorking: true, showsBase: false)

        XCTAssertEqual(
            building.image, plain.image,
            "the previous rendering stays while the new one builds")
        XCTAssertTrue(building.showsProgress, "and the work is reported over it")
        XCTAssertNotEqual(building.image, base, "the canvas does not fall back to the base")
    }

    func test_withNothingAwaitedALateRenderingDoesNotLand() {
        let inFlight = StampedRendering(image: RenderedImage(id: "upscale"), key: key(asset: "base"))

        let content = CanvasContent.decide(
            base: base, derivation: inFlight, expecting: nil,
            isWorking: false, showsBase: false)

        XCTAssertEqual(content.image, base)
    }
}
