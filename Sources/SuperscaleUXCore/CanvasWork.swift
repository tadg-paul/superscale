// ABOUTME: What the canvas reports as happening: any work, named by whichever is under way.
// ABOUTME: The canvas previously watched the local upscale alone, so a paid call ran in silence.

import Foundation

/// What the canvas says is happening.
///
/// The defect this replaces: pressing Apply started a provider call that ran for tens of seconds
/// while the canvas showed nothing at all. The application knew — the status dot and the filter
/// panel both consulted the coordinator — and the one surface the user was looking at did not ask.
///
/// A value rather than an expression inside a `ViewBuilder`, so that "is anything happening, and
/// what" is a question with a tested answer rather than a condition nobody can reach.
public struct CanvasWork: Equatable, Sendable {
    public let isBusy: Bool
    public let message: String

    public init(isBusy: Bool, message: String) {
        self.isBusy = isBusy
        self.message = message
    }

    /// Applying a filter is the slower operation, it is the one that costs money, and it is the one
    /// the user is waiting on — so where both are somehow in flight, it is the one named.
    public static let filterMessage = "Applying filter…"

    public static func of(
        isUpscaling: Bool,
        isApplyingFilter: Bool,
        upscaleMessage: String
    ) -> CanvasWork {
        if isApplyingFilter {
            // Never the upscale's wording: `UpscaleProgressReader` maps kit phases to text, and a
            // provider call has no tiles to count.
            return CanvasWork(isBusy: true, message: filterMessage)
        }
        if isUpscaling {
            return CanvasWork(
                isBusy: true,
                message: upscaleMessage.isEmpty ? "Upscaling…" : upscaleMessage)
        }
        return CanvasWork(isBusy: false, message: "")
    }
}
