// ABOUTME: Splits images into overlapping tiles and stitches processed tiles back together.
// ABOUTME: Handles tile overlap blending for seamless output when reassembling.

import CoreGraphics
import Foundation

/// A single tile extracted from a larger image.
public struct Tile {
    public let image: CGImage
    public let origin: CGPoint
    public let size: CGSize

    public init(image: CGImage, origin: CGPoint, size: CGSize) {
        self.image = image
        self.origin = origin
        self.size = size
    }
}

/// Splits images into overlapping tiles and stitches them back together.
///
/// The tiling engine enables processing of images larger than the model's
/// input size by breaking them into overlapping tiles, processing each
/// independently, and blending the overlapping regions during reassembly.
public enum Tiler {

    /// Split an image into overlapping tiles.
    ///
    /// - Parameters:
    ///   - image: The source image to split.
    ///   - tileSize: The maximum width and height of each tile in pixels.
    ///   - overlap: The number of pixels each tile overlaps with its neighbours.
    /// - Returns: An array of tiles covering the entire image.
    public static func split(image: CGImage, tileSize: Int, overlap: Int) -> [Tile] {
        let width = image.width
        let height = image.height
        let stride = max(tileSize - overlap, 1)

        var tiles: [Tile] = []

        var y = 0
        while y < height {
            var x = 0
            while x < width {
                // Clamp tile dimensions to image bounds
                let tileW = min(tileSize, width - x)
                let tileH = min(tileSize, height - y)

                let rect = CGRect(x: x, y: y, width: tileW, height: tileH)

                if let cropped = image.cropping(to: rect) {
                    let tile = Tile(
                        image: cropped,
                        origin: CGPoint(x: x, y: y),
                        size: CGSize(width: tileW, height: tileH)
                    )
                    tiles.append(tile)
                }

                x += stride
                // If this tile already reaches the right edge, stop
                if x + tileSize >= width && x < width && x > 0 {
                    // Place final tile flush against right edge
                    let finalX = max(width - tileSize, 0)
                    if finalX != x - stride {
                        x = finalX
                    } else {
                        break
                    }
                }
            }

            y += stride
            // If this tile already reaches the bottom edge, stop
            if y + tileSize >= height && y < height && y > 0 {
                let finalY = max(height - tileSize, 0)
                if finalY != y - stride {
                    y = finalY
                } else {
                    break
                }
            }
        }

        return tiles
    }

    /// Run each tile through `upscale`, reporting progress and stopping when cancelled.
    ///
    /// The per-tile work is a closure so the loop's behaviour — what it reports, and what it
    /// leaves undone when cancelled — is verifiable without Core ML.
    ///
    /// - Parameters:
    ///   - tiles: The tiles to process, in the order `split` produced them.
    ///   - scale: The factor the upscale applies, used to place the output tiles.
    ///   - tileSize: The model's expected input size; smaller tiles are padded and cropped back.
    ///   - report: Receives a phase for each tile as it starts.
    ///   - upscale: Produces the upscaled image for one tile.
    static func processTiles(
        _ tiles: [Tile],
        scale: Int,
        tileSize: Int,
        report: (PipelineProgress) -> Void,
        upscale: (CGImage) throws -> CGImage
    ) throws -> [Tile] {
        var processed: [Tile] = []
        processed.reserveCapacity(tiles.count)

        for (index, tile) in tiles.enumerated() {
            try Task.checkCancellation()
            report(.tiling(completed: index + 1, total: tiles.count))

            // Pad undersized tiles to tileSize before inference. VNCoreMLRequest.scaleFill
            // stretches an undersized tile to the model's expected input, distorting content.
            // Reflection padding preserves it; the padded region is cropped from the output.
            let needsPadding = tile.image.width < tileSize || tile.image.height < tileSize
            let inferenceInput = needsPadding
                ? try Pipeline.padToSize(tile.image, width: tileSize, height: tileSize)
                : tile.image

            let upscaledImage = try upscale(inferenceInput)

            let croppedImage: CGImage
            if needsPadding {
                let cropRect = CGRect(
                    x: 0, y: 0,
                    width: tile.image.width * scale,
                    height: tile.image.height * scale
                )
                guard let cropped = upscaledImage.cropping(to: cropRect) else {
                    throw ImageIOError.contextCreationFailed
                }
                croppedImage = cropped
            } else {
                croppedImage = upscaledImage
            }

            processed.append(
                Tile(
                    image: croppedImage,
                    origin: CGPoint(
                        x: tile.origin.x * CGFloat(scale),
                        y: tile.origin.y * CGFloat(scale)
                    ),
                    size: CGSize(width: croppedImage.width, height: croppedImage.height)
                )
            )
        }

        return processed
    }

