// ABOUTME: Verifies that a picture is measured in pixels, through the one function that measures.
// ABOUTME: Two paths measured pictures and disagreed for months, and no test could tell them apart.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import SuperscaleUXCore

/// What the application records as a picture's size.
///
/// The six tests in `ImageIOTests` pin `SuperscaleKit`'s contract, which was never broken. **These
/// pin the function that was.** `MainView.importedPixelSize` used `NSImage.size`, which reports
/// points adjusted by the file's stored resolution, and it was private to a view and exercised by
/// nothing.
final class ImageDimensionsTests: XCTestCase {

    /// A per-run directory beneath the operating system's temporary directory.
    ///
    /// Removed exactly, never a shared parent, on success and on failure alike.
    private func scratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dimensions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    /// Writes a picture of a given size, recording the resolution asked for.
    ///
    /// Each fixture in this file has **distinct dimensions**, so an implementation returning a
    /// hard-coded pair fails rather than passing every test in the group.
    @discardableResult
    private func writeImage(
        width: Int, height: Int,
        resolution: (horizontal: Double, vertical: Double)?,
        named name: String,
        in directory: URL
    ) throws -> URL {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())

        let url = directory.appendingPathComponent(name)
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil))

        var properties: [CFString: Any] = [:]
        if let resolution {
            properties[kCGImagePropertyDPIWidth] = resolution.horizontal
            properties[kCGImagePropertyDPIHeight] = resolution.vertical
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination), "the fixture was written")
        return url
    }

    // RT-100.7
    //
    // The defect itself. A 2048 x 1536 photograph at 300 dpi measures about 492 x 369 through
    // `NSImage.size`, so the floor judges it undersized, raises it 4x it does not need, alters the
    // user's picture and turns their scale selection off — on a photograph twice the minimum.
    func test_aPictureRecording300DPIMeasuresAtItsPixelDimensions_RT100_7() throws {
        let directory = try scratchDirectory()
        let url = try writeImage(
            width: 2048, height: 1536, resolution: (300, 300),
            named: "high.png", in: directory)

        XCTAssertEqual(
            ImageDimensions.pixelSize(of: url), CGSize(width: 2048, height: 1536),
            "pixels, not points")
    }

    // RT-100.8
    //
    // A picture with no resolution recorded at all, which is the commonest real file and a distinct
    // path through `ImageIO` from one recording 72.
    func test_aPictureRecordingNoResolutionMeasuresAtItsPixelDimensions_RT100_8() throws {
        let directory = try scratchDirectory()
        let url = try writeImage(
            width: 1101, height: 733, resolution: nil, named: "bare.png", in: directory)

        XCTAssertEqual(
            ImageDimensions.pixelSize(of: url), CGSize(width: 1101, height: 733))
    }

    // RT-100.9
    //
    // A file that cannot be decoded measures as zero rather than crashing. Reachable rather than
    // theoretical: the function is called on the raise path, where a failed run may have written
    // nothing to the location the graph allocated.
    func test_anUndecodableFileMeasuresAsZeroRatherThanCrashing_RT100_9() throws {
        let directory = try scratchDirectory()
        let url = directory.appendingPathComponent("not-an-image.png")
        try Data("this is not a picture".utf8).write(to: url)

        XCTAssertEqual(ImageDimensions.pixelSize(of: url), .zero)
        XCTAssertEqual(
            ImageDimensions.pixelSize(of: directory.appendingPathComponent("absent.png")), .zero,
            "and a file that is not there at all")
    }

    /// A picture whose axes record different resolutions is still measured in pixels.
    ///
    /// An implementation dividing by a single resolution value passes every square case and is
    /// wrong here.
    func test_differingAxisResolutionsDoNotReachTheMeasurement() throws {
        let directory = try scratchDirectory()
        let url = try writeImage(
            width: 640, height: 960, resolution: (300, 150),
            named: "anisotropic.png", in: directory)

        XCTAssertEqual(
            ImageDimensions.pixelSize(of: url), CGSize(width: 640, height: 960))
    }
}
