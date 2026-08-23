// ABOUTME: Verifies the stage shape: structured progress, one run-state model, one error path.
// ABOUTME: Covers what a stage writes and what it leaves behind when a run does not complete.

import CoreGraphics
import Foundation
import SuperscaleKit
import XCTest
@testable import SuperscaleUXCore

final class StageTests: XCTestCase {

    // MARK: - AC82.1 structured progress

    // RT-82.1
    //
    // Rewritten against `PipelineProgress` now that the kit reports phases rather than sentences.
    // The criterion is unchanged: a phase is identified as a value, and none of the phases the
    // kit reports is absorbed by the catch-all.
    func test_eachReportedPhaseArrivesAsADistinctCase() {
        let reports: [PipelineProgress] = [
            .loading(fileName: "remy1.png"),
            .inspecting(width: 1024, height: 768, scale: 4),
            .tiling(completed: 3, total: 12),
            .stitching(width: 4096, height: 3072),
            .upscalingAlpha,
            .enhancingFaces(count: 2),
            .resizing(width: 2000, height: 1500),
            .writing(fileName: "remy1_4x.png"),
            .finished(width: 2000, height: 1500, fileName: "remy1_4x.png"),
        ]

        let phases = reports.map { UpscaleProgressReader.phase(for: $0) }

        XCTAssertEqual(
            Set(phases.map(\.discriminator)).count,
            reports.count,
            "two phases the pipeline distinguishes collapsed into one"
        )
        XCTAssertFalse(
            phases.contains(.unclassified),
            "a phase the pipeline reports was absorbed by the catch-all"
        )
    }

    // RT-82.2
    func test_theFaceCountIsAvailableWithoutReadingMessageText() {
        XCTAssertEqual(
            UpscaleProgressReader.phase(for: .enhancingFaces(count: 3)),
            .enhancingFaces(count: 3)
        )
        XCTAssertEqual(
            UpscaleProgressReader.phase(for: .enhancingFaces(count: 1)),
            .enhancingFaces(count: 1)
        )
    }

    // RT-82.3
    func test_tileProgressArrivesAsCompletedAndTotalCounts() {
        XCTAssertEqual(
            UpscaleProgressReader.phase(for: .tiling(completed: 5, total: 16)),
            .tiling(completed: 5, total: 16)
        )
        XCTAssertEqual(
            UpscaleProgressReader.phase(for: .split(tiles: 16, tileSize: 512, overlap: 16)),
            .tiling(completed: 0, total: 16)
        )
    }

    // RT-82.26
    //
    // A warning is a diagnostic rather than a phase, so it has no case of its own — and it must
    // still reach the caller with its text rather than vanishing.
    func test_anUnrecognizedReportStillReachesTheCallerWithItsText() {
        let progress = UpscaleProgressReader.progress(for: .warning("Reticulating splines"))

        XCTAssertEqual(progress.phase, .unclassified)
        XCTAssertEqual(progress.detail, "Reticulating splines")
    }

    // MARK: - AC82.1, extended by #83

    // RT-83.20
    func test_everyPhaseTheKitReportsMapsToADistinctCase_RT083_20() {
        let reports: [PipelineProgress] = [
            .loading(fileName: "a.png"),
            .inspecting(width: 1, height: 1, scale: 1),
            .split(tiles: 4, tileSize: 512, overlap: 16),
            .tiling(completed: 1, total: 4),
            .stitching(width: 1, height: 1),
            .upscalingAlpha,
            .enhancingFaces(count: 1),
            .resizing(width: 1, height: 1),
            .writing(fileName: "a.png"),
            .finished(width: 1, height: 1, fileName: "a.png"),
        ]

        for report in reports {
            XCTAssertNotEqual(
                UpscaleProgressReader.phase(for: report),
                .unclassified,
                "falls through the mapping: \(report)"
            )
        }
    }

    // RT-83.21
    func test_aKitPhaseTheStageDoesNotMapReachesTheCallerAsUnclassified_RT083_21() {
        let progress = UpscaleProgressReader.progress(for: .warning("something new"))

        XCTAssertEqual(progress.phase, .unclassified)
        XCTAssertEqual(
            progress.detail, "something new",
            "an unmapped phase must keep its text rather than being dropped"
        )
    }

    // MARK: - AC82.2 one run-state model

