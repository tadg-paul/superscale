// ABOUTME: The local upscale as a stage, wrapping SuperscaleKit through the existing seam.
// ABOUTME: Recovers structured phases from the kit's wording in one place rather than at each caller.

import CoreGraphics
import Foundation
import ImageIO

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

/// Turns the pipeline's progress sentences into phases.
///
/// The kit reports progress as text, and structured progress inside it is a later change. Until
/// then the coupling to its wording lives here, in one place, rather than in every caller that
/// wants a face count or a tile position.
public enum UpscaleProgressReader {
    public static func progress(for message: String) -> StageProgress {
        StageProgress(phase: phase(for: message), detail: message)
    }

    public static func phase(for message: String) -> StagePhase {
        if message.hasPrefix("Loading ") { return .loading }
        if message.hasPrefix("Input: ") { return .inspecting }
        if message.hasPrefix("Split into ") { return splitPhase(message) }
        if message.hasPrefix("Processing tile ") { return tilePhase(message) }
        if message.hasPrefix("Stitching output") { return .stitching }
        if message.hasPrefix("Upscaling alpha channel") { return .upscalingAlpha }
        if message.hasPrefix("Enhancing ") { return facePhase(message) }
        if message.hasPrefix("Resizing to ") { return .resizing }
        if message.hasPrefix("Writing ") { return .writing }
        if message.hasPrefix("Done: ") { return .finished }
        return .unclassified
    }

    /// "Split into 12 tiles ..." announces the work without having completed any of it.
    private static func splitPhase(_ message: String) -> StagePhase {
        guard let total = firstNumber(in: message) else { return .unclassified }
        return .tiling(completed: 0, total: total)
    }

    /// "Processing tile 3 of 12..."
    private static func tilePhase(_ message: String) -> StagePhase {
        let numbers = allNumbers(in: message)
        guard numbers.count >= 2 else { return .unclassified }
        return .tiling(completed: numbers[0], total: numbers[1])
    }

    /// "Enhancing 2 faces..."
    private static func facePhase(_ message: String) -> StagePhase {
        guard let count = firstNumber(in: message) else { return .unclassified }
        return .enhancingFaces(count: count)
    }

    private static func firstNumber(in message: String) -> Int? {
        allNumbers(in: message).first
    }

    private static func allNumbers(in message: String) -> [Int] {
        message
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
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

        let processed = try process(input: input, options: options, progress: progress)
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
    ) throws -> GUIUpscaleProcessedImage {
        do {
            return try processor.process(
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
