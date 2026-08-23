// ABOUTME: One shape for local and cloud work, so the app has one progress and cancellation model.
// ABOUTME: A stage reads what the graph resolved and writes to the location the graph allocated.

import CoreGraphics
import Foundation

/// What a run is doing, as a value rather than as prose a caller has to parse.
public enum StagePhase: Equatable, Sendable {
    case loading
    case inspecting
    case tiling(completed: Int, total: Int)
    case stitching
    case upscalingAlpha
    case enhancingFaces(count: Int)
    case resizing
    case writing
    case finished
    case uploading
    case awaitingModel
    case downloading
    /// A report that carries no phase, or one this version cannot classify. It still reaches the
    /// caller with its text, so a message the mapping does not know degrades to plain wording
    /// rather than leaving progress frozen while work continues.
    case unclassified
}

public struct StageProgress: Equatable, Sendable {
    public let phase: StagePhase
    /// Wording for the user. Never parsed to decide anything.
    public let detail: String?

    public init(phase: StagePhase, detail: String? = nil) {
        self.phase = phase
        self.detail = detail
    }
}

public enum StageRunState: Equatable, Sendable {
    case idle
    case running(StageProgress)
    case succeeded(AssetReference)
    case cancelled
    case failed(StageFailure)
}

/// One failure type for both stages. Slice 8 maps the FAL error taxonomy into it; this
/// establishes that there is a single shape to map into.
public enum StageFailure: LocalizedError, Equatable, Sendable {
    case inputUnavailable(URL)
    case processingFailed(stage: String, reason: String)
    case outputNotWritten(URL)

    public var errorDescription: String? {
        switch self {
        case let .inputUnavailable(url):
            return "The image at \(url.lastPathComponent) could not be read."
        case let .processingFailed(stage, reason):
            return "The \(stage) stage failed: \(reason)"
        case let .outputNotWritten(url):
            return "No output was written to \(url.lastPathComponent)."
        }
    }
}

/// What a stage reads. The graph's reference travels with the location so a completion can be
/// recorded against the right asset.
public struct StageInput: Equatable, Sendable {
    public let reference: AssetReference
    public let fileURL: URL
    public let pixelSize: CGSize

    public init(reference: AssetReference, fileURL: URL, pixelSize: CGSize) {
        self.reference = reference
        self.fileURL = fileURL
        self.pixelSize = pixelSize
    }
}

/// Where a stage writes. Allocated by the graph, never chosen by the stage.
public struct StageOutputLocation: Equatable, Sendable {
    public let reference: AssetReference
    public let fileURL: URL

    public init(reference: AssetReference, fileURL: URL) {
        self.reference = reference
        self.fileURL = fileURL
    }
}

public struct StageOutput: Equatable, Sendable {
    public let pixelSize: CGSize
    public let resolvedModelName: String?
    public let wasAutoDetect: Bool

    public init(pixelSize: CGSize, resolvedModelName: String?, wasAutoDetect: Bool) {
        self.pixelSize = pixelSize
        self.resolvedModelName = resolvedModelName
        self.wasAutoDetect = wasAutoDetect
    }
}

/// Local and cloud work take the same shape.
///
/// The stage writes its output to the location it is given and reports what it made. It does not
/// hand bytes back: the image is already held in memory once, and a 4096-pixel output is roughly
/// 50 MB, so returning it would move that buffer again for nothing.
public protocol Stage {
    associatedtype Options

    func run(
        input: StageInput,
        output: StageOutputLocation,
        options: Options,
        progress: @escaping @Sendable (StageProgress) -> Void
    ) async throws -> StageOutput
}

/// The upscale side of `Stage`, named so a runner can hold one without binding to a concrete type.
public protocol UpscaleStaging: Sendable {
    func run(
        input: StageInput,
        output: StageOutputLocation,
        options: UpscaleStageOptions,
        progress: @escaping @Sendable (StageProgress) -> Void
    ) async throws -> StageOutput
}