    // RT-82.4
    func test_eitherStageObservedThroughTheProtocolYieldsTheSameRunStateSequence() async throws {
        let upscale = await observedStates {
            try await self.runUpscaleStage(processor: StubUpscaleProcessor())
        }
        let filter = await observedStates {
            try await self.runFilterStage(service: StubFilterService())
        }

        XCTAssertEqual(upscale.map(\.discriminator), filter.map(\.discriminator))
    }

    // RT-82.5
    func test_aFailureInEitherStageArrivesAsAFailedRunStateCarryingTheReason() async throws {
        let upscaleStates = await observedStates {
            try await self.runUpscaleStage(processor: StubUpscaleProcessor(failure: "disk full"))
        }
        let filterStates = await observedStates {
            try await self.runFilterStage(service: StubFilterService(failure: "gateway timeout"))
        }

        XCTAssertEqual(reason(in: upscaleStates), "disk full")
        XCTAssertEqual(reason(in: filterStates), "gateway timeout")
    }

    // RT-82.6
    func test_aCancellationIsDistinguishableFromAFailure() async throws {
        let states = await observedStates {
            try await self.runUpscaleStage(processor: StubUpscaleProcessor(cancels: true))
        }

        XCTAssertTrue(states.contains(.cancelled))
        XCTAssertNil(reason(in: states))
    }

    // MARK: - AC82.5 where a stage writes

