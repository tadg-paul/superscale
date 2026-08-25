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
    private let baseURL: URL?

    public init() {
        self.baseURL = URL(string: "https://fal.run")
    }

    public init(baseURL: URL) {
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

        let isEdit = !acceptedReferences.isEmpty

        var payload: [String: Any] = [
            "prompt": request.prompt,
            "num_images": 1,
        ]
        // Sizing is a property of the endpoint. Grok's edit endpoint rejects it, and a rejected
        // parameter does not produce the sizing asked for — it produces whatever the model does by
        // default, which is one candidate explanation for filtered results coming back square.
        if !isEdit || handler.editAcceptsSizing {
            payload[handler.sizingField] = request.aspectRatio
        }
        if let referenceField = handler.referenceField, isEdit {
            // In the form the field expects: a plural field receives a list, a singular field one
            // value. Grok's `image_urls` takes a list even for a single reference.
            payload[referenceField] = handler.referenceLimit == 1
                ? acceptedReferences[0]
                : acceptedReferences
        }

        let endpoint = isEdit ? handler.editEndpoint : handler.textEndpoint
        guard let baseURL else {
            throw FalGenerationError.invalidRequest("The FAL base URL is invalid.")
        }
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

/// What one model's endpoint expects.
///
/// A value in a table rather than a branch in a `switch`, so that a further model is an entry.
/// Guide 3.6 calls the handler declarative; it was a `switch`, which made "adding a model is a data
/// change" untrue and the test for it unwritable.
struct FalModelHandler: Sendable {
    let textEndpoint: String
    let editEndpoint: String
    let referenceField: String?
    /// How many references the model accepts. A plural field receives a list; a singular field
    /// receives one value.
    let referenceLimit: Int
    let sizingField: String
    /// Whether the *edit* endpoint accepts a sizing parameter.
    ///
    /// Grok's does not, and sent one anyway until this was a property rather than an assumption.
    /// A rejected sizing parameter does not produce the sizing that was asked for; it produces
    /// whatever the model does by default.
    let editAcceptsSizing: Bool

    /// The known models, keyed by identifier.
    ///
    /// `fal-ai/flux-pro/kontext` is here and is *not* selectable. Guide 3.6 keeps the family matrix
    /// deliberately: "knowledge held for later, not work to do now."
    static let table: [String: FalModelHandler] = [
        FalGenerationRequest.defaultModelID: FalModelHandler(
            textEndpoint: FalGenerationRequest.defaultModelID,
            editEndpoint: "\(FalGenerationRequest.defaultModelID)/edit",
            referenceField: "image_urls",
            referenceLimit: 3,
            sizingField: "aspect_ratio",
            editAcceptsSizing: false
        ),
        "fal-ai/flux-pro/kontext": FalModelHandler(
            textEndpoint: "fal-ai/flux-pro/kontext",
            editEndpoint: "fal-ai/flux-pro/kontext",
            referenceField: "image_url",
            referenceLimit: 1,
            sizingField: "aspect_ratio",
            editAcceptsSizing: true
        ),
    ]

    static func handler(for modelID: String) throws -> FalModelHandler {
        guard let handler = table[modelID] else {
            throw FalGenerationError.unsupportedModel(modelID)
        }
        return handler
    }
}
