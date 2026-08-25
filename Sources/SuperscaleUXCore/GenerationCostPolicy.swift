// ABOUTME: The account and availability states the paused pricing surface reports.
// ABOUTME: The cost-confirmation policy that shared this file is removed by #103.

import Foundation

// 🚫 `GenerationCostDecision` and `GenerationCostPolicy` are removed by #103.
//
// `IMPLEMENTATION_GUIDE_v2.md` section 6 takes the cost-confirmation policy out of MVP scope along
// with the pricing and account clients: grok is a known flat rate, held as a documented constant
// beside Apply, so there is no threshold for the application to weigh a cost against. #95 removed
// the control that configured it and the preference that stored it, leaving a type nothing
// consulted — which is a thing a later reader has to prove is dead.
//
// AC76's cost-confirmation criterion is marked superseded in `docs/ACs.md`, and RT-76.5 goes with
// its subject. That test's identifier is retired and not reused.
//
// The policy itself was correct and is preserved in the history of this file, should a second model
// ever make a flat rate untenable.

/// What is known about the account, when the account surface is available at all.
///
/// Retained while `GenerationCloudStatus.swift` still declares the pricing and account service
/// protocols. Removing a protocol's state types while leaving the protocol is a half-removal that
/// reads worse than either whole, and the clients are explicitly out of scope for #99.
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

    /// Generation depends on a key, never on the account surface being reachable.
    public var canGenerate: Bool { generationKeyConfigured }
}
