// ABOUTME: Coordinates FAL pricing and account status for GUI presentation.
// ABOUTME: Keeps network lifecycle and actionable failure states outside SwiftUI views.

import Combine
import FalGenerationKit
import Foundation

public protocol GenerationPricingServing: Sendable {
    func pricing(modelID: String, apiKey: String) async throws -> FalPricing
}

public protocol GenerationAccountServing: Sendable {
    func summary(accountKey: String) async throws -> FalAccountSummary
}

public struct FalGenerationPricingService: GenerationPricingServing {
    private let client: FalPricingClient

    public init(client: FalPricingClient = FalPricingClient()) {
        self.client = client
    }

    public func pricing(modelID: String, apiKey: String) async throws -> FalPricing {
        try await client.pricing(modelID: modelID, apiKey: apiKey)
    }
}

public struct FalGenerationAccountService: GenerationAccountServing {
    private let client: FalAccountClient

    public init(client: FalAccountClient = FalAccountClient()) {
        self.client = client
    }

    public func summary(accountKey: String) async throws -> FalAccountSummary {
        try await client.summary(accountKey: accountKey)
    }
}

public enum GenerationPricingState: Equatable, Sendable {
    case idle
    case loading
    case available(FalPricing)
    case unavailable(String)
}

public enum GenerationAccountSummaryState: Equatable, Sendable {
    case idle
    case loading
    case available(FalAccountSummary)
    case unavailable(String)
}

@MainActor
public final class GenerationPricingCoordinator: ObservableObject {
    @Published public private(set) var state: GenerationPricingState = .idle

    private let service: any GenerationPricingServing

    public init(service: any GenerationPricingServing = FalGenerationPricingService()) {
        self.service = service
    }

    public func refresh(modelID: String, apiKey: String) async {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .unavailable("Add a FAL generation key in Settings to check pricing.")
            return
        }
        state = .loading
        do {
            state = .available(try await service.pricing(modelID: modelID, apiKey: apiKey))
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }

    public func reset() {
        state = .idle
    }
}

@MainActor
public final class GenerationAccountCoordinator: ObservableObject {
    @Published public private(set) var state: GenerationAccountSummaryState = .idle

    private let service: any GenerationAccountServing

    public init(service: any GenerationAccountServing = FalGenerationAccountService()) {
        self.service = service
    }

    public func refresh(accountKey: String) async {
        guard !accountKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .unavailable("Add a FAL account/admin key in Settings to load account details.")
            return
        }
        state = .loading
        do {
            state = .available(try await service.summary(accountKey: accountKey))
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }

    public func reset() {
        state = .idle
    }
}
