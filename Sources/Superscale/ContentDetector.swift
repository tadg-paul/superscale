// ABOUTME: Detects image content type (photo vs illustration) using colour diversity analysis.
// ABOUTME: Uses pixel sampling heuristic + Vision labels to auto-select the best upscaling model.

import CoreGraphics
import Vision

/// Detected content type of an image.
enum ContentType: String, CustomStringConvertible {
    case photo = "photograph"
    case illustration = "illustration"

    var description: String { rawValue }
}

/// Detects image content type to select the best upscaling model.
///
/// Uses a two-stage approach:
/// 1. **Colour diversity** (primary): illustrations have far fewer distinct colours
///    than photographs. Pixels are sampled, quantized to 5 bits per channel, and
///    distinct colours counted. A low ratio of distinct colours to samples indicates
///    illustration content.
/// 2. **Vision labels** (secondary): VNClassifyImageRequest's "illustrations" label
///    catches cases the colour heuristic might miss. Only trusted at high confidence
///    (≥0.5) since it is unreliable for many illustration styles.
enum ContentDetector {

    /// Maximum colour diversity ratio (distinct colours / samples at 6-bit quantization)
    /// for an image to be classified as illustration. Below this → illustration.
    /// Empirical data: photos ≥ 0.39, illustrations ≤ 0.18.
    static let colourDiversityThreshold: Float = 0.28

    /// Minimum confidence for the "illustrations" Vision label.
    static let illustrationLabelThreshold: Float = 0.5

    /// VNClassifyImageRequest label identifiers that indicate illustration/anime content.
    static let illustrationLabels: Set<String> = ["illustrations"]

    /// Maximum number of pixels to sample for colour diversity analysis.
    static let maxSamples = 10_000

    /// Bits per channel for colour quantization (6 bits = 64 levels per channel).
    static let quantizationBits = 6

    /// Detect the content type of an image.
    ///
    /// - Parameter image: The image to classify.
    /// - Returns: Detected content type and confidence score.
    static func detect(image: CGImage) throws -> (type: ContentType, confidence: Float) {
        // Primary: colour diversity analysis
        let diversityRatio = colourDiversityRatio(image: image)
        if diversityRatio < colourDiversityThreshold {
            return (.illustration, 1.0 - diversityRatio)
        }

        // Secondary: Vision framework labels
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        if let observations = request.results {
            let labels = observations.map {
                (identifier: $0.identifier, confidence: $0.confidence)
            }
            let visionResult = interpret(labels: labels)
            if visionResult.type == .illustration {
                return visionResult
            }
        }

        return (.photo, diversityRatio)
    }

    /// Compute the colour diversity ratio for an image.
    ///
    /// Samples pixels, quantizes to reduced bit depth, and counts distinct colours.
    /// Photos produce high ratios (many distinct colours); illustrations produce low
    /// ratios (flat fills, limited palettes).
    ///
    /// - Parameter image: The image to analyse.
    /// - Returns: Ratio of distinct quantized colours to sample count (0.0–1.0).
    static func colourDiversityRatio(image: CGImage) -> Float {
        let width = image.width
        let height = image.height
        let totalPixels = width * height

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return 1.0  // Cannot analyse — assume photo
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let sampleCount = min(totalPixels, maxSamples)
        let step = max(1, totalPixels / sampleCount)
        let shift = 8 - quantizationBits

        var colours = Set<UInt32>()
        var sampledCount = 0

        for i in stride(from: 0, to: totalPixels, by: step) {
            let offset = i * bytesPerPixel
            let r = UInt32(rawData[offset]) >> shift
            let g = UInt32(rawData[offset + 1]) >> shift
            let b = UInt32(rawData[offset + 2]) >> shift
            colours.insert((r << 16) | (g << 8) | b)
            sampledCount += 1
        }

        guard sampledCount > 0 else { return 1.0 }
        return Float(colours.count) / Float(sampledCount)
    }

    /// Interpret Vision classification labels to determine content type.
    ///
    /// Separated from `detect()` for testability — allows testing the
    /// threshold/mapping logic without running VNClassifyImageRequest.
    ///
    /// - Parameter labels: Classification labels with confidence scores.
    /// - Returns: Detected content type and confidence score.
    static func interpret(
        labels: [(identifier: String, confidence: Float)]
    ) -> (type: ContentType, confidence: Float) {
        let maxIllustration = labels
            .filter { illustrationLabels.contains($0.identifier) }
            .map { $0.confidence }
            .max() ?? 0.0

        if maxIllustration >= illustrationLabelThreshold {
            return (.illustration, maxIllustration)
        }
        return (.photo, 1.0 - maxIllustration)
    }

    /// Map a detected content type and scale factor to the best model name.
    ///
    /// - Parameters:
    ///   - contentType: Detected content type.
    ///   - scale: Desired scale factor (2 or 4).
    /// - Returns: CLI model name for ModelRegistry.
    static func modelName(for contentType: ContentType, scale: Int) -> String {
        switch (contentType, scale) {
        case (.illustration, 4):
            return "realesrgan-anime-6b"
        case (.illustration, _):
            // No 2× anime model available — fall back to general 2×
            return "realesrgan-x2plus"
        case (.photo, 2):
            return "realesrgan-x2plus"
        case (.photo, _):
            return "realesrgan-x4plus"
        }
    }
}
