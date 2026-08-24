// ABOUTME: Decides what the canvas draws: which image, whether progress sits over it, and
// ABOUTME: whether there are two different images for the curtain to compare.

import Foundation

/// An image the canvas can draw, identified rather than carried.
///
/// The decision is about *which* image, not about pixels, so this holds an identity. The view
/// resolves it to something drawable; the rule stays testable without AppKit.
public struct RenderedImage: Equatable, Hashable, Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

/// The two sides of the curtain.
public struct CanvasComparison: Equatable, Sendable {
    public let before: RenderedImage
    public let after: RenderedImage

    public init(before: RenderedImage, after: RenderedImage) {
        self.before = before
        self.after = after
    }
}

/// What the canvas shows.
///
/// One rule, from which the rest follows: **the canvas always shows the base; when an operation
/// has produced something from it, the canvas shows that instead, and the curtain compares the
/// two.** Work in flight changes whether progress is drawn, never which image is drawn — a canvas
/// that empties itself to say it is busy has thrown away the thing the user came for.
public struct CanvasContent: Equatable, Sendable {
    public let image: RenderedImage?
    public let showsProgress: Bool
    public let comparison: CanvasComparison?

    public static func decide(
        base: RenderedImage?,
        derivation: RenderedImage?,
        isWorking: Bool,
        showsBase: Bool
    ) -> CanvasContent {
        // With nothing imported there is nothing to draw, and only then.
        guard let base else {
            return CanvasContent(image: nil, showsProgress: isWorking, comparison: nil)
        }

        // Showing the base is a choice the user made; a derivation existing does not override it.
        let displayed = showsBase ? base : (derivation ?? base)

        // The curtain needs two different things to show. Decided on whether a derivation exists
        // and is what is being displayed, rather than by comparing images.
        let comparison = (!showsBase && derivation != nil)
            ? CanvasComparison(before: base, after: displayed)
            : nil

        return CanvasContent(image: displayed, showsProgress: isWorking, comparison: comparison)
    }

    public init(image: RenderedImage?, showsProgress: Bool, comparison: CanvasComparison?) {
        self.image = image
        self.showsProgress = showsProgress
        self.comparison = comparison
    }
}
