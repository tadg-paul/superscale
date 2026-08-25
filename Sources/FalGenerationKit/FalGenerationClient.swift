// ABOUTME: Submits FAL generation requests and downloads the first returned image.
// ABOUTME: Converts provider and transport failures into redacted, actionable diagnostics.

import Foundation

public struct FalHTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    fileprivate func header(named name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

public protocol FalHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> FalHTTPResponse
}

public struct URLSessionFalHTTPTransport: FalHTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> FalHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FalGenerationError.transportFailure("FAL returned a non-HTTP response.")
        }
        let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            guard let key = entry.key as? String, let value = entry.value as? String else { return }
            result[key] = value
        }
        return FalHTTPResponse(statusCode: httpResponse.statusCode, headers: headers, body: data)
    }
}

public struct FalGenerationClient: Sendable {
    private let transport: any FalHTTPTransport
    private let requestBuilder: FalRequestBuilder

    public init(transport: any FalHTTPTransport = URLSessionFalHTTPTransport()) {
        self.transport = transport
        self.requestBuilder = FalRequestBuilder()
    }

    public init(transport: any FalHTTPTransport = URLSessionFalHTTPTransport(), baseURL: URL) {
        self.transport = transport
        self.requestBuilder = FalRequestBuilder(baseURL: baseURL)
    }

    public func generate(_ request: FalGenerationRequest, apiKey: String) async throws -> FalGeneratedImage {
        let prepared = try requestBuilder.prepare(request, apiKey: apiKey)
        let generationResponse: FalHTTPResponse
        do {
            generationResponse = try await transport.send(prepared.urlRequest)
        } catch let error as FalGenerationError {
            throw error
        } catch {
            throw FalGenerationError.transportFailure(
                FalDiagnosticRedactor.redact(error.localizedDescription, secrets: [apiKey])
            )
        }

        guard (200..<300).contains(generationResponse.statusCode) else {
            throw FalGenerationError.providerFailure(
                statusCode: generationResponse.statusCode,
                diagnostic: FalDiagnosticRedactor.providerDiagnostic(
                    from: generationResponse.body,
                    secrets: [apiKey]
                )
            )
        }

        let response: FalAPIResponse
        do {
            response = try JSONDecoder().decode(FalAPIResponse.self, from: generationResponse.body)
        } catch {
            throw FalGenerationError.malformedResponse("FAL returned an invalid image response.")
        }
        guard let imageURL = response.images.first?.url else {
            throw FalGenerationError.malformedResponse("FAL returned no generated image.")
        }

        let imageResponse: FalHTTPResponse
        do {
            imageResponse = try await transport.send(URLRequest(url: imageURL))
        } catch {
            throw FalGenerationError.downloadFailure(
                FalDiagnosticRedactor.redact(error.localizedDescription, secrets: [apiKey])
            )
        }
        guard (200..<300).contains(imageResponse.statusCode) else {
            throw FalGenerationError.downloadFailure("Image download returned HTTP \(imageResponse.statusCode).")
        }

        return FalGeneratedImage(
            remoteURL: imageURL,
            data: imageResponse.body,
            contentType: imageResponse.header(named: "Content-Type"),
            warnings: prepared.warnings
        )
    }
}

private struct FalAPIResponse: Decodable {
    struct Image: Decodable {
        let url: URL
    }

    let images: [Image]
}

public enum FalGenerationError: LocalizedError, Sendable {
    case invalidRequest(String)
    case unsupportedModel(String)
    case providerFailure(statusCode: Int, diagnostic: String)
    case malformedResponse(String)
    case downloadFailure(String)
    case transportFailure(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidRequest(message):
            return message
        case let .unsupportedModel(modelID):
            return "The FAL model '\(modelID)' is not supported."
        case let .providerFailure(statusCode, diagnostic):
            return "FAL request failed with HTTP \(statusCode): \(diagnostic)"
        case let .malformedResponse(message):
            return message
        case let .downloadFailure(message):
            return "FAL image download failed: \(message)"
        case let .transportFailure(message):
            return "FAL network request failed: \(message)"
        }
    }
}

/// Reads a provider's error body, whichever shape it arrives in, and removes every credential.
///
/// Shared rather than private to one client. `FalPricingClient` had its own smaller version with no
/// nesting, no request identifier and **no redaction**, so an identical failure could surface a key
/// from pricing and not from generation.
enum FalDiagnosticRedactor {
    /// How much of an unreadable body to keep, so an echoed payload cannot flood a diagnostic.
    static let unparseableBodyLimit = 500

    static func redact(_ value: String, secrets: [String]) -> String {
        secrets.filter { !$0.isEmpty }.reduce(value) { result, secret in
            result.replacingOccurrences(of: secret, with: "[REDACTED]")
        }
    }

    static func providerDiagnostic(from data: Data, secrets: [String]) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data),
           let dictionary = object as? [String: Any] {
            let message = stringValue(dictionary["message"])
                ?? detailMessage(dictionary["detail"])
                ?? nestedErrorMessage(dictionary["error"])
                ?? "The provider rejected the request."
            let diagnostic: String
            if let requestID = stringValue(dictionary["request_id"]) {
                diagnostic = "\(message) (request \(requestID))"
            } else {
                diagnostic = message
            }
            return redact(diagnostic, secrets: secrets)
        }

        // Redact *before* truncating. The other order leaves a fragment of any secret straddling
        // the limit, because `redact` replaces whole occurrences and half a key is not one — and a
        // test asserting the key is absent would pass, since the whole key genuinely is.
        let whole = String(data: data, encoding: .utf8) ?? ""
        guard !whole.isEmpty else { return "The provider rejected the request." }
        return String(redact(whole, secrets: secrets).prefix(unparseableBodyLimit))
    }

    /// FastAPI reports validation failures as `detail`, which is a string or a list of objects.
    ///
    /// The list form was falling through to the next envelope and then to a generic sentence,
    /// discarding the only part that said what was actually wrong.
    private static func detailMessage(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        guard let entries = value as? [[String: Any]] else { return stringValue(value) }

        let messages = entries.compactMap { entry in
            stringValue(entry["msg"]) ?? stringValue(entry["message"])
        }
        return messages.isEmpty ? nil : messages.joined(separator: "; ")
    }

    private static func nestedErrorMessage(_ value: Any?) -> String? {
        guard let dictionary = value as? [String: Any] else { return nil }
        return stringValue(dictionary["message"])
    }

    static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        guard let value else { return nil }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return nil
    }
}
