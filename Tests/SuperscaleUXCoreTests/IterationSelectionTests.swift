// ABOUTME: Verifies that selecting a locked iteration restores the working context it was made in.
// ABOUTME: The base moves backwards to the iteration's parent; the tip keeps the chain reachable.

import Foundation
import XCTest
@testable import SuperscaleUXCore

/// Guide 2.4 and 3.2, as amended at 3.32.
///
/// Until then the base moved only forwards, on lock, so an earlier iteration was something a user
/// could look at but not work from: a filter reads the base (I2), and the base had not moved. The
/// author reported it as filters landing on the wrong picture.
///
/// These drive `WorkspaceState` directly rather than through the window, because every claim here
/// is about graph state and guide 3.2 says those rules are pure logic over the graph. The two
/// claims that are about what reaches the user — the control's presence, and what the canvas shows
/// — are GUI tests instead.
final class IterationSelectionTests: XCTestCase {
    /// A workspace whose output directory is unique to this run and removed in teardown.
    @MainActor
    private func makeWorkspace() throws -> (WorkspaceState, URL) {
        let root = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true)
        return (WorkspaceState(outputDirectory: root), root)
    }

    /// Writes a one-pixel file so an asset refers to something that exists on disk.
    private func writeFixture(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data([0x00]).write(to: url)
        return url
    }

    /// Builds a chain of `count` locked iterations above an imported source.
    ///
    /// Each iteration is a recorded filter result promoted by a lock, which is the only way a real
    /// chain is ever built. Returns the source and each locked reference, oldest first.
    @MainActor
    private func buildChain(
        of count: Int, in workspace: WorkspaceState, root: URL
    ) throws -> (source: AssetReference, locks: [AssetReference]) {
        let sourceURL = try writeFixture(named: "source.png", in: root)
        workspace.importImage(fileURL: sourceURL, pixelSize: CGSize(width: 2048, height: 2048))
        let source = try XCTUnwrap(workspace.graph.base)

        var locks: [AssetReference] = []
        for index in 0..<count {
            let filteredURL = try writeFixture(named: "filtered-\(index).png", in: root)
            _ = try workspace.recordFilter(
                named: "filter-\(index)",
                fileURL: filteredURL,
                pixelSize: CGSize(width: 2048, height: 2048),
                modelID: "test-model",
                prompt: "prompt-\(index)",
                sessionID: UUID(),
                sentSize: CGSize(width: 2048, height: 2048))
            locks.append(try workspace.lock())
        }
        return (source, locks)
    }

    // RT-121.1
    //
    // The reported defect, at the level the graph decides it.
    //
    // **Three locks, and the first is selected.** With two, the selected iteration's parent can
    // coincide with the current base, and the test passes against the unfixed behaviour. With three
    // the correct asset and the wrong one are provably different, which is the whole point.
    @MainActor
    func test_aFilterAfterSelectingAnIterationReadsThatIterationsParent_RT121_1() throws {
        let (workspace, root) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let (source, locks) = try buildChain(of: 3, in: workspace, root: root)

        XCTAssertEqual(workspace.graph.base, locks[2], "the newest lock is the base before selection")

        try workspace.selectIteration(locks[0])

        let filterInput = try workspace.graph.input(for: .filter)
        XCTAssertEqual(
            filterInput, source,
            "a filter after selecting the first iteration must read that iteration's parent")
        XCTAssertNotEqual(
            filterInput, locks[2],
            "the unfixed behaviour reads the newest lock; that is the defect")
    }

    // RT-121.2
    //
    // What the curtain compares, at the level that decides it. AC94.3 and AC90.6 are unchanged as
    // rules — the pair is the candidate and the base it descends from — and selection changes only
    // which assets those are.
    @MainActor
    func test_selectingAnIterationMakesItTheCandidateAgainstItsParent_RT121_2() throws {
        let (workspace, root) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let (source, locks) = try buildChain(of: 3, in: workspace, root: root)

        try workspace.selectIteration(locks[0])

        XCTAssertEqual(workspace.graph.candidate, locks[0], "the selected iteration is the candidate")
        XCTAssertEqual(workspace.graph.base, source, "its parent is the base")
        XCTAssertTrue(workspace.canCompare, "so there are two assets to compare")
    }

    // RT-121.4
    //
    // Locking after a selection extends the chain from where the user is standing, not from the
    // tip. Otherwise selection would be a read-only detour and the whole point of it is to work
    // from an earlier point.
    @MainActor
    func test_lockingAfterSelectingExtendsTheChainFromTheSelectedPoint_RT121_4() throws {
        let (workspace, root) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let (source, locks) = try buildChain(of: 3, in: workspace, root: root)

        try workspace.selectIteration(locks[0])

        let newURL = try writeFixture(named: "filtered-new.png", in: root)
        _ = try workspace.recordFilter(
            named: "filter-new",
            fileURL: newURL,
            pixelSize: CGSize(width: 2048, height: 2048),
            modelID: "test-model",
            prompt: "prompt-new",
            sessionID: UUID(),
            sentSize: CGSize(width: 2048, height: 2048))
        let newLock = try workspace.lock()

        let parent = try workspace.graph.asset(for: newLock).parentID
        XCTAssertEqual(
            parent, try workspace.graph.asset(for: source).id,
            "the new iteration descends from the selected point, not from the tip")
    }

    // RT-121.6
    //
    // AC89.10. The source has no parent, and neither does a raise performed on it, so "the base
    // becomes the selected asset's parent" has no answer for either. This is the case the author
    // actually described — *"clicked back to my original image"*.
    @MainActor
    func test_selectingAnAssetWithNoParentMakesItTheBase_RT121_6() throws {
        let (workspace, root) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let (source, _) = try buildChain(of: 2, in: workspace, root: root)

        try workspace.selectIteration(source)

        XCTAssertEqual(workspace.graph.base, source, "a parentless asset becomes the base itself")
        XCTAssertNil(workspace.graph.candidate, "and there is nothing to compare it against")
        XCTAssertEqual(
            try workspace.graph.input(for: .filter), source,
            "so a filter reads the source, which is what selecting it means")
    }

    // RT-121.7
    //
    // AC89.3, and the finding that made this issue's design amendment incomplete.
    //
    // `lockedIterations` derived the chain by walking back from the **base**. Move the base
    // backwards and every later iteration leaves the strip — which is #111's unreachability
    // returning by a new route, and it passes every test #111 left behind because none of them
    // moves the base.
    @MainActor
    func test_selectingAnEarlierIterationLeavesTheLaterOnesReachable_RT121_7() throws {
        let (workspace, root) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, locks) = try buildChain(of: 3, in: workspace, root: root)

        let before = workspace.lockedIterations.count
        try workspace.selectIteration(locks[0])
        let after = workspace.lockedIterations

        XCTAssertEqual(
            after.count, before,
            "the chain is the tip's lineage, so selecting within it removes nothing")
        for lock in locks {
            XCTAssertTrue(
                after.contains { $0.id == (try? workspace.graph.asset(for: lock).id) },
                "every locked iteration stays reachable after a selection")
        }
    }

    // RT-121.9
    //
    // The other half of the tip, and the direction the old derivation lost. Without this there is
    // no test that a user who scrolled back can get *forward* again.
    //
    // Asserted through the graph's own pointers and then through what a filter would read, because
    // the tip itself is deliberately not public: what AC89.3 is about is the effect.
    @MainActor
    func test_returningToTheNewestIterationRestoresItAsTheWorkingPoint_RT121_9() throws {
        let (workspace, root) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, locks) = try buildChain(of: 3, in: workspace, root: root)

        try workspace.selectIteration(locks[0])
        try workspace.selectIteration(locks[2])

        XCTAssertEqual(workspace.graph.candidate, locks[2], "the newest iteration is selected again")
        XCTAssertEqual(
            try workspace.graph.input(for: .filter), locks[1],
            "and a filter reads its parent, which is the second lock")
    }

    // RT-121.8
    //
    // Guide 2.5 cancels an upscale when the working image changes, and selection changes it. The
    // seam this issue closes is exactly where that gets dropped.
    //
    // Asserted as the observable consequence rather than by catching the cancellation: the suite's
    // fixture finishes faster than a poll can see, which cost #119 four remediation cycles. What
    // matters is that no rendering of the previously-working asset is presented afterwards.
    @MainActor
    func test_selectingAnIterationDiscardsTheOutgoingAssetsRendering_RT121_8() throws {
        let (workspace, root) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, locks) = try buildChain(of: 3, in: workspace, root: root)

        let upscaleURL = try writeFixture(named: "upscaled.png", in: root)
        let upscaled = try workspace.recordUpscale(pixelSize: CGSize(width: 4096, height: 4096))
        try Data([0x00]).write(to: upscaleURL)
        XCTAssertNotNil(upscaled, "the tip has a rendering before the selection")

        try workspace.selectIteration(locks[0])

        let displayed = try XCTUnwrap(workspace.displayedAsset(upscaledWhenAvailable: true))
        XCTAssertEqual(
            displayed, locks[0],
            "the selected iteration is shown, not a rendering of the asset that was working")
    }
}
