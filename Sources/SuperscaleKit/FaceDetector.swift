// ABOUTME: Detects face regions in images using Apple's Vision framework.
// ABOUTME: Uses VNDetectFaceRectanglesRequest for native, fast face detection.

import CoreGraphics
import Vision

/// Detects face bounding boxes in images using Apple's VNDetectFaceRectanglesRequest.
///
/// This uses the built-in macOS face detector (available since macOS 10.13),
/// providing fast, native face detection with no external dependencies.
public enum FaceDetector {

    /// Detect face bounding boxes in an image.
    ///
    /// - Parameter image: The image to scan for faces.
    /// - Returns: Array of face rectangles in pixel coordinates (origin at top-left).
    public static func detect(in image: CGImage) throws -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let observations = request.results else {
            return []
        }

        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)

        // Convert normalized Vision coordinates to pixel coordinates.
        // Vision uses bottom-left origin with normalized [0,1] coordinates.
        return observations.map { face in
            let box = face.boundingBox
            return CGRect(
                x: box.origin.x * imageWidth,
                y: (1.0 - box.origin.y - box.height) * imageHeight,
                width: box.width * imageWidth,
                height: box.height * imageHeight
            )
        }
    }

    /// Expand a face rectangle by a padding factor for context.
    ///
    /// The upstream GFPGAN implementation uses 1.5× the face bounding box.
    /// The expanded rect is clamped to image bounds.
    ///
    /// - Parameters:
    ///   - rect: Face bounding box in pixel coordinates.
    ///   - factor: Expansion factor (1.5 = 50% padding on each side).
    ///   - imageWidth: Image width for clamping.
    ///   - imageHeight: Image height for clamping.
    /// - Returns: Expanded and clamped rectangle.
    public static func expandRect(
        _ rect: CGRect,
        by factor: CGFloat = 1.5,
        imageWidth: Int,
        imageHeight: Int
    ) -> CGRect {
        let expandW = rect.width * (factor - 1.0) / 2.0
        let expandH = rect.height * (factor - 1.0) / 2.0

        let x = max(0, rect.origin.x - expandW)
        let y = max(0, rect.origin.y - expandH)
        let w = min(CGFloat(imageWidth) - x, rect.width + expandW * 2)
        let h = min(CGFloat(imageHeight) - y, rect.height + expandH * 2)

        return CGRect(x: x, y: y, width: w, height: h)
    }
}
