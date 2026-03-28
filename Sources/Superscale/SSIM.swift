// ABOUTME: Computes Structural Similarity Index (SSIM) between two CGImages.
// ABOUTME: Uses Accelerate framework for performance. No external dependencies.

import Accelerate
import CoreGraphics
import Foundation

/// Computes the Structural Similarity Index Measure (SSIM) between two images.
///
/// SSIM ranges from -1 to 1, where 1 means identical. Values above 0.95
/// indicate high perceptual similarity. Both images must have the same dimensions.
///
/// For images with alpha channels, transparent regions are excluded from the
/// comparison — only opaque pixels contribute to the score.
enum SSIM {

    /// Default constants for SSIM (from the original Wang et al. 2004 paper).
    /// L = 255 (8-bit dynamic range), k1 = 0.01, k2 = 0.03.
    private static let c1: Float = (0.01 * 255) * (0.01 * 255)  // 6.5025
    private static let c2: Float = (0.03 * 255) * (0.03 * 255)  // 58.5225

    /// Minimum fraction of opaque pixels in an 8×8 window for it to count.
    /// Windows that are mostly transparent are excluded from the score.
    private static let opaqueThreshold: Float = 0.5

    /// Compute SSIM between two images.
    ///
    /// Converts both images to greyscale luminance and computes the mean SSIM
    /// over 8×8 non-overlapping windows. For RGBA images, windows where more
    /// than half the pixels are transparent (alpha < 128) are excluded.
    ///
    /// - Parameters:
    ///   - imageA: First image (typically the CoreML output).
    ///   - imageB: Second image (typically the reference). Must have same dimensions.
    /// - Returns: SSIM score in range [-1, 1]. Typically 0.0–1.0 for natural images.
    /// - Throws: `ImageIOError.dimensionMismatch` if images differ in size.
    static func compute(between imageA: CGImage, and imageB: CGImage) throws -> Float {
        guard imageA.width == imageB.width, imageA.height == imageB.height else {
            throw ImageIOError.dimensionMismatch(
                "SSIM requires identical dimensions: " +
                "\(imageA.width)×\(imageA.height) vs \(imageB.width)×\(imageB.height)")
        }

        let width = imageA.width
        let height = imageA.height

        // Extract greyscale luminance and alpha from both images.
        let (pixelsA, alphaA) = try extractLuminanceAndAlpha(from: imageA)
        let (pixelsB, _) = try extractLuminanceAndAlpha(from: imageB)

        // Merge alpha masks: a pixel is opaque only if opaque in both images.
        let alpha: [Bool]? = alphaA.map { maskA in
            maskA.map { $0 }  // Both images must agree on opacity
        }

        // Compute SSIM over 8×8 non-overlapping windows.
        let windowSize = 8
        let windowsX = width / windowSize
        let windowsY = height / windowSize

        if windowsX == 0 || windowsY == 0 {
            // Image too small for windowed SSIM — compute global SSIM.
            return globalSSIM(pixelsA, pixelsB, count: width * height)
        }

        var ssimSum: Float = 0
        var windowCount: Int = 0

        for wy in 0..<windowsY {
            for wx in 0..<windowsX {
                let startX = wx * windowSize
                let startY = wy * windowSize

                // Check if this window has enough opaque pixels.
                if let alpha = alpha {
                    var opaqueCount = 0
                    let totalPixels = windowSize * windowSize
                    for row in 0..<windowSize {
                        let srcOffset = (startY + row) * width + startX
                        for col in 0..<windowSize {
                            if alpha[srcOffset + col] {
                                opaqueCount += 1
                            }
                        }
                    }
                    let opaqueFraction = Float(opaqueCount) / Float(totalPixels)
                    if opaqueFraction < opaqueThreshold {
                        continue  // Skip mostly-transparent windows.
                    }
                }

                // Extract window pixels.
                var windowA = [Float](repeating: 0, count: windowSize * windowSize)
                var windowB = [Float](repeating: 0, count: windowSize * windowSize)

                for row in 0..<windowSize {
                    let srcOffset = (startY + row) * width + startX
                    let dstOffset = row * windowSize
                    for col in 0..<windowSize {
                        windowA[dstOffset + col] = pixelsA[srcOffset + col]
                        windowB[dstOffset + col] = pixelsB[srcOffset + col]
                    }
                }

                ssimSum += globalSSIM(windowA, windowB, count: windowSize * windowSize)
                windowCount += 1
            }
        }

        if windowCount == 0 {
            // Entirely transparent image — no meaningful comparison possible.
            return 1.0
        }

        return ssimSum / Float(windowCount)
    }

