// ABOUTME: CLI entry point for Superscale.
// ABOUTME: Parses arguments and dispatches to the upscaling pipeline.

import ArgumentParser
import Foundation

@main
struct Superscale: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "superscale",
        abstract: "AI image upscaling for Apple Silicon.",
        version: "v1.0.1 Superscale by Taḋg Paul",
        helpNames: []
    )

    @Argument(help: "Input image file(s).")
    var inputs: [String] = []

    @Option(name: .shortAndLong, help: "Scale factor (e.g. 2, 4, 2.4). Default: 4.")
    var scale: Double?

    @Option(name: .shortAndLong, help: "Output directory.")
    var output: String?

    @Option(name: .shortAndLong, help: "Model name (auto-detected if omitted; see --list-models).")
    var model: String?

    @Option(name: .long, help: "Target output width in pixels.")
    var width: Int?

    @Option(name: .long, help: "Target output height in pixels.")
    var height: Int?

    @Flag(name: .long, help: "Stretch to exact --width and --height, ignoring aspect ratio.")
    var stretch: Bool = false

    @Option(name: .long, help: "Tile size in pixels (smaller = less memory, more passes).")
    var tileSize: Int?

    @Flag(name: .long, help: "List available models.")
    var listModels: Bool = false

    @Flag(name: .long, help: "Skip face enhancement even when the face model is installed (see --download-face-model).")
    var noFaceEnhance: Bool = false

    @Flag(name: .long, help: "Download the GFPGAN face enhancement model. Once installed, runs automatically on every upscale.")
    var downloadFaceModel: Bool = false

    @Flag(name: .long, help: "Clear the compiled model cache. Models will be recompiled on next use.")
    var clearCache: Bool = false

    @Flag(name: [.customShort("h"), .customLong("help")], help: "Show help information.")
    var showHelp: Bool = false

    mutating func run() throws {
        if showHelp {
            Pager.display(coloured: HelpText.coloured, plain: HelpText.plain)
            return
        }

        if clearCache {
            try ModelCache.clearCache()
            fputs("Compiled model cache cleared.\n", stderr)
            return
        }

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
            print("")
            print("Face enhancement:")
            let faceNameCol = "gfpgan-v1.4".padding(toLength: 24, withPad: " ", startingAt: 0)
            if FaceModelRegistry.isInstalled {
                let faceDescCol = "Face enhancement (optional)"
                    .padding(toLength: 38, withPad: " ", startingAt: 0)
                print("  \(faceNameCol) \(faceDescCol) [installed]")
            } else {
                let faceDescCol = "Face enhancement (optional)"
                    .padding(toLength: 38, withPad: " ", startingAt: 0)
                print("  \(faceNameCol) \(faceDescCol) [not installed]")
                print("  Install with: superscale --download-face-model")
            }
            return
        }

        guard !inputs.isEmpty else {
            throw ValidationError("No input files specified.")
        }

        // Validate target resolution options
        if scale != nil && (width != nil || height != nil) {
            throw ValidationError(
                "Cannot specify both --scale and --width/--height.")
        }
        if stretch && (width == nil || height == nil) {
            throw ValidationError(
                "--stretch requires both --width and --height.")
        }
        if let s = scale, s <= 0 {
            throw ValidationError("--scale must be a positive number.")
        }

        // Determine the model scale (2 or 4) for auto-detection
        let modelScale: Int
        if let s = scale, s > 0, s <= 2.0 {
            modelScale = 2
        } else {
            modelScale = 4
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
            resolvedModelName = ContentDetector.modelName(
                for: contentType, scale: modelScale)
            fputs("Detected: \(contentType) \u{2192} using \(resolvedModelName)\n", stderr)
        }

        // Validate model exists
        guard let resolvedModelInfo = ModelRegistry.model(named: resolvedModelName) else {
            let available = ModelRegistry.models.map { $0.name }.joined(separator: ", ")
            throw ValidationError(
                "Unknown model '\(resolvedModelName)'. Available: \(available)")
        }

        // Effective scale for output filename (model native when using --width/--height)
        let filenameScale: Double = scale ?? Double(resolvedModelInfo.scale)

        // Face enhancement: automatic when model is present, unless --no-face-enhance
        let useFaceEnhance = !noFaceEnhance && FaceModelRegistry.isInstalled
        if useFaceEnhance {
            fputs("Face enhancement enabled (GFPGAN model found).\n", stderr)
        }

        // Create pipeline
        let pipeline = try Pipeline(
            modelName: resolvedModelName, tileSize: tileSize,
            faceEnhance: useFaceEnhance)
        pipeline.onProgress = { message in
            fputs("\(message)\n", stderr)
        }

        // Process each input file, accumulating errors
        var errors: [(String, Error)] = []

        for inputPath in inputs {
            let inputURL = URL(fileURLWithPath: inputPath)
            let outputFilename = ImageWriter.outputFilename(
                for: inputPath, scale: filenameScale)
            let outputURL: URL
            if let dir = outputDir {
                outputURL = dir.appendingPathComponent(outputFilename)
            } else {
                outputURL = inputURL.deletingLastPathComponent()
                    .appendingPathComponent(outputFilename)
            }

            do {
                try pipeline.process(
                    input: inputURL, output: outputURL,
                    requestedScale: scale,
                    targetWidth: width, targetHeight: height,
                    stretch: stretch)
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

        This downloads CoreML-converted weights derived from GFPGAN, for use
        on Apple Silicon. The weights contain components with non-commercial
        licences:

          - StyleGAN2 (NVIDIA Source Code Licence — non-commercial use only)
            https://github.com/NVlabs/stylegan2/blob/master/LICENSE.txt

          - DFDNet (CC BY-NC-SA 4.0 — non-commercial, share-alike)
            https://creativecommons.org/licenses/by-nc-sa/4.0/

        By downloading, you confirm that:
          - You will use this model for non-commercial purposes only
          - Any redistribution of these weights must carry the same licence terms

        Full licence details: docs/model-licensing.md
        """

        // Licence acceptance requires an interactive terminal
        guard isatty(fileno(stdin)) != 0 else {
            fputs("Error: --download-face-model requires an interactive terminal.\n", stderr)
            fputs("Run this command in a terminal to view and accept the licence terms.\n", stderr)
            throw ExitCode.failure
        }

        fputs("\(licenceNotice)\n", stderr)
        fputs("Do you accept these terms? [y/N] ", stderr)
        guard let response = readLine(),
              response.lowercased().hasPrefix("y") else {
            fputs("Download cancelled.\n", stderr)
            throw ExitCode.failure
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

        // Download the CoreML model zip from our release
        let downloadURL = FaceModelRegistry.downloadURL
        fputs("Downloading from \(downloadURL)...\n", stderr)

        let tempZip = destDir.appendingPathComponent(
            "\(FaceModelRegistry.modelFilename).zip")

        // Clean up temp file on exit
        defer { try? FileManager.default.removeItem(at: tempZip) }

        // Use URLSession for proper HTTP error reporting
        let semaphore = DispatchSemaphore(value: 0)
        var downloadError: Error?
        var httpStatusCode: Int?

        let task = URLSession.shared.downloadTask(with: downloadURL) { url, response, error in
            defer { semaphore.signal() }

            if let error = error {
                downloadError = error
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                httpStatusCode = httpResponse.statusCode
                guard (200...299).contains(httpResponse.statusCode) else {
                    return
                }
            }

            guard let tempURL = url else { return }

            do {
                try FileManager.default.moveItem(at: tempURL, to: tempZip)
            } catch {
                downloadError = error
            }
        }
        task.resume()
        semaphore.wait()

        if let error = downloadError {
            fputs("Download failed: \(error.localizedDescription)\n", stderr)
            throw ExitCode.failure
        }

        if let status = httpStatusCode, !(200...299).contains(status) {
            fputs("Download failed (HTTP \(status)). The model may not be available yet.\n", stderr)
            throw ExitCode.failure
        }

        // Unzip the downloaded archive
        fputs("Extracting model...\n", stderr)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-o", "-q", tempZip.path, "-d", destDir.path]
        unzip.standardOutput = FileHandle.nullDevice
        unzip.standardError = FileHandle.nullDevice

        try unzip.run()
        unzip.waitUntilExit()

        if unzip.terminationStatus != 0 {
            // Clean up any partial extraction
            try? FileManager.default.removeItem(at: destPath)
            fputs("Download failed: could not extract model archive.\n", stderr)
            throw ExitCode.failure
        }

        if !FileManager.default.fileExists(atPath: destPath.path) {
            fputs("Download failed: extracted archive did not contain \(FaceModelRegistry.modelFilename).\n", stderr)
            throw ExitCode.failure
        }

        fputs("Face model installed at \(destPath.path)\n", stderr)
    }
}
