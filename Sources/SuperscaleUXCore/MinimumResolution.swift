// ABOUTME: The smallest picture a filter can work from, and how to raise one that falls short.
// ABOUTME: Documented since the guide was written and never enforced, so undersized images went as-is.

import CoreGraphics
import Foundation

/// What raising a picture to the filterable minimum comes to.
public struct MinimumResolutionDecision: Equatable, Sendable {
    /// The scale to upscale by, or nothing where the picture already suffices.
    public let scale: Int?
    /// The size the picture will be afterwards.
    public let resultingSize: CGSize
    /// Whether the result still falls short of the minimum.
    ///
    /// The scale control offers 2x, 4x and 8x, so a 50-pixel picture reaches 400 and no further.
    /// The picture is legitimate; only reaching the floor is impossible, and the user is told the
    /// provider may alter it rather than being refused outright.
    public let stillBelowMinimum: Bool

    public var wasRaised: Bool { scale != nil }

    /// What the user is told, or nothing where nothing happened.
    ///
    /// Two sentences, because there are two situations and they set different expectations. A
    /// picture that reaches the floor is simply reported: the application upscaled it and says so,
    /// rather than silently altering the user's photograph before sending it. A picture that cannot
    /// reach the floor at any scale the control offers is raised as far as it goes and the user is
    /// warned the provider may reshape it — the reduce-and-tell posture the memory ceiling takes in
    /// the other direction, and the fact behind the report that produced this issue.
    public var report: String? {
        guard wasRaised else { return nil }
        let width = Int(resultingSize.width.rounded())
        let height = Int(resultingSize.height.rounded())
        let floor = Int(MinimumResolution.longEdge)

        if stillBelowMinimum {
            return "Upscaled to \(width) x \(height), the largest available. "
                + "That is still below the \(floor)-pixel minimum, "
                + "so the filter may change the picture's shape."
        }
        return "Upscaled to \(width) x \(height) to meet the "
            + "\(floor)-pixel minimum for filtering."
    }
}

/// The floor beneath which a filter has too little to work with.
///
/// **1024 pixels on the long edge**, held in one place and open to revision. Guide 2.5 is explicit
/// that this is an assumption rather than a published figure: FAL documents no minimum per model,
/// and the supporting evidence is indirect — `pix` maps its aspect presets to sizes around
/// 1536x1024, and `storyboard-gen` prices at roughly one megapixel, which 1024x1024 matches.
///
/// Long edge rather than a width and a height, so portrait, landscape and square are covered without
/// baking in an aspect ratio.
public enum MinimumResolution {
    public static let longEdge: CGFloat = 1024

    /// The presets the scale control offers, smallest first: the least upscale that clears the floor
    /// is the one to use.
    private static let presets = [2, 4, 8]

    public static func decide(sourceSize: CGSize) -> MinimumResolutionDecision {
        let longest = max(sourceSize.width, sourceSize.height)

        guard longest > 0 else {
            return MinimumResolutionDecision(
                scale: nil, resultingSize: sourceSize, stillBelowMinimum: true)
        }

        guard longest < longEdge else {
            return MinimumResolutionDecision(
                scale: nil, resultingSize: sourceSize, stillBelowMinimum: false)
        }

        for scale in presets {
            let raised = CGSize(
                width: sourceSize.width * CGFloat(scale),
                height: sourceSize.height * CGFloat(scale))
            if max(raised.width, raised.height) >= longEdge {
                return MinimumResolutionDecision(
                    scale: scale, resultingSize: raised, stillBelowMinimum: false)
            }
        }

        // Nothing on offer reaches the floor. Raise as far as it goes and say so: a picture the
        // provider may reshape is more use than a refusal, which is the same posture the memory
        // ceiling takes in the other direction.
        let largest = presets[presets.count - 1]
        let raised = CGSize(
            width: sourceSize.width * CGFloat(largest),
            height: sourceSize.height * CGFloat(largest))
        return MinimumResolutionDecision(
            scale: largest, resultingSize: raised, stillBelowMinimum: true)
    }
}