    /// Stitch tiles back into a single image, blending overlapping regions.
    ///
    /// - Parameters:
    ///   - tiles: The tiles to stitch together.
    ///   - outputWidth: The width of the output image.
    ///   - outputHeight: The height of the output image.
    ///   - overlap: The overlap used during splitting (for blend weighting).
    /// - Returns: The reassembled image.
    public static func stitch(
        tiles: [Tile],
        outputWidth: Int,
        outputHeight: Int,
        overlap: Int
    ) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = outputWidth * 4
        let totalBytes = outputHeight * bytesPerRow

        // Accumulation buffers for blending
        var colorAccum = [Float](repeating: 0, count: totalBytes)
        var weightAccum = [Float](repeating: 0, count: totalBytes)

        for tile in tiles {
            let tileW = tile.image.width
            let tileH = tile.image.height
            let originX = Int(tile.origin.x)
            let originY = Int(tile.origin.y)

            // Render tile to get pixel data
            let tileBytesPerRow = tileW * 4
            var tilePixels = [UInt8](repeating: 0, count: tileH * tileBytesPerRow)

            guard let tileCtx = CGContext(
                data: &tilePixels,
                width: tileW, height: tileH,
                bitsPerComponent: 8, bytesPerRow: tileBytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw ImageIOError.contextCreationFailed
            }
            tileCtx.draw(tile.image, in: CGRect(x: 0, y: 0, width: tileW, height: tileH))

            let feathering = TileFeathering(
                origin: tile.origin,
                width: tileW, height: tileH,
                outputWidth: outputWidth, outputHeight: outputHeight
            )

            // Blend tile into the accumulation buffer with distance-based weights
            for ty in 0..<tileH {
                try Task.checkCancellation()
                for tx in 0..<tileW {
                    let outX = originX + tx
                    let outY = originY + ty
                    guard outX < outputWidth, outY < outputHeight else { continue }

                    // Compute blend weight based on distance from tile edges
                    let weight = blendWeight(
                        x: tx, y: ty, width: tileW, height: tileH, overlap: overlap,
                        feathering: feathering)

                    let tileIdx = (ty * tileBytesPerRow) + (tx * 4)
                    let outIdx = (outY * bytesPerRow) + (outX * 4)

                    for c in 0..<4 {
                        colorAccum[outIdx + c] += Float(tilePixels[tileIdx + c]) * weight
                        weightAccum[outIdx + c] += weight
                    }
                }
            }
        }

        // Normalize accumulated colours by total weight
        var outputPixels = [UInt8](repeating: 0, count: totalBytes)
        for i in 0..<totalBytes {
            // The guard is a division-by-zero precondition. With boundary edges at full weight
            // every pixel is covered by at least one tile at non-zero weight, so it is no longer
            // a path an output can silently take.
            if weightAccum[i] > 0 {
                // Rounded rather than truncated: two tiles carrying the same value with weights
                // summing to one should give that value back, and in floating point the quotient
                // can be a fraction short of it. Truncation also biases every blended pixel of
                // a real upscale downwards.
                let value = (colorAccum[i] / weightAccum[i]).rounded()
                outputPixels[i] = UInt8(min(max(value, 0), 255))
            }
        }

        // Create output image
        guard let outCtx = CGContext(
            data: &outputPixels,
            width: outputWidth, height: outputHeight,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageIOError.contextCreationFailed
        }

        guard let result = outCtx.makeImage() else {
            throw ImageIOError.contextCreationFailed
        }
        return result
    }

    /// Compute a blend weight for a pixel within a tile.
    ///
    /// Pixels near tile edges within the overlap zone get lower weight,
    /// creating a smooth transition between overlapping tiles.
    private static func blendWeight(
        x: Int, y: Int, width: Int, height: Int, overlap: Int,
        feathering: TileFeathering
    ) -> Float {
        guard overlap > 0 else { return 1.0 }

        let o = Float(overlap)

        // Distance from each edge, normalized to [0, 1] within the overlap zone. An edge that
        // lies on the image boundary is not feathered: feathering exists so two overlapping
        // tiles can sum to one, and on the boundary there is no second tile. Ramping there
        // leaves the pixel with no weight at all, and it keeps its initialized zero — which is
        // the one-pixel black border every output carried.
        let left = feathering.left ? min(Float(x) / o, 1.0) : 1.0
        let right = feathering.right ? min(Float(width - 1 - x) / o, 1.0) : 1.0
        let top = feathering.top ? min(Float(y) / o, 1.0) : 1.0
        let bottom = feathering.bottom ? min(Float(height - 1 - y) / o, 1.0) : 1.0

        // Minimum of all edge distances gives the blend weight
        return min(left, right, top, bottom)
    }
}

/// Which of a tile's edges meet another tile rather than the edge of the image.
struct TileFeathering: Equatable {
    let left: Bool
    let right: Bool
    let top: Bool
    let bottom: Bool

    init(origin: CGPoint, width: Int, height: Int, outputWidth: Int, outputHeight: Int) {
        let originX = Int(origin.x)
        let originY = Int(origin.y)
        left = originX > 0
        right = originX + width < outputWidth
        top = originY > 0
        bottom = originY + height < outputHeight
    }
}
