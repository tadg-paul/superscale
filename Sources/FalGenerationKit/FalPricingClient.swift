// ABOUTME: Queries FAL unit pricing and historical per-call cost estimates.
// ABOUTME: Uses the generation credential while keeping pricing failures independently reportable.

import Foundation

public struct FalUnitPrice: Equatable, Sendable {
    public let amount: Double
    public let unit: String
    public let currency: String

    public init(amount: Double, unit: String, currency: String) {
        self.amount = amount
        self.unit = unit
        self.currency = currency
    }
}

public struct FalPricing: Equatable, Sendable {
    public let unitPrice: FalUnitPrice
    public let estimatedCost: Double
    public let currency: String

    public init(unitPrice: FalUnitPrice, estimatedCost: Double, currency: String) {
        self.unitPrice = unitPrice
        self.estimatedCost = estimatedCost
        self.currency = currency
    }
}

public struct FalPricingClient: Sendable {
    public static let productionBaseURL = URL(string: "https://api.fal.ai")
        ?? URL(fileURLWithPath: "/")

    private let transport: any FalHTTPTransport
    private let baseURL: URL

    public init(
        transport: any FalHTTPTransport = URLSessionFalHTTPTransport(),
        baseURL: URL = FalPricingClient.productionBaseURL
    ) {
        self.transport = transport
        self.baseURL = baseURL
    }

    public func pricing(modelID: String, apiKey: String) async throws -> FalPricing {
        try validate(key: apiKey)
        let unitPrice = try await fetchUnitPrice(modelID: modelID, apiKey: apiKey)
        let estimate = try await fetchEstimate(modelID: modelID, apiKey: apiKey)
        return FalPricing(unitPrice: unitPrice, estimatedCost: estimate.amount, currency: estimate.currency)
    }

    private func fetchUnitPrice(modelID: String, apiKey: String) async throws -> FalUnitPrice {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/models/pricing"),
            resolvingAgainstBaseURL: false
        ) else {
            throw FalPricingError.invalidRequest
        }
        components.queryItems = [URLQueryItem(name: "endpoint_id", value: modelID)]
        guard let url = components.url else { throw FalPricingError.invalidRequest }
        var request = URLRequest(url: url)
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        let response = try await send(request, apiKey: apiKey)
        let decoded: PricingResponse
        do {
            decoded = try JSONDecoder().decode(PricingResponse.self, from: response.body)
        } catch {
            throw FalPricingError.malformedResponse
        }
        guard let price = decoded.prices.first else { throw FalPricingError.unavailable }
        return FalUnitPrice(amount: price.unitPrice, unit: price.unit, currency: price.currency)
    }

    private func fetchEstimate(modelID: String, apiKey: String) async throws -> Estimate {
        let url = baseURL.appendingPathComponent("v1/models/pricing/estimate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "estimate_type": "historical_api_price",
            "endpoints": [modelID: ["call_quantity": 1]],
        ])
        let response = try await send(request, apiKey: apiKey)
        do {
            let decoded = try JSONDecoder().decode(EstimateResponse.self, from: response.body)
            return Estimate(amount: decoded.totalCost, currency: decoded.currency)
        } catch {
            throw FalPricingError.malformedResponse
        }
    }

    private func send(_ request: URLRequest, apiKey: String) async throws -> FalHTTPResponse {
        let response: FalHTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            throw FalPricingError.transportFailure(
                falRedact(error.localizedDescription, secrets: [apiKey]))
        }
        guard (200..<300).contains(response.statusCode) else {
            throw FalPricingError.httpFailure(
                statusCode: response.statusCode,
                diagnostic: falDiagnostic(from: response.body, secrets: [apiKey])
            )
        }
        return response
    }

    private func validate(key: String) throws {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FalPricingError.missingCredential
        }
    }
}

public enum FalPricingError: LocalizedError, Sendable {
    case missingCredential
    case invalidRequest
    case unavailable
    case malformedResponse
    case httpFailure(statusCode: Int, diagnostic: String)
    case transportFailure(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "A FAL generation key is required for pricing."
        case .invalidRequest:
            return "The FAL pricing request could not be created."
        case .unavailable:
            return "FAL pricing is unavailable for this model."
        case .malformedResponse:
            return "FAL returned malformed pricing data."
        case let .httpFailure(statusCode, diagnostic):
            return "FAL pricing failed with HTTP \(statusCode): \(diagnostic)"
        case let .transportFailure(message):
            return "FAL pricing request failed: \(message)"
        }
    }
}

private struct PricingResponse: Decodable {
    struct Price: Decodable {
        let unitPrice: Double
        let unit: String
        let currency: String

        enum CodingKeys: String, CodingKey {
            case unitPrice = "unit_price"
            case unit
            case currency
        }
    }

    let prices: [Price]
}

private struct EstimateResponse: Decodable {
    let totalCost: Double
    let currency: String

    enum CodingKeys: String, CodingKey {
        case totalCost = "total_cost"
        case currency
    }
}

private struct Estimate {
    let amount: Double
    let currency: String
}

/// Reads a provider failure through the shared parser.
///
/// This was a smaller reimplementation: `message` or `detail`, no nesting, no request identifier
/// and — because it took a single `secret` — no protection for the other credential. An identical
/// body could therefore surface a key from pricing and not from generation.
///
/// `secrets` takes every credential the application holds, not the one the failing call used.
func falDiagnostic(from data: Data, secrets: [String]) -> String {
    FalDiagnosticRedactor.providerDiagnostic(from: data, secrets: secrets)
}

func falRedact(_ value: String, secrets: [String]) -> String {
    FalDiagnosticRedactor.redact(value, secrets: secrets)
}
