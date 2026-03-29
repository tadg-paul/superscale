// ABOUTME: Registry of supported Real-ESRGAN models and their metadata.
// ABOUTME: Provides model lookup, path resolution, and installation status.

import Foundation

/// Metadata for a single supported model.
public struct ModelInfo {
    public let name: String               // CLI name, e.g. "realesrgan-x4plus"
    public let displayName: String        // Human-readable, e.g. "General photo (4×)"
    public let filename: String           // CoreML package name
    public let scale: Int                 // 2 or 4
    public let tileSize: Int              // Recommended tile size in pixels
    public let isDefault: Bool            // Whether this is the default model
    public let shortDescription: String   // One-line summary for pickers/lists
    public let detailedDescription: String // Full description for help text/info panels

    public init(name: String, displayName: String, filename: String, scale: Int, tileSize: Int, isDefault: Bool,
                shortDescription: String, detailedDescription: String) {
        self.name = name
        self.displayName = displayName
        self.filename = filename
        self.scale = scale
        self.tileSize = tileSize
        self.isDefault = isDefault
        self.shortDescription = shortDescription
        self.detailedDescription = detailedDescription
    }
}

/// Static catalogue of supported models and their storage locations.
public enum ModelRegistry {

    public static let models: [ModelInfo] = [
        ModelInfo(
            name: "realesrgan-x4plus",
            displayName: "General photo (4×)",
            filename: "RealESRGAN_x4plus.mlpackage",
            scale: 4, tileSize: 512, isDefault: true,
            shortDescription: "General photographs — balanced sharpening and detail (default)",
            detailedDescription: "Best for general photographs. Balanced sharpening and detail preservation. RRDBNet architecture (23 residual blocks). The default when no model is specified and the image is detected as a photograph."
        ),
        ModelInfo(
            name: "realesrgan-x2plus",
            displayName: "General photo (2×)",
            filename: "RealESRGAN_x2plus.mlpackage",
            scale: 2, tileSize: 512, isDefault: false,
            shortDescription: "General photographs at 2× — closer to source, less hallucination",
            detailedDescription: "General photographs at 2× scale. Preserves more original detail with less hallucination than 4× models. Use when you need a lighter upscale or want to stay closer to the source."
        ),
        ModelInfo(
            name: "realesrnet-x4plus",
            displayName: "General photo, PSNR-oriented (4×)",
            filename: "RealESRNet_x4plus.mlpackage",
            scale: 4, tileSize: 512, isDefault: false,
            shortDescription: "PSNR-oriented — less sharpening, fewer artefacts",
            detailedDescription: "PSNR-oriented variant — less aggressive sharpening, fewer artefacts. Preferred for images where fidelity matters more than perceived sharpness (e.g. medical, scientific)."
        ),
        ModelInfo(
            name: "realesrgan-anime-6b",
            displayName: "Anime/illustration (4×)",
            filename: "RealESRGAN_x4plus_anime_6B.mlpackage",
            scale: 4, tileSize: 512, isDefault: false,
            shortDescription: "Anime and cel-shaded illustration — clean lines, flat colour",
            detailedDescription: "Optimized for anime and cel-shaded illustration. Preserves flat colour regions and clean line art. 6-block RRDBNet — lighter than the full 23-block photo models."
        ),
        ModelInfo(
            name: "realesr-animevideov3",
            displayName: "Anime video frames (4×)",
            filename: "realesr-animevideov3.mlpackage",
            scale: 4, tileSize: 512, isDefault: false,
            shortDescription: "Anime video frames — fast, temporally consistent",
            detailedDescription: "Compact model designed for anime video frame consistency. SRVGGNetCompact architecture — faster inference, suitable for batch processing of animation frames."
        ),
        ModelInfo(
            name: "realesr-general-x4v3",
            displayName: "General scenes, compact (4×)",
            filename: "realesr-general-x4v3.mlpackage",
            scale: 4, tileSize: 512, isDefault: false,
            shortDescription: "General scenes — faster, lighter than x4plus",
            detailedDescription: "General scenes with SRVGGNetCompact architecture — faster and lighter than x4plus. Good when speed matters more than maximum quality."
        ),
        ModelInfo(
            name: "realesr-general-wdn-x4v3",
            displayName: "General scenes with denoise (4×)",
            filename: "realesr-general-wdn-x4v3.mlpackage",
            scale: 4, tileSize: 512, isDefault: false,
            shortDescription: "Denoise + upscale — for grainy photos and compressed sources",
            detailedDescription: "Denoise variant of general-x4v3. Effective for old photographs, grainy scans, and heavily compressed JPEG sources. Reduces noise while upscaling."
        ),
    ]

    /// User-side model storage directory (macOS convention, sandbox-compatible).
    public static var userModelsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("superscale")
            .appendingPathComponent("models")
    }

    /// Search paths for installed model files, in priority order.
    public static var searchPaths: [URL] {
        var paths: [URL] = []

        // 1a. Models directory next to the executable (direct install)
        if let execURL = Bundle.main.executableURL {
            let resolved = execURL.resolvingSymlinksInPath()
            let alongside = resolved.deletingLastPathComponent()
                .appendingPathComponent("models")
            paths.append(alongside)

            // 1b. Models in Cellar prefix (Homebrew layout: <prefix>/bin/superscale → <prefix>/models/)
            let cellar = resolved.deletingLastPathComponent()  // bin/
                .deletingLastPathComponent()  // prefix/
                .appendingPathComponent("models")
            if cellar != alongside {
                paths.append(cellar)
            }
        }

        // 2. User application support directory
        paths.append(userModelsDirectory)

        // 3. Working directory models/ (development and testing)
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        paths.append(cwd.appendingPathComponent("models"))

        return paths
    }

    /// Check whether a model's .mlpackage file exists at any search path.
    public static func isInstalled(_ model: ModelInfo) -> Bool {
        for path in searchPaths {
            let modelURL = path.appendingPathComponent(model.filename)
            if FileManager.default.fileExists(atPath: modelURL.path) {
                return true
            }
        }
        return false
    }

    /// Find a model by its CLI name.
    public static func model(named name: String) -> ModelInfo? {
        models.first { $0.name == name }
    }

    /// Resolve a CLI model name to the URL of its `.mlpackage` file.
    ///
    /// Searches all known paths in priority order. Returns nil if the model
    /// name is unknown or the package file is not installed at any location.
    public static func modelURL(for name: String) -> URL? {
        guard let model = model(named: name) else {
            return nil
        }
        for path in searchPaths {
            let url = path.appendingPathComponent(model.filename)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// The default model (always present).
    public static var defaultModel: ModelInfo {
        models.first { $0.isDefault }!
    }
}
