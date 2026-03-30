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

    // MARK: - Scale mode

    enum ScaleMode: Equatable {
        case preset(Int)
        case custom
    }

    enum DefiningDimension {
        case width, height
    }

    // MARK: - Published state

    @Published var selectedModelName: String = "auto"
    @Published var scaleMode: ScaleMode = .preset(4)
    @Published var showCustomFields: Bool = false
    @Published var customWidth: String = ""
    @Published var customHeight: String = ""
    @Published var definingDimension: DefiningDimension = .width
    @Published var stretchEnabled: Bool = false
    @Published var faceEnhance: Bool = FaceModelRegistry.isInstalled
    @Published var isProcessing: Bool = false
    @Published var progressMessage: String = ""
    @Published var originalImage: NSImage?
    @Published var result: NSImage?
    @Published var inputURL: URL?

    /// Cached upscale results for instant face enhancement toggling.
    private var cachedWithFaces: NSImage?
    private var cachedWithoutFaces: NSImage?
    @Published var inputWidth: Int?
    @Published var inputHeight: Int?
    @Published var errorMessage: String?
    @Published var showComparison: Bool = false


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
                displayName: model.displayName))
        }
        return options
    }

    /// Native scale factor of the selected model.
    var nativeScale: Int {
        if selectedModelName == "auto" {
            return ModelRegistry.defaultModel.scale
        }
        return ModelRegistry.model(named: selectedModelName)?.scale
            ?? ModelRegistry.defaultModel.scale
    }

    private var cancellables = Set<AnyCancellable>()

    private var suppressDimensionUpdates = false

    init() {
        // When width changes: strip non-digits, become defining dimension, update other
        $customWidth
            .dropFirst()
            .sink { [weak self] newValue in
                guard let self, !self.suppressDimensionUpdates else { return }
                let filtered = newValue.filter { $0.isNumber }
                if filtered != newValue {
                    self.suppressDimensionUpdates = true
                    self.customWidth = filtered
                    self.suppressDimensionUpdates = false
                    return
                }
                // Only set defining dimension if this wasn't a programmatic update
                if !self.suppressDimensionUpdates {
                    self.definingDimension = .width
                }
                // Activate custom mode when a valid (non-zero) number is entered
                if self.showCustomFields, let val = Int(filtered), val > 0 {
                    self.scaleMode = .custom
                } else if case .custom = self.scaleMode {
                    self.scaleMode = .preset(self.nativeScale)
                }
                if !self.stretchEnabled && self.definingDimension == .width {
                    // Delay indicative update to avoid disrupting TextField input
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        guard let self, self.definingDimension == .width else { return }
                        self.suppressDimensionUpdates = true
                        self.updateIndicativeDimension()
                        DispatchQueue.main.async { self.suppressDimensionUpdates = false }
                    }
                }
            }
            .store(in: &cancellables)

        // When height changes: strip non-digits, become defining dimension, update other
        $customHeight
            .dropFirst()
            .sink { [weak self] newValue in
                guard let self else { return }
                let filtered = newValue.filter { $0.isNumber }
                if filtered != newValue {
                    self.suppressDimensionUpdates = true
                    self.customHeight = filtered
                    DispatchQueue.main.async { self.suppressDimensionUpdates = false }
                    return
                }
                if self.suppressDimensionUpdates { return }
                self.definingDimension = .height
                // Activate custom mode when a valid (non-zero) number is entered
                if self.showCustomFields, let val = Int(filtered), val > 0 {
                    self.scaleMode = .custom
                } else if case .custom = self.scaleMode {
                    self.scaleMode = .preset(self.nativeScale)
                }
                if !self.stretchEnabled && self.definingDimension == .height {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        guard let self, self.definingDimension == .height else { return }
                        self.suppressDimensionUpdates = true
                        self.updateIndicativeDimension()
                        DispatchQueue.main.async { self.suppressDimensionUpdates = false }
                    }
                }
            }
            .store(in: &cancellables)

        // When stretch is unchecked, recalculate the non-defining dimension
        $stretchEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self, !enabled else { return }
                self.suppressDimensionUpdates = true
                // Clear the non-defining field, then recalculate
                if self.definingDimension == .width {
                    self.customHeight = ""
                } else {
                    self.customWidth = ""
                }
                self.updateIndicativeDimension()
                self.suppressDimensionUpdates = false
            }
            .store(in: &cancellables)

        // Face enhance toggle: swap cached versions or re-upscale
        $faceEnhance
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self, self.inputURL != nil else { return }
                if enabled, let cached = self.cachedWithFaces {
                    self.result = cached
                } else if !enabled, let cached = self.cachedWithoutFaces {
                    self.result = cached
                } else {
                    self.reupscaleIfNeeded()
                }
            }
            .store(in: &cancellables)

        // When model changes, update scale to match native and re-upscale
        $selectedModelName
            .dropFirst()
            .sink { [weak self] newName in
                guard let self else { return }
                let scale: Int
                if newName == "auto" {
                    scale = ModelRegistry.defaultModel.scale
                } else {
                    scale = ModelRegistry.model(named: newName)?.scale
                        ?? ModelRegistry.defaultModel.scale
                }
                self.scaleMode = .preset(scale)
            }
            .store(in: &cancellables)

        // Preset scale changes trigger re-upscale immediately
        $scaleMode
            .dropFirst()
            .sink { [weak self] newMode in
                guard let self else { return }
                if case .preset = newMode {
                    self.reupscaleIfNeeded()
                }
                // Custom mode re-upscale is debounced via dimension subscribers below
            }
            .store(in: &cancellables)

        // Custom dimension changes trigger re-upscale after 1s debounce
        $customWidth
            .dropFirst()
            .debounce(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] val in
                guard let self,
                      case .custom = self.scaleMode,
                      let v = Int(val), v > 0 else { return }
                self.reupscaleIfNeeded()
            }
            .store(in: &cancellables)

        $customHeight
            .dropFirst()
            .debounce(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] val in
                guard let self,
                      case .custom = self.scaleMode,
                      let v = Int(val), v > 0 else { return }
                self.reupscaleIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func reupscaleIfNeeded() {
        guard let url = inputURL, !isProcessing else { return }
        processImage(url: url)
    }

    // MARK: - Scale helpers

    /// Target dimensions for a given preset scale, based on current input image.
    func targetDimensions(forScale scale: Int) -> (width: Int, height: Int)? {
        guard let w = inputWidth, let h = inputHeight else { return nil }
        return (w * scale, h * scale)
    }

    /// Update the non-defining custom dimension to preserve aspect ratio.
    /// When no image is loaded, clears the non-defining field instead.
    func updateIndicativeDimension() {
        guard !stretchEnabled else { return }

        // No image — clear the non-defining field
        guard let w = inputWidth, let h = inputHeight,
              w > 0, h > 0 else {
            if definingDimension == .width {
                customHeight = ""
            } else {
                customWidth = ""
            }
            return
        }

        let aspectRatio = Double(w) / Double(h)

        if definingDimension == .width, let typed = Int(customWidth), typed > 0 {
            customHeight = "\(Int(round(Double(typed) / aspectRatio)))"
        } else if definingDimension == .height, let typed = Int(customHeight), typed > 0 {
            customWidth = "\(Int(round(Double(typed) * aspectRatio)))"
        }
    }

    // MARK: - Actions

    func handleDrop(urls: [URL]) {
        guard let url = urls.first else { return }
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
        let isNewImage = inputURL != url

        errorMessage = nil
        isProcessing = true
        progressMessage = "Loading..."
        result = nil
        showComparison = false

        // Invalidate face enhancement cache on re-upscale
        cachedWithFaces = nil
        cachedWithoutFaces = nil

        // If stretch is on but both dimensions aren't valid, deselect immediately
        if stretchEnabled {
            let w = Int(customWidth).flatMap { $0 > 0 ? $0 : nil }
            let h = Int(customHeight).flatMap { $0 > 0 ? $0 : nil }
            if w == nil || h == nil {
                stretchEnabled = false
            }
        }

        if isNewImage {
            inputURL = url
            originalImage = NSImage(contentsOfFile: url.path)
            // Use ImageLoader for accurate pixel dimensions (not DPI-adjusted)
            if let loaded = try? ImageLoader.load(from: url) {
                inputWidth = loaded.image.width
                inputHeight = loaded.image.height
            }
            scaleMode = .preset(nativeScale)
        }

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let modelName = try await self.resolveModelName(for: url)
                let pipeline = try Pipeline(
                    modelName: modelName,
                    faceEnhance: await self.faceEnhance)
                pipeline.onProgress = { [weak self] message in
                    Task { @MainActor in
                        guard let self else { return }
                        // Replace native-scale dimension reports with target dimensions
                        if message.hasPrefix("Stitching output"),
                           case .custom = self.scaleMode {
                            let tw = self.customWidth
                            let th = self.customHeight
                            self.progressMessage = "Resizing to \(tw)×\(th)..."
                        } else {
                            self.progressMessage = message
                        }
                    }
                }

                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("superscale_gui_\(UUID().uuidString).png")

                // Resolve scale/resolution parameters
                let currentMode = await self.scaleMode
                let requestedScale: Double?
                let targetWidth: Int?
                let targetHeight: Int?
                let stretch: Bool

                switch currentMode {
                case .preset(let scale):
                    requestedScale = Double(scale)
                    targetWidth = nil
                    targetHeight = nil
                    stretch = false
                case .custom:
                    let stretchOn = await self.stretchEnabled
                    let defining = await self.definingDimension
                    let wStr = await self.customWidth
                    let hStr = await self.customHeight
                    let w = Int(wStr).flatMap { $0 > 0 ? $0 : nil }
                    let h = Int(hStr).flatMap { $0 > 0 ? $0 : nil }

                    if stretchOn, let w, let h {
                        requestedScale = nil
                        targetWidth = w
                        targetHeight = h
                        stretch = true
                    } else if stretchOn {
                        // Stretch selected but missing a dimension — fall back to non-stretch
                        await MainActor.run { self.stretchEnabled = false }
                        if let w {
                            requestedScale = nil
                            targetWidth = w
                            targetHeight = nil
                            stretch = false
                        } else if let h {
                            requestedScale = nil
                            targetWidth = nil
                            targetHeight = h
                            stretch = false
                        } else {
                            let native = await self.nativeScale
                            requestedScale = Double(native)
                            targetWidth = nil
                            targetHeight = nil
                            stretch = false
                        }
                    } else if defining == .width, let w {
                        requestedScale = nil
                        targetWidth = w
                        targetHeight = nil
                        stretch = false
                    } else if defining == .height, let h {
                        requestedScale = nil
                        targetWidth = nil
                        targetHeight = h
                        stretch = false
                    } else {
                        // Invalid custom values — fall back to native scale
                        let native = await self.nativeScale
                        requestedScale = Double(native)
                        targetWidth = nil
                        targetHeight = nil
                        stretch = false
                    }
                }

                // Capture pre-face-enhance image for cache
                var preFaceImage: NSImage?
                try pipeline.process(
                    input: url, output: outputURL,
                    requestedScale: requestedScale,
                    targetWidth: targetWidth, targetHeight: targetHeight,
                    stretch: stretch,
                    onPreFaceEnhance: { cgImage in
                        preFaceImage = NSImage(
                            cgImage: cgImage,
                            size: NSSize(width: cgImage.width, height: cgImage.height))
                    })

                let image = NSImage(contentsOf: outputURL)
                try? FileManager.default.removeItem(at: outputURL)

                let faceWasEnabled = await self.faceEnhance
                await MainActor.run {
                    self.result = image
                    if faceWasEnabled {
                        self.cachedWithFaces = image
                        self.cachedWithoutFaces = preFaceImage ?? image
                    } else {
                        self.cachedWithoutFaces = image
                        // cachedWithFaces stays nil — toggling on will trigger re-upscale
                    }
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
        switch scaleMode {
        case .preset(let scale):
            return "\(stem)_\(scale)x.png"
        case .custom:
            if stretchEnabled, let w = Int(customWidth), let h = Int(customHeight) {
                return "\(stem)_\(w)x\(h).png"
            } else if definingDimension == .width, let w = Int(customWidth) {
                return "\(stem)_w\(w).png"
            } else if let h = Int(customHeight) {
                return "\(stem)_h\(h).png"
            }
            return "\(stem)_custom.png"
        }
    }
}
