// ABOUTME: Observable view model for the upscaling workflow.
// ABOUTME: Manages state for model selection, processing, progress, and results.

import AppKit
import Combine
import CoreGraphics
import Foundation
import SuperscaleKit
import SuperscaleUXCore
import SwiftUI

@MainActor
final class UpscaleViewModel: ObservableObject {

    // MARK: - Scale mode

    enum DefiningDimension {
        case width, height
    }

    // MARK: - Published state

    @Published var showButtonLabels: Bool = true
    @Published var selectedModelName: String = "auto"
    /// What the scale control holds. Private to the setter, so a view cannot assign around
    /// `choose(_:)` and lose the toggle-group behaviour it encodes.
    @Published private(set) var scaleSelection: ScaleSelection = .preset(4)
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
    @Published private(set) var resultData: Data?
    /// The input the current result was produced from, carried through the upscale so that
    /// attribution follows the work rather than view state that an unrelated drop can outlive.
    @Published private(set) var resultSource: GUIUpscaleSource?
    @Published var inputURL: URL?

    /// Cached upscale results for instant face enhancement toggling.
    private var cachedWithFaces: NSImage?
    private var cachedWithoutFaces: NSImage?
    @Published var inputWidth: Int?
    @Published var inputHeight: Int?
    @Published var errorMessage: String?
    @Published var dimensionCapWarning: String?
    @Published var lastUpscaleModelName: String?
    @Published var lastUpscaleFaceCount: Int = 0
    @Published var lastUpscaleWasAutoDetect: Bool = false
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
    private let upscaleCoordinator: GUIUpscaleCoordinator
    private var currentInputSource: GUIUpscaleSource?

    private var suppressDimensionUpdates = false

    init(upscaleCoordinator: GUIUpscaleCoordinator = GUIUpscaleCoordinator()) {
        self.upscaleCoordinator = upscaleCoordinator
        // When width changes: strip non-digits, become defining dimension, update other
        $customWidth
            .dropFirst()
            .sink { [weak self] newValue in
                guard let self, !self.suppressDimensionUpdates else { return }
                var filtered = newValue.filter { $0.isNumber }
                // Cap at 8× input or 16384px
                if let val = Int(filtered), val > self.maxCustomDimension {
                    filtered = "\(self.maxCustomDimension)"
                }
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
                // Typing a dimension never creates a selection: choosing custom does that.
                // It only moves an existing selection between custom and the model's scale.
                self.reflectTypedDimension(isValid: Int(filtered).map { $0 > 0 } ?? false)
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
                var filtered = newValue.filter { $0.isNumber }
                // Cap at 8× input or 16384px
                if let val = Int(filtered), val > self.maxCustomDimension {
                    filtered = "\(self.maxCustomDimension)"
                }
                if filtered != newValue {
                    self.suppressDimensionUpdates = true
                    self.customHeight = filtered
                    DispatchQueue.main.async { self.suppressDimensionUpdates = false }
                    return
                }
                if self.suppressDimensionUpdates { return }
                self.definingDimension = .height
                // Typing a dimension never creates a selection: choosing custom does that.
                // It only moves an existing selection between custom and the model's scale.
                self.reflectTypedDimension(isValid: Int(filtered).map { $0 > 0 } ?? false)
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
                    self.reupscaleForFaceToggle()
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
                // The model's native scale replaces a selected scale; it does not create one.
                self.adoptNativeScale(scale)
                self.showCustomFields = false
                self.customWidth = ""
                self.customHeight = ""
            }
            .store(in: &cancellables)

        // Preset scale changes trigger re-upscale immediately. Clearing the selection releases
        // the result instead, because with nothing selected there is no upscale to show.
        $scaleSelection
            .dropFirst()
            .sink { [weak self] selection in
                guard let self else { return }
                switch selection {
                case .off:
                    self.releaseUpscaledResult()
                case .preset:
                    self.reupscaleIfNeeded()
                case .custom:
                    break  // debounced by the dimension subscribers below
                }
            }
            .store(in: &cancellables)

        // Mark custom edit as pending when user types in custom fields
        // Custom dimension changes trigger re-upscale after 1.5s debounce
        $customWidth
            .dropFirst()
            .debounce(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] val in
                guard let self,
                      self.scaleSelection == .custom,
                      let v = Int(val), v > 0 else { return }
                self.reupscaleIfNeeded()
            }
            .store(in: &cancellables)

