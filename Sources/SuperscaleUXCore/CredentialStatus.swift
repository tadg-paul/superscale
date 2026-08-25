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
}
