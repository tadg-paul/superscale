// ABOUTME: Writes images to disk via CGImageDestination (PNG, JPEG).
// ABOUTME: Preserves colour profiles from input and handles format selection.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Supported output image formats.
public enum OutputFormat {
    case png
    case jpeg

    var utType: CFString {
        switch self {
        case .png: return UTType.png.identifier as CFString
        case .jpeg: return UTType.jpeg.identifier as CFString
        }
    }

    /// Infer output format from a file extension.
    public static func from(extension ext: String) -> OutputFormat? {
        switch ext.lowercased() {
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        default: return nil
        }
    }
}

/// Writes CGImage instances to disk with format and colour profile options.
public enum ImageWriter {

    /// Write an image to a file URL.
    ///
    /// - Parameters:
    ///   - image: The image to write.
    ///   - url: Destination file URL.
    ///   - format: Output format (PNG or JPEG).
    ///   - colorSpace: Colour space to embed. Pass nil to use the image's own colour space.
    public static func write(
        _ image: CGImage,
        to url: URL,
        format: OutputFormat,
        colorSpace: CGColorSpace?
    ) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, format.utType, 1, nil
        ) else {
            throw ImageIOError.cannotWriteFile(url.path)
        }

        // Embed colour profile if provided — re-render image with the target colour space
        // rather than injecting ICC data, as CGImageDestination handles profile embedding
        // when the image carries the correct colour space
        let outputImage: CGImage
        if let space = colorSpace, image.colorSpace?.name != space.name {
            // Re-render the image in the target colour space
            if let ctx = CGContext(
                data: nil,
                width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) {
                ctx.draw(image, in: CGRect(x: 0, y: 0,
                                           width: image.width, height: image.height))
                outputImage = ctx.makeImage() ?? image
            } else {
                outputImage = image
            }
        } else {
            outputImage = image
        }

        CGImageDestinationAddImage(destination, outputImage, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageIOError.cannotWriteFile(url.path)
        }
    }

    /// Generate an output filename from an input filename.
    ///
    /// Appends `_{scale}x` before the extension. Integer scales produce `_4x`,
    /// fractional scales produce `_2.4x`.
    public static func outputFilename(for inputPath: String, scale: Double) -> String {
        let url = URL(fileURLWithPath: inputPath)
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let scaleStr: String
        if scale == scale.rounded(.towardZero) && scale >= 1 {
            scaleStr = "\(Int(scale))x"
        } else {
            scaleStr = String(format: "%.1fx", scale)
        }
        return "\(stem)_\(scaleStr).\(ext)"
    }
}