        $customHeight
            .dropFirst()
            .debounce(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] val in
                guard let self,
                      self.scaleSelection == .custom,
                      let v = Int(val), v > 0 else { return }
                self.reupscaleIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func reupscaleIfNeeded() {
        guard !scaleSelection.isOff, let url = inputURL, !isProcessing else { return }
        processImage(source: currentInputSource ?? .imported(url))
    }

    /// Re-upscale for face enhance toggle only — preserves scale settings.
    private func reupscaleForFaceToggle() {
        guard !scaleSelection.isOff, let url = inputURL, !isProcessing else { return }
        // Capture current scale state before processImage can interfere
        let savedSelection = scaleSelection
        let savedCustomW = customWidth
        let savedCustomH = customHeight
        let savedDefining = definingDimension
        let savedShowCustom = showCustomFields
        processImage(source: currentInputSource ?? .imported(url))
        // Restore scale state in case anything reset it
        scaleSelection = savedSelection
        customWidth = savedCustomW
        customHeight = savedCustomH
        definingDimension = savedDefining
        showCustomFields = savedShowCustom
    }

    /// Re-cap custom dimensions against current image's 8× limit.
    private func reapplyDimensionCap() {
        let cap = maxCustomDimension
        if let w = Int(customWidth), w > cap { customWidth = "\(cap)" }
        if let h = Int(customHeight), h > cap { customHeight = "\(cap)" }
    }

