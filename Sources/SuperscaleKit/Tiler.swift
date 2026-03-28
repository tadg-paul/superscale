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

            // Blend tile into the accumulation buffer with distance-based weights
            for ty in 0..<tileH {
                for tx in 0..<tileW {
                    let outX = originX + tx
                    let outY = originY + ty
                    guard outX < outputWidth, outY < outputHeight else { continue }

                    // Compute blend weight based on distance from tile edges
                    let weight = blendWeight(
                        x: tx, y: ty, width: tileW, height: tileH, overlap: overlap)

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
            if weightAccum[i] > 0 {
                outputPixels[i] = UInt8(min(max(colorAccum[i] / weightAccum[i], 0), 255))
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
        x: Int, y: Int, width: Int, height: Int, overlap: Int
    ) -> Float {
        guard overlap > 0 else { return 1.0 }

        let o = Float(overlap)

        // Distance from each edge, normalized to [0, 1] within the overlap zone
        let left = min(Float(x) / o, 1.0)
        let right = min(Float(width - 1 - x) / o, 1.0)
        let top = min(Float(y) / o, 1.0)
        let bottom = min(Float(height - 1 - y) / o, 1.0)

        // Minimum of all edge distances gives the blend weight
        return min(left, right, top, bottom)
    }
}