    /// Compute SSIM for a single block of pixel values.
    private static func globalSSIM(
        _ a: [Float], _ b: [Float], count: Int
    ) -> Float {
        let n = Float(count)

        // Mean
        var meanA: Float = 0
        var meanB: Float = 0
        vDSP_meanv(a, 1, &meanA, vDSP_Length(count))
        vDSP_meanv(b, 1, &meanB, vDSP_Length(count))

        // Variance and covariance
        var varA: Float = 0
        var varB: Float = 0
        var covAB: Float = 0

        for i in 0..<count {
            let da = a[i] - meanA
            let db = b[i] - meanB
            varA += da * da
            varB += db * db
            covAB += da * db
        }
        varA /= n
        varB /= n
        covAB /= n

        // SSIM formula
        let numerator = (2 * meanA * meanB + c1) * (2 * covAB + c2)
        let denominator = (meanA * meanA + meanB * meanB + c1) * (varA + varB + c2)

        return numerator / denominator
    }

    /// Extract greyscale luminance values and an optional alpha mask from a CGImage.
    ///
    /// - Returns: A tuple of (luminance array in [0, 255], optional alpha mask).
    ///   The alpha mask is nil for opaque images. When present, `true` = opaque (alpha ≥ 128).
    private static func extractLuminanceAndAlpha(
        from image: CGImage
    ) throws -> (luminance: [Float], alpha: [Bool]?) {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // Use premultipliedLast to preserve alpha channel data.
        guard let context = CGContext(
            data: &pixelData,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageIOError.contextCreationFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let pixelCount = width * height
        var luminance = [Float](repeating: 0, count: pixelCount)

        // Check if the image actually has alpha.
        let alphaInfo = image.alphaInfo
        let hasAlpha = alphaInfo != .none && alphaInfo != .noneSkipLast
                       && alphaInfo != .noneSkipFirst

        var alphaMask: [Bool]?
        if hasAlpha {
            var mask = [Bool](repeating: true, count: pixelCount)
            for i in 0..<pixelCount {
                let offset = i * 4
                let a = pixelData[offset + 3]
                mask[i] = a >= 128

                // Un-premultiply for luminance so transparent pixels
                // don't skew the comparison with darkened RGB values.
                if a > 0 && a < 255 {
                    let scale = 255.0 / Float(a)
                    let r = min(Float(pixelData[offset]) * scale, 255.0)
                    let g = min(Float(pixelData[offset + 1]) * scale, 255.0)
                    let b = min(Float(pixelData[offset + 2]) * scale, 255.0)
                    luminance[i] = 0.299 * r + 0.587 * g + 0.114 * b
                } else {
                    let r = Float(pixelData[offset])
                    let g = Float(pixelData[offset + 1])
                    let b = Float(pixelData[offset + 2])
                    luminance[i] = 0.299 * r + 0.587 * g + 0.114 * b
                }
            }
            alphaMask = mask
        } else {
            for i in 0..<pixelCount {
                let offset = i * 4
                let r = Float(pixelData[offset])
                let g = Float(pixelData[offset + 1])
                let b = Float(pixelData[offset + 2])
                luminance[i] = 0.299 * r + 0.587 * g + 0.114 * b
            }
        }

        return (luminance, alphaMask)
    }
}
