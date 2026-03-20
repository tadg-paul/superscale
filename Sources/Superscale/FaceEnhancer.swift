// ABOUTME: Enhances face regions using the GFPGAN CoreML model.
// ABOUTME: Crops detected faces, runs GFPGAN inference at 512×512, blends results back.

import CoreGraphics
import CoreImage
import CoreML
import Vision

/// Enhances face regions in an image using the GFPGAN CoreML model.
///
/// Pipeline: crop face with padding → resize to 512×512 → run GFPGAN →
/// resize back to original crop size → blend into image with feathered edges.
struct FaceEnhancer {

    /// GFPGAN operates on 512×512 face crops.
    static let faceInputSize = 512

    /// Expansion factor for face bounding boxes (1.5× matches upstream).
    static let expandFactor: CGFloat = 1.5

    /// Feather radius in pixels for blending edges (as fraction of crop size).
    static let featherFraction: CGFloat = 0.05

    /// Minimum mean brightness for a valid GFPGAN output. Below this threshold
    /// the output is considered corrupted (e.g. [0,1]→UInt8 truncation) and
    /// the original face is preserved instead.
    static let minOutputBrightness: Double = 5.0

    private let inference: CoreMLInference

    /// Create a face enhancer using the installed GFPGAN model.
    ///
    /// - Throws: If the GFPGAN model is not installed or cannot be loaded.
    init() throws {
        guard let modelURL = FaceModelRegistry.modelURL else {
            throw FaceEnhancerError.modelNotInstalled
        }
        self.inference = try CoreMLInference(modelURL: modelURL)
    }

    /// Enhance all detected faces in an image.
    ///
    /// - Parameters:
    ///   - image: The full image (typically after upscaling).
    ///   - faceRects: Face bounding boxes in pixel coordinates (from FaceDetector).
    /// - Returns: Image with enhanced face regions blended back in.
    func enhance(image: CGImage, faceRects: [CGRect]) throws -> CGImage {
        guard !faceRects.isEmpty else { return image }

        let width = image.width
        let height = image.height

        // Start with a mutable copy of the image
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let ctx = CGContext(
            data: &pixelData,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw ImageIOError.contextCreationFailed
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        for faceRect in faceRects {
            // Expand face rect with padding
            let expandedRect = FaceDetector.expandRect(
                faceRect, by: Self.expandFactor,
                imageWidth: width, imageHeight: height)

            // Crop face region
            let cropRect = CGRect(
                x: Int(expandedRect.origin.x),
                y: Int(expandedRect.origin.y),
                width: Int(expandedRect.width),
                height: Int(expandedRect.height))

            guard let faceCrop = image.cropping(to: cropRect) else { continue }

            // Resize to 512×512 for GFPGAN
            guard let resized = resize(
                faceCrop,
                to: CGSize(width: Self.faceInputSize, height: Self.faceInputSize)
            ) else { continue }

            // Run GFPGAN inference
            let enhanced = try inference.upscale(resized)

            // Validate output brightness — skip if model produces black output
            // (caused by [0,1]→UInt8 truncation in models missing ×255 output scaling)
            if isBlack(enhanced) {
                fputs("warning: GFPGAN output is black — skipping face enhancement. " +
                      "Re-download the face model: superscale --download-face-model\n", stderr)
                continue
            }

            // Resize enhanced face back to original crop size
            guard let resizedBack = resize(
                enhanced,
                to: CGSize(width: Int(cropRect.width), height: Int(cropRect.height))
            ) else { continue }

            // Blend enhanced face back into the image with feathered edges
            blendFace(
                enhanced: resizedBack,
                into: &pixelData,
                at: cropRect,
                imageWidth: width,
                imageHeight: height)
        }

        // Create output image from modified pixel data
        guard let outputCtx = CGContext(
            data: &pixelData,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw ImageIOError.contextCreationFailed
        }

        guard let result = outputCtx.makeImage() else {
            throw ImageIOError.contextCreationFailed
        }
        return result
    }

    // MARK: - Private

    /// Check if an image is essentially black (mean RGB brightness below threshold).
    ///
    /// This catches GFPGAN models whose output [0,1] floats were truncated to UInt8,
    /// producing all-black or near-black pixels.
    private func isBlack(_ image: CGImage) -> Bool {
        let w = image.width
        let h = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: h * w * 4)

        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return true
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Sample every 16th pixel for speed (512×512 = 1024 samples)
        var sum: UInt64 = 0
        var count: UInt64 = 0
        let stride = 16
        for y in Swift.stride(from: 0, to: h, by: stride) {
            for x in Swift.stride(from: 0, to: w, by: stride) {
                let idx = (y * w + x) * 4
                for c in 0..<3 {
                    sum += UInt64(pixels[idx + c])
                    count += 1
                }
            }
        }

        let mean = count > 0 ? Double(sum) / Double(count) : 0
        return mean < Self.minOutputBrightness
    }

