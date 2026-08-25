// ABOUTME: The pixel size of a picture on disk, measured one way for the whole application.
// ABOUTME: Two paths measured pictures and disagreed for months; NSImage.size reports points.

import CoreGraphics
import Foundation
import SuperscaleKit

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
    public static func pixelSize(of url: URL) -> CGSize {
        guard let loaded = try? ImageLoader.load(from: url) else { return .zero }
        return CGSize(width: loaded.image.width, height: loaded.image.height)
    }
}
