// ABOUTME: Whether a credential is absent, stored, verified by the provider, or rejected by it.
// ABOUTME: Green previously meant "saved", so a typo saved and showed a tick.

import Foundation

/// What is known about a credential.
///
/// The badge beside each key read from whether a key was *stored*: paste a typo, press save, and it
/// went green. Green now means the provider accepted it, and the distinction between the two is the
/// point of this type.
///
/// **`stored` is not a failure.** It is what a key looks like before anyone has asked, and what it
/// returns to when the provider cannot be reached. Reporting an unreachable provider as `rejected`
/// would have a user delete a working key — the difference between "we could not ask" and "the
/// answer was no".
public enum CredentialStatus: Equatable, Sendable {
    case absent
    case stored
    case verified
    case rejected(reason: String)

    /// Whether anything is held at all, verified or not.
    public var isPresent: Bool {
        self != .absent
    }

    /// What the badge says, in words.
    ///
    /// Held here rather than in the view because it is the value a test reads and the sentence
    /// VoiceOver speaks, and a state that exists only as a tint reaches neither. A rejection carries
    /// the provider's own reason: "rejected" without one leaves the user guessing between a typo, an
    /// expired key and a key for the wrong account.
    public var badgeDescription: String {
        switch self {
        case .absent:
            return "not configured"
        case .stored:
            return "stored, not checked"
        case .verified:
            return "working"
        case let .rejected(reason):
            return "rejected: \(reason)"
        }
    }

    /// The SF Symbol drawn for this state.
    public var badgeSymbol: String {
        switch self {
        case .absent:
            return "minus.circle"
        case .stored:
            return "questionmark.circle"
        case .verified:
            return "checkmark.circle.fill"
        case .rejected:
            return "exclamationmark.circle.fill"
        }
    }
}
