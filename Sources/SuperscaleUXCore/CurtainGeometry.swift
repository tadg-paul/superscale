// ABOUTME: Where the curtain divider sits, given the pointer and the frame the picture occupies.
// ABOUTME: Takes no window, no zoom and no pan, because consulting any of them is the defect.

import CoreGraphics

/// The curtain's arithmetic.
///
/// The divider is a curtain across the *view*, not across the picture's own pixels. Its position is
/// a fraction of the frame the picture is displayed in, and that frame is the same for the base and
/// for any derivation of it, so replacing a picture with its 4x upscale does not move the divider.
///
/// The defect this replaces read `value.location.x / window.contentView.frame.width`: a location
/// local to a 28-point drag handle over the width of the whole window, filter panel included, with
/// a `?? 600` when there was no key window. Three faults in one expression, none of them visible
/// while reading it. The mapping is stated here as a function of exactly two things so that the
/// wrong numbers are not reachable.
public enum CurtainGeometry {

    /// The divider stops short of both ends, so that a sliver of each side always remains and the
    /// handle never leaves the picture.
    public static let minimumFraction: CGFloat = 0.05
    public static let maximumFraction: CGFloat = 0.95

    /// The frame a picture of `imageSize` occupies when fitted into `container`, centred.
    ///
    /// Depends on the aspect ratio alone, never on pixel dimensions, which is what makes a picture
    /// and its upscale share one frame.
    public static func displayedFrame(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
            container.width > 0, container.height > 0
        else {
            return .zero
        }

        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = container.width / container.height

        let size: CGSize =
            imageAspect > containerAspect
            ? CGSize(width: container.width, height: container.width / imageAspect)
            : CGSize(width: container.height * imageAspect, height: container.height)

        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height)
    }

    /// Where the divider belongs for a pointer at `pointerX`, in the same coordinate space as
    /// `frame`.
    public static func dividerFraction(pointerX: CGFloat, in frame: CGRect) -> CGFloat {
        guard frame.width > 0 else { return minimumFraction }

        let fraction = (pointerX - frame.minX) / frame.width
        return min(max(fraction, minimumFraction), maximumFraction)
    }

    /// Where to draw the divider for a given fraction, in the same coordinate space as `frame`.
    public static func dividerX(fraction: CGFloat, in frame: CGRect) -> CGFloat {
        frame.minX + frame.width * fraction
    }

    /// Whether a scroll at `location` belongs to the picture.
    ///
    /// `ComparisonView` panned the image from an `NSEvent` monitor that never asked where the
    /// pointer was, so scrolling the filter category strip moved the photograph. A monitor is a
    /// global interception dressed as a view behaviour: it fires for the toolbar, the side panel,
    /// the lock chain and the status bar alike.
    public static func scrollBelongsToPicture(at location: CGPoint, in frame: CGRect) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        return frame.contains(location)
    }
}
