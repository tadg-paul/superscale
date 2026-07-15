// ABOUTME: Decides when cloud generation requires explicit cost confirmation.
// ABOUTME: Keeps account visibility independent from generation availability.

import Foundation

public enum GenerationCostDecision: Equatable, Sendable {
    case proceed
    case requireConfirmation
}

public struct GenerationCostPolicy: Equatable, Sendable {
    public let threshold: Double
    public let confirmWhenUnavailable: Bool

    public init(threshold: Double, confirmWhenUnavailable: Bool) {
        self.threshold = threshold
        self.confirmWhenUnavailable = confirmWhenUnavailable
    }

    public func decision(for estimatedCost: Double?) -> GenerationCostDecision {
        guard let estimatedCost else {
            return confirmWhenUnavailable ? .requireConfirmation : .proceed
        }
        return estimatedCost > threshold ? .requireConfirmation : .proceed
    }
}

public enum GenerationAccountState: Equatable, Sendable {
    case unavailable
    case loading
    case available(balance: Double, recentUsage: Double, currency: String)
    case failed(String)
}

public struct GenerationAvailability: Equatable, Sendable {
    public let generationKeyConfigured: Bool
    public let accountState: GenerationAccountState

    public init(generationKeyConfigured: Bool, accountState: GenerationAccountState) {
        self.generationKeyConfigured = generationKeyConfigured
        self.accountState = accountState
    }

    public var canGenerate: Bool { generationKeyConfigured }
}