    // RT-82.13
    func test_theOutputIsWrittenAtTheAllocatedLocation() async throws {
        let harness = try makeHarness()
        let allocation = try harness.allocateUpscale()

        _ = try await harness.stage.run(
            input: harness.input,
            output: allocation,
            options: .fixture,
            progress: { _ in }
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: allocation.fileURL.path))
    }

    // RT-82.14
    func test_theCompletedRunResolvesToTheAssetTheGraphAllocated() async throws {
        let harness = try makeHarness()
        let allocation = try harness.allocateUpscale()

        _ = try await harness.stage.run(
            input: harness.input,
            output: allocation,
            options: .fixture,
            progress: { _ in }
        )

        XCTAssertEqual(
            try harness.graph.asset(for: allocation.reference).fileURL,
            allocation.fileURL
        )
    }

    // RT-82.35
    func test_aCompletedRunLeavesTheAllocatedOutputAndNothingElse() async throws {
        let harness = try makeHarness()
        let allocation = try harness.allocateUpscale()

        _ = try await harness.stage.run(
            input: harness.input,
            output: allocation,
            options: .fixture,
            progress: { _ in }
        )

        let contents = try FileManager.default.contentsOfDirectory(
            atPath: harness.graph.outputDirectory.path
        )
        XCTAssertEqual(contents, [allocation.fileURL.lastPathComponent])
    }

    // MARK: - AC82.4 a run that does not complete

    // RT-82.29
    //
    // The stage writes once, atomically, after the work returns, so there is no window in which
    // it has written and not completed. A run that does not complete therefore leaves nothing at
    // its location by construction. The other case — a superseded run that keeps working and
    // writes after its allocation was released — is the runner's, not the stage's.
    func test_aRunCancelledAfterWritingLeavesNoFileAtItsAllocatedLocation() async throws {
        let harness = try makeHarness(processor: StubUpscaleProcessor(failsAfterProducing: true))
        let allocation = try harness.allocateUpscale()

        _ = try? await harness.stage.run(
            input: harness.input,
            output: allocation,
            options: .fixture,
            progress: { _ in }
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: allocation.fileURL.path))
    }

    // MARK: - Helpers

    /// A reference type, so an allocation made through it is visible to the assertions afterwards.
    private final class Harness {
        var graph: AssetGraph
        let stage: UpscaleStage
        let input: StageInput
        private let source: AssetReference

        init(graph: AssetGraph, stage: UpscaleStage, input: StageInput, source: AssetReference) {
            self.graph = graph
            self.stage = stage
            self.input = input
            self.source = source
        }

        func allocateUpscale() throws -> StageOutputLocation {
            let allocation = try graph.recordUpscale(
                of: source,
                pixelSize: CGSize(width: 2048, height: 1536),
                fileExtension: "png"
            )
            return StageOutputLocation(reference: allocation.reference, fileURL: allocation.fileURL)
        }
    }

    private func makeHarness(
        processor: StubUpscaleProcessor = StubUpscaleProcessor()
    ) throws -> Harness {
        let scratch = try makeScratch()
        let output = scratch.appendingPathComponent("outputs")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var graph = AssetGraph(outputDirectory: output)
        let sourceURL = scratch.appendingPathComponent("source.png")
        try Data("source".utf8).write(to: sourceURL)
        let source = graph.importSource(fileURL: sourceURL, pixelSize: .init(width: 1024, height: 768))
        return Harness(
            graph: graph,
            stage: UpscaleStage(processor: processor),
            input: StageInput(
                reference: source,
                fileURL: sourceURL,
                pixelSize: CGSize(width: 1024, height: 768)
            ),
            source: source
        )
    }

    /// Drives a stage through a runner-shaped observer and returns every state it published.
    ///
    /// The body's error is caught here rather than at the call site, because the mapping from a
    /// thrown error to a run state is the thing under test.
    private func observedStates(
        _ body: @escaping () async throws -> Void
    ) async -> [StageRunState] {
        let recorder = StateRecorder()
        await recorder.record(.idle)
        do {
            try await body()
            await recorder.record(.succeeded(AssetReference(id: UUID())))
        } catch let failure as StageFailure {
            await recorder.record(.failed(failure))
        } catch is CancellationError {
            await recorder.record(.cancelled)
        } catch {
            await recorder.record(
                .failed(.processingFailed(stage: "unknown", reason: error.localizedDescription))
            )
        }
        return await recorder.states
    }

    private func reason(in states: [StageRunState]) -> String? {
        for state in states {
            if case let .failed(failure) = state, case let .processingFailed(_, reason) = failure {
                return reason
            }
        }
        return nil
    }

    private func runUpscaleStage(processor: StubUpscaleProcessor) async throws {
        let harness = try makeHarness(processor: processor)
        let allocation = try harness.allocateUpscale()
        _ = try await harness.stage.run(
            input: harness.input,
            output: allocation,
            options: .fixture,
            progress: { _ in }
        )
    }

    private func runFilterStage(service: StubFilterService) async throws {
        let scratch = try makeScratch()
        let output = scratch.appendingPathComponent("outputs")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var graph = AssetGraph(outputDirectory: output)
        let sourceURL = scratch.appendingPathComponent("source.png")
        try Data("source".utf8).write(to: sourceURL)
        let source = graph.importSource(fileURL: sourceURL, pixelSize: .init(width: 1024, height: 768))
        let destination = output.appendingPathComponent("filtered.png")
        _ = try await FilterStage(service: service).run(
            input: StageInput(
                reference: source,
                fileURL: sourceURL,
                pixelSize: CGSize(width: 1024, height: 768)
            ),
            output: StageOutputLocation(reference: source, fileURL: destination),
            options: FilterStageOptions(prompt: "warm", modelID: "xai/grok-imagine-image/edit"),
            progress: { _ in }
        )
    }

    /// A unique directory beneath the operating-system temporary directory, removed in teardown
    /// on success, on failure, and on handled interruption.
    private func makeScratch() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("superscale-stage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: root.path) {
                try FileManager.default.removeItem(at: root)
            }
        }
        return root
    }
}

private actor StateRecorder {
    private(set) var states: [StageRunState] = []

    func record(_ state: StageRunState) {
        states.append(state)
    }
}

extension StagePhase {
    /// Identifies the case without its payload, so tests can compare shape rather than values.
    var discriminator: String {
        switch self {
        case .loading: return "loading"
        case .inspecting: return "inspecting"
        case .tiling: return "tiling"
        case .stitching: return "stitching"
        case .upscalingAlpha: return "upscalingAlpha"
        case .enhancingFaces: return "enhancingFaces"
        case .resizing: return "resizing"
        case .writing: return "writing"
        case .finished: return "finished"
        case .uploading: return "uploading"
        case .awaitingModel: return "awaitingModel"
        case .downloading: return "downloading"
        case .unclassified: return "unclassified"
        }
    }
}

extension StageRunState {
    var discriminator: String {
        switch self {
        case .idle: return "idle"
        case .running: return "running"
        case .succeeded: return "succeeded"
        case .cancelled: return "cancelled"
        case .failed: return "failed"
        }
    }
}

extension UpscaleStageOptions {
    static var fixture: UpscaleStageOptions {
        UpscaleStageOptions(modelName: "auto", faceEnhance: false, sizing: .preset(scale: 2))
    }
}
