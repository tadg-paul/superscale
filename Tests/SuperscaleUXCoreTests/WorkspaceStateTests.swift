// ABOUTME: Verifies the workspace's state: what a filter reads, what lock promotes, what is shown.
// ABOUTME: Drives the asset graph as the application does, without launching a window.

import CoreGraphics
import Foundation
import XCTest
@testable import SuperscaleUXCore

@MainActor
final class WorkspaceStateTests: XCTestCase {
    private let modelSize = CGSize(width: 1024, height: 1024)
    private let upscaledSize = CGSize(width: 4096, height: 4096)

    // MARK: - What a filter reads

    // RT-89.1
    func test_aSecondFilterWithoutALockReadsTheBase_RT089_1() throws {
        let workspace = try importedWorkspace()
        let base = try XCTUnwrap(workspace.graph.base)

        try workspace.recordFilter(named: "noir", fileURL: file("noir"), pixelSize: modelSize)
        let secondInput = try workspace.graph.input(for: .filter)

        XCTAssertEqual(secondInput, base, "a filter reads the base, so results chain only when locked")
    }

    // RT-89.2
    func test_aSecondFilterAfterALockReadsTheLockedResult_RT089_2() throws {
        let workspace = try importedWorkspace()
        try workspace.recordFilter(named: "noir", fileURL: file("noir"), pixelSize: modelSize)
        let locked = try workspace.lock()

        let secondInput = try workspace.graph.input(for: .filter)

        XCTAssertEqual(secondInput, locked)
    }

    // RT-89.3
    //
    // Stated as what the user sees rather than as what the graph holds: after two filters, going
    // back shows the imported image, not the first filter's output.
    func test_afterTwoApplicationsTogglingToTheBaseShowsTheImportedImage_RT089_3() throws {
        let workspace = try importedWorkspace()
        let imported = try XCTUnwrap(workspace.graph.base)

        try workspace.recordFilter(named: "noir", fileURL: file("noir"), pixelSize: modelSize)
        try workspace.recordFilter(named: "woodblock", fileURL: file("woodblock"), pixelSize: modelSize)
        workspace.showsBase = true

        XCTAssertEqual(workspace.displayedAsset, imported)
    }

    // MARK: - Lock

    // RT-89.4
    func test_lockingPromotesTheCandidateAndTheBaseChanges_RT089_4() throws {
        let workspace = try importedWorkspace()
        let imported = try XCTUnwrap(workspace.graph.base)
        let candidate = try workspace.recordFilter(named: "noir", fileURL: file("noir"), pixelSize: modelSize)

        try workspace.lock()

        XCTAssertEqual(workspace.graph.base, candidate)
        XCTAssertNotEqual(workspace.graph.base, imported)
        XCTAssertNil(workspace.graph.candidate, "the candidate has become the base")
    }

    // RT-89.5
    func test_applyingAFilterLeavesTheBaseUnchanged_RT089_5() throws {
        let workspace = try importedWorkspace()
        let imported = try XCTUnwrap(workspace.graph.base)

        try workspace.recordFilter(named: "noir", fileURL: file("noir"), pixelSize: modelSize)

        XCTAssertEqual(workspace.graph.base, imported)
    }

    // RT-89.6
    func test_anUpscaleLeavesTheBaseUnchanged_RT089_6() throws {
        let workspace = try importedWorkspace()
        let imported = try XCTUnwrap(workspace.graph.base)

        _ = try workspace.recordUpscale(pixelSize: upscaledSize)

        XCTAssertEqual(workspace.graph.base, imported)
    }

    // RT-89.7
    func test_lockingWithNoCandidateLeavesTheBaseAndReportsWhy_RT089_7() throws {
        let workspace = try importedWorkspace()
        let imported = try XCTUnwrap(workspace.graph.base)

        XCTAssertThrowsError(try workspace.lock()) { error in
            XCTAssertTrue(
                error.localizedDescription.localizedCaseInsensitiveContains("candidate"),
                "the reason should name what is missing, got '\(error.localizedDescription)'"
            )
        }
        XCTAssertEqual(workspace.graph.base, imported)
    }

    // RT-89.23
    //
    // The case an implementation gets wrong by accident: with the scale on, what the user is
    // looking at is the upscaled rendering, so "lock what I see" is the natural code and it stores
    // a derivation as the base. The precondition is asserted rather than assumed.
    func test_lockingWithAnUpscaleShownPromotesTheCandidate_RT089_23() throws {
        let workspace = try importedWorkspace()
        let candidate = try workspace.recordFilter(named: "noir", fileURL: file("noir"), pixelSize: modelSize)
        let rendering = try workspace.recordUpscale(pixelSize: upscaledSize)
        workspace.showsBase = false

        XCTAssertEqual(
            workspace.displayedAsset(upscaledWhenAvailable: true), rendering,
            "the rendering should be what is displayed before the lock"
        )

        try workspace.lock()

        XCTAssertEqual(workspace.graph.base, candidate)
        XCTAssertEqual(try workspace.graph.asset(for: XCTUnwrap(workspace.graph.base)).pixelSize, modelSize)
    }

    // MARK: - The chain

    // RT-89.8
    func test_afterTwoLocksBothIterationsAreReachableInOrder_RT089_8() throws {
        let workspace = try importedWorkspace()
        try workspace.recordFilter(named: "noir", fileURL: file("noir"), pixelSize: modelSize)
        try workspace.lock()
        try workspace.recordFilter(named: "woodblock", fileURL: file("woodblock"), pixelSize: modelSize)
        try workspace.lock()

        let chain = workspace.lockedIterations

        XCTAssertEqual(chain.count, 2, "the imported image and the first locked result")
        XCTAssertEqual(chain.first?.role, .source)
        XCTAssertEqual(chain.last?.provenance?.filterID, "noir")
    }

