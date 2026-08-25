// ABOUTME: What kind of failure this is, so a caller can decide what to do without knowing who raised it.
// ABOUTME: Three clients raised three unrelated enums, and callers matched on all of them.

import Foundation

/// What sort of thing went wrong.
///
/// Each client raises its own error type — `FalGenerationError`, `FalPricingError`,
/// `FalAccountError` — so a caller asking "is this worth retrying, or is it the user's to fix"
/// had to match on three unrelated enums. This is the question they were all being asked.
public enum FalFailureKind: Equatable, Sendable {
    /// The credential is missing, or the provider would not accept it. The user can fix this.
    case credential
    /// The request was malformed or asked for something unsupported. Retrying it unchanged will
    /// fail again.
    case request
    /// The provider failed on its own side. Retrying later may work.
    case provider
    /// The provider could not be reached at all. Nothing is known about the request.
    case transport
}

/// A failure, classified, **without losing what the provider said**.
///
/// The classification is added to the diagnostic rather than replacing it. A taxonomy that turned
/// "the model rejected that aspect ratio" into "request error" would be worse than no taxonomy: the
/// category tells the caller what to do, and the words tell the user what happened.
public struct FalFailure: LocalizedError, Equatable, Sendable {
    public let kind: FalFailureKind
    public let diagnostic: String

    public init(kind: FalFailureKind, diagnostic: String) {
        self.kind = kind
        self.diagnostic = diagnostic
    }

    public var errorDescription: String? { diagnostic }

    /// Whether the user can do something about this themselves.
    public var isUserActionable: Bool {
        kind == .credential
    }

    /// Whether trying the same thing again might succeed.
    public var isWorthRetrying: Bool {
        kind == .provider || kind == .transport
    }

    /// Classifies by the status the provider returned.
    ///
    /// 401 and 403 are the credential; 4xx otherwise is the request; 5xx is the provider.
    public static func fromStatus(_ statusCode: Int, diagnostic: String) -> FalFailure {
        let kind: FalFailureKind
        switch statusCode {
        case 401, 403:
            kind = .credential
        case 400..<500:
            kind = .request
        default:
            kind = .provider
        }
        return FalFailure(kind: kind, diagnostic: diagnostic)
    }

    /// A failure to reach the provider at all.
    public static func unreachable(diagnostic: String) -> FalFailure {
        FalFailure(kind: .transport, diagnostic: diagnostic)
    }
}
