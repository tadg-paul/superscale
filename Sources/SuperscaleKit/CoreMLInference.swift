// ABOUTME: Loads a CoreML .mlpackage model and runs image upscaling inference.
// ABOUTME: Wraps Vision framework's VNCoreMLRequest for single-image prediction.

import CoreML
import Vision
import CoreGraphics
import CoreImage

/// Runs super-resolution inference on a single image using a CoreML model.
public struct CoreMLInference {
    public let mlModel: MLModel
    public let vnModel: VNCoreMLModel

    /// Load a CoreML model from an `.mlpackage` directory URL.
    ///
    /// Uses the compiled model cache to avoid recompilation on subsequent loads.
    /// - Parameter modelURL: Path to the `.mlpackage` directory.
    public init(modelURL: URL) throws {
        let compiledURL = try ModelCache.loadCompiledModel(at: modelURL)
        mlModel = try MLModel(contentsOf: compiledURL)
        vnModel = try VNCoreMLModel(for: mlModel)
    }

    /// Upscale an image through the loaded model.
    ///
    /// The input image is fed to the model via Vision framework. The model
    /// determines the output dimensions (input tile size × scale factor).
    ///
    /// - Parameter image: Input image (any size — Vision resizes to model's expected input).
    /// - Returns: Upscaled output image.
    public func upscale(_ image: CGImage) throws -> CGImage {
        var outputImage: CGImage?
        var inferenceError: Error?

        let request = VNCoreMLRequest(model: vnModel) { request, error in
            if let error = error {
                inferenceError = error
                return
            }
            guard let observations = request.results as? [VNPixelBufferObservation],
                  let pixelBuffer = observations.first?.pixelBuffer else {
                inferenceError = SuperscaleError.noModelOutput
                return
            }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            outputImage = context.createCGImage(ciImage, from: ciImage.extent)
        }

        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        if let error = inferenceError {
            throw error
        }
        guard let result = outputImage else {
            throw SuperscaleError.noModelOutput
        }
        return result
    }
}

/// Errors specific to the Superscale inference pipeline.
public enum SuperscaleError: Error, CustomStringConvertible {
    case noModelOutput
    case modelNotFound(String)

    public var description: String {
        switch self {
        case .noModelOutput:
            return "Model produced no output image."
        case .modelNotFound(let name):
            return "Model not found: \(name). Run 'make convert-models' or download via --download-models."
        }
    }
}
