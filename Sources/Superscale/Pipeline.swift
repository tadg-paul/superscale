// ABOUTME: Orchestrates the full upscaling pipeline: load, tile, infer, stitch, write.
// ABOUTME: Coordinates ImageLoader, Tiler, CoreMLInference, and ImageWriter into an end-to-end flow.

import CoreGraphics
import Foundation

/// Orchestrates the complete image upscaling pipeline.
///
/// Coordinates loading, tiling, inference, stitching, and writing
/// into a single `process(input:output:)` call.
class Pipeline {
    let modelName: String
    let modelInfo: ModelInfo
    let tileSize: Int
    let overlap: Int
    let faceEnhance: Bool
    let inference: CoreMLInference

    /// Callback for progress reporting. Called with human-readable messages.
    var onProgress: ((String) -> Void)?

    /// Create a pipeline for a given model.
    ///
    /// - Parameters:
    ///   - modelName: CLI model name (e.g. "realesrgan-x4plus").
    ///   - tileSize: Override tile size. Pass nil to use the model's default.
    ///   - overlap: Tile overlap in pixels.
    ///   - faceEnhance: Whether to run face enhancement (requires GFPGAN model).
    init(modelName: String, tileSize: Int? = nil, overlap: Int = 16,
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
    func process(input: URL, output: URL) throws {
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

            let upscaledImage = try inference.upscale(tile.image)

            let upscaledTile = Tile(
                image: upscaledImage,
                origin: CGPoint(
                    x: tile.origin.x * CGFloat(scale),
                    y: tile.origin.y * CGFloat(scale)),
                size: CGSize(
                    width: CGFloat(upscaledImage.width),
                    height: CGFloat(upscaledImage.height))
            )
            upscaledTiles.append(upscaledTile)
        }

        // 4. Stitch tiles
        let outputWidth = loaded.image.width * scale
        let outputHeight = loaded.image.height * scale
        let scaledOverlap = overlap * scale

        report("Stitching output (\(outputWidth)×\(outputHeight))...")
        var stitched = try Tiler.stitch(
            tiles: upscaledTiles,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            overlap: scaledOverlap
        )

        // 5. Face enhancement (when enabled and model is present)
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
                alphaChannel, toWidth: outputWidth, height: outputHeight)
            stitched = try ImageLoader.recombineAlpha(rgb: stitched, alpha: upscaledAlpha)
        }

        // 7. Write output
        let format = OutputFormat.from(extension: output.pathExtension) ?? .png
        report("Writing \(output.lastPathComponent)...")
        try ImageWriter.write(stitched, to: output, format: format,
                              colorSpace: loaded.colorSpace)

        report("Done: \(outputWidth)×\(outputHeight) → \(output.lastPathComponent)")
    }

    // MARK: - Private

    private func report(_ message: String) {
        onProgress?(message)
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
