// ABOUTME: Coordinates selected and generated image files through one local upscale processor.
// ABOUTME: Adapts GUI options to SuperscaleKit while keeping source handoff independently testable.

import AppKit
import Foundation
import SuperscaleKit

/// The input to a local upscale, together with where it came from.
///
/// The memberwise initializer is deliberately not public. A caller outside this module obtains a
/// source either from the asset graph, from a generation session, or by declaring a file the user
/// supplied directly — so a location chosen for display cannot be submitted for processing.
public struct GUIUpscaleSource: Equatable, Sendable {
    public enum Origin: String, Equatable, Sendable {
        case selectedFile
        case generatedFile
        case graphAsset
    }

    public let origin: Origin
    public let url: URL
    /// The generation session this input belongs to, when it has one. Attribution travels with
    /// the input rather than being held in view state alongside it.
    public let sessionID: UUID?
    public let assetID: UUID?

    init(origin: Origin, url: URL, sessionID: UUID? = nil, assetID: UUID? = nil) {
        self.origin = origin
        self.url = url
        self.sessionID = sessionID
        self.assetID = assetID
    }

    /// A file the user supplied directly, by dropping or choosing it.
    ///
    /// This is the one entry point that accepts a bare location, because a file arriving from
    /// outside the application has no asset to be resolved from.
    public static func imported(_ url: URL) -> GUIUpscaleSource {
        GUIUpscaleSource(origin: .selectedFile, url: url)
    }

    /// Resolves an asset held by the graph, rejecting a reference it does not hold and one that
    /// names an upscaled output.
    public init(resolving reference: AssetReference, in graph: AssetGraph) throws {
        try graph.validateStageInput(reference)
        let asset = try graph.asset(for: reference)
        self.init(
            origin: .graphAsset,
            url: asset.fileURL,
            sessionID: try graph.sessionID(associatedWith: reference),
            assetID: asset.id
        )
    }

    /// The same input, attributed to a generation session.
    public func associating(sessionID: UUID?) -> GUIUpscaleSource {
        GUIUpscaleSource(origin: origin, url: url, sessionID: sessionID, assetID: assetID)
    }
}

public enum GUIUpscaleSizing: Equatable, Sendable {
    case preset(scale: Int)
    case custom(width: Int?, height: Int?, stretch: Bool)
}

public struct GUIUpscaleOptions: Equatable, Sendable {
    public let selectedModelName: String
    public let faceEnhance: Bool
    public let sizing: GUIUpscaleSizing

    public init(selectedModelName: String, faceEnhance: Bool, sizing: GUIUpscaleSizing) {
        self.selectedModelName = selectedModelName
        self.faceEnhance = faceEnhance
        self.sizing = sizing
    }
}

public struct GUIUpscaleProcessedImage: Equatable, Sendable {
    public let imageData: Data
    public let preFaceImageData: Data?
    public let resolvedModelName: String
    public let wasAutoDetect: Bool

    public init(
        imageData: Data,
        preFaceImageData: Data?,
        resolvedModelName: String,
        wasAutoDetect: Bool
    ) {
        self.imageData = imageData
        self.preFaceImageData = preFaceImageData
        self.resolvedModelName = resolvedModelName
        self.wasAutoDetect = wasAutoDetect
    }
}

public struct GUIUpscaleResult: Equatable, Sendable {
    public let source: GUIUpscaleSource
    public let imageData: Data
    public let preFaceImageData: Data?
    public let resolvedModelName: String
    public let wasAutoDetect: Bool
    /// What the ceiling decided, when the source's dimensions were known.
    ///
    /// Carried as a value rather than announced, so the regression pack can assert what the user
    /// will be told. The message is a rendering of this; without it the reporting would live in the
    /// app target, which `make test` does not build.
    public let reduction: UpscaleDecision?
}

public protocol GUIUpscaleProcessing: Sendable {
    /// Asynchronous because the pipeline is lent by an actor. The blocking work runs on that
    /// actor's executor rather than the caller's, so a main-actor caller does not need to
    /// detach a task to stay responsive.
    func process(
        inputURL: URL,
        options: GUIUpscaleOptions,
        onProgress: @escaping @Sendable (PipelineProgress) -> Void
    ) async throws -> GUIUpscaleProcessedImage
}

public struct GUIUpscaleCoordinator: Sendable {
    private let processor: any GUIUpscaleProcessing

    public init(processor: any GUIUpscaleProcessing = SuperscaleGUIUpscaleProcessor()) {
        self.processor = processor
    }

