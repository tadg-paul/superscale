// ABOUTME: Snaps a requested aspect ratio to the nearest one the provider actually offers.
// ABOUTME: Sending an unsupported ratio gets whatever the model defaults to, silently.

import Foundation

/// The aspect ratios the provider accepts, and how to reach the nearest.
///
/// `FAL_REQUEST_REFERENCE.md` records the supported set and that both reference implementations
/// snap to it. Sending something outside it does not produce that shape; it produces whatever the
/// model does instead, which the user did not ask for and is not told about.
public enum FalAspectRatio {
    /// `FAL_REQUEST_REFERENCE.md`: "snapped to a supported set: {9:16, 1:1, 4:3, 16:9}".
    public static let supported = ["9:16", "1:1", "4:3", "16:9"]

    /// The nearest supported ratio to `requested`, and whether that differs from what was asked.
    ///
    /// Nearest by the ratio's *value* rather than by its text, so "2:3" finds "9:16" and not
    /// whichever happens to sort first.
    public static func snap(_ requested: String) -> (sent: String, wasSnapped: Bool) {
        guard let target = value(of: requested) else {
            // Unparseable: send the default rather than guessing at what was meant.
            return (supported[1], requested != supported[1])
        }
        if supported.contains(requested) { return (requested, false) }

        let nearest = supported.min { left, right in
            abs((value(of: left) ?? 0) - target) < abs((value(of: right) ?? 0) - target)
        }
        let sent = nearest ?? supported[1]
        return (sent, sent != requested)
    }

    /// A ratio's numeric value, or nothing where it is not two positive numbers separated by a
    /// colon.
    static func value(of ratio: String) -> Double? {
        let parts = ratio.split(separator: ":")
        guard parts.count == 2,
            let width = Double(parts[0]), let height = Double(parts[1]),
            width > 0, height > 0
        else { return nil }
        return width / height
    }
}
