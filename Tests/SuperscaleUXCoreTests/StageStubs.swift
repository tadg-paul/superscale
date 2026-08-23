// ABOUTME: Stub stages and processors shared by the stage and runner tests.
// ABOUTME: Let a run be held open, failed, or cancelled on demand without Core ML or network.

import CoreGraphics
import Foundation
@testable import SuperscaleUXCore

/// A local upscale processor whose behaviour each test chooses.
final class StubUpscaleProcessor: GUIUpscaleProcessing, @unchecked Sendable {
    let reports: [String]
    private let failure: String?
    private let cancels: Bool
    private let cancelsAfterWriting: Bool

    init(
        reports: [String] = [],
        failure: String? = nil,
        cancels: Bool = false,
        cancelsAfterWriting: Bool = false
    ) {
        self.reports = reports
        self.failure = failure
        self.cancels = cancels
        self.cancelsAfterWriting = cancelsAfterWriting
    }

    func process(
        inputURL: URL,
        options: GUIUpscaleOptions,
        onProgress: @escaping @Sendable (String) -> Void
    ) throws -> GUIUpscaleProcessedImage {
        for report in reports {
            onProgress(report)
        }
        if cancels {
            throw CancellationError()
        }
        if let failure {
            throw StageFailure.processingFailed(stage: "upscale", reason: failure)
        }
        if cancelsAfterWriting {
            throw StubCancellationAfterWriting()
        }
        return GUIUpscaleProcessedImage(
            imageData: Data("upscaled".utf8),
            preFaceImageData: nil,
            resolvedModelName: "realesrgan-x2plus",
            wasAutoDetect: false
        )
    }
}

/// Signals that the processor produced bytes and was then cancelled, so the stage has something
/// to clean up at the allocated location.
struct StubCancellationAfterWriting: Error {}

/// A cloud filter service whose behaviour each test chooses.
struct StubFilterService: FilterServicing {
    var failure: String?

    init(failure: String? = nil) {
        self.failure = failure
    }

    func filter(
        input: URL,
        options: FilterStageOptions,
        progress: @Sendable (StageProgress) -> Void
    ) async throws -> Data {
        progress(StageProgress(phase: .uploading, detail: nil))
        progress(StageProgress(phase: .awaitingModel, detail: nil))
        if let failure {
            throw StageFailure.processingFailed(stage: "filter", reason: failure)
        }
        progress(StageProgress(phase: .downloading, detail: nil))
        return Data("filtered".utf8)
    }
}

/// An upscale stage a test can hold open, so supersession can be arranged deterministically.
actor GatedUpscaleStage: UpscaleStaging {
    private var gates: [UUID: CheckedContinuation<Void, Error>] = [:]
    private(set) var startedRuns: [UUID] = []
    private var pendingProgress: [UUID: [StageProgress]] = [:]
    private var observers: [UUID: @Sendable (StageProgress) -> Void] = [:]
    private var failures: [UUID: String] = [:]

    /// Fails the run for the given output reference rather than completing it.
    func failRun(_ id: UUID, reason: String) {
        failures[id] = reason
    }

    func run(
        input: StageInput,
        output: StageOutputLocation,
        options: UpscaleStageOptions,
        progress: @escaping @Sendable (StageProgress) -> Void
    ) async throws -> StageOutput {
        let id = output.reference.id
        startedRuns.append(id)
        observers[id] = progress
        try await withCheckedThrowingContinuation { continuation in
            gates[id] = continuation
        }
        if let reason = failures[id] {
            throw StageFailure.processingFailed(stage: "upscale", reason: reason)
        }
        try Data("upscaled".utf8).write(to: output.fileURL, options: .atomic)
        return StageOutput(
            pixelSize: CGSize(width: 2048, height: 1536),
            resolvedModelName: "realesrgan-x2plus",
            wasAutoDetect: false
        )
    }

    /// Lets the run for the given output reference finish.
    func release(_ id: UUID) {
        guard let continuation = gates.removeValue(forKey: id) else { return }
        continuation.resume()
    }

    /// Emits a progress report from the run for the given output reference.
    func emitProgress(_ progress: StageProgress, from id: UUID) {
        observers[id]?(progress)
    }

    func hasStarted(_ id: UUID) -> Bool {
        startedRuns.contains(id)
    }
}
