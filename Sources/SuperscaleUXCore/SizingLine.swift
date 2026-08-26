// ABOUTME: The sentence the info panel shows about scale, derived from the ceiling's decision.
// ABOUTME: The panel multiplied input by scale itself and named outputs four times the limit.

import CoreGraphics
import Foundation

/// What the info panel says about scale.
///
/// A pure function over the source size and the selection, so the panel renders a sentence rather
/// than deriving one. It lived in `InfoPanel` as `\(w * scale)×\(h * scale)` and was the **third**
/// private derivation of sizing truth in this application, after two ways of measuring a picture
/// (#100) and an apparent two routes to an upscale (#103). With a 3840×2160 photograph and 8x
/// requested it read *"Scale: 4× → 15360×8640"*: 132 megapixels, over four times the ceiling, and
/// an output nothing was ever going to produce.
///
/// It is here rather than in the view for the reason `StorageRoots` and `ImageDimensions.pixelSize`
/// are: a decision that must agree everywhere has to live somewhere a test can reach.
public enum SizingLine {

    /// The panel's scale sentence.
    ///
    /// - Parameter sourceSize: the picture's own pixel size, or `nil` before one is loaded.
    /// - Parameter definesWidth: for custom sizing without stretch, whether the width is the
    ///   dimension the user is defining.
    public static func of(
        sourceSize: CGSize?,
        selection: ScaleSelection,
        customWidth: String,
        customHeight: String,
        stretch: Bool,
        definesWidth: Bool
    ) -> String {
        switch selection {
        case .off:
            return "Upscaling off — select a scale to upscale this image"

        case let .preset(scale):
            return presetLine(scale: scale, sourceSize: sourceSize, stretch: stretch)

        case .custom:
            return customLine(
                sourceSize: sourceSize, customWidth: customWidth, customHeight: customHeight,
                stretch: stretch, definesWidth: definesWidth)
        }
    }

    private static func presetLine(scale: Int, sourceSize: CGSize?, stretch: Bool) -> String {
        // With no picture there is nothing to judge against the ceiling, so the request is all
        // there is to report. `ScaleReadout` makes the same choice for the same reason.
        guard let sourceSize else { return "Scale: \(scale)×" }

        let readout = ScaleReadout.of(
            sourceSize: sourceSize, selection: .preset(scale),
            customWidth: nil, customHeight: nil, stretch: stretch)

        guard let effective = readout.effective else {
            return "Scale: \(scale)× requested — too large to upscale, so the image is left as it is"
        }
        guard case let .preset(effectiveScale) = effective else {
            return "Scale: \(scale)×"
        }

        let output = dimensions(readout.displayedDimensions)
        if readout.wasReduced {
            return "Scale: \(effectiveScale)× in effect (\(scale)× requested)\(output)"
        }
        return "Scale: \(effectiveScale)×\(output)"
    }

    private static func customLine(
        sourceSize: CGSize?,
        customWidth: String,
        customHeight: String,
        stretch: Bool,
        definesWidth: Bool
    ) -> String {
        let typedWidth = Int(customWidth)
        let typedHeight = Int(customHeight)
        let readout = ScaleReadout.of(
            sourceSize: sourceSize, selection: .custom,
            customWidth: typedWidth, customHeight: typedHeight, stretch: stretch)

        // What the ceiling permits, which is not always what was typed. `ScaleReadout` keeps the
        // two apart as `displayedDimensions` and `requestedDimensions` precisely because they
        // differ, and reporting the typed pair is the same defect one branch along.
        let effective = readout.displayedDimensions
        let reduced = readout.wasReduced

        if stretch {
            guard let effective else { return "Custom: \(customWidth)×\(customHeight) (stretch)" }
            let shown = "\(Int(effective.width))×\(Int(effective.height))"
            if reduced {
                return "Custom: \(shown) in effect (\(customWidth)×\(customHeight) requested, stretch)"
            }
            return "Custom: \(shown) (stretch)"
        }

        if definesWidth, !customWidth.isEmpty {
            if reduced, let effective {
                return "Custom width: \(Int(effective.width))px in effect (\(customWidth)px requested)"
            }
            return "Custom width: \(customWidth)px"
        }
        if !customHeight.isEmpty {
            if reduced, let effective {
                return "Custom height: \(Int(effective.height))px in effect (\(customHeight)px requested)"
            }
            return "Custom height: \(customHeight)px"
        }
        return "Custom resolution: enter width or height"
    }

    private static func dimensions(_ size: CGSize?) -> String {
        guard let size, size != .zero else { return "" }
        return " → \(Int(size.width))×\(Int(size.height))"
    }
}
