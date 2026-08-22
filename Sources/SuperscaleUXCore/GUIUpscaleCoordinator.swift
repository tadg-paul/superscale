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
}

public protocol GUIUpscaleProcessing: Sendable {
    func process(
        inputURL: URL,
        options: GUIUpscaleOptions,
        onProgress: @escaping @Sendable (String) -> Void
    ) throws -> GUIUpscaleProcessedImage
}

public struct GUIUpscaleCoordinator: Sendable {
    private let processor: any GUIUpscaleProcessing

    public init(processor: any GUIUpscaleProcessing = SuperscaleGUIUpscaleProcessor()) {
        self.processor = processor
    }

    public func process(
        source: GUIUpscaleSource,
        options: GUIUpscaleOptions,
        onProgress: @escaping @Sendable (String) -> Void
    ) throws -> GUIUpscaleResult {
        let processed = try processor.process(
            inputURL: source.url,
            options: options,
            onProgress: onProgress
        )
        return GUIUpscaleResult(
            source: source,
            imageData: processed.imageData,
            preFaceImageData: processed.preFaceImageData,
            resolvedModelName: processed.resolvedModelName,
            wasAutoDetect: processed.wasAutoDetect
        )
    }
}

public struct SuperscaleGUIUpscaleProcessor: GUIUpscaleProcessing {
    public init() {}

    public func process(
        inputURL: URL,
        options: GUIUpscaleOptions,
        onProgress: @escaping @Sendable (String) -> Void
    ) throws -> GUIUpscaleProcessedImage {
        let wasAutoDetect = options.selectedModelName == "auto"
        let modelName = try resolvedModelName(inputURL: inputURL, selectedModelName: options.selectedModelName)
        let pipeline = try Pipeline(modelName: modelName, faceEnhance: options.faceEnhance)
        pipeline.onProgress = onProgress

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscale_gui_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        var preFaceImageData: Data?
        let sizing = pipelineSizing(for: options.sizing)
        try pipeline.process(
            input: inputURL,
            output: outputURL,
            requestedScale: sizing.requestedScale,
            targetWidth: sizing.targetWidth,
            targetHeight: sizing.targetHeight,
            stretch: sizing.stretch,
            onPreFaceEnhance: { image in
                preFaceImageData = NSBitmapImageRep(cgImage: image)
                    .representation(using: .png, properties: [:])
            }
        )

        return GUIUpscaleProcessedImage(
            imageData: try Data(contentsOf: outputURL),
            preFaceImageData: preFaceImageData,
            resolvedModelName: modelName,
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
