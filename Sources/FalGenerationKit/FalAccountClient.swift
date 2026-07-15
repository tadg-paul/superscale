// ABOUTME: Queries FAL account balance, usage, and billing events with an admin credential.
// ABOUTME: Keeps privileged account requests separate from generation and pricing operations.

import Foundation

public struct FalBillingEvent: Codable, Equatable, Sendable {
    public let requestID: String
    public let endpointID: String
    public let timestamp: String
    public let outputUnits: Double
    public let unitPrice: Double
    public let costEstimateNanoUSD: Int64

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case endpointID = "endpoint_id"
        case timestamp
        case outputUnits = "output_units"
        case unitPrice = "unit_price"
        case costEstimateNanoUSD = "cost_estimate_nano_usd"
    }
}

public struct FalAccountSummary: Equatable, Sendable {
    public let username: String
    public let balance: Double
    public let currency: String
    public let recentUsageCost: Double
    public let billingEvents: [FalBillingEvent]

    public init(
        username: String,
        balance: Double,
        currency: String,
        recentUsageCost: Double,
        billingEvents: [FalBillingEvent]
    ) {
        self.username = username
        self.balance = balance
        self.currency = currency
        self.recentUsageCost = recentUsageCost
        self.billingEvents = billingEvents
    }
}

public struct FalAccountClient: Sendable {
    public static let productionBaseURL = URL(string: "https://api.fal.ai")
        ?? URL(fileURLWithPath: "/")

    private let transport: any FalHTTPTransport
    private let baseURL: URL

    public init(
        transport: any FalHTTPTransport = URLSessionFalHTTPTransport(),
        baseURL: URL = FalAccountClient.productionBaseURL
    ) {
        self.transport = transport
        self.baseURL = baseURL
    }

    public func summary(accountKey: String) async throws -> FalAccountSummary {
        guard !accountKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FalAccountError.missingCredential
        }
        let billing: AccountBillingResponse = try await get(
            path: "v1/account/billing",
            queryItems: [URLQueryItem(name: "expand", value: "credits")],
            accountKey: accountKey
        )
        let usage: UsageResponse = try await get(
            path: "v1/models/usage",
            queryItems: [URLQueryItem(name: "expand", value: "time_series")],
            accountKey: accountKey
        )
        let events: BillingEventsResponse = try await get(
            path: "v1/models/billing-events",
            queryItems: [URLQueryItem(name: "limit", value: "20")],
            accountKey: accountKey
        )
        let usageCost = usage.timeSeries.flatMap(\.results).reduce(0) { $0 + $1.cost }
        return FalAccountSummary(
            username: billing.username,
            balance: billing.credits.currentBalance,
            currency: billing.credits.currency,
            recentUsageCost: usageCost,
            billingEvents: events.billingEvents
        )
    }

    private func get<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem],
        accountKey: String
    ) async throws -> Response {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw FalAccountError.invalidRequest
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw FalAccountError.invalidRequest }
        var request = URLRequest(url: url)
        request.setValue("Key \(accountKey)", forHTTPHeaderField: "Authorization")

        let response: FalHTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            throw FalAccountError.transportFailure(falRedact(error.localizedDescription, secret: accountKey))
        }
        switch response.statusCode {
        case 200..<300:
            break
        case 401:
            throw FalAccountError.unauthorized
        case 403:
            throw FalAccountError.adminScopeRequired
        default:
            throw FalAccountError.httpFailure(
                statusCode: response.statusCode,
                diagnostic: falDiagnostic(from: response.body, secret: accountKey)
            )
        }
        do {
            return try JSONDecoder().decode(Response.self, from: response.body)
        } catch {
            throw FalAccountError.malformedResponse
        }
    }
}

public enum FalAccountError: LocalizedError, Sendable {
    case missingCredential
    case invalidRequest
    case unauthorized
    case adminScopeRequired
    case malformedResponse
    case httpFailure(statusCode: Int, diagnostic: String)
    case transportFailure(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "A FAL account/admin key is required."
        case .invalidRequest:
            return "The FAL account request could not be created."
        case .unauthorized:
            return "The FAL account key is unauthorized."
        case .adminScopeRequired:
            return "The FAL account key requires Admin scope."
        case .malformedResponse:
            return "FAL returned malformed account data."
        case let .httpFailure(statusCode, diagnostic):
            return "FAL account request failed with HTTP \(statusCode): \(diagnostic)"
        case let .transportFailure(message):
            return "FAL account request failed: \(message)"
        }
    }
}

private struct AccountBillingResponse: Decodable {
    struct Credits: Decodable {
        let currentBalance: Double
        let currency: String

        enum CodingKeys: String, CodingKey {
            case currentBalance = "current_balance"
            case currency
        }
    }

    let username: String
    let credits: Credits
}

private struct UsageResponse: Decodable {
    struct Bucket: Decodable {
        struct Result: Decodable {
            let cost: Double
        }

        let results: [Result]
    }

    let timeSeries: [Bucket]

    enum CodingKeys: String, CodingKey {
        case timeSeries = "time_series"
    }
}

private struct BillingEventsResponse: Decodable {
    let billingEvents: [FalBillingEvent]

    enum CodingKeys: String, CodingKey {
        case billingEvents = "billing_events"
    }
}
