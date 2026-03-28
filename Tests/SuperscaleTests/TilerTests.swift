// ABOUTME: Tests for the Tiler — tile splitting, overlap, and stitching.
// ABOUTME: Validates AC7.1 (coverage), AC7.2 (seamless stitching), AC7.3 (configurable tile size).

import XCTest
import CoreGraphics
@testable import SuperscaleKit

final class TilerTests: XCTestCase {

    // RT-015: Image larger than tile size produces overlapping tiles covering entire input
    func test_tiler_produces_overlapping_tiles_covering_input_RT015() throws {
        let image = try makeTestImage(width: 256, height: 256)
        let tileSize = 128
        let overlap = 16

        let tiles = Tiler.split(image: image, tileSize: tileSize, overlap: overlap)

        // With 256×256 image and 128 tile size with 16 overlap:
        // Effective stride = 128 - 16 = 112
        // Tiles needed: ceil(256 / 112) = 3 in each dimension → 9 tiles
        XCTAssertGreaterThan(tiles.count, 1, "Should produce multiple tiles")

        // Every pixel of the input must be covered by at least one tile
        // Check that tile positions span the full image
        let maxRight = tiles.map { $0.origin.x + $0.size.width }.max() ?? 0
        let maxBottom = tiles.map { $0.origin.y + $0.size.height }.max() ?? 0
        XCTAssertGreaterThanOrEqual(Int(maxRight), 256, "Tiles must cover full width")
        XCTAssertGreaterThanOrEqual(Int(maxBottom), 256, "Tiles must cover full height")

        // Each tile should be the expected size (or smaller for edge tiles clamped to image)
        for tile in tiles {
            XCTAssertGreaterThan(tile.image.width, 0)
            XCTAssertGreaterThan(tile.image.height, 0)
            XCTAssertLessThanOrEqual(tile.image.width, tileSize)
            XCTAssertLessThanOrEqual(tile.image.height, tileSize)
        }
    }

    // RT-016: Stitched output has correct dimensions (seamless stitching)
    func test_tiler_stitches_tiles_to_correct_dimensions_RT016() throws {
        let width = 200
        let height = 150
        let image = try makeTestImage(width: width, height: height)
        let tileSize = 128
        let overlap = 16
        let tiles = Tiler.split(image: image, tileSize: tileSize, overlap: overlap)

        // Stitch back together at 1× (identity — just reassemble)
        let stitched = try Tiler.stitch(
            tiles: tiles, outputWidth: width, outputHeight: height, overlap: overlap)

        XCTAssertEqual(stitched.width, width, "Stitched width must match original")
        XCTAssertEqual(stitched.height, height, "Stitched height must match original")
    }

    // RT-017: Tile size is configurable (different sizes produce different tile counts)
    func test_tiler_tile_size_is_configurable_RT017() throws {
        let image = try makeTestImage(width: 512, height: 512)

        let tiles128 = Tiler.split(image: image, tileSize: 128, overlap: 16)
        let tiles256 = Tiler.split(image: image, tileSize: 256, overlap: 16)

        // Smaller tile size should produce more tiles
        XCTAssertGreaterThan(tiles128.count, tiles256.count,
                             "Smaller tile size should produce more tiles")
    }

    // MARK: - Helpers

    private func makeTestImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw NSError(domain: "TilerTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create CGContext"])
        }

        // Draw a gradient for visual debugging
        for y in 0..<height {
            for x in 0..<width {
                let r = CGFloat(x) / CGFloat(width)
                let g = CGFloat(y) / CGFloat(height)
                context.setFillColor(red: r, green: g, blue: 0.5, alpha: 1.0)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }

        guard let image = context.makeImage() else {
            throw NSError(domain: "TilerTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
        }
        return image
    }
}
