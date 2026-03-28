// ABOUTME: Observable view model for the upscaling workflow.
// ABOUTME: Manages state for model selection, processing, progress, and results.

import AppKit
import Combine
import CoreGraphics
import Foundation
import SuperscaleKit
import SwiftUI

@MainActor
final class UpscaleViewModel: ObservableObject {

    // MARK: - Published state

    @Published var selectedModelName: String = "auto"
    @Published var isProcessing: Bool = false
    @Published var progressMessage: String = ""
    @Published var result: NSImage?
    @Published var inputURL: URL?
    @Published var errorMessage: String?

    // MARK: - Model list

    struct ModelOption: Identifiable {
        let id: String
        let displayName: String
    }

    var modelOptions: [ModelOption] {
        var options = [ModelOption(id: "auto", displayName: "Auto-detect")]
        for model in ModelRegistry.models {
            options.append(ModelOption(
                id: model.name,
                displayName: "\(model.displayName) (\(model.scale)×)"))
        }
        return options
    }

    /// Scale factor of the selected (or default) model.
    var selectedScale: Int {
        if selectedModelName == "auto" {
            return ModelRegistry.defaultModel.scale
        }
        return ModelRegistry.model(named: selectedModelName)?.scale
            ?? ModelRegistry.defaultModel.scale
    }

    // MARK: - Actions

    func handleDrop(urls: [URL]) {
        guard let url = urls.first else { return }
        inputURL = url
        processImage(url: url)
    }

    func saveAs() {
        guard let image = result else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = outputFilename()
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            errorMessage = "Failed to create image data for saving."
            return
        }

        let isPNG = url.pathExtension.lowercased() == "png"
        let data = isPNG
            ? bitmap.representation(using: .png, properties: [:])
            : bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])

        guard let imageData = data else {
            errorMessage = "Failed to encode image."
            return
        }

        do {
            try imageData.write(to: url)
        } catch {
            errorMessage = "Failed to write file: \(error.localizedDescription)"
        }
    }

    // MARK: - Private

    private func processImage(url: URL) {
        errorMessage = nil
        isProcessing = true
        progressMessage = "Loading..."
        result = nil

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let modelName = try await self.resolveModelName(for: url)
                let pipeline = try Pipeline(
                    modelName: modelName, faceEnhance: true)
                pipeline.onProgress = { message in
                    Task { @MainActor in
                        self.progressMessage = message
                    }
                }

                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("superscale_gui_\(UUID().uuidString).png")

                try pipeline.process(input: url, output: outputURL)

                let image = NSImage(contentsOf: outputURL)
                try? FileManager.default.removeItem(at: outputURL)

                await MainActor.run {
                    self.result = image
                    self.isProcessing = false
                    self.progressMessage = ""
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isProcessing = false
                    self.progressMessage = ""
                }
            }
        }
    }

    private func resolveModelName(for url: URL) async throws -> String {
        if selectedModelName != "auto" {
            return selectedModelName
        }
        let loaded = try ImageLoader.load(from: url)
        let (contentType, _) = try ContentDetector.detect(image: loaded.image)
        return ContentDetector.modelName(for: contentType, scale: 4)
    }

    private func outputFilename() -> String {
        guard let inputURL else { return "upscaled.png" }
        let stem = inputURL.deletingPathExtension().lastPathComponent
        return "\(stem)_\(selectedScale)x.png"
    }
}
