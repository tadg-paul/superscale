// ABOUTME: What the canvas is currently displaying, reported as a value rather than inferred.
// ABOUTME: The suite's completion signal reads this, so two kinds sharing a value would blind it.

import Foundation

/// The kind of picture on the canvas.
///
/// A state a user can see, so it is carried as an `accessibilityValue` rather than left to be
/// inferred from which controls happen to be present. Guide section 3.9 states the rule; this is
/// its sixth application, and the first where a test harness depends on it as well as a reader.
///
/// **The four cases are display states and deliberately do not mirror `AssetRole`.** A base raised
/// to the filterable minimum is a `raisedToMinimum` asset and is still *the base* to somebody
/// looking at it. Mapping one enum onto the other would have the canvas report "raised" at a moment
/// no user would call it that.
public enum CanvasKind: String, Sendable, CaseIterable {
    case nothing
    case base
    case filterResult
    case upscaledRendering

    /// What the accessibility tree reports.
    ///
    /// The four strings are distinct, and RT-117.9 holds them so. `waitForUpscaleComplete`
    /// discriminates on exactly one of them, so two kinds sharing a value would return it on the
    /// wrong state at every one of its call sites.
    public var reportedValue: String {
        switch self {
        case .nothing: return "Nothing"
        case .base: return "The base"
        case .filterResult: return "A filter result"
        case .upscaledRendering: return "An upscaled rendering"
        }
    }

    /// What the canvas is displaying, from the state that decides what it draws.
    ///
    /// - Parameter hasImage: whether there is anything on the canvas at all.
    /// - Parameter showsBase: whether the user has asked to see the base rather than the candidate.
    /// - Parameter hasCandidate: whether a filter has produced a result.
    /// - Parameter hasUpscaledRendering: whether an upscale has **completed** and its rendering is
    ///   in hand. Not whether one is running: AC90.2 keeps the previous picture on the canvas while
    ///   work is in flight, so a kind derived from the request rather than the result would report a
    ///   rendering that is not on screen yet.
    public static func of(
        hasImage: Bool,
        showsBase: Bool,
        hasCandidate: Bool,
        hasUpscaledRendering: Bool
    ) -> CanvasKind {
        guard hasImage else { return .nothing }
        // The base is drawn whole when it is asked for, whatever else exists — the canvas prefers
        // the derivation only when the user has not asked to look past it.
        if showsBase { return .base }
        if hasUpscaledRendering { return .upscaledRendering }
        if hasCandidate { return .filterResult }
        return .base
    }
}
