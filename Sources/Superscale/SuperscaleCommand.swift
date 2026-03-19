// ABOUTME: CLI entry point for Superscale.
// ABOUTME: Parses arguments and dispatches to the upscaling pipeline.

import ArgumentParser
import Foundation

@main
struct Superscale: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "superscale",
        abstract: "AI image upscaling for Apple Silicon.",
        version: "0.2.0"
    )

    @Argument(help: "Input image file(s).")
    var inputs: [String] = []

    @Option(name: .shortAndLong, help: "Scale factor (2 or 4).")
    var scale: Int = 4

    @Option(name: .shortAndLong, help: "Output directory.")
    var output: String?

    @Option(name: .shortAndLong, help: "Model name (auto-detected if omitted; see --list-models).")
    var model: String?

    @Option(name: .long, help: "Tile size in pixels (smaller = less memory, more passes).")
    var tileSize: Int?

    @Flag(name: .long, help: "List available models.")
    var listModels: Bool = false

    @Flag(name: .long, help: "Skip face enhancement even when the face model is installed (see --download-face-model).")
    var noFaceEnhance: Bool = false

    @Flag(name: .long, help: "Download the GFPGAN face enhancement model. Once installed, runs automatically on every upscale.")
    var downloadFaceModel: Bool = false

    @Flag(name: .long, help: "Accept the GFPGAN licence (non-commercial use only).")
    var acceptLicence: Bool = false

    mutating func run() throws {
        if downloadFaceModel {
            try handleDownloadFaceModel()
            return
        }

        if listModels {
            print("Models:")
            for model in ModelRegistry.models {
                let status = ModelRegistry.isInstalled(model) ? "installed" : "not installed"
                let defaultLabel = model.isDefault ? " [default]" : ""
                let nameCol = model.name.padding(toLength: 24, withPad: " ", startingAt: 0)
                let descCol = "\(model.displayName)\(defaultLabel)"
                    .padding(toLength: 38, withPad: " ", startingAt: 0)
                print("  \(nameCol) \(descCol) [\(status)]")
            }
            return
        }

        guard !inputs.isEmpty else {
            throw ValidationError("No input files specified.")
        }

        // Create output directory if needed
        let outputDir: URL?
        if let outputPath = output {
            let dirURL = URL(fileURLWithPath: outputPath)
            if !FileManager.default.fileExists(atPath: dirURL.path) {
                try FileManager.default.createDirectory(
                    at: dirURL, withIntermediateDirectories: true)
            }
            outputDir = dirURL
        } else {
            outputDir = nil
        }

        // Resolve model — explicit or auto-detected
        let resolvedModelName: String
        if let explicitModel = model {
            // User explicitly specified -m
            resolvedModelName = explicitModel
            fputs("Using model: \(resolvedModelName)\n", stderr)
        } else {
            // Auto-detect content type from first input image
            let firstInputURL = URL(fileURLWithPath: inputs[0])
            let loaded = try ImageLoader.load(from: firstInputURL)
            let (contentType, _) = try ContentDetector.detect(image: loaded.image)
            resolvedModelName = ContentDetector.modelName(for: contentType, scale: scale)
            fputs("Detected: \(contentType) \u{2192} using \(resolvedModelName)\n", stderr)
        }

        // Validate model exists
        guard let modelInfo = ModelRegistry.model(named: resolvedModelName) else {
            let available = ModelRegistry.models.map { $0.name }.joined(separator: ", ")
            throw ValidationError(
                "Unknown model '\(resolvedModelName)'. Available: \(available)")
        }

        // Face enhancement: automatic when model is present, unless --no-face-enhance
        let useFaceEnhance = !noFaceEnhance && FaceModelRegistry.isInstalled
        if useFaceEnhance {
            fputs("Face enhancement enabled (GFPGAN model found).\n", stderr)
        }

        // Create pipeline
        let pipeline = try Pipeline(
            modelName: resolvedModelName, tileSize: tileSize)
        pipeline.onProgress = { message in
            fputs("\(message)\n", stderr)
        }

        // Process each input file, accumulating errors
        var errors: [(String, Error)] = []

        for inputPath in inputs {
            let inputURL = URL(fileURLWithPath: inputPath)
            let outputFilename = ImageWriter.outputFilename(
                for: inputPath, scale: modelInfo.scale)
            let outputURL: URL
            if let dir = outputDir {
                outputURL = dir.appendingPathComponent(outputFilename)
            } else {
                outputURL = inputURL.deletingLastPathComponent()
                    .appendingPathComponent(outputFilename)
            }

            do {
                try pipeline.process(input: inputURL, output: outputURL)
            } catch {
                errors.append((inputPath, error))
                fputs("Error processing \(inputPath): \(error)\n", stderr)
            }
        }

        if !errors.isEmpty {
            let total = inputs.count
            let failed = errors.count
            fputs("\(failed) of \(total) file(s) failed.\n", stderr)
            if failed == total {
                throw ExitCode.failure
            }
        }
    }

    /// Handle --download-face-model: download GFPGAN weights with licence notice.
    private func handleDownloadFaceModel() throws {
        let licenceNotice = """
        GFPGAN Face Enhancement Model — Licence Notice

        The GFPGAN model contains components with non-commercial licences:
          - StyleGAN2 (NVIDIA): non-commercial use only
          - DFDNet: CC BY-NC-SA 4.0 (non-commercial, share-alike)

        By downloading this model, you acknowledge that it may only be used
        for non-commercial purposes.
        """

        if !acceptLicence {
            // Check if we have a terminal for interactive prompt
            if isatty(fileno(stdin)) != 0 {
                fputs("\(licenceNotice)\n", stderr)
                fputs("Do you accept these terms? [y/N] ", stderr)
                guard let response = readLine(),
                      response.lowercased().hasPrefix("y") else {
                    fputs("Download cancelled.\n", stderr)
                    throw ExitCode.failure
                }
            } else {
                fputs("Error: Licence acceptance required.\n", stderr)
                fputs("Run with --accept-licence to accept non-commercial terms.\n", stderr)
                throw ExitCode.failure
            }
        }

        fputs("Downloading GFPGAN model...\n", stderr)

        let destDir = ModelRegistry.userModelsDirectory
        try FileManager.default.createDirectory(
            at: destDir, withIntermediateDirectories: true)

        let destPath = destDir.appendingPathComponent(
            FaceModelRegistry.modelFilename)

        if FileManager.default.fileExists(atPath: destPath.path) {
            fputs("Face model already installed at \(destPath.path)\n", stderr)
            return
        }

        // Download the CoreML model from our release
        let downloadURL = FaceModelRegistry.downloadURL
        fputs("Downloading from \(downloadURL)...\n", stderr)

        let data = try Data(contentsOf: downloadURL)
        try data.write(to: destPath)

        fputs("Face model installed at \(destPath.path)\n", stderr)
    }
}
