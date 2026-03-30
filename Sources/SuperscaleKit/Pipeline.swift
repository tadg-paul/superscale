// ABOUTME: Orchestrates the full upscaling pipeline: load, tile, infer, stitch, write.
// ABOUTME: Coordinates ImageLoader, Tiler, CoreMLInference, and ImageWriter into an end-to-end flow.

import CoreGraphics
import Foundation

/// Orchestrates the complete image upscaling pipeline.
///
/// Coordinates loading, tiling, inference, stitching, and writing
/// into a single `process(input:output:)` call.
public class Pipeline {
    public let modelName: String
    public let modelInfo: ModelInfo
    public let tileSize: Int
    public let overlap: Int
    public let faceEnhance: Bool
    public let inference: CoreMLInference

    /// Callback for progress reporting. Called with human-readable messages.
    public var onProgress: ((String) -> Void)?

    /// Create a pipeline for a given model.
    ///
    /// - Parameters:
    ///   - modelName: CLI model name (e.g. "realesrgan-x4plus").
    ///   - tileSize: Override tile size. Pass nil to use the model's default.
    ///   - overlap: Tile overlap in pixels.
    ///   - faceEnhance: Whether to run face enhancement (requires GFPGAN model).
    public init(modelName: String, tileSize: Int? = nil, overlap: Int = 16,
         faceEnhance: Bool = true) throws {
        guard let info = ModelRegistry.model(named: modelName) else {
            throw SuperscaleError.modelNotFound(modelName)
        }
        guard let modelURL = ModelRegistry.modelURL(for: modelName) else {
            throw SuperscaleError.modelNotFound(modelName)
        }

        self.modelName = modelName
        self.modelInfo = info
        self.tileSize = tileSize ?? info.tileSize
        self.overlap = overlap
        self.faceEnhance = faceEnhance
        self.inference = try CoreMLInference(modelURL: modelURL)
    }