    /// Maximum custom dimension: 8× the longest input side, or 16384px if no image.
    var maxCustomDimension: Int {
        let longest = max(inputWidth ?? 0, inputHeight ?? 0)
        if longest > 0 { return longest * 8 }
        return 16384
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

    // MARK: - Scale selection

    /// The only route to a new selection. Pressing the active choice clears it, which is what
    /// makes the scale buttons a toggle group rather than a set that can never be emptied.
    func choose(_ choice: ScaleChoice) {
        scaleSelection = scaleSelection.choosing(choice)
        showCustomFields = scaleSelection == .custom
    }

    func isActive(_ choice: ScaleChoice) -> Bool {
        scaleSelection.isActive(choice)
    }

    /// Replaces a selected scale with the model's native one. A cleared selection stays cleared:
    /// adopting a scale is not the same as creating a selection.
    private func adoptNativeScale(_ scale: Int) {
        guard case .preset = scaleSelection else { return }
        scaleSelection = .preset(scale)
    }

    /// Moves an existing selection between custom and the model's scale as dimensions are typed
    /// or emptied. Never creates a selection where there was none.
    private func reflectTypedDimension(isValid: Bool) {
        guard !scaleSelection.isOff else { return }
        if showCustomFields, isValid {
            scaleSelection = .custom
        } else if scaleSelection == .custom {
            scaleSelection = .preset(nativeScale)
        }
    }

    /// With nothing selected there is no upscale to show, so the result is released rather than
    /// left on screen contradicting the control.
    private func releaseUpscaledResult() {
        result = nil
        resultData = nil
        resultSource = nil
        cachedWithFaces = nil
        cachedWithoutFaces = nil
        showComparison = false
        progressMessage = ""
    }

    // MARK: - Actions

    func handleDrop(urls: [URL]) {
        guard let url = urls.first else { return }
        processImage(source: .imported(url))
    }

    /// Upscales an image that came from elsewhere in the application, such as a generation
    /// result or a history session.
    ///
    /// Takes the source rather than a location, so a caller cannot substitute the image it is
    /// displaying for the image that should be processed.
    func upscale(_ source: GUIUpscaleSource) {
        processImage(source: source)
    }

    func saveAs(defaultDirectory: URL? = nil) {
        guard let image = result else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = outputFilename()
        panel.canCreateDirectories = true
        panel.directoryURL = defaultDirectory

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

    private func processImage(source: GUIUpscaleSource) {
        let url = source.url
        let isNewImage = inputURL != url
        currentInputSource = source

        errorMessage = nil
        isProcessing = true
        progressMessage = "Loading..."
        result = nil
        resultData = nil
        resultSource = nil
        showComparison = false

        // Invalidate face enhancement cache and upscale metadata
        cachedWithFaces = nil
        cachedWithoutFaces = nil
        lastUpscaleModelName = nil
        lastUpscaleFaceCount = 0
        lastUpscaleWasAutoDetect = false

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
            // Re-cap custom dimensions against new image's 8× limit
            reapplyDimensionCap()
            // A new image adopts the model's native scale, as in v1 — but it does not create a
            // selection. Dropped with the scale off, it simply becomes the image to work on.
            adoptNativeScale(nativeScale)
        }

        guard let options = coordinatorOptions() else {
            isProcessing = false
            progressMessage = ""
            return
        }
        let coordinator = upscaleCoordinator
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let output = try coordinator.process(source: source, options: options) { [weak self] message in
                    Task { @MainActor in
                        guard let self else { return }
                        // Track face count from progress messages
                        if message.hasPrefix("Enhancing") && message.contains("face") {
                            if let num = Int(message.components(separatedBy: " ")[1]) {
                                self.lastUpscaleFaceCount = num
                            }
                        }
                        // Replace native-scale dimension reports with target dimensions
                        if message.hasPrefix("Stitching output"),
                           self.scaleSelection == .custom {
                            let tw = self.customWidth
                            let th = self.customHeight
                            self.progressMessage = "Resizing to \(tw)×\(th)..."
                        } else {
                            self.progressMessage = message
                        }
                    }
                }
                let image = NSImage(data: output.imageData)
                let preFaceImage = output.preFaceImageData.flatMap(NSImage.init(data:))
                let faceWasEnabled = await self.faceEnhance
                await MainActor.run {
                    self.result = image
                    // Set before the data, so an observer of the data always sees the input it
                    // came from rather than the input of the previous run.
                    self.resultSource = output.source
                    self.resultData = output.imageData
                    if faceWasEnabled {
                        self.cachedWithFaces = image
                        self.cachedWithoutFaces = preFaceImage ?? image
                    } else {
                        self.cachedWithoutFaces = image
                        // cachedWithFaces stays nil — toggling on will trigger re-upscale
                    }
                    self.lastUpscaleModelName = output.resolvedModelName
                    self.lastUpscaleWasAutoDetect = output.wasAutoDetect
                    self.isProcessing = false
                    self.progressMessage = ""
                    self.showComparison = true
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

    /// The options for a run, or nothing when no scale is selected and no run is due.
    private func coordinatorOptions() -> GUIUpscaleOptions? {
        let sizing: GUIUpscaleSizing
        switch scaleSelection {
        case .off:
            return nil
        case let .preset(scale):
            sizing = .preset(scale: scale)
        case .custom:
            let width = Int(customWidth).flatMap { $0 > 0 ? $0 : nil }
            let height = Int(customHeight).flatMap { $0 > 0 ? $0 : nil }
            if stretchEnabled, let width, let height {
                sizing = .custom(width: width, height: height, stretch: true)
            } else if definingDimension == .width, let width {
                sizing = .custom(width: width, height: nil, stretch: false)
            } else if definingDimension == .height, let height {
                sizing = .custom(width: nil, height: height, stretch: false)
            } else {
                sizing = .preset(scale: nativeScale)
            }
        }
        return GUIUpscaleOptions(
            selectedModelName: selectedModelName,
            faceEnhance: faceEnhance,
            sizing: sizing
        )
    }

    private func outputFilename() -> String {
        guard let inputURL else { return "upscaled.png" }
        let stem = inputURL.deletingPathExtension().lastPathComponent
        switch scaleSelection {
        case .off:
            return "\(stem).png"
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
