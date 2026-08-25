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

    // MARK: - AC96.1: what the workspace does about it

    // RT-96.3
    //
    // The raising is reported. An application that silently upscaled the user's photograph before
    // sending it would be making a decision on their behalf and not saying so.
    func test_theRaisingIsReported_RT096_3() {
        let decision = MinimumResolution.decide(sourceSize: CGSize(width: 240, height: 320))

        let message = decision.report
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("1024") ?? false, message ?? "")
        XCTAssertFalse(
            message?.contains("shape") ?? true,
            "this picture reaches the floor; nothing warns about the provider reshaping it")
    }

    // RT-96.17, continued
    //
    // The other message. A picture the control cannot lift to the floor is raised as far as it goes
    // and the user is warned the provider may reshape it, which is the fact behind the report that
    // produced #96.
    func test_aPictureThatCannotReachTheFloorIsReportedDifferently_RT096_17() {
        let decision = MinimumResolution.decide(sourceSize: CGSize(width: 50, height: 50))

        let message = decision.report ?? ""
        XCTAssertTrue(message.contains("400"), message)
        XCTAssertTrue(message.contains("shape"), "the provider may reshape it: \(message)")
    }

    func test_aPictureThatNeedsNoRaisingIsNotReported() {
        let decision = MinimumResolution.decide(sourceSize: CGSize(width: 2000, height: 1500))

        XCTAssertNil(decision.report)
    }

    // RT-96.4
    //
    // Guide 2.5's own reasoning: the raised picture becomes the base. Without that the application
    // keeps re-upscaling a picture that is already the size the provider wants, once per filter.
    @MainActor
    func test_theRaisedPictureBecomesTheBase_RT096_4() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = WorkspaceState(outputDirectory: directory)
        let source = directory.appendingPathComponent("source.png")
        try Data("not really a png".utf8).write(to: source)
        workspace.importImage(fileURL: source, pixelSize: CGSize(width: 240, height: 320))

        let decision = try XCTUnwrap(workspace.raiseToMinimumNeeded())
        let allocation = try workspace.allocateRaiseToMinimum(pixelSize: decision.resultingSize)

        let base = try XCTUnwrap(workspace.graph.base)
        XCTAssertEqual(base, allocation.reference, "the raised picture is the base")
        let asset = try workspace.graph.asset(for: base)
        XCTAssertEqual(asset.role, .raisedToMinimum)
        XCTAssertEqual(asset.pixelSize, decision.resultingSize)

        // And a filter now reads it, rather than the undersized original. This is the assertion
        // that matters: raising the picture is not the same as raising what goes out, and the
        // defect was entirely in the second.
        XCTAssertEqual(try workspace.graph.input(for: .filter), allocation.reference)
        XCTAssertGreaterThanOrEqual(
            max(asset.pixelSize.width, asset.pixelSize.height), MinimumResolution.longEdge)
    }

    /// A raised picture is still a legitimate filter input, unlike an upscale.
    ///
    /// The harm the stage rules prevent is exceeding the filter model's working resolution, not
    /// upscaling as such — which is why `AssetRole` distinguishes the two at all. A raise recorded
    /// as `.upscaled` would be refused by the graph and the floor could never be enforced.
    @MainActor
    func test_aRaisedPictureIsAcceptedAsFilterInputWhereAnUpscaleIsNot() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = WorkspaceState(outputDirectory: directory)
        let source = directory.appendingPathComponent("source.png")
        try Data("not really a png".utf8).write(to: source)
        workspace.importImage(fileURL: source, pixelSize: CGSize(width: 240, height: 320))

        let raised = try workspace.allocateRaiseToMinimum(
            pixelSize: CGSize(width: 960, height: 1280))
        XCTAssertNoThrow(try workspace.graph.validateStageInput(raised.reference))

        let upscale = try workspace.recordUpscale(pixelSize: CGSize(width: 1920, height: 2560))
        XCTAssertThrowsError(try workspace.graph.validateStageInput(upscale))
    }

    // RT-96.7
    //
    // Once raised, nothing raises again. The check is asked continuously, so a check that answered
    // from the original size rather than the current base would re-raise on every setting change.
    @MainActor
    func test_aBaseAlreadyAtTheFloorNeedsNoFurtherRaising_RT096_7() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = WorkspaceState(outputDirectory: directory)
        let source = directory.appendingPathComponent("source.png")
        try Data("not really a png".utf8).write(to: source)

        workspace.importImage(fileURL: source, pixelSize: CGSize(width: 2000, height: 1500))
        XCTAssertNil(workspace.raiseToMinimumNeeded(), "already above the floor")

        workspace.importImage(fileURL: source, pixelSize: CGSize(width: 240, height: 320))
        let decision = try XCTUnwrap(workspace.raiseToMinimumNeeded())
        try workspace.allocateRaiseToMinimum(pixelSize: decision.resultingSize)

        XCTAssertNil(workspace.raiseToMinimumNeeded(), "raised once, not repeatedly")
    }

    /// With nothing imported there is nothing to raise, and no message about it.
    @MainActor
    func test_withNoBaseThereIsNothingToRaise() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertNil(WorkspaceState(outputDirectory: directory).raiseToMinimumNeeded())
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("minimum-resolution-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
