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

    // MARK: - AC83.1 the round trip reproduces the image

    // RT-83.1
    //
    // The zero-valued channel is deliberate. D3 left boundary pixels at their initialized zero,
    // so the obvious wrong fix is to clamp channels away from zero — which would hide the border
    // without touching the weighting. Requiring a source zero to come back as zero blocks it.
    func test_stitch_reproduces_outermost_row_and_column_RT083_1() throws {
        let source = try makeGradientImage(width: 200, height: 150)
        let tiles = Tiler.split(image: source, tileSize: 128, overlap: 16)

        let stitched = try Tiler.stitch(
            tiles: tiles, outputWidth: 200, outputHeight: 150, overlap: 16)

        XCTAssertEqual(
            try pixel(in: stitched, x: 0, y: 0).red, 0,
            "the source's zero red channel at the origin must survive the round trip"
        )
        for x in 0..<200 {
            assertPixelsEqual(stitched, source, x: x, y: 0, label: "top row")
            assertPixelsEqual(stitched, source, x: x, y: 149, label: "bottom row")
        }
        for y in 0..<150 {
            assertPixelsEqual(stitched, source, x: 0, y: y, label: "left column")
            assertPixelsEqual(stitched, source, x: 199, y: y, label: "right column")
        }
    }

    // RT-83.2
    func test_stitch_reproduces_an_interior_row_crossing_a_seam_RT083_2() throws {
        let source = try makeGradientImage(width: 200, height: 150)
        let tiles = Tiler.split(image: source, tileSize: 128, overlap: 16)

        let stitched = try Tiler.stitch(
            tiles: tiles, outputWidth: 200, outputHeight: 150, overlap: 16)

        // A row inside the image, crossing the horizontal seam between the two columns of tiles.
        for x in 0..<200 {
            assertPixelsEqual(stitched, source, x: x, y: 75, label: "interior row")
        }
    }

    // RT-83.3
    func test_stitch_reproduces_an_image_smaller_than_one_tile_RT083_3() throws {
        try assertRoundTripReproducesSource(width: 64, height: 48, tileSize: 128, overlap: 16)
    }

    // RT-83.4
    func test_stitch_reproduces_an_image_sized_to_an_exact_stride_multiple_RT083_4() throws {
        // stride = tileSize - overlap = 112; 224 is exactly two strides.
        try assertRoundTripReproducesSource(width: 224, height: 224, tileSize: 128, overlap: 16)
    }

    // RT-83.18
    func test_stitch_reproduces_an_image_with_a_narrow_final_tile_RT083_18() throws {
        // 118 leaves a final tile of 6 pixels, narrower than the 16-pixel overlap, so that tile's
        // own left and right ramps overlap each other.
        try assertRoundTripReproducesSource(width: 118, height: 118, tileSize: 112, overlap: 16)
    }

    // MARK: - AC83.2 boundaries are not seams

    // RT-83.5
    func test_aBoundaryPixelHoldsTheValueOfItsOnlyTile_RT083_5() throws {
        let left = try makeFlatTile(red: 200, origin: CGPoint(x: 0, y: 0), size: 64)
        let right = try makeFlatTile(red: 40, origin: CGPoint(x: 48, y: 0), size: 64)

        let stitched = try Tiler.stitch(
            tiles: [left, right], outputWidth: 112, outputHeight: 64, overlap: 16)

        XCTAssertEqual(try pixel(in: stitched, x: 0, y: 0).red, 200, "left boundary")
        XCTAssertEqual(try pixel(in: stitched, x: 111, y: 0).red, 40, "right boundary")
    }

    // RT-83.6
    //
    // Asserts the ramp rather than the mixture. A weight of 1.0 everywhere would average the two
    // tiles equally across the whole overlap, which is a blend of both and the value of neither —
    // and which replaces a gradient with a visible band at every seam on a real upscale.
    func test_anInteriorSeamRampsBetweenItsTiles_RT083_6() throws {
        let left = try makeFlatTile(red: 200, origin: CGPoint(x: 0, y: 0), size: 64)
        let right = try makeFlatTile(red: 40, origin: CGPoint(x: 48, y: 0), size: 64)

        let stitched = try Tiler.stitch(
            tiles: [left, right], outputWidth: 112, outputHeight: 64, overlap: 16)

        // The overlap spans x = 48...63. Nearer the left tile the result must be nearer 200.
        let nearLeft = try pixel(in: stitched, x: 50, y: 0).red
        let nearRight = try pixel(in: stitched, x: 61, y: 0).red

        XCTAssertGreaterThan(
            nearLeft, nearRight,
            "the seam is an average rather than a ramp: \(nearLeft) at x=50, \(nearRight) at x=61"
        )
        XCTAssertLessThan(nearLeft, 200, "the seam should blend, not hold the left tile's value")
        XCTAssertGreaterThan(nearRight, 40, "the seam should blend, not hold the right tile's value")
    }

    // MARK: - AC83.3 cancellation

    // RT-83.19
    func test_aCancelledStitchStopsRatherThanComposingEveryRow_RT083_19() async throws {
        let source = try makeGradientImage(width: 256, height: 256)
        let tiles = Tiler.split(image: source, tileSize: 128, overlap: 16)

        let task = Task {
            try Tiler.stitch(tiles: tiles, outputWidth: 256, outputHeight: 256, overlap: 16)
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("a cancelled stitch produced an image")
        } catch is CancellationError {
            // The expected outcome.
        }
    }

    // MARK: - Helpers

    private struct Channels: Equatable {
        let red: Int
        let green: Int
        let blue: Int
    }

    private func assertRoundTripReproducesSource(
        width: Int,
        height: Int,
        tileSize: Int,
        overlap: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makeGradientImage(width: width, height: height)
        let tiles = Tiler.split(image: source, tileSize: tileSize, overlap: overlap)

        let stitched = try Tiler.stitch(
            tiles: tiles, outputWidth: width, outputHeight: height, overlap: overlap)

        for y in 0..<height {
            for x in 0..<width {
                assertPixelsEqual(stitched, source, x: x, y: y, label: "round trip", file: file, line: line)
            }
        }
    }

    private func assertPixelsEqual(
        _ stitched: CGImage,
        _ source: CGImage,
        x: Int,
        y: Int,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let got = try pixel(in: stitched, x: x, y: y)
            let want = try pixel(in: source, x: x, y: y)
            XCTAssertEqual(got, want, "\(label) at (\(x), \(y))", file: file, line: line)
        } catch {
            XCTFail("could not sample (\(x), \(y)): \(error)", file: file, line: line)
        }
    }

    private func pixel(in image: CGImage, x: Int, y: Int) throws -> Channels {
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: image.height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageIOError.contextCreationFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let index = (y * bytesPerRow) + (x * 4)
        return Channels(
            red: Int(pixels[index]),
            green: Int(pixels[index + 1]),
            blue: Int(pixels[index + 2])
        )
    }

    /// A gradient whose red channel is zero along the left column and whose green is zero along
    /// the top row, so a round trip has a zero-valued source channel to reproduce.
    private func makeGradientImage(width: Int, height: Int) throws -> CGImage {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * bytesPerRow) + (x * 4)
                pixels[index] = UInt8(x * 255 / max(width - 1, 1))
                pixels[index + 1] = UInt8(y * 255 / max(height - 1, 1))
                pixels[index + 2] = 128
                pixels[index + 3] = 255
            }
        }
        return try makeImage(from: &pixels, width: width, height: height)
    }

    private func makeFlatTile(red: UInt8, origin: CGPoint, size: Int) throws -> Tile {
        let bytesPerRow = size * 4
        var pixels = [UInt8](repeating: 0, count: size * bytesPerRow)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = red
            pixels[i + 1] = 0
            pixels[i + 2] = 0
            pixels[i + 3] = 255
        }
        let image = try makeImage(from: &pixels, width: size, height: size)
        return Tile(
            image: image,
            origin: origin,
            size: CGSize(width: size, height: size)
        )
    }

    private func makeImage(from pixels: inout [UInt8], width: Int, height: Int) throws -> CGImage {
        guard let context = CGContext(
            data: &pixels,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw ImageIOError.contextCreationFailed
        }
        return image
    }

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
