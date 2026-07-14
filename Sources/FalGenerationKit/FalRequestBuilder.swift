// ABOUTME: Builds authenticated FAL requests using model-family payload strategies.
// ABOUTME: Limits references and reports model-specific option reductions before submission.

import Foundation

public struct FalPreparedRequest: Sendable {
    public let urlRequest: URLRequest
    public let warnings: [FalGenerationWarning]

    public init(urlRequest: URLRequest, warnings: [FalGenerationWarning]) {
        self.urlRequest = urlRequest
        self.warnings = warnings
    }
}

public struct FalRequestBuilder: Sendable {
    private let baseURL: URL

    public init(baseURL: URL = URL(string: "https://fal.run")!) {
        self.baseURL = baseURL
    }

    public func prepare(_ request: FalGenerationRequest, apiKey: String) throws -> FalPreparedRequest {
        guard !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FalGenerationError.invalidRequest("A prompt is required.")
        }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FalGenerationError.invalidRequest("A FAL generation key is required.")
        }
        guard request.referenceImageURLs.count <= 3 else {
            throw FalGenerationError.invalidRequest("FAL generation accepts at most three reference images.")
        }

        let handler = try FalModelHandler.handler(for: request.modelID)
        let acceptedReferences = Array(request.referenceImageURLs.prefix(handler.referenceLimit))
        var warnings: [FalGenerationWarning] = []
        if acceptedReferences.count < request.referenceImageURLs.count {
            warnings.append(
                .extraReferencesIgnored(
                    modelID: request.modelID,
                    accepted: handler.referenceLimit,
                    provided: request.referenceImageURLs.count
                )
            )
        }

        var payload: [String: Any] = [
            "prompt": request.prompt,
            "num_images": 1,
            handler.sizingField: request.aspectRatio,
        ]
        if let referenceField = handler.referenceField, !acceptedReferences.isEmpty {
            payload[referenceField] = handler.referenceLimit == 1
                ? acceptedReferences[0]
                : acceptedReferences
        }

        let endpoint = acceptedReferences.isEmpty ? handler.textEndpoint : handler.editEndpoint
        guard let url = URL(string: endpoint, relativeTo: baseURL.appendingPathComponent("/"))?.absoluteURL else {
            throw FalGenerationError.invalidRequest("The FAL endpoint for \(request.modelID) is invalid.")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return FalPreparedRequest(urlRequest: urlRequest, warnings: warnings)
    }
}

private struct FalModelHandler {
    let textEndpoint: String
    let editEndpoint: String
    let referenceField: String?
    let referenceLimit: Int
    let sizingField: String

    static func handler(for modelID: String) throws -> FalModelHandler {
        switch modelID {
        case FalGenerationRequest.defaultModelID:
            return FalModelHandler(
                textEndpoint: modelID,
                editEndpoint: "\(modelID)/edit",
                referenceField: "image_urls",
                referenceLimit: 3,
                sizingField: "aspect_ratio"
            )
        case "fal-ai/flux-pro/kontext":
            return FalModelHandler(
                textEndpoint: modelID,
                editEndpoint: modelID,
                referenceField: "image_url",
                referenceLimit: 1,
                sizingField: "aspect_ratio"
            )
        default:
            throw FalGenerationError.unsupportedModel(modelID)
        }
    }
}