    // RT-89.9
    func test_aLockedIterationCarriesTheFilterThatMadeIt_RT089_9() throws {
        let workspace = try importedWorkspace()
        try workspace.recordFilter(named: "noir", fileURL: file("noir"), pixelSize: modelSize)
        try workspace.lock()

        let base = try workspace.graph.asset(for: XCTUnwrap(workspace.graph.base))

        XCTAssertEqual(base.provenance?.filterID, "noir")
    }

    // RT-89.25
    func test_importingANewImageEmptiesTheLockChain_RT089_25() throws {
        let workspace = try importedWorkspace()
        try workspace.recordFilter(named: "noir", fileURL: file("noir"), pixelSize: modelSize)
        try workspace.lock()
        XCTAssertFalse(workspace.lockedIterations.isEmpty)

        workspace.importImage(fileURL: file("second"), pixelSize: modelSize)

        XCTAssertTrue(
            workspace.lockedIterations.isEmpty,
            "the chain belongs to the image it was built from"
        )
        XCTAssertNil(workspace.graph.candidate)
    }

    // MARK: - The toggle

    // RT-89.13, RT-89.14
    func test_theToggleShowsTheBaseAndThenTheCandidateAgain_RT089_13() throws {
        let workspace = try importedWorkspace()
        let imported = try XCTUnwrap(workspace.graph.base)
        let candidate = try workspace.recordFilter(named: "noir", fileURL: file("noir"), pixelSize: modelSize)

        workspace.showsBase = true
        XCTAssertEqual(workspace.displayedAsset, imported)

        workspace.showsBase = false
        XCTAssertEqual(workspace.displayedAsset, candidate)
    }

    // The guard suppresses a comparison only where it can prove both sides are one asset. With no
    // base tracked there is nothing to prove it with, and returning false there suppressed the
    // curtain outright — which the GUI suite caught as "entering comparison shows the curtain"
    // failing, an hour after the guard was written.
    func test_withNoBaseTrackedTheComparisonIsNotSuppressed() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let workspace = WorkspaceState(outputDirectory: directory)

        XCTAssertTrue(workspace.hasTwoAssetsToCompare(displaying: nil))
    }

    func test_aDisplayedAssetThatIsTheBaseIsNotAComparison() throws {
        let workspace = try importedWorkspace()
        let base = try XCTUnwrap(workspace.graph.base)

        XCTAssertFalse(workspace.hasTwoAssetsToCompare(displaying: base))
    }

    func test_aDisplayedCandidateIsAComparisonAgainstTheBase() throws {
        let workspace = try importedWorkspace()
        let candidate = try workspace.recordFilter(
            named: "noir", fileURL: file("noir"), pixelSize: modelSize)

        XCTAssertTrue(workspace.hasTwoAssetsToCompare(displaying: candidate))
    }

    // RT-89.15
    func test_togglingLeavesTheGraphUnchanged_RT089_15() throws {
        let workspace = try importedWorkspace()
        try workspace.recordFilter(named: "noir", fileURL: file("noir"), pixelSize: modelSize)
        let before = workspace.graph

        workspace.showsBase = true
        workspace.showsBase = false

        XCTAssertEqual(workspace.graph.base, before.base)
        XCTAssertEqual(workspace.graph.candidate, before.candidate)
    }

    // RT-89.27
    func test_withNoCandidateTheToggleIsUnavailable_RT089_27() throws {
        let workspace = try importedWorkspace()

        XCTAssertFalse(workspace.canCompare, "there is nothing to compare against")
    }

    // RT-89.28
    //
    // Applying while showing the base would otherwise look as though nothing had happened.
    func test_applyingWhileShowingTheBaseShowsTheNewCandidate_RT089_28() throws {
        let workspace = try importedWorkspace()
        workspace.showsBase = true

        let candidate = try workspace.recordFilter(named: "noir", fileURL: file("noir"), pixelSize: modelSize)

        XCTAssertFalse(workspace.showsBase)
        XCTAssertEqual(workspace.displayedAsset, candidate)
    }

    // MARK: - The graph enforces I1

    // RT-89.11
    func test_aFilterAppliedWhileAnUpscaleExistsReadsTheBase_RT089_11() throws {
        let workspace = try importedWorkspace()
        let base = try XCTUnwrap(workspace.graph.base)
        _ = try workspace.recordUpscale(pixelSize: upscaledSize)

        XCTAssertEqual(try workspace.graph.input(for: .filter), base)
    }

    // RT-89.12
    func test_submittingAnUpscaledReferenceReportsTheRuleItBreaks_RT089_12() throws {
        let workspace = try importedWorkspace()
        let upscale = try workspace.recordUpscale(pixelSize: upscaledSize)

        XCTAssertThrowsError(try workspace.graph.validateStageInput(upscale)) { error in
            XCTAssertTrue(
                error.localizedDescription.localizedCaseInsensitiveContains("upscal"),
                "the reason should name the rule, got '\(error.localizedDescription)'"
            )
        }
    }

    // MARK: - Fixtures

    private func importedWorkspace() throws -> WorkspaceState {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let workspace = WorkspaceState(outputDirectory: directory)
        workspace.importImage(fileURL: directory.appendingPathComponent("source.png"), pixelSize: modelSize)
        return workspace
    }

    private func file(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name).png")
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceStateTests-\(UUID().uuidString)", isDirectory: true)
    }
}
