// ABOUTME: Verifies the runner: what starts a run, what supersedes one, and what a stale run may do.
// ABOUTME: Covers the scale selection driving upscales and the state left by runs that do not complete.

import Combine
import CoreGraphics
import Foundation
import XCTest
@testable import SuperscaleUXCore

@MainActor
final class StageRunnerTests: XCTestCase {

    // MARK: - AC82.3 supersession

    // RT-82.7
    func test_aRunSupersededByANewerOneIsCancelled() async throws {
        let harness = try makeHarness()
        await harness.runner.importImage(fileURL: harness.sourceURL, pixelSize: .fixture)
        let first = try await harness.awaitStartedRun()

        await harness.runner.choose(.preset(8))
        _ = try await harness.awaitStartedRun(after: first)

        XCTAssertTrue(harness.runner.isCancelled(first))
    }

    // RT-82.8
    func test_theSupersededRunsOutputIsNotPublishedEvenWhenItFinishesLast() async throws {
        let harness = try makeHarness()
        await harness.runner.importImage(fileURL: harness.sourceURL, pixelSize: .fixture)
        let first = try await harness.awaitStartedRun()
        await harness.runner.choose(.preset(8))
        let second = try await harness.awaitStartedRun(after: first)

        await harness.stage.release(second)
        try await harness.awaitSucceeded()
        await harness.stage.release(first)
        try await harness.settle()

        XCTAssertEqual(harness.runner.currentUpscale?.id, second)
    }

    // RT-82.9
    func test_theNewerRunsOutputIsTheOnePublished() async throws {
        let harness = try makeHarness()
        await harness.runner.importImage(fileURL: harness.sourceURL, pixelSize: .fixture)
        let first = try await harness.awaitStartedRun()
        await harness.runner.choose(.preset(8))
        let second = try await harness.awaitStartedRun(after: first)

        await harness.stage.release(second)
        try await harness.awaitSucceeded()

        XCTAssertEqual(harness.runner.currentUpscale?.id, second)
        XCTAssertNotEqual(harness.runner.currentUpscale?.id, first)
    }

    // RT-82.28
    func test_whenTheNewerRunFailsTheSupersededOutputIsStillNotPublished() async throws {
        let harness = try makeHarness()
        await harness.runner.importImage(fileURL: harness.sourceURL, pixelSize: .fixture)
        let first = try await harness.awaitStartedRun()
        await harness.runner.choose(.preset(8))
        let second = try await harness.awaitStartedRun(after: first)

        await harness.stage.failRun(second, reason: "model unavailable")
        await harness.stage.release(second)
        try await harness.awaitFailed()
        await harness.stage.release(first)
        try await harness.settle()

        XCTAssertNil(harness.runner.currentUpscale)
    }

    // RT-82.36
    func test_progressFromASupersededRunIsNotObserved() async throws {
        let harness = try makeHarness()
        await harness.runner.importImage(fileURL: harness.sourceURL, pixelSize: .fixture)
        let first = try await harness.awaitStartedRun()
        await harness.runner.choose(.preset(8))
        _ = try await harness.awaitStartedRun(after: first)
        let stateBefore = harness.runner.state

        await harness.stage.emitProgress(
            StageProgress(phase: .tiling(completed: 9, total: 9), detail: nil),
            from: first
        )
        try await harness.settle()

        XCTAssertEqual(harness.runner.state, stateBefore)
    }

    // MARK: - AC82.4 a run that does not complete

    // RT-82.10
    func test_aCancelledRunLeavesNoAssetBehind() async throws {
        let harness = try makeHarness()
        await harness.runner.importImage(fileURL: harness.sourceURL, pixelSize: .fixture)
        let run = try await harness.awaitStartedRun()

        harness.runner.cancel()
        try await harness.settle()

        XCTAssertThrowsError(try harness.runner.graph.asset(for: AssetReference(id: run)))
    }

    // RT-82.11
    func test_aFailedRunLeavesNoAssetBehind() async throws {
        let harness = try makeHarness()
        await harness.runner.importImage(fileURL: harness.sourceURL, pixelSize: .fixture)
        let run = try await harness.awaitStartedRun()

        await harness.stage.failRun(run, reason: "disk full")
        await harness.stage.release(run)
        try await harness.awaitFailed()

        XCTAssertThrowsError(try harness.runner.graph.asset(for: AssetReference(id: run)))
    }

    // RT-82.12
    func test_theCurrentOutputIsUnchangedAfterARunThatDidNotComplete() async throws {
        let harness = try makeHarness()
        await harness.runner.importImage(fileURL: harness.sourceURL, pixelSize: .fixture)
        let first = try await harness.awaitStartedRun()
        await harness.stage.release(first)
        try await harness.awaitSucceeded()
        let established = harness.runner.currentUpscale

        await harness.runner.setFaceEnhance(true)
        let second = try await harness.awaitStartedRun(after: first)
        await harness.stage.failRun(second, reason: "disk full")
        await harness.stage.release(second)
        try await harness.awaitFailed()

        XCTAssertEqual(harness.runner.currentUpscale, established)
    }

    // MARK: - AC82.6 an upscale exists only while a scale is selected

    // RT-82.15
    func test_anImageImportedWithNoScaleSelectedLeavesNoUpscaledOutput() async throws {
        let harness = try makeHarness(selection: .off)

        await harness.runner.importImage(fileURL: harness.sourceURL, pixelSize: .fixture)
        try await harness.settle()

        XCTAssertNil(harness.runner.currentUpscale)
        XCTAssertEqual(await harness.stage.startedRuns, [])
    }