    /// Run the full upscaling pipeline.
    ///
    /// - Parameters:
    ///   - input: URL of the input image file.
    ///   - output: URL for the output image file.
    ///   - requestedScale: User-requested scale factor (e.g. 2.4). Nil means native model scale.
    ///   - targetWidth: Target width in pixels. Nil means no dimension target.
    ///   - targetHeight: Target height in pixels. Nil means no dimension target.
    ///   - stretch: If true, stretch to exact width×height ignoring aspect ratio.
    public func process(
        input: URL, output: URL,
        requestedScale: Double? = nil,
        targetWidth: Int? = nil, targetHeight: Int? = nil,
        stretch: Bool = false,
        onPreFaceEnhance: ((CGImage) -> Void)? = nil
    ) throws {
        // 1. Load image
        report("Loading \(input.lastPathComponent)...")
        let loaded = try ImageLoader.load(from: input)
        let scale = modelInfo.scale

        report("Input: \(loaded.image.width)×\(loaded.image.height), scale: \(scale)×")

        // 2. Split into tiles
        let tiles = Tiler.split(
            image: loaded.image, tileSize: tileSize, overlap: overlap)
        let totalTiles = tiles.count
        report("Split into \(totalTiles) tile\(totalTiles == 1 ? "" : "s") " +
               "(tile size: \(tileSize), overlap: \(overlap))")

        // 3. Run inference on each tile
        var upscaledTiles: [Tile] = []
        for (index, tile) in tiles.enumerated() {
            report("Processing tile \(index + 1) of \(totalTiles)...")

            // Pad undersized tiles to tileSize before inference.
            // VNCoreMLRequest.scaleFill stretches undersized tiles to the model's
            // expected input, distorting content. Reflection padding preserves
            // content integrity; the padded region is cropped from the output.
            let needsPadding = tile.image.width < tileSize || tile.image.height < tileSize
            let inferenceInput: CGImage
            if needsPadding {
                inferenceInput = try padToSize(
                    tile.image, width: tileSize, height: tileSize)
            } else {
                inferenceInput = tile.image
            }

            let upscaledImage = try inference.upscale(inferenceInput)

            // Crop away the upscaled padding region to get the correct output tile.
            let croppedImage: CGImage
            if needsPadding {
                let cropW = tile.image.width * scale
                let cropH = tile.image.height * scale
                let cropRect = CGRect(x: 0, y: 0, width: cropW, height: cropH)
                guard let cropped = upscaledImage.cropping(to: cropRect) else {
                    throw ImageIOError.contextCreationFailed
                }
                croppedImage = cropped
            } else {
                croppedImage = upscaledImage
            }

            let upscaledTile = Tile(
                image: croppedImage,
                origin: CGPoint(
                    x: tile.origin.x * CGFloat(scale),
                    y: tile.origin.y * CGFloat(scale)),
                size: CGSize(
                    width: CGFloat(croppedImage.width),
                    height: CGFloat(croppedImage.height))
            )
            upscaledTiles.append(upscaledTile)
        }

        // 4. Stitch tiles
        let nativeWidth = loaded.image.width * scale
        let nativeHeight = loaded.image.height * scale
        let scaledOverlap = overlap * scale

        report("Stitching output (\(nativeWidth)×\(nativeHeight))...")
        var stitched = try Tiler.stitch(
            tiles: upscaledTiles,
            outputWidth: nativeWidth,
            outputHeight: nativeHeight,
            overlap: scaledOverlap
        )

        // 5. Pre-face-enhance callback (for GUI caching)
        onPreFaceEnhance?(stitched)

        // 5b. Face enhancement (when enabled and model is present)
        if faceEnhance && FaceModelRegistry.isInstalled {
            let faces = try FaceDetector.detect(in: stitched)
            if !faces.isEmpty {
                report("Enhancing \(faces.count) face\(faces.count == 1 ? "" : "s")...")
                let enhancer = try FaceEnhancer()
                stitched = try enhancer.enhance(image: stitched, faceRects: faces)
            }
        }

        // 6. Handle alpha channel
        if let alphaChannel = loaded.alphaChannel {
            report("Upscaling alpha channel...")
            let upscaledAlpha = try upscaleAlpha(
                alphaChannel, toWidth: nativeWidth, height: nativeHeight)
            stitched = try ImageLoader.recombineAlpha(rgb: stitched, alpha: upscaledAlpha)
        }

        // 7. Resize to target (if different from native output)
        let (finalWidth, finalHeight) = resolveTargetDimensions(
            inputWidth: loaded.image.width,
            inputHeight: loaded.image.height,
            nativeScale: scale,
            requestedScale: requestedScale,
            targetWidth: targetWidth,
            targetHeight: targetHeight,
            stretch: stretch)

        if finalWidth != nativeWidth || finalHeight != nativeHeight {
            let effectiveScale = Double(finalWidth) / Double(loaded.image.width)
            if effectiveScale > Double(scale) {
                report("Warning: Target scale \(String(format: "%.1f", effectiveScale))× " +
                       "exceeds model's native \(scale)× — standard interpolation " +
                       "will be used for the remaining " +
                       "\(String(format: "%.1f", effectiveScale / Double(scale)))×. " +
                       "Some pixellation may be visible.")
            }
            report("Resizing to \(finalWidth)×\(finalHeight)...")
            stitched = try resizeImage(
                stitched, toWidth: finalWidth, height: finalHeight)
        }

        // 8. Write output
        let format = OutputFormat.from(extension: output.pathExtension) ?? .png
        report("Writing \(output.lastPathComponent)...")
        try ImageWriter.write(stitched, to: output, format: format,
                              colorSpace: loaded.colorSpace)

        report("Done: \(finalWidth)×\(finalHeight) → \(output.lastPathComponent)")
    }

    // MARK: - Private

    private func report(_ message: String) {
        onProgress?(message)
    }

    /// Compute final target dimensions from user-requested scale or dimensions.
    ///
    /// Returns (width, height) for the final output after any post-pipeline resize.
    /// If no custom target is requested, returns the native upscaled dimensions.
    private func resolveTargetDimensions(
        inputWidth: Int, inputHeight: Int,
        nativeScale: Int,
        requestedScale: Double?,
        targetWidth: Int?, targetHeight: Int?,
        stretch: Bool
    ) -> (width: Int, height: Int) {
        // Case 1: explicit --scale
        if let s = requestedScale {
            let w = Int(round(Double(inputWidth) * s))
            let h = Int(round(Double(inputHeight) * s))
            return (max(w, 1), max(h, 1))
        }

        // Case 2: --width and/or --height
        if let tw = targetWidth, let th = targetHeight {
            if stretch {
                return (tw, th)
            }
            // Fit within bounding box preserving aspect ratio
            let scaleW = Double(tw) / Double(inputWidth)
            let scaleH = Double(th) / Double(inputHeight)
            let fitScale = min(scaleW, scaleH)
            return (max(Int(round(Double(inputWidth) * fitScale)), 1),
                    max(Int(round(Double(inputHeight) * fitScale)), 1))
        }
        if let tw = targetWidth {
            // Width only: scale proportionally
            let fitScale = Double(tw) / Double(inputWidth)
            return (tw, max(Int(round(Double(inputHeight) * fitScale)), 1))
        }
        if let th = targetHeight {
            // Height only: scale proportionally
            let fitScale = Double(th) / Double(inputHeight)
            return (max(Int(round(Double(inputWidth) * fitScale)), 1), th)
        }

        // Case 3: no custom target — native model scale
        return (inputWidth * nativeScale, inputHeight * nativeScale)
    }

