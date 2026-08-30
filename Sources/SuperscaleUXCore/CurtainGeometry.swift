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
    ///
    /// **Use this for one picture. Use `pairedFrames` for two.** Fitting two pictures with this
    /// function independently gives each the largest frame its own shape allows, so two shapes get
    /// two different widths — and the curtain's single vertical divider then falls at a different
    /// fraction of each. That is the defect #96 fixed, and grok produces it on any picture whose
    /// short edge is under 1024, by returning a square.
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

    /// How wide the divider's handle is drawn.
    public static let handleDiameter: CGFloat = 28

    /// How wide the divider's handle is to the pointer.
    ///
    /// Larger than what is drawn, and that is the point of it. The drag gesture sat on the 28-point
    /// circle itself, so the reachable target and the painted one were the same thing --- over a
    /// photograph that also accepts a drag, which is why the author reported *"I always end up
    /// grabbing the image and moving it instead"*. Always, not sometimes.
    ///
    /// 44 points is the target size the platform's own guidance asks for, and it is the reason to
    /// prefer a number over "bigger". The circle stays 28: how reachable a control is and how large
    /// it looks are different questions, and only the first is about whether it can be taken hold
    /// of.
    public static let handleHitDiameter: CGFloat = 44

    /// Where the divider belongs after a scroll of `delta` from `fraction`.
    ///
    /// **Takes both axes and uses whichever dominates.** A trackpad's sideways swipe reports
    /// `scrollingDeltaX`; **a wheel mouse reports only `scrollingDeltaY` and no X at all**, so a
    /// mapping written against X alone would do nothing for most mice while looking correct on the
    /// machine it was written on.
    ///
    /// The sign is used as reported rather than negated. macOS applies the user's natural-scrolling
    /// preference to the deltas before they arrive, so following the sign *is* following the
    /// preference; inverting here would fight it for half of all users.
    ///
    /// Clamped by `dividerFraction`'s own bounds, reached through the same call the pointer path
    /// uses, so a scroll and a drag cannot come to disagree about where the divider may go.
    public static func dividerFraction(
        scrolledFrom fraction: CGFloat, byX deltaX: CGFloat, y deltaY: CGFloat, in frame: CGRect
    ) -> CGFloat {
        guard frame.width > 0 else { return fraction }

        let dominant = abs(deltaX) >= abs(deltaY) ? deltaX : deltaY
        let x = dividerX(fraction: fraction, in: frame) + dominant
        return dividerFraction(pointerX: x, in: frame)
    }

    /// Frames for two pictures that may not be the same shape.
    ///
    /// Grok squares anything whose short edge is under 1024, so a 3:4 original can come back 1:1.
    /// AC90.10 required both sides at "one displayed size", which is right when the shapes match and
    /// is exactly what breaks when they do not: one size means one rectangle, and something has to
    /// be stretched to fill it.
    ///
    /// **The two share a width and differ in height.** A vertical divider then falls at the same
    /// fraction of width on each side, so it means the same thing on both, while each picture keeps
    /// its own proportions. A 1:1 return simply appears shorter than a 3:4 original, which is
    /// honest — it is a different shape.
    ///
    /// The width is the largest at which *both* fit: the container's, unless the taller side would
    /// then exceed the container's height, in which case whatever width makes it exactly fit. Using
    /// the full width unconditionally clips the more portrait of the two off the bottom.
    /// **Use this for the curtain's two sides. Use `displayedFrame` for a single picture.** This
    /// gives both a shared width so one divider means one thing on each; a lone picture given a
    /// shared width with nothing has simply been fitted, which `displayedFrame` says more plainly.
    public static func pairedFrames(
        first: CGSize, second: CGSize, in container: CGSize
    ) -> (first: CGRect, second: CGRect) {
        guard first.width > 0, first.height > 0, second.width > 0, second.height > 0,
            container.width > 0, container.height > 0
        else {
            return (.zero, .zero)
        }

        // The taller of the two at any given width is the one with the smaller aspect ratio.
        let tallestInverseAspect = max(first.height / first.width, second.height / second.width)
        let widthLimitedByHeight = container.height / tallestInverseAspect
        let sharedWidth = min(container.width, widthLimitedByHeight)

        func frame(for size: CGSize) -> CGRect {
            let height = sharedWidth * (size.height / size.width)
            return CGRect(
                x: (container.width - sharedWidth) / 2,
                y: (container.height - height) / 2,
                width: sharedWidth,
                height: height)
        }

        return (frame(for: first), frame(for: second))
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
