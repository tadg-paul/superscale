// ABOUTME: Registry for the optional GFPGAN face enhancement model.
// ABOUTME: Manages download URL, installation status, and model path resolution.

import Foundation

/// Registry for the optional GFPGAN face enhancement model.
///
/// Unlike the upscaling models (bundled with every install), the GFPGAN model
/// is an optional user-initiated download due to its non-commercial licence.
public enum FaceModelRegistry {

    /// CoreML package filename for the GFPGAN model.
    public static let modelFilename = "GFPGANv1.4.mlpackage"

    /// Download URL for the converted CoreML GFPGAN model.
    ///
    /// The model is hosted on our GitHub release and has been pre-converted
    /// from the original PyTorch weights.
    public static let downloadURL = URL(
        string: "https://github.com/tigger04/superscale/releases/download/models-v1/GFPGANv1.4.mlpackage.zip"
    )!

    /// Check whether the GFPGAN model is installed.
    public static var isInstalled: Bool {
        if let url = modelURL {
            return FileManager.default.fileExists(atPath: url.path)
        }
        return false
    }

    /// Resolve the GFPGAN model path, searching all known locations.
    ///
    /// Searches the same paths as the upscaling models, plus the user
    /// application support directory.
    public static var modelURL: URL? {
        for path in ModelRegistry.searchPaths {
            let url = path.appendingPathComponent(modelFilename)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}
