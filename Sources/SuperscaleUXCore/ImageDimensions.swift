// ABOUTME: The pixel size of a picture on disk, measured one way for the whole application.
// ABOUTME: Two paths measured pictures and disagreed for months; NSImage.size reports points.

import CoreGraphics
import Foundation
import ImageIO

/// How large a picture is, in pixels.
///
/// **Every sizing decision the application makes is arithmetic on pixels**: the 1024-pixel minimum
/// long edge for filtering, the 32-megapixel output ceiling, the effective-scale readout, and the
/// record of what was sent to the provider against what came back.
///
/// `NSImage.size` does not report pixels. It reports points, adjusted by the resolution stored in
/// the file, so a 2048 x 1536 photograph saved at 300 dpi reports about 492 x 369 — undersized by
/// the floor's reckoning, and raised 4x it does not need.
///
/// One function rather than two. The defect existed *because* the view and the view model each had
/// their own, and nothing could tell them apart.
public enum ImageDimensions {

    /// The picture's size in pixels, or `.zero` where the file cannot be decoded.
    ///
    /// `.zero` rather than a thrown error because every caller is on a path where an unreadable
    /// file is a state to carry rather than a failure to report: a raise whose output was never
    /// written, a source the user has since deleted. Callers guard on a zero size already.
    ///
    /// **Asks the file its size without decoding it.** The obvious implementation calls
    /// `ImageLoader.load`, which runs `CGImageSourceCreateImageAtIndex` to decompress the whole
    /// picture and then, where there is an alpha channel, builds a second full-size plane for it —
    /// roughly 160 MB for a 32-megapixel RGBA output, all discarded, to keep two integers. One
    /// caller measures on import, on the main actor, so that cost is paid on the thread drawing
    /// the window. Properties come from the file's header and cost none of it.
    ///
    /// `kCGImagePropertyPixelWidth` is the stored pixel count, unaffected by the resolution that
    /// caused this issue. It is also uncorrected for EXIF orientation — and so is
    /// `CGImageSourceCreateImageAtIndex`, which is what `SuperscaleKit` upscales. A rotated
    /// photograph therefore measures as the pipeline will actually treat it. An
    /// orientation-correcting source would look more careful and would disagree with the pixels.
    public static func pixelSize(of url: URL) -> CGSize {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return .zero }

        return CGSize(width: width, height: height)
    }
}