    /// Resize an image to a target size using high-quality interpolation.
    private func resize(_ image: CGImage, to size: CGSize) -> CGImage? {
        let w = Int(size.width)
        let h = Int(size.height)

        guard w > 0, h > 0 else { return nil }

        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Blend an enhanced face crop into the full image pixel buffer with feathered edges.
    private func blendFace(
        enhanced: CGImage,
        into pixelData: inout [UInt8],
        at rect: CGRect,
        imageWidth: Int,
        imageHeight: Int
    ) {
        let cropW = Int(rect.width)
        let cropH = Int(rect.height)
        let cropX = Int(rect.origin.x)
        let cropY = Int(rect.origin.y)

        // Render enhanced face to raw pixels
        let colorSpace = enhanced.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        var facePixels = [UInt8](repeating: 0, count: cropH * cropW * 4)
        guard let faceCtx = CGContext(
            data: &facePixels,
            width: cropW, height: cropH,
            bitsPerComponent: 8, bytesPerRow: cropW * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return
        }
        faceCtx.draw(enhanced, in: CGRect(x: 0, y: 0, width: cropW, height: cropH))

        // Feather radius in pixels
        let featherRadius = Int(Self.featherFraction * CGFloat(min(cropW, cropH)))

        for y in 0..<cropH {
            for x in 0..<cropW {
                let imgX = cropX + x
                let imgY = cropY + y

                guard imgX >= 0, imgX < imageWidth, imgY >= 0, imgY < imageHeight else {
                    continue
                }

                // Compute feather blend weight (1.0 in centre, 0.0 at edges)
                let alpha = featherWeight(
                    x: x, y: y,
                    width: cropW, height: cropH,
                    radius: featherRadius)

                if alpha <= 0 { continue }

                let srcIdx = (y * cropW + x) * 4
                let dstIdx = (imgY * imageWidth + imgX) * 4

                // Blend: output = enhanced * alpha + original * (1 - alpha)
                for c in 0..<3 {
                    let enhanced = Float(facePixels[srcIdx + c])
                    let original = Float(pixelData[dstIdx + c])
                    pixelData[dstIdx + c] = UInt8(enhanced * alpha + original * (1.0 - alpha))
                }
            }
        }
    }

    /// Compute feather weight for a pixel position within a crop.
    ///
    /// Returns 1.0 for interior pixels, tapering to 0.0 at the edges
    /// over the feather radius.
    private func featherWeight(
        x: Int, y: Int,
        width: Int, height: Int,
        radius: Int
    ) -> Float {
        guard radius > 0 else { return 1.0 }

        let distLeft = Float(x)
        let distRight = Float(width - 1 - x)
        let distTop = Float(y)
        let distBottom = Float(height - 1 - y)
        let minDist = min(distLeft, distRight, distTop, distBottom)

        if minDist >= Float(radius) { return 1.0 }
        if minDist <= 0 { return 0.0 }

        return minDist / Float(radius)
    }
}

/// Errors from face enhancement operations.
enum FaceEnhancerError: Error, CustomStringConvertible {
    case modelNotInstalled

    var description: String {
        switch self {
        case .modelNotInstalled:
            return "GFPGAN face model not installed. Run: superscale --download-face-model"
        }
    }
}
