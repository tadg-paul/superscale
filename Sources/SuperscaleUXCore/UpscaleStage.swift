// ABOUTME: The local upscale as a stage, wrapping SuperscaleKit through the existing seam.
// ABOUTME: Maps the kit's reported phases to the shape both stages share.

import CoreGraphics
import Foundation
import ImageIO
import SuperscaleKit

public struct UpscaleStageOptions: Equatable, Sendable {
    public let modelName: String
    public let faceEnhance: Bool
    public let sizing: GUIUpscaleSizing

    public init(modelName: String, faceEnhance: Bool, sizing: GUIUpscaleSizing) {
        self.modelName = modelName
        self.faceEnhance = faceEnhance
        self.sizing = sizing
    }
}

/// Maps what the kit reports to what a stage observer sees.
///
/// The kit used to report sentences, and this recovered the structure by matching prefixes and
/// splitting on spaces — so rewording "Enhancing 3 faces..." silently broke the face count. The
/// kit now reports phases, and the mapping is case to case with no wording involved.
public enum UpscaleProgressReader {
    public static func progress(for progress: PipelineProgress) -> StageProgress {
        StageProgress(phase: phase(for: progress), detail: progress.description)
    }

    public static func phase(for progress: PipelineProgress) -> StagePhase {
        switch progress {
        case .loading:
            return .loading
        case .inspecting:
            return .inspecting
        case let .split(tiles, _, _):
            // The split announces the work without having completed any of it.
            return .tiling(completed: 0, total: tiles)
        case let .tiling(completed, total):
            return .tiling(completed: completed, total: total)
        case .stitching:
            return .stitching
        case .upscalingAlpha:
            return .upscalingAlpha
        case let .enhancingFaces(count):
            return .enhancingFaces(count: count)
        case .resizing:
            return .resizing
        case .writing:
            return .writing
        case .finished:
            return .finished
        case .warning:
            // A warning is a diagnostic rather than a phase. It reaches the caller with its text
            // so the user still sees it, which is what the unclassified case is for.
            return .unclassified
        }
    }
}

public struct UpscaleStage: Stage, UpscaleStaging {
    private let processor: any GUIUpscaleProcessing

    public init(processor: any GUIUpscaleProcessing = SuperscaleGUIUpscaleProcessor()) {
        self.processor = processor
    }

    public func run(
        input: StageInput,
        output: StageOutputLocation,
        options: UpscaleStageOptions,
        progress: @escaping @Sendable (StageProgress) -> Void
    ) async throws -> StageOutput {
        guard FileManager.default.fileExists(atPath: input.fileURL.path) else {
            throw StageFailure.inputUnavailable(input.fileURL)
        }

        let processed = try await process(input: input, options: options, progress: progress)
        try Task.checkCancellation()
        try write(processed.imageData, to: output.fileURL)

        return StageOutput(
            pixelSize: pixelSize(of: processed.imageData) ?? input.pixelSize,
            resolvedModelName: processed.resolvedModelName,
            wasAutoDetect: processed.wasAutoDetect
        )
    }

    private func process(
        input: StageInput,
        options: UpscaleStageOptions,
        progress: @escaping @Sendable (StageProgress) -> Void
    ) async throws -> GUIUpscaleProcessedImage {
        do {
            return try await processor.process(
                inputURL: input.fileURL,
                options: GUIUpscaleOptions(
                    selectedModelName: options.modelName,
                    faceEnhance: options.faceEnhance,
                    sizing: options.sizing
                ),
                onProgress: { message in
                    progress(UpscaleProgressReader.progress(for: message))
                }
            )
        } catch let failure as StageFailure {
            throw failure
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw StageFailure.processingFailed(stage: "upscale", reason: error.localizedDescription)
        }
    }

    private func write(_ data: Data, to fileURL: URL) throws {
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw StageFailure.outputNotWritten(fileURL)
        }
    }

    private func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return nil
        }
        return CGSize(width: width, height: height)
    }
}
