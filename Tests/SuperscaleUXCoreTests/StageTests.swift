// ABOUTME: Verifies the stage shape: structured progress, one run-state model, one error path.
// ABOUTME: Covers what a stage writes and what it leaves behind when a run does not complete.

import CoreGraphics
import Foundation
import XCTest
@testable import SuperscaleUXCore

final class StageTests: XCTestCase {

    // MARK: - AC82.1 structured progress

    // RT-82.1
    func test_eachReportedPhaseArrivesAsADistinctCase() {
        let reports = [
            "Loading image...",
            "Detecting content type...",
            "Upscaling tile 3 of 12...",
            "Stitching output...",
            "Enhancing 2 faces...",
        ]

        let phases = reports.map { UpscaleProgressReader.phase(for: $0) }

        XCTAssertEqual(phases.count, Set(phases.map(\.discriminator)).count, "phases collapsed together")
        XCTAssertFalse(
            phases.contains(.unclassified),
            "a phase the pipeline reports was absorbed by the catch-all"
        )
    }

    // RT-82.2
    func test_theFaceCountIsAvailableWithoutReadingMessageText() {
        let phase = UpscaleProgressReader.phase(for: "Enhancing 3 faces...")

        XCTAssertEqual(phase, .enhancingFaces(count: 3))
    }

    // RT-82.3
    func test_tileProgressArrivesAsCompletedAndTotalCounts() {
        let phase = UpscaleProgressReader.phase(for: "Upscaling tile 5 of 16...")

        XCTAssertEqual(phase, .tiling(completed: 5, total: 16))
    }

    // RT-82.26
    func test_anUnrecognizedReportStillReachesTheCallerWithItsText() {
        let progress = UpscaleProgressReader.progress(for: "Reticulating splines")

        XCTAssertEqual(progress.phase, .unclassified)
        XCTAssertEqual(progress.detail, "Reticulating splines")
    }

    // MARK: - AC82.2 one run-state model

    // RT-82.4
    func test_eitherStageObservedThroughTheProtocolYieldsTheSameRunStateSequence() async throws {
        let upscale = try await observedStates {
            try await self.runUpscaleStage(processor: StubUpscaleProcessor())
        }
        let filter = try await observedStates {
            try await self.runFilterStage(service: StubFilterService())
        }

        XCTAssertEqual(upscale.map(\.discriminator), filter.map(\.discriminator))
    }

    // RT-82.5
    func test_aFailureInEitherStageArrivesAsAFailedRunStateCarryingTheReason() async throws {
        let upscaleStates = try await observedStates {
            try? await self.runUpscaleStage(processor: StubUpscaleProcessor(failure: "disk full"))
        }
        let filterStates = try await observedStates {
            try? await self.runFilterStage(service: StubFilterService(failure: "gateway timeout"))
        }

        XCTAssertEqual(reason(in: upscaleStates), "disk full")
        XCTAssertEqual(reason(in: filterStates), "gateway timeout")
    }

    // RT-82.6
    func test_aCancellationIsDistinguishableFromAFailure() async throws {
        let states = try await observedStates {
            try? await self.runUpscaleStage(processor: StubUpscaleProcessor(cancels: true))
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
    func test_aRunCancelledAfterWritingLeavesNoFileAtItsAllocatedLocation() async throws {
        let harness = try makeHarness(processor: StubUpscaleProcessor(cancelsAfterWriting: true))
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

    private struct Harness {
        let graph: AssetGraph
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
            var mutable = graph
            let allocation = try mutable.recordUpscale(
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
    private func observedStates(
        _ body: @escaping () async throws -> Void
    ) async throws -> [StageRunState] {
        let recorder = StateRecorder()
        await recorder.record(.idle)
        do {
            try await body()
            await recorder.record(.succeeded(AssetReference(id: UUID())))
        } catch let failure as StageFailure {
            await recorder.record(.failed(failure))
        } catch is CancellationError {
            await recorder.record(.cancelled)
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
        case .detecting: return "detecting"
        case .tiling: return "tiling"
        case .stitching: return "stitching"
        case .enhancingFaces: return "enhancingFaces"
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
