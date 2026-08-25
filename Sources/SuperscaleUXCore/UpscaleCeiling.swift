// ABOUTME: Bounds an upscale's output by area, because that is what the stitching buffer scales with.
// ABOUTME: Reduces to the largest size that fits and reports the reduction rather than refusing.

import CoreGraphics
import Foundation

/// What an upscale will actually do, once memory has had its say.
public struct UpscaleDecision: Equatable, Sendable {
    /// What the user asked for.
    public let requested: GUIUpscaleSizing
    /// What will run, or nothing when no upscale can fit.
    public let sizing: GUIUpscaleSizing?
    /// The size of the result, or the source's own size when no upscale can fit.
    public let outputSize: CGSize
    /// Whether what runs differs from what was asked for.
    public let wasReduced: Bool

    public init(
        requested: GUIUpscaleSizing, sizing: GUIUpscaleSizing?, outputSize: CGSize,
        wasReduced: Bool
    ) {
        self.requested = requested
        self.sizing = sizing
        self.outputSize = outputSize
        self.wasReduced = wasReduced
    }
}

/// The ceiling on an upscale's output.
///
/// **The unit is area, not edge length.** `Tiler.stitch` holds roughly 36 bytes per output pixel,
/// all resident: a colour accumulator and a weight accumulator across the whole output, plus the
/// output itself. The documented caps were a long edge, which says nothing about area — 8192 × 8192
/// is 67 megapixels and about 2.4 GB, while 8192 × 1000 is 8 megapixels and about 300 MB. One of
/// those is fine and the other kills the process, and a long-edge rule treats them identically. A
/// 2000-pixel-wide picture at 4x produces 8000 on the long edge, which sat between "warn above
/// 4096" and "refuse above 8192": permitted, and fatal.
///
/// **The floor is a different question and is untouched.** The 1024-pixel minimum long edge exists
/// because the provider's model needs enough to work with. A floor expressed as an edge and a
/// ceiling expressed as an area answer different questions, and neither constrains the other.
public enum UpscaleCeiling {

    /// Roughly 1.2 GB of accumulators at 36 bytes per output pixel, which leaves the process, the
    /// Core ML model and the window their room on an 8 GB machine.
    ///
    /// One named constant, revisable, exactly as the minimum long edge is. It covers the stitching
    /// buffer; face enhancement's working set is additional and is recorded as residual risk rather
    /// than accounted for here.
    public static let maximumOutputPixels = 32_000_000

    /// The presets the scale control offers, largest first.
    private static let presets = [8, 4, 2]

    /// What will run for a source of `sourceSize` when `requested` is asked for.
    public static func decide(
        sourceSize: CGSize, requested: GUIUpscaleSizing
    ) -> UpscaleDecision {
        switch requested {
        case let .preset(scale):
            return decidePreset(sourceSize: sourceSize, requestedScale: scale)
        case let .custom(width, height, stretch):
            return decideCustom(
                sourceSize: sourceSize, width: width, height: height, stretch: stretch,
                requested: requested)
        }
    }

    private static func decidePreset(
        sourceSize: CGSize, requestedScale: Int
    ) -> UpscaleDecision {
        let requested = GUIUpscaleSizing.preset(scale: requestedScale)

        // What was asked for, when it already fits. Checked before the ladder rather than through
        // it, so correctness does not depend on the requested scale appearing in `presets`.
        let requestedOutput = CGSize(
            width: sourceSize.width * CGFloat(requestedScale),
            height: sourceSize.height * CGFloat(requestedScale))
        if fits(requestedOutput) {
            return UpscaleDecision(
                requested: requested, sizing: requested, outputSize: requestedOutput,
                wasReduced: false)
        }

        // Largest first, and never above what was asked for: a ceiling reduces, it never enlarges.
        for scale in presets where scale < requestedScale {
            let output = CGSize(
                width: sourceSize.width * CGFloat(scale),
                height: sourceSize.height * CGFloat(scale))
            if fits(output) {
                return UpscaleDecision(
                    requested: requested,
                    sizing: .preset(scale: scale),
                    outputSize: output,
                    wasReduced: true)
            }
        }

        // Nothing fits, not even the smallest step up. The picture is left as it is: there is no
        // upscale small enough to be worth performing, and refusing to allocate beats crashing.
        return UpscaleDecision(
            requested: requested, sizing: nil, outputSize: sourceSize, wasReduced: true)
    }

    private static func decideCustom(
        sourceSize: CGSize, width: Int?, height: Int?, stretch: Bool,
        requested: GUIUpscaleSizing
    ) -> UpscaleDecision {
        let target = customTarget(
            sourceSize: sourceSize, width: width, height: height, stretch: stretch)

        // Nothing was asked for, which is not the same as nothing fitting. A custom selection with
        // no dimensions typed is the existing validation's business, and reporting it here as a
        // memory refusal would tell the user their picture is too large when it is not.
        guard target.width > 0, target.height > 0 else {
            return UpscaleDecision(
                requested: requested, sizing: requested, outputSize: sourceSize, wasReduced: false)
        }

        if fits(target) {
            return UpscaleDecision(
                requested: requested, sizing: requested, outputSize: target, wasReduced: false)
        }

        // Reduced proportionally, so the shape the user asked for survives even though the size
        // does not.
        let ratio = (CGFloat(maximumOutputPixels) / (target.width * target.height)).squareRoot()
        let reduced = CGSize(
            width: (target.width * ratio).rounded(.down),
            height: (target.height * ratio).rounded(.down))

        return UpscaleDecision(
            requested: requested,
            sizing: .custom(width: Int(reduced.width), height: Int(reduced.height), stretch: stretch),
            outputSize: reduced,
            wasReduced: true)
    }

    /// What a custom request actually produces.
    ///
    /// With stretch off the target is fitted inside the requested box at the source's aspect, so
    /// the output differs from what was typed. The ceiling binds that output, not the request,
    /// which is why this is resolved before it is measured.
    private static func customTarget(
        sourceSize: CGSize, width: Int?, height: Int?, stretch: Bool
    ) -> CGSize {
        let requestedWidth = width.map(CGFloat.init)
        let requestedHeight = height.map(CGFloat.init)

        guard sourceSize.width > 0, sourceSize.height > 0 else { return .zero }

        switch (requestedWidth, requestedHeight) {
        case let (.some(w), .some(h)):
            guard !stretch else { return CGSize(width: w, height: h) }
            let scale = min(w / sourceSize.width, h / sourceSize.height)
            return CGSize(
                width: (sourceSize.width * scale).rounded(.down),
                height: (sourceSize.height * scale).rounded(.down))
        case let (.some(w), .none):
            let scale = w / sourceSize.width
            return CGSize(width: w, height: (sourceSize.height * scale).rounded(.down))
        case let (.none, .some(h)):
            let scale = h / sourceSize.height
            return CGSize(width: (sourceSize.width * scale).rounded(.down), height: h)
        case (.none, .none):
            return .zero
        }
    }

    private static func fits(_ size: CGSize) -> Bool {
        size.width * size.height <= CGFloat(maximumOutputPixels)
    }
}