    /// Resize an image using high-quality interpolation.
    private func resizeImage(
        _ image: CGImage, toWidth width: Int, height: Int
    ) throws -> CGImage {
        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else {
            throw ImageIOError.contextCreationFailed
        }
        guard let ctx = CGContext(
            data: nil,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageIOError.contextCreationFailed
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let result = ctx.makeImage() else {
            throw ImageIOError.contextCreationFailed
        }
        return result
    }

    /// Pad an image to the given dimensions using reflection padding.
    ///
    /// Operates at the pixel-buffer level to avoid CGContext coordinate
    /// system confusion (bottom-left origin vs top-left CGImage convention).
    /// Renders the source to a pixel buffer, copies rows into a larger
    /// target buffer with reflected edges, and creates a CGImage from it.
    private func padToSize(
        _ image: CGImage, width targetW: Int, height targetH: Int
    ) throws -> CGImage {
        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else {
            throw ImageIOError.contextCreationFailed
        }

        let srcW = image.width
        let srcH = image.height
        let bytesPerPixel = 4
        let srcBytesPerRow = srcW * bytesPerPixel
        let dstBytesPerRow = targetW * bytesPerPixel

        // Render source image to a pixel buffer (top-down raster order).
        var srcPixels = [UInt8](repeating: 0, count: srcH * srcBytesPerRow)
        guard let srcCtx = CGContext(
            data: &srcPixels,
            width: srcW, height: srcH,
            bitsPerComponent: 8, bytesPerRow: srcBytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw ImageIOError.contextCreationFailed
        }
        srcCtx.draw(image, in: CGRect(x: 0, y: 0, width: srcW, height: srcH))

        // Create target buffer, initialized to zero (black padding).
        var dstPixels = [UInt8](repeating: 0, count: targetH * dstBytesPerRow)

        // Copy source rows into the top-left of the target buffer.
        for row in 0..<srcH {
            let srcOffset = row * srcBytesPerRow
            let dstOffset = row * dstBytesPerRow
            dstPixels.replaceSubrange(
                dstOffset..<(dstOffset + srcBytesPerRow),
                with: srcPixels[srcOffset..<(srcOffset + srcBytesPerRow)])
        }

        // Reflect-pad the right edge: mirror the rightmost columns.
        if srcW < targetW {
            let padW = targetW - srcW
            let reflectW = min(padW, srcW)
            for row in 0..<srcH {
                for col in 0..<reflectW {
                    let srcCol = srcW - 1 - col  // mirror from right edge
                    let srcIdx = row * srcBytesPerRow + srcCol * bytesPerPixel
                    let dstIdx = row * dstBytesPerRow + (srcW + col) * bytesPerPixel
                    for b in 0..<bytesPerPixel {
                        dstPixels[dstIdx + b] = srcPixels[srcIdx + b]
                    }
                }
            }
        }

        // Reflect-pad the bottom edge: mirror the bottommost rows.
        if srcH < targetH {
            let padH = targetH - srcH
            let reflectH = min(padH, srcH)
            for padRow in 0..<reflectH {
                let srcRow = srcH - 1 - padRow  // mirror from bottom edge
                let dstRow = srcH + padRow
                // Copy the full target width (includes right-padded pixels).
                let srcRowStart = srcRow * dstBytesPerRow
                let dstRowStart = dstRow * dstBytesPerRow
                let copyLen = min(srcW + min(targetW - srcW, srcW), targetW) * bytesPerPixel
                dstPixels.replaceSubrange(
                    dstRowStart..<(dstRowStart + copyLen),
                    with: dstPixels[srcRowStart..<(srcRowStart + copyLen)])
            }
        }

        // Create CGImage from the padded pixel buffer.
        guard let dstCtx = CGContext(
            data: &dstPixels,
            width: targetW, height: targetH,
            bitsPerComponent: 8, bytesPerRow: dstBytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw ImageIOError.contextCreationFailed
        }

        guard let result = dstCtx.makeImage() else {
            throw ImageIOError.contextCreationFailed
        }
        return result
    }

    /// Upscale a greyscale alpha channel using bicubic interpolation.
    private func upscaleAlpha(
        _ alpha: CGImage, toWidth width: Int, height: Int
    ) throws -> CGImage {
        let greySpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: greySpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw ImageIOError.contextCreationFailed
        }
        ctx.interpolationQuality = .high
        ctx.draw(alpha, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let result = ctx.makeImage() else {
            throw ImageIOError.contextCreationFailed
        }
        return result
    }
}