    // RT-82.16
    func test_anImageImportedWithAScaleSelectedHasAnUpscaledOutput() async throws {
        let harness = try makeHarness()

        await harness.runner.importImage(fileURL: harness.sourceURL, pixelSize: .fixture)
        let run = try await harness.awaitStartedRun()
        await harness.stage.release(run)
        try await harness.awaitSucceeded()

        XCTAssertEqual(harness.runner.currentUpscale?.id, run)
    }

    // RT-82.17
    func test_selectingAScaleAfterAnImportMadeWithNoneLeavesAnUpscaledOutput() async throws {
        let harness = try makeHarness(selection: .off)
        await harness.runner.importImage(fileURL: harness.sourceURL, pixelSize: .fixture)
        try await harness.settle()

        await harness.runner.choose(.preset(4))
        let run = try await harness.awaitStartedRun()
        await harness.stage.release(run)
        try await harness.awaitSucceeded()

        XCTAssertEqual(harness.runner.currentUpscale?.id, run)
    }

    // RT-82.31
    func test_clearingTheSelectionWhileAnUpscaledOutputExistsReleasesIt() async throws {
        let harness = try makeHarness()
        await harness.runner.importImage(fileURL: harness.sourceURL, pixelSize: .fixture)
        let run = try await harness.awaitStartedRun()
        await harness.stage.release(run)
        try await harness.awaitSucceeded()
        let outputURL = try harness.runner.graph.asset(for: XCTUnwrap(harness.runner.currentUpscale)).fileURL

        await harness.runner.choose(.preset(4))
        try await harness.settle()

        XCTAssertNil(harness.runner.currentUpscale)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    // RT-82.33
    func test_togglingFaceEnhancementWhileTheSelectionIsClearedLeavesNoUpscaledOutput() async throws {
        let harness = try makeHarness(selection: .off)
        await harness.runner.importImage(fileURL: harness.sourceURL, pixelSize: .fixture)

        await harness.runner.setFaceEnhance(true)
        try await harness.settle()

        XCTAssertNil(harness.runner.currentUpscale)
        XCTAssertEqual(await harness.stage.startedRuns, [])
    }

    // RT-82.34
    func test_changingTheModelWhileTheSelectionIsClearedLeavesNoUpscaledOutput() async throws {
        let harness = try makeHarness(selection: .off)
        await harness.runner.importImage(fileURL: harness.sourceURL, pixelSize: .fixture)

        await harness.runner.setModel(named: "realesrgan-x2plus", nativeScale: 2)
        try await harness.settle()

        XCTAssertNil(harness.runner.currentUpscale)
        XCTAssertEqual(await harness.stage.startedRuns, [])
    }

    // MARK: - AC82.2 cancelling something that is not running

    // RT-82.27
    func test_cancellingAStageThatIsNotRunningLeavesItIdle() async throws {
        let harness = try makeHarness(selection: .off)

        harness.runner.cancel()
        try await harness.settle()

        XCTAssertEqual(harness.runner.state, .idle)
    }

    // MARK: - Helpers

    private struct Harness {
        let runner: UpscaleRunner
        let stage: GatedUpscaleStage
        let sourceURL: URL

        /// Waits until a run has started that is not `previous`, and returns its identifier.
        @MainActor
        func awaitStartedRun(after previous: UUID? = nil) async throws -> UUID {
            try await until { started in
                started.last != nil && started.last != previous
            }
        }

        @MainActor
        private func until(
            _ predicate: @escaping ([UUID]) -> Bool
        ) async throws -> UUID {
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                let started = await stage.startedRuns
                if predicate(started), let last = started.last { return last }
                await Task.yield()
            }
            throw HarnessTimeout()
        }

        @MainActor
        func awaitSucceeded() async throws {
            try await awaitState { if case .succeeded = $0 { return true } else { return false } }
        }

        @MainActor
        func awaitFailed() async throws {
            try await awaitState { if case .failed = $0 { return true } else { return false } }
        }

        @MainActor
        private func awaitState(_ predicate: @escaping (StageRunState) -> Bool) async throws {
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                if predicate(runner.state) { return }
                await Task.yield()
            }
            throw HarnessTimeout()
        }

        /// Lets any work the runner has scheduled reach a resting point.
        @MainActor
        func settle() async throws {
            for _ in 0..<200 {
                await Task.yield()
            }
        }
    }

    private struct HarnessTimeout: Error {}

    private func makeHarness(selection: ScaleSelection = .preset(4)) throws -> Harness {
        let scratch = try makeScratch()
        let output = scratch.appendingPathComponent("outputs")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let sourceURL = scratch.appendingPathComponent("source.png")
        try Data("source".utf8).write(to: sourceURL)

        var settings = UpscaleRunSettings.fixture
        settings.selection = selection
        let stage = GatedUpscaleStage()
        return Harness(
            runner: UpscaleRunner(
                stage: stage,
                graph: AssetGraph(outputDirectory: output),
                settings: settings
            ),
            stage: stage,
            sourceURL: sourceURL
        )
    }

    /// A unique directory beneath the operating-system temporary directory, removed in teardown
    /// on success, on failure, and on handled interruption.
    private func makeScratch() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("superscale-runner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: root.path) {
                try FileManager.default.removeItem(at: root)
            }
        }
        return root
    }
}

private extension CGSize {
    static let fixture = CGSize(width: 1024, height: 768)
}
