// ABOUTME: Asks the provider whether a generation key works, using a call that costs nothing.
// ABOUTME: The badge in Settings previously reported storage, so a typo saved and showed a tick.

import Foundation

/// What the provider said about a key.
public enum FalCredentialVerdict: Equatable, Sendable {
    case accepted
    case rejected(reason: String)
    /// The provider could not be reached, so nothing is known.
    ///
    /// Deliberately distinct from `rejected`. "We could not ask" and "the answer was no" look the
    /// same to a caller that collapses them, and the difference is whether the user waits or deletes
    /// a working key.
    case unreachable
}

/// Checks a generation key against the provider.
///
/// **The call is free, and that is a requirement rather than a convenience.** It asks the model
/// catalogue — `GET /v1/models`, which `FAL_REQUEST_REFERENCE.md` lists on the platform host and
/// which the generation key authorizes. The obvious alternative is to submit a generation, which
/// would charge the user 2c to find out whether they typed their key correctly, and twice if they
/// typed it wrongly the first time.
public struct FalCredentialVerifier: Sendable {
    public static let productionBaseURL = URL(string: "https://api.fal.ai")
        ?? URL(fileURLWithPath: "/")

    private let transport: any FalHTTPTransport
    private let baseURL: URL

    public init(
        transport: any FalHTTPTransport = URLSessionFalHTTPTransport(),
        baseURL: URL = FalCredentialVerifier.productionBaseURL
    ) {
        self.transport = transport
        self.baseURL = baseURL
    }

    public func verifyGenerationKey(_ apiKey: String) async -> FalCredentialVerdict {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .rejected(reason: "No key entered.")
        }

        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/models"),
            resolvingAgainstBaseURL: false
        ) else {
            return .unreachable
        }
        components.queryItems = [URLQueryItem(name: "status", value: "active")]
        guard let url = components.url else { return .unreachable }

        var request = URLRequest(url: url)
        // The secret lives only in the header, never in a body, a URL, a log or a persisted record.
        request.setValue("Key \(trimmed)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let response: FalHTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            // A transport failure is not an answer about the key.
            return .unreachable
        }

        switch response.statusCode {
        case 200..<300:
            return .accepted
        case 401, 403:
            return .rejected(reason: "The provider did not accept this key.")
        default:
            return .unreachable
        }
    }
}
