// ABOUTME: Defines provider-neutral generation requests, results, and the MVP model registry.
// ABOUTME: Keeps the selectable v2 model set explicit while allowing later provider registries.

import Foundation

public enum GenerationProvider: String, Sendable {
    case fal
}

public struct GenerationModel: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let provider: GenerationProvider

    public init(id: String, displayName: String, provider: GenerationProvider) {
        self.id = id
        self.displayName = displayName
        self.provider = provider
    }
}

public struct GenerationModelRegistry: Sendable {
    public static let mvp = GenerationModelRegistry(
        defaultModel: GenerationModel(
            id: FalGenerationRequest.defaultModelID,
            displayName: "Grok Imagine Image",
            provider: .fal
        ),
        selectableModels: [
            GenerationModel(
                id: FalGenerationRequest.defaultModelID,
                displayName: "Grok Imagine Image",
                provider: .fal
            ),
        ]
    )

    public let defaultModel: GenerationModel
    public let selectableModels: [GenerationModel]

    public init(defaultModel: GenerationModel, selectableModels: [GenerationModel]) {
        self.defaultModel = defaultModel
        self.selectableModels = selectableModels
    }
}

public struct FalGenerationRequest: Equatable, Sendable {
    public static let defaultModelID = "xai/grok-imagine-image"

    public let prompt: String
    public let modelID: String
    public let aspectRatio: String
    public let referenceImageURLs: [String]

    public init(
        prompt: String,
        modelID: String = FalGenerationRequest.defaultModelID,
        aspectRatio: String = "1:1",
        referenceImageURLs: [String] = []
    ) {
        self.prompt = prompt
        self.modelID = modelID
        self.aspectRatio = aspectRatio
        self.referenceImageURLs = referenceImageURLs
    }
}

public enum FalGenerationWarning: Equatable, Sendable {
    case extraReferencesIgnored(modelID: String, accepted: Int, provided: Int)
    /// The requested aspect ratio is not one the model offers, so the nearest was sent instead.
    ///
    /// Reported rather than applied silently: the user asked for one shape and is getting another,
    /// and dropped references are already reported the same way.
    case aspectRatioSnapped(requested: String, sent: String)
}

public struct FalGeneratedImage: Equatable, Sendable {
    public let remoteURL: URL
    public let data: Data
    public let contentType: String?
    public let warnings: [FalGenerationWarning]

    public init(
        remoteURL: URL,
        data: Data,
        contentType: String?,
        warnings: [FalGenerationWarning]
    ) {
        self.remoteURL = remoteURL
        self.data = data
        self.contentType = contentType
        self.warnings = warnings
    }
}
