// ABOUTME: Circular magnifier loupe showing split before/after comparison.
// ABOUTME: Left half shows original (nearest-neighbour), right half shows upscaled, at high magnification.

import SwiftUI

/// A circular magnifier loupe that shows a split before/after view at the cursor position.
///
/// The left semicircle shows the original image with nearest-neighbour interpolation
/// (revealing actual source pixels). The right semicircle shows the upscaled image.
/// Both halves show the same region at the same magnification.
struct MagnifierView: View {
    let original: NSImage
    let upscaled: NSImage
    let position: CGPoint
    let viewSize: CGSize
    let diameter: CGFloat
    let magnification: CGFloat

    var body: some View {
        let crops = computeCrops()

        ZStack {
            // Left semicircle: original (nearest-neighbour — shows source pixels)
            if let origCrop = crops.original {
                Image(nsImage: origCrop)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: diameter, height: diameter)
                    .clipShape(LeftSemicircle())
            }

            // Right semicircle: upscaled
            if let upCrop = crops.upscaled {
                Image(nsImage: upCrop)
                    .interpolation(.high)
                    .resizable()
                    .frame(width: diameter, height: diameter)
                    .clipShape(RightSemicircle())
            }

            // Centre divider line
            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: diameter)
                .shadow(color: .black.opacity(0.5), radius: 1)

            // Border
            Circle()
                .stroke(Color.white, lineWidth: 2.5)
                .shadow(color: .black.opacity(0.4), radius: 3)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.3), radius: 6)
        .accessibilityIdentifier("magnifierLoupe")
    }

    // MARK: - Crop computation

    private struct CropResult {
        let original: NSImage?
        let upscaled: NSImage?
    }

    private func computeCrops() -> CropResult {
        let fitSize = computeFitSize(for: upscaled.size, in: viewSize)

        // Image origin within the view (centred by aspect-fit)
        let imageOriginX = (viewSize.width - fitSize.width) / 2
        let imageOriginY = (viewSize.height - fitSize.height) / 2

        // Normalised position within the image [0, 1]
        let normX = (position.x - imageOriginX) / fitSize.width
        let normY = (position.y - imageOriginY) / fitSize.height

        guard normX >= 0, normX <= 1, normY >= 0, normY <= 1 else {
            return CropResult(original: nil, upscaled: nil)
        }

        // Source region size in normalised coords
        let sourceWidthNorm = (diameter / magnification) / fitSize.width
        let sourceHeightNorm = (diameter / magnification) / fitSize.height

        let origCrop = cropRegion(
            from: original, normX: normX, normY: normY,
            normW: sourceWidthNorm, normH: sourceHeightNorm)
        let upCrop = cropRegion(
            from: upscaled, normX: normX, normY: normY,
            normW: sourceWidthNorm, normH: sourceHeightNorm)

        return CropResult(original: origCrop, upscaled: upCrop)
    }

    private func cropRegion(
        from image: NSImage, normX: CGFloat, normY: CGFloat,
        normW: CGFloat, normH: CGFloat
    ) -> NSImage? {
        guard let cgImage = image.cgImage(
            forProposedRect: nil, context: nil, hints: nil
        ) else {
            return nil
        }

        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)

        // Compute crop rect in pixel coordinates
        var cropX = (normX - normW / 2) * imgW
        var cropY = (normY - normH / 2) * imgH
        var cropW = normW * imgW
        var cropH = normH * imgH

        // Clamp to image bounds
        if cropX < 0 { cropW += cropX; cropX = 0 }
        if cropY < 0 { cropH += cropY; cropY = 0 }
        if cropX + cropW > imgW { cropW = imgW - cropX }
        if cropY + cropH > imgH { cropH = imgH - cropY }

        guard cropW > 0, cropH > 0 else { return nil }

        let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }

        return NSImage(
            cgImage: cropped,
            size: NSSize(width: cropped.width, height: cropped.height))
    }

    // MARK: - Geometry helpers

    private func computeFitSize(for imageSize: NSSize, in viewSize: CGSize) -> CGSize {
        let imgAspect = imageSize.width / max(imageSize.height, 1)
        let viewAspect = viewSize.width / max(viewSize.height, 1)
        if imgAspect > viewAspect {
            return CGSize(
                width: viewSize.width,
                height: viewSize.width / imgAspect)
        } else {
            return CGSize(
                width: viewSize.height * imgAspect,
                height: viewSize.height)
        }
    }
}

/// Checks whether a mouse position is within the aspect-fit image area.
func isMouseOverImage(
    position: CGPoint, imageSize: NSSize, viewSize: CGSize
) -> Bool {
    let imgAspect = imageSize.width / max(imageSize.height, 1)
    let viewAspect = viewSize.width / max(viewSize.height, 1)
    let fitW: CGFloat
    let fitH: CGFloat
    if imgAspect > viewAspect {
        fitW = viewSize.width
        fitH = viewSize.width / imgAspect
    } else {
        fitH = viewSize.height
        fitW = viewSize.height * imgAspect
    }
    let originX = (viewSize.width - fitW) / 2
    let originY = (viewSize.height - fitH) / 2
    return position.x >= originX && position.x <= originX + fitW
        && position.y >= originY && position.y <= originY + fitH
}

// MARK: - Semicircle clip shapes

/// Clips to the left half of the bounding rect.
struct LeftSemicircle: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: 0, y: 0, width: rect.width / 2, height: rect.height))
    }
}

/// Clips to the right half of the bounding rect.
struct RightSemicircle: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(
            x: rect.width / 2, y: 0,
            width: rect.width / 2, height: rect.height))
    }
}
