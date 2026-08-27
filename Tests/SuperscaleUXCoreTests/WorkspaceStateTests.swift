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
    //
    // **The expected count moved from two to three by #121, and that is the criterion changing
    // rather than the test weakening.** The chain was the base's ancestry, so the newest lock was
    // excluded: it was where the user stood, not somewhere they could go. Guide 3.32 makes the
    // chain the tip's lineage, because selecting an iteration now moves the base backwards and a
    // chain read from the base would lose everything forward of the selection. The newest lock is
    // therefore an iteration like any other, and must be selectable — which is what lets a user who
    // scrolled back get forward again.
    func test_afterTwoLocksBothIterationsAreReachableInOrder_RT089_8() throws {
        let workspace = try importedWorkspace()
        try workspace.recordFilter(named: "noir", fileURL: file("noir"), pixelSize: modelSize)
        try workspace.lock()
        try workspace.recordFilter(named: "woodblock", fileURL: file("woodblock"), pixelSize: modelSize)
        try workspace.lock()

        let chain = workspace.lockedIterations

        XCTAssertEqual(chain.count, 3, "the imported image and both locked results")
        XCTAssertEqual(chain.first?.role, .source)
        XCTAssertEqual(chain[1].provenance?.filterID, "noir")
        XCTAssertEqual(chain.last?.provenance?.filterID, "woodblock", "the newest lock is reachable")
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

    // MARK: - AC89.6 the scale and the toggle are independent

    // RT-89.16, RT-89.17, RT-89.18, RT-89.19
    //
    // The four combinations, asserted together because the criterion is that they are *four* — the
    // toggle chooses which asset and the scale chooses whether its upscale is preferred, and an
    // implementation coupling the two would still pass any single one of them.
    //
    // Showing the base upscaled means running Core ML on the base, which is seconds of work started
    // by flicking a toggle. Showing an unupscaled base while the scale is on would be cheaper and
    // worse: the user could not tell whether they were looking at a rendering or a raw image.
    func test_theToggleAndTheScaleReachAllFourCombinations_RT089_16() throws {
        let workspace = try importedWorkspace()
        let base = try XCTUnwrap(workspace.graph.base)
        let candidate = try workspace.recordFilter(
            named: "noir", fileURL: file("candidate"), pixelSize: modelSize)

        // The candidate, unupscaled and upscaled. RT-89.18, RT-89.19.
        workspace.showsBase = false
        XCTAssertEqual(
            workspace.displayedAsset(upscaledWhenAvailable: false), candidate,
            "the candidate with the scale off")

        let candidateUpscale = try workspace.recordUpscale(pixelSize: upscaledSize)
        XCTAssertEqual(
            workspace.displayedAsset(upscaledWhenAvailable: true), candidateUpscale,
            "the candidate's upscale with a scale selected")
        XCTAssertEqual(
            workspace.displayedAsset(upscaledWhenAvailable: false), candidate,
            "and the candidate itself is still reachable with the scale off")

        // The base, unupscaled and upscaled. RT-89.16, RT-89.17.
        workspace.showsBase = true
        XCTAssertEqual(
            workspace.displayedAsset(upscaledWhenAvailable: false), base,
            "the base with the scale off")

        let baseUpscale = try workspace.recordUpscale(pixelSize: upscaledSize)
        XCTAssertEqual(
            workspace.displayedAsset(upscaledWhenAvailable: true), baseUpscale,
            "the base's upscale with a scale selected")
        XCTAssertNotEqual(baseUpscale, candidateUpscale, "two renderings, not one reused")
    }

    // RT-89.14
    //
    // Separated from RT-89.13's outward journey. A toggle that could show the base and not return
    // is a trap, and one assertion covering both directions cannot say which half failed.
    func test_togglingBackShowsTheCandidateAgain_RT089_14() throws {
        let workspace = try importedWorkspace()
        let base = try XCTUnwrap(workspace.graph.base)
        let candidate = try workspace.recordFilter(
            named: "noir", fileURL: file("candidate"), pixelSize: modelSize)

        workspace.showsBase = true
        XCTAssertEqual(workspace.displayedAsset, base)

        workspace.showsBase = false
        XCTAssertEqual(workspace.displayedAsset, candidate)
        XCTAssertEqual(workspace.graph.candidate, candidate, "and it is the same candidate")
    }

    // MARK: - AC89.8 a released chain releases its files

    // RT-89.26
    //
    // The chain belongs to the image it was built from. Keeping the files would grow the output
    // directory for the life of the session, one upscale of one photograph at a time.
    func test_theFilesOfAReleasedChainNoLongerOccupyTheOutputDirectory_RT089_26() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let workspace = WorkspaceState(outputDirectory: directory)

        let source = directory.appendingPathComponent("source.png")
        try Data("not really a png".utf8).write(to: source)
        workspace.importImage(fileURL: source, pixelSize: modelSize)

        // An upscale is allocated a location in the output directory, and its pixels written there.
        let upscale = try workspace.recordUpscale(pixelSize: upscaledSize)
        let upscaleURL = try workspace.graph.asset(for: upscale).fileURL
        try Data("upscaled pixels".utf8).write(to: upscaleURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: upscaleURL.path))

        // A second upscale of the same input supersedes the first, which is released.
        let replacement = try workspace.recordUpscale(pixelSize: upscaledSize)
        XCTAssertNotEqual(replacement, upscale, "a new location, never a reused one")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: upscaleURL.path),
            "the superseded rendering's file is released rather than left behind")
    }

    // MARK: - AC92.7 what goes to the provider is the base's own file

    // RT-92.17, RT-92.18, RT-92.19
    //
    // The application uploads `graph.asset(for: graph.input(for: .filter)).fileURL`, so what is
    // asserted here is the file that names. The three conditions are the three ways the wrong
    // picture could be chosen: reaching for what is on screen (which is the upscale), reaching for
    // the working asset (which is the candidate), or reaching for the last thing produced.
    func test_whatAFilterUploadsIsTheBasesOwnFile_RT092_17() throws {
        let workspace = try importedWorkspace()
        let base = try XCTUnwrap(workspace.graph.base)
        let baseFile = try workspace.graph.asset(for: base).fileURL

        func fileAFilterWouldUpload() throws -> URL {
            let input = try workspace.graph.input(for: .filter)
            return try workspace.graph.asset(for: input).fileURL
        }

        // RT-92.17: with nothing else present.
        XCTAssertEqual(try fileAFilterWouldUpload(), baseFile)

        // RT-92.18: with an upscale on the canvas. The rendering is what the user is looking at,
        // and "upload what I see" is the natural code and the wrong one — an upscale of a picture
        // is not the picture, and the provider's working resolution is the base's.
        let upscale = try workspace.recordUpscale(pixelSize: upscaledSize)
        XCTAssertEqual(
            workspace.displayedAsset(upscaledWhenAvailable: true), upscale,
            "the rendering is genuinely what is displayed")
        XCTAssertEqual(try fileAFilterWouldUpload(), baseFile, "and it is not what goes out")

        // RT-92.19: with a candidate present. A filter reads the base so results chain only when
        // locked; uploading the candidate would compound filters by accident.
        let candidate = try workspace.recordFilter(
            named: "noir", fileURL: file("candidate"), pixelSize: modelSize)
        XCTAssertEqual(workspace.graph.candidate, candidate)
        XCTAssertEqual(try fileAFilterWouldUpload(), baseFile)

        // And after a lock the base has moved, so the *new* base is what goes out — the rule is
        // "the base", not "the imported image".
        let locked = try workspace.lock()
        XCTAssertEqual(
            try fileAFilterWouldUpload(), try workspace.graph.asset(for: locked).fileURL)
    }

    // MARK: - AC94.3 what the curtain compares

    // RT-94.7, RT-94.8, RT-94.9
    //
    // **Asserted against `baseFileURL`, which is the property the view actually reads**, rather than
    // against a helper written for the occasion. The curtain's far side is whatever picture that
    // names, so the criterion is a statement about it and about nothing else.
    //
    // The defect: the view took the far side from `viewModel.originalImage`, which `processImage`
    // replaces with whatever it was last asked to upscale. After a filter that is the filter's own
    // output, so the curtain showed the filtered picture against the upscale of the same filtered
    // picture — two images differing in resolution and in nothing else. "The before/after image is
    // the same" was the author's description of it, and it was accurate.
    func test_theFarSideOfTheCurtainIsTheBaseThroughoutAFilterAndItsUpscale_RT094_7() throws {
        let workspace = try importedWorkspace()
        let imported = try XCTUnwrap(workspace.graph.base)
        let importedFile = try workspace.graph.asset(for: imported).fileURL
        XCTAssertEqual(workspace.baseFileURL, importedFile)

        // RT-94.8: an upscale of an unfiltered picture. The base does not move, so the far side is
        // still the picture and the near side is its upscale — the plain upscale case, and a real
        // comparison rather than one to suppress.
        try workspace.recordUpscale(pixelSize: upscaledSize)
        XCTAssertEqual(workspace.baseFileURL, importedFile, "an upscale does not move the base")

        // RT-94.7: after a filter, the far side is the picture the filter was made from.
        let candidate = try workspace.recordFilter(
            named: "noir", fileURL: file("candidate"), pixelSize: modelSize)
        let candidateFile = try workspace.graph.asset(for: candidate).fileURL
        XCTAssertEqual(workspace.baseFileURL, importedFile)
        XCTAssertNotEqual(
            workspace.baseFileURL, candidateFile,
            "the filter result is the near side, never the far one")

        // RT-94.9: after a filter *and* an upscale of it. This is the case the old code got wrong:
        // the far side must still be the original, not the unupscaled filter result.
        try workspace.recordUpscale(pixelSize: upscaledSize)
        XCTAssertEqual(workspace.baseFileURL, importedFile)
        XCTAssertNotEqual(workspace.baseFileURL, candidateFile)
    }

    // RT-94.10
    //
    // The two sides are never the same asset. A curtain drawn across one picture divides it from
    // itself, which looks like a working control and compares nothing.
    //
    // `hasTwoAssetsToCompare` is the decision the view consults, and its asymmetry is deliberate:
    // it suppresses the curtain only where it can *prove* both sides are one asset. With no base
    // tracked there is nothing to prove it with, and returning false there suppressed the curtain
    // outright — which is worse than the defect the guard exists to prevent, and is what happened.
    func test_theTwoSidesAreNeverTheSameAsset_RT094_10() throws {
        let workspace = try importedWorkspace()
        let base = try XCTUnwrap(workspace.graph.base)

        XCTAssertFalse(
            workspace.hasTwoAssetsToCompare(displaying: base),
            "the base against itself is not a comparison")

        let candidate = try workspace.recordFilter(
            named: "noir", fileURL: file("candidate"), pixelSize: modelSize)
        XCTAssertTrue(workspace.hasTwoAssetsToCompare(displaying: candidate))

        // Not provable, so not suppressed. The view model performs upscales the graph never
        // records, so "the graph does not know what this is" is the ordinary case rather than an
        // error, and treating it as one is what stopped the curtain appearing at all.
        XCTAssertTrue(workspace.hasTwoAssetsToCompare(displaying: nil))
    }

    // RT-94.16
    //
    // Viewing an earlier locked iteration. The criterion allows either answer — that iteration
    // against what descends from it, or no curtain at all — and forbids the third: the iteration
    // compared against a base it does not descend from, presenting two unrelated pictures as though
    // one were made from the other.
    func test_viewingAnEarlierIterationComparesItAgainstTheChainOrNotAtAll_RT094_16() throws {
        let workspace = try importedWorkspace()
        let imported = try XCTUnwrap(workspace.graph.base)
        try workspace.recordFilter(named: "noir", fileURL: file("first"), pixelSize: modelSize)
        let firstLock = try workspace.lock()
        try workspace.recordFilter(named: "woodblock", fileURL: file("second"), pixelSize: modelSize)
        let secondLock = try workspace.lock()

        XCTAssertEqual(workspace.graph.base, secondLock, "the base is the latest lock")

        // Every earlier iteration is in the current base's own ancestry, so a comparison against the
        // base is a comparison against something it genuinely descends from. That is the property
        // the criterion is protecting, and it is what makes the first answer legitimate.
        let ancestry = workspace.lockedIterations.map(\.id)
        XCTAssertTrue(ancestry.contains(imported.id), "the imported picture")
        XCTAssertTrue(ancestry.contains(firstLock.id), "and the first lock")

        // Each is a different asset from the base, so a curtain drawn there compares two pictures.
        XCTAssertTrue(workspace.hasTwoAssetsToCompare(displaying: imported))
        XCTAssertTrue(workspace.hasTwoAssetsToCompare(displaying: firstLock))
        XCTAssertFalse(workspace.hasTwoAssetsToCompare(displaying: secondLock))
    }

    // MARK: - AC96.5 the mark reaches somewhere a user can see it

    // RT-96.14, RT-96.15, at the level the view reads
    //
    // The provenance records whether the provider reshaped the picture. **Recorded and never shown,
    // the criterion is delivered to its tests and not to anybody using the application** — the fault
    // this delivery found twice over. `reshapedByProvider` is what the view asks, so it is what the
    // question is asserted against.
    func test_theViewCanTellWhetherTheProviderReshapedThePicture_RT096_14() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let workspace = WorkspaceState(outputDirectory: directory)

        // A portrait base, because the fixture used elsewhere here is square and a square base
        // cannot demonstrate a squared return. That is the shape the author reported.
        workspace.importImage(
            fileURL: directory.appendingPathComponent("source.png"),
            pixelSize: CGSize(width: 768, height: 1024))

        let squared = try workspace.recordFilter(
            named: "noir", fileURL: file("squared"),
            pixelSize: CGSize(width: 1024, height: 1024))
        XCTAssertTrue(
            workspace.reshapedByProvider(squared),
            "3:4 went out and 1:1 came back")

        // RT-96.15: a return of the same shape is not marked, whatever its size.
        try workspace.lock()
        let preserved = try workspace.recordFilter(
            named: "woodblock", fileURL: file("preserved"),
            pixelSize: CGSize(width: 2048, height: 2048))
        XCTAssertFalse(
            workspace.reshapedByProvider(preserved),
            "the base is 1:1 by now, so a 1:1 return preserved the framing")
    }

    /// "Not known" reads as "not reshaped" at the view's boundary, deliberately.
    ///
    /// The caller is deciding whether to *tell* the user something, and telling them on a guess is
    /// worse than staying quiet. The uncertainty stays on the asset, where a later reader can find
    /// it; only the decision folds it away.
    func test_anUnknownShapeIsNotReportedAsAReshaping() throws {
        let workspace = try importedWorkspace()
        let base = try XCTUnwrap(workspace.graph.base)

        XCTAssertFalse(
            workspace.reshapedByProvider(base),
            "an imported picture has no provenance and was reshaped by nobody")
    }

    // MARK: - AC103.1 an allocation derives from the picture on the canvas

    // RT-103.1, RT-103.2
    //
    // The condition #89 found broken: `recordUpscale` asked the graph for the *working* asset, which
    // is the candidate whenever one exists, while the criterion is about what is *displayed*. The
    // two differ exactly when the filter toggle shows the base.
    func test_anAllocationDerivesFromWhicheverPictureIsShown_RT103_1() throws {
        let workspace = try importedWorkspace()
        let base = try XCTUnwrap(workspace.graph.base)
        let candidate = try workspace.recordFilter(
            named: "noir", fileURL: file("candidate"), pixelSize: modelSize)

        // RT-103.2: the ordinary case.
        workspace.showsBase = false
        let fromCandidate = try workspace.recordUpscale(pixelSize: upscaledSize)
        XCTAssertEqual(
            try workspace.graph.asset(for: fromCandidate).parentID, candidate.id,
            "the candidate is on the canvas, so the allocation derives from it")

        // RT-103.1: the case the parallel route got wrong.
        workspace.showsBase = true
        let fromBase = try workspace.recordUpscale(pixelSize: upscaledSize)
        XCTAssertEqual(
            try workspace.graph.asset(for: fromBase).parentID, base.id,
            "the toggle shows the base, so the allocation derives from the base")
    }

    // RT-103.3
    //
    // The graph's own rule, which must survive: an upscaled asset is never a stage input.
    func test_anUpscaledAssetIsRefusedAsTheInput_RT103_3() throws {
        let workspace = try importedWorkspace()
        let upscale = try workspace.recordUpscale(pixelSize: upscaledSize)

        XCTAssertThrowsError(try workspace.graph.validateStageInput(upscale)) { error in
            XCTAssertTrue(
                error.localizedDescription.localizedCaseInsensitiveContains("upscal"),
                "the reason names the rule: \(error.localizedDescription)")
        }
    }

    // RT-103.6
    //
    // **The condition that would have bitten.** With a scale selected the canvas shows a
    // *rendering*, so "derive from what is on the canvas" read naively derives from the rendering
    // rather than from its subject — which is the mistake the criterion exists to prevent, and a
    // different condition from offering an upscaled asset explicitly.
    func test_withARenderingOnTheCanvasTheAllocationDerivesFromItsSubject_RT103_6() throws {
        let workspace = try importedWorkspace()
        let base = try XCTUnwrap(workspace.graph.base)

        let rendering = try workspace.recordUpscale(pixelSize: upscaledSize)
        XCTAssertEqual(
            workspace.displayedAsset(upscaledWhenAvailable: true), rendering,
            "the rendering is genuinely what the canvas shows")

        // Allocating again must derive from the base, not from the rendering of it.
        let second = try workspace.recordUpscale(pixelSize: upscaledSize)
        XCTAssertEqual(
            try workspace.graph.asset(for: second).parentID, base.id,
            "an upscale of an upscale is what the asset roles exist to prevent")
    }

    // RT-103.7
    //
    // After a lock the displayed picture is the new base. A route caching the previous one satisfies
    // every condition above and fails here.
    func test_afterALockTheAllocationDerivesFromTheNewBase_RT103_7() throws {
        let workspace = try importedWorkspace()
        let imported = try XCTUnwrap(workspace.graph.base)
        try workspace.recordFilter(
            named: "noir", fileURL: file("candidate"), pixelSize: modelSize)
        let locked = try workspace.lock()

        XCTAssertNotEqual(locked, imported, "the base moved")

        let allocation = try workspace.recordUpscale(pixelSize: upscaledSize)
        XCTAssertEqual(
            try workspace.graph.asset(for: allocation).parentID, locked.id,
            "the allocation follows the base rather than remembering the old one")
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