    /// Runs the upscale, within what memory allows.
    ///
    /// `sourceSize` is optional so that a caller which does not know the picture's dimensions still
    /// compiles; the ceiling can only bind when it is supplied, and every caller in the application
    /// supplies it. The decision is applied here rather than in the processor because it is
    /// application policy about what a user may ask for, and `SuperscaleKit` allocates what it is
    /// told to.
    public func process(
        source: GUIUpscaleSource,
        options: GUIUpscaleOptions,
        sourceSize: CGSize? = nil,
        onProgress: @escaping @Sendable (PipelineProgress) -> Void
    ) async throws -> GUIUpscaleResult {
        var options = options
        var decision: UpscaleDecision?

        if let sourceSize {
            let made = UpscaleCeiling.decide(sourceSize: sourceSize, requested: options.sizing)
            decision = made
            guard let permitted = made.sizing else {
                throw UpscaleCeilingError.noScaleFits(
                    sourceSize: sourceSize, requested: options.sizing)
            }
            options = GUIUpscaleOptions(
                selectedModelName: options.selectedModelName,
                faceEnhance: options.faceEnhance,
                sizing: permitted)
        }

        let processed = try await processor.process(
            inputURL: source.url,
            options: options,
            onProgress: onProgress
        )
        return GUIUpscaleResult(
            source: source,
            imageData: processed.imageData,
            preFaceImageData: processed.preFaceImageData,
            resolvedModelName: processed.resolvedModelName,
            wasAutoDetect: processed.wasAutoDetect,
            reduction: decision
        )
    }
}

/// Raised when no upscale of a picture fits within the supported area.
///
/// A refusal rather than a crash. The picture is legitimate; only the operation is impossible, and
/// the caller shows it unchanged with this as the reason.
public enum UpscaleCeilingError: Error, LocalizedError, Equatable {
    case noScaleFits(sourceSize: CGSize, requested: GUIUpscaleSizing)

    public var errorDescription: String? {
        switch self {
        case let .noScaleFits(sourceSize, _):
            let megapixels = (sourceSize.width * sourceSize.height) / 1_000_000
            return String(
                format:
                    "This image is %.0f megapixels, and upscaling it would need more memory than "
                    + "is available. It is shown at its original size.",
                megapixels)
        }
    }
}

/// Holds the pre-face-enhancement image the pipeline reports mid-run, so it survives the closure
/// that receives it without a captured `var` crossing the concurrency boundary.
final class PreFaceCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    var imageData: Data? {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func capture(_ image: CGImage) {
        let encoded = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        lock.lock()
        defer { lock.unlock() }
        data = encoded
    }
}

public struct SuperscaleGUIUpscaleProcessor: GUIUpscaleProcessing {
    private let cache: PipelineCache

    /// Takes its cache rather than reaching for the shared one, so a test can observe which
    /// pipeline a run obtained. A seam a test cannot reach is the seam that breaks.
    public init(cache: PipelineCache = .shared) {
        self.cache = cache
    }

    public func process(
        inputURL: URL,
        options: GUIUpscaleOptions,
        onProgress: @escaping @Sendable (PipelineProgress) -> Void
    ) async throws -> GUIUpscaleProcessedImage {
        let wasAutoDetect = options.selectedModelName == "auto"
        let modelName = try resolvedModelName(inputURL: inputURL, selectedModelName: options.selectedModelName)
        let settings = try PipelineSettings(modelName: modelName, faceEnhance: options.faceEnhance)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscale_gui_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let preFace = PreFaceCapture()
        let sizing = pipelineSizing(for: options.sizing)
        let resolvedModel = try await cache.withPipeline(settings) { pipeline in
            pipeline.onProgress = onProgress
            try pipeline.process(
                input: inputURL,
                output: outputURL,
                requestedScale: sizing.requestedScale,
                targetWidth: sizing.targetWidth,
                targetHeight: sizing.targetHeight,
                stretch: sizing.stretch,
                onPreFaceEnhance: { image in
                    preFace.capture(image)
                }
            )
            return pipeline.modelName
        }

        return GUIUpscaleProcessedImage(
            imageData: try Data(contentsOf: outputURL),
            preFaceImageData: preFace.imageData,
            resolvedModelName: resolvedModel,
            wasAutoDetect: wasAutoDetect
        )
    }

    private func resolvedModelName(inputURL: URL, selectedModelName: String) throws -> String {
        guard selectedModelName == "auto" else { return selectedModelName }
        let loaded = try ImageLoader.load(from: inputURL)
        let (contentType, _) = try ContentDetector.detect(image: loaded.image)
        return ContentDetector.modelName(for: contentType, scale: 4)
    }

    private func pipelineSizing(for sizing: GUIUpscaleSizing) -> PipelineSizing {
        switch sizing {
        case let .preset(scale):
            return PipelineSizing(
                requestedScale: Double(scale),
                targetWidth: nil,
                targetHeight: nil,
                stretch: false
            )
        case let .custom(width, height, stretch):
            return PipelineSizing(
                requestedScale: nil,
                targetWidth: width,
                targetHeight: height,
                stretch: stretch
            )
        }
    }

    private struct PipelineSizing {
        let requestedScale: Double?
        let targetWidth: Int?
        let targetHeight: Int?
        let stretch: Bool
    }
}
