// ABOUTME: Reads images from disk via CGImageSource (PNG, JPEG, TIFF, HEIC).
// ABOUTME: Extracts colour profile metadata and separates alpha channels for processing.

import CoreGraphics
import Foundation
import ImageIO

/// Result of loading an image — includes the RGB image, optional alpha, and metadata.
public struct LoadedImage {
    public let image: CGImage
    public let alphaChannel: CGImage?
    public let colorSpace: CGColorSpace?
    public let hasAlpha: Bool

    public init(image: CGImage, alphaChannel: CGImage?, colorSpace: CGColorSpace?, hasAlpha: Bool) {
        self.image = image
        self.alphaChannel = alphaChannel
        self.colorSpace = colorSpace
        self.hasAlpha = hasAlpha
    }
}

/// Loads images from disk in common formats using CGImageSource.
public enum ImageLoader {

    /// Load an image from a file URL.
    ///
    /// Detects alpha channels and separates them as a greyscale image
    /// for independent processing. The returned `image` is the RGB data.
    public static func load(from url: URL) throws -> LoadedImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageIOError.cannotReadFile(url.path)
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageIOError.cannotDecodeImage(url.path)
        }

        let colorSpace = cgImage.colorSpace
        let alphaInfo = cgImage.alphaInfo
        let hasAlpha = alphaInfo != .none && alphaInfo != .noneSkipLast
                       && alphaInfo != .noneSkipFirst

        var alphaChannel: CGImage?
        if hasAlpha {
            alphaChannel = extractAlpha(from: cgImage)
        }

        return LoadedImage(
            image: cgImage,
            alphaChannel: alphaChannel,
            colorSpace: colorSpace,
            hasAlpha: hasAlpha
        )
    }

    /// Extract the alpha channel from an image as a greyscale CGImage.
    public static func extractAlpha(from image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height

        // Render the image to get raw RGBA pixel data
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixelData,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Extract alpha bytes into a greyscale buffer
        var alphaData = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            alphaData[i] = pixelData[i * 4 + 3]  // Alpha is the 4th byte (RGBA)
        }

        // Create greyscale image from alpha data
        let greySpace = CGColorSpaceCreateDeviceGray()
        guard let alphaContext = CGContext(
            data: &alphaData,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: greySpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        return alphaContext.makeImage()
    }

    /// Recombine an RGB image with a greyscale alpha channel.
    ///
    /// Both images must have the same dimensions.
    public static func recombineAlpha(rgb: CGImage, alpha: CGImage) throws -> CGImage {
        let width = rgb.width
        let height = rgb.height

        guard alpha.width == width, alpha.height == height else {
            throw ImageIOError.dimensionMismatch(
                "RGB (\(width)×\(height)) vs alpha (\(alpha.width)×\(alpha.height))")
        }

        // Render RGB to get pixel data
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var rgbData = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let rgbContext = CGContext(
            data: &rgbData,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageIOError.contextCreationFailed
        }
        rgbContext.draw(rgb, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Render alpha to get greyscale data
        let greySpace = CGColorSpaceCreateDeviceGray()
        var alphaData = [UInt8](repeating: 0, count: width * height)

        guard let alphaContext = CGContext(
            data: &alphaData,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: greySpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw ImageIOError.contextCreationFailed
        }
        alphaContext.draw(alpha, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Merge alpha into RGBA data
        for i in 0..<(width * height) {
            rgbData[i * 4 + 3] = alphaData[i]
        }

        // Create output image with alpha
        guard let outContext = CGContext(
            data: &rgbData,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageIOError.contextCreationFailed
        }

        guard let result = outContext.makeImage() else {
            throw ImageIOError.contextCreationFailed
        }
        return result
    }
}

/// Errors from image loading and writing operations.
public enum ImageIOError: Error, CustomStringConvertible {
    case cannotReadFile(String)
    case cannotDecodeImage(String)
    case cannotWriteFile(String)
    case unsupportedFormat(String)
    case dimensionMismatch(String)
    case contextCreationFailed

    public var description: String {
        switch self {
        case .cannotReadFile(let path):
            return "Cannot read file: \(path)"
        case .cannotDecodeImage(let path):
            return "Cannot decode image: \(path)"
        case .cannotWriteFile(let path):
            return "Cannot write file: \(path)"
        case .unsupportedFormat(let fmt):
            return "Unsupported image format: \(fmt)"
        case .dimensionMismatch(let msg):
            return "Dimension mismatch: \(msg)"
        case .contextCreationFailed:
            return "Failed to create graphics context"
        }
    }
}
