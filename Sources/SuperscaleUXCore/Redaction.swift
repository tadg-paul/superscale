// ABOUTME: Removes supplied secrets from text before it is persisted or attached to provenance.
// ABOUTME: Shared by generation session metadata and asset provenance so both redact identically.

import Foundation

enum Redaction {
    static let placeholder = "[REDACTED]"

    /// Replaces every non-empty secret with the placeholder.
    static func applied(to value: String, secrets: [String]) -> String {
        secrets
            .filter { !$0.isEmpty }
            .reduce(value) { partial, secret in
                partial.replacingOccurrences(of: secret, with: placeholder)
            }
    }
}
