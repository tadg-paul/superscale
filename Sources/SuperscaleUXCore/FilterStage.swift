// ABOUTME: The cloud filter as a stage, so it reports and fails the same way the local one does.
// ABOUTME: What it sends is settled in the request-construction slices; this gives it the shape.

import CoreGraphics
import Foundation

public struct FilterStageOptions: Equatable, Sendable {
    public let prompt: String
    public let modelID: String

    public init(prompt: String, modelID: String) {
        self.prompt = prompt
        self.modelID = modelID
    }
}

/// The cloud work behind a filter, kept behind a protocol so the stage is testable without
/// network access.
public protocol FilterServicing: Sendable {
    func filter(
        input: URL,
        options: FilterStageOptions,
        progress: @escaping @Sendable (StageProgress) -> Void
    ) async throws -> Data
}

public struct FilterStage: Stage {
    private let service: any FilterServicing

    public init(service: any FilterServicing) {
        self.service = service
    }

    public func run(
        input: StageInput,
        output: StageOutputLocation,
        options: FilterStageOptions,
        progress: @escaping @Sendable (StageProgress) -> Void
    ) async throws -> StageOutput {
        guard FileManager.default.fileExists(atPath: input.fileURL.path) else {
            throw StageFailure.inputUnavailable(input.fileURL)
        }

        let data = try await produce(input: input, options: options, progress: progress)
        try Task.checkCancellation()

        do {
            try data.write(to: output.fileURL, options: .atomic)
        } catch {
            throw StageFailure.outputNotWritten(output.fileURL)
        }

        return StageOutput(
            pixelSize: input.pixelSize,
            resolvedModelName: options.modelID,
            wasAutoDetect: false
        )
    }

    private func produce(
        input: StageInput,
        options: FilterStageOptions,
        progress: @escaping @Sendable (StageProgress) -> Void
    ) async throws -> Data {
        do {
            return try await service.filter(input: input.fileURL, options: options, progress: progress)
        } catch let failure as StageFailure {
            throw failure
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw StageFailure.processingFailed(stage: "filter", reason: error.localizedDescription)
        }
    }
}
