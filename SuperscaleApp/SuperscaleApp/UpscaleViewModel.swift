// ABOUTME: Observable view model for the upscaling workflow.
// ABOUTME: Manages state for model selection, processing, progress, and results.

import AppKit
import Combine
import CoreGraphics
import FalGenerationKit
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
    /// Nothing is selected on launch, so the first upscale of a session is one the user asked for.
    ///
    /// Guide 2.5. Upscaling stays reactive — it runs whenever a scale is selected and there is
    /// something to run on — but it no longer starts a session already in effect. The cost was
    /// otherwise paid on the first action every time, on an output a filter-first user is about to
    /// set aside, before they had chosen anything.
    ///
    /// Not persisted between sessions, deliberately: a scale carried over is a decision made about
    /// a different picture.
    @Published private(set) var scaleSelection: ScaleSelection = .off
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
    /// Renderings already produced, keyed by what produced them.
    ///
    /// Replaces a pair of `cachedWithFaces` / `cachedWithoutFaces` fields, which held one asset at
    /// one setting and had to be nilled by hand wherever anything changed. Keying by asset, model,
    /// sizing and face setting makes invalidation fall out: a key that no longer matches simply
    /// misses.
    private let renderings = RenderingStore()

    /// The images themselves, alongside the identities the store holds.
    ///
    /// `RenderedImage` is an identity, deliberately, so that the decision about *which* picture to
    /// draw stays testable without AppKit. The pixels have to live somewhere, and this is the one
    /// place that knows both.
    private var renderedImages: [String: NSImage] = [:]
    @Published var inputWidth: Int?
    @Published var inputHeight: Int?
    /// The failure the user is shown, and the only one.
    ///
    /// `private(set)`, so `report` and `dismissError` are the only ways in. It was assignable from
    /// `MainView`, `SuperscaleApp` and this class alike — nine sites in `MainView` alone — and every
    /// one of them decided for itself how to turn an error into a sentence. A later path now finds
    /// nowhere else to write and fails to compile, which is a stronger guarantee than a test that
    /// nobody re-runs.
    @Published private(set) var errorMessage: String?

    /// The one way a failure reaches the user.
    ///
    /// A `FalFailure` carries a diagnostic already read from the provider's own words and already
    /// stripped of every credential; `localizedDescription` on it would say the same thing, but
    /// going through the diagnostic makes the guarantee explicit rather than incidental.
    func report(_ error: any Error) {
        if let failure = error as? FalFailure {
            errorMessage = failure.diagnostic
        } else {
            errorMessage = error.localizedDescription
        }
    }

    /// The one way a failure with no `Error` behind it reaches the user.
    func report(_ message: String) {
        errorMessage = message
    }

    func dismissError() {
        errorMessage = nil
    }

    /// Something the user should know that is not a failure.
    ///
    /// An upscale reduced to fit memory is the first of these; the minimum-resolution message of
    /// guide 2.5 is the next, and will use the same channel. Unobtrusive deliberately: an alert
    /// would demand a click for something the application has already handled correctly.
    @Published var noticeMessage: String?
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
    /// The run in flight, and which run may publish. Anything from a superseded run is ignored.
    private var upscaleTask: Task<Void, Never>?
    private var activeRun: UUID?

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
                // Both versions are renderings of one operation rather than one being a fallback
                // for the other, so the display holds until the new one exists. A rendering already
                // built comes back without being rebuilt; otherwise the work is done.
                if let held = self.heldRendering(facesEnhanced: enabled) {
                    self.result = held
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
                    // The emitted value, not the property. `@Published` publishes in `willSet`, so
                    // inside this sink `self.scaleSelection` is still the *previous* selection.
                    // Reading it back made choosing a scale after turning upscaling off do
                    // nothing at all — the guard saw `.off` and returned — and made a change from
                    // one preset to another run at the scale being replaced.
                    self.reupscaleIfNeeded(with: selection)
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

    /// Set while a run is being configured, so the configuration cannot start another run.
    ///
    /// Not `@Published`: nothing renders it, and publishing it would make it exactly the kind of
    /// state whose own notification re-enters the code that set it.
    private var isConfiguringRun = false

    /// Re-runs the upscale for a selection.
    ///
    /// Takes the selection rather than reading it, so a caller inside a `@Published` sink passes
    /// the value being published rather than the one it is replacing.
    private func reupscaleIfNeeded(with selection: ScaleSelection? = nil) {
        let selection = selection ?? scaleSelection
        // **Re-entrancy, not busyness, is what must be refused here.**
        //
        // This guard read `!isProcessing`, which conflated the two and dropped the user's request
        // silently: a scale chosen while the import's own upscale was still running never started
        // anything, while the readout — a pure function of the source and the request — began
        // reporting "8x requested, 4x in effect" about a run that did not exist.
        //
        // But `isProcessing` was doing real work as a proxy. `processImage` mutates published state
        // its own subscribers watch: `adoptNativeScale` assigns `scaleSelection`, and `@Published`
        // republishes even when the value is unchanged, so the sink re-enters `processImage` while
        // it is still setting up. Removing the guard outright hung the application at import and
        // took 17 GUI tests with it, including two that only launch it.
        //
        // `isConfiguringRun` says the narrow thing instead: a run is being configured right now, so
        // a mutation this method caused must not start another. A run already *in flight* is no
        // reason to refuse — superseding is handled where it belongs, in `start`'s cancellation and
        // in `publish` and `abandon` guarding on `activeRun`, with cancellation treated as not a
        // failure so the discarded run says nothing.
        guard !isConfiguringRun, !selection.isOff, let url = inputURL else { return }
        processImage(source: currentInputSource ?? .imported(url), selection: selection)
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

        // The restore is inside the flag as well as the call. Every line of it assigns a
        // `@Published` property that has a subscriber, and `@Published` republishes even when the
        // value is unchanged — so a restore that changes nothing still wakes the sinks and, with
        // the flag clear, would cancel the run this method just started and begin another.
        isConfiguringRun = true
        defer { isConfiguringRun = false }

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
    /// Clears the selection outright.
    ///
    /// `choose` is a toggle and needs to be handed the choice that is currently active in order to
    /// clear it, which a caller that simply wants the scale off should not have to work out. Used
    /// when the floor raises the base: with the raised picture as the base and the scale off, the
    /// application stops re-upscaling a picture that is already the size the provider wants.
    func turnScaleOff() {
        guard !scaleSelection.isOff else { return }
        scaleSelection = .off
    }

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
        upscaleTask?.cancel()
        upscaleTask = nil
        activeRun = nil
        isProcessing = false
        result = nil
        resultData = nil
        resultSource = nil
        renderings.forget()
        renderedImages.removeAll()
        showComparison = false
        progressMessage = ""
    }

    // MARK: - Actions

    /// Renders an upscale at a fixed scale and hands back its bytes, without touching the canvas.
    ///
    /// Used to raise an undersized picture to the filterable minimum. It goes through **this**
    /// coordinator rather than one built at the call site, so a stubbed processor is stubbed for
    /// this work too — the same rule that the reference upload broke by constructing its own client.
    ///
    /// Deliberately does not publish: the raise is a correction on the way to the provider, not a
    /// result the user asked to look at, and putting it on the canvas would replace what they are
    /// working on with a bigger copy of it.
    func renderRaise(
        _ source: GUIUpscaleSource, scale: Int, sourceSize: CGSize
    ) async throws -> Data {
        // **It reports.** A raise runs the same Neural Engine work as any other upscale and takes
        // the same seconds, and AC94.1 requires work of any kind on the working image to show
        // progress on the canvas. Pressing Apply on a small picture and watching nothing happen for
        // several seconds is the defect #94 fixed for the filter, arriving on a new path.
        isProcessing = true
        progressMessage = "Preparing for filtering…"
        defer {
            isProcessing = false
            progressMessage = ""
        }

        let (reports, continuation) = AsyncStream<StageProgress>.makeStream()
        let observer = Task { @MainActor [weak self] in
            for await progress in reports {
                self?.progressMessage = progress.detail ?? "Preparing for filtering…"
            }
        }
        defer { observer.cancel() }

        let result = try await upscaleCoordinator.process(
            source: source,
            options: GUIUpscaleOptions(
                selectedModelName: selectedModelName,
                // Faces are the user's choice about their own output. This is a size correction on
                // the way to the provider, so it borrows nothing from that choice.
                faceEnhance: false,
                sizing: .preset(scale: scale)),
            sourceSize: sourceSize
        ) { progress in
            continuation.yield(UpscaleProgressReader.progress(for: progress))
        }
        continuation.finish()
        return result.imageData
    }

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

    /// What Save writes: the upscaled rendering when one exists, otherwise the picture itself.
    ///
    /// Save was bound to `result`, which only exists after an *upscale*. With the scale off there
    /// was nothing to save at all — and #96 puts every user with a picture under 1024 pixels into
    /// exactly that state, because raising it to the filterable minimum turns the scale off. A
    /// filtered result the user had just paid 2c for could not be written to disk.
    ///
    /// AC89.3 asks for every iteration to be saveable *at the current scale selection*. With no
    /// scale selected, that is the picture as it stands.
    var savableImage: NSImage? {
        result ?? originalImage
    }

    func saveAs(defaultDirectory: URL? = nil) {
        guard let image = savableImage else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = outputFilename()
        panel.canCreateDirectories = true
        panel.directoryURL = defaultDirectory

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            report("Failed to create image data for saving.")
            return
        }

        let isPNG = url.pathExtension.lowercased() == "png"
        let data = isPNG
            ? bitmap.representation(using: .png, properties: [:])
            : bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])

        guard let imageData = data else {
            report("Failed to encode image.")
            return
        }

        do {
            try imageData.write(to: url)
        } catch {
            report("Failed to write file: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    /// - Parameter selection: the scale to run at, when the caller holds a newer one than the
    ///   property does. A `@Published` sink is such a caller.
    private func processImage(source: GUIUpscaleSource, selection: ScaleSelection? = nil) {
        // This method assigns published properties that its own subscribers watch —
        // `adoptNativeScale` and `reapplyDimensionCap` among them — and `@Published` republishes
        // even when the value is unchanged. Without this, setting a run up starts another one.
        isConfiguringRun = true
        defer { isConfiguringRun = false }

        let url = source.url
        let isNewImage = inputURL != url
        currentInputSource = source

        dismissError()
        isProcessing = true
        progressMessage = "Loading..."

        // The previous rendering stays on the canvas until the new one exists. Clearing it here is
        // what emptied the canvas the moment anything was adjusted, and falling back to the base
        // mid-operation would be a regression dressed as a fix. A *new* picture is different: its
        // predecessor's upscale describes something the user is no longer looking at, so it goes.
        if isNewImage {
            result = nil
            resultData = nil
            resultSource = nil
            showComparison = false
            renderings.forget()
        }

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
            // Through the one function that measures a picture. This path was already correct and
            // the view's was not, which is exactly the problem: two measurements, no way to tell
            // them apart, and months of disagreement about the same file.
            let measured = ImageDimensions.pixelSize(of: url)
            if measured != .zero {
                inputWidth = Int(measured.width)
                inputHeight = Int(measured.height)
            }
            // Re-cap custom dimensions against new image's 8× limit
            reapplyDimensionCap()
            // A new image adopts the model's native scale, as in v1 — but it does not create a
            // selection. Dropped with the scale off, it simply becomes the image to work on.
            adoptNativeScale(nativeScale)
        }

        guard let options = coordinatorOptions(for: selection ?? scaleSelection) else {
            isProcessing = false
            progressMessage = ""
            return
        }

        // A rendering already produced for this asset, model, sizing and face setting is shown
        // again rather than rebuilt. The store was consulted on the face-enhancement path only, so
        // toggling the scale off and on again rebuilt from scratch every time while toggling faces
        // was instant — the asymmetry the author noticed, and the evidence for where the omission
        // was.
        // 🚫 **Deliberately reads the property rather than the effective selection**, and that is a
        // known latent defect rather than an oversight. `@Published` publishes in `willSet`, so
        // inside the `$scaleSelection` sink this keys the store by the scale being *replaced*:
        // choosing 8x looks up 4x, and where a 4x rendering is held it is returned instantly, so
        // the user sees the previous scale's picture beneath a readout naming the new one.
        //
        // Threading the effective selection through here fixes it in three lines and was tried.
        // It also changes when a run happens rather than a cached rendering being served, which
        // moved three closed issues' GUI tests (RT-156, RT-158, RT-090.52) from passing to failing
        // — not because they were wrong, but because they were written against the timings the
        // defect produces. That is a change with its own tests and its own verification burden.
        // **Tracked as #106**, which carries the reachability analysis, the harmful case, and the
        // staged fix procedure. Remove this note as part of that fix.
        if let held = heldRendering(facesEnhanced: faceEnhance) {
            result = held
            isProcessing = false
            progressMessage = ""
            showComparison = true
            return
        }

        start(source: source, options: options)
    }

    /// Runs an upscale, replacing any run already in flight.
    ///
    /// The task is retained rather than detached, so a run superseded by a new image or a changed
    /// setting can be cancelled and its result ignored. Two runs previously raced here, and which
    /// one landed last was not determined by anything.
    private func start(source: GUIUpscaleSource, options: GUIUpscaleOptions) {
        upscaleTask?.cancel()
        let run = UUID()
        activeRun = run

        // Cleared where a run actually begins, not in `processImage`. Cleared there, a rendering
        // served from the store returned before any run started and left the metadata empty, so the
        // info panel reported "Auto-detect" for a picture whose model had in fact been resolved.
        lastUpscaleModelName = nil
        lastUpscaleFaceCount = 0
        lastUpscaleWasAutoDetect = false

        let coordinator = upscaleCoordinator
        let faceWasEnabled = faceEnhance
        // The source's true pixel dimensions, so the coordinator can bound the output by area.
        // Without them the ceiling cannot bind, and a large picture takes the process down with it.
        let sourcePixelSize: CGSize? = {
            guard let width = inputWidth, let height = inputHeight else { return nil }
            return CGSize(width: width, height: height)
        }()
        // One stream per run, consumed in order. Reports arrive once per tile, and unstructured
        // per-report tasks carry no ordering between them.
        let (reports, continuation) = AsyncStream<StageProgress>.makeStream()

        upscaleTask = Task { [weak self] in
            let observer = Task { @MainActor [weak self] in
                for await progress in reports {
                    self?.receive(progress, from: run)
                }
            }
            defer { observer.cancel() }

            do {
                // No detached task: the pipeline is lent by an actor, so the blocking work runs
                // on that actor's executor rather than on this main-actor-isolated view model.
                // Awaiting it here keeps the run structured, and cancelling this task now reaches
                // the pipeline's own cancellation checks.
                let output = try await coordinator.process(
                    source: source, options: options, sourceSize: sourcePixelSize
                ) { progress in
                    continuation.yield(UpscaleProgressReader.progress(for: progress))
                }
                continuation.finish()
                await observer.value
                await MainActor.run {
                    self?.publish(output, from: run, faceEnhanceWasEnabled: faceWasEnabled)
                }
            } catch {
                continuation.finish()
                await observer.value
                await MainActor.run { self?.abandon(run, error: error) }
            }
        }
    }

    /// Progress from a run that has been superseded reaches nothing.
    private func receive(_ progress: StageProgress, from run: UUID) {
        guard activeRun == run else { return }
        if case let .enhancingFaces(count) = progress.phase {
            lastUpscaleFaceCount = count
        }
        progressMessage = displayText(for: progress)
    }

    /// The phase decides what is shown; the detail is wording, never parsed.
    private func displayText(for progress: StageProgress) -> String {
        if case .stitching = progress.phase, scaleSelection == .custom {
            return "Resizing to \(customWidth)×\(customHeight)..."
        }
        return progress.detail ?? ""
    }

    // MARK: - Renderings already produced

    /// What produced the rendering the current settings call for.
    ///
    /// `nil` when there is nothing to key: no picture, or no scale selected, in which case there is
    /// no upscale to hold and nothing to look up.
    /// What the scale control should report, given the picture and the selection.
    ///
    /// Derived rather than awaited: the coordinator returns an `UpscaleDecision` when a run
    /// completes, and reading the reduction from *that* would show 4x, run, and then correct itself
    /// to 2x. The reported defect, briefer. `UpscaleCeiling.decide` is pure, so the truth is
    /// available the moment the picture's dimensions are known.
    var scaleReadout: ScaleReadout {
        let sourceSize: CGSize? = {
            guard let width = inputWidth, let height = inputHeight else { return nil }
            return CGSize(width: width, height: height)
        }()

        return ScaleReadout.of(
            sourceSize: sourceSize,
            selection: scaleSelection,
            customWidth: Int(customWidth),
            customHeight: Int(customHeight),
            stretch: stretchEnabled)
    }

    /// The sizing, as a value two runs can be compared on.
    ///
    /// Custom dimensions are part of it: a rendering at 1920 wide is not a rendering at 800 wide,
    /// and a key that said only "custom" would serve one for the other.
    private func renderingSizingDescription(for selection: ScaleSelection) -> String {
        switch selection {
        case .off:
            return "off"
        case let .preset(scale):
            return "preset:\(scale)"
        case .custom:
            // Parsed rather than interpolated raw: the fields are text, and "0500" and "500" are
            // the same output but would key differently, costing a rebuild that would read as a
            // performance problem rather than a formatting one.
            let width = Int(customWidth).map(String.init) ?? "-"
            let height = Int(customHeight).map(String.init) ?? "-"
            return "custom:\(width)x\(height):\(stretchEnabled)"
        }
    }

    /// What to say about a reduction, or nothing when there was none.
    ///
    /// A rendering of the decision the coordinator returned, rather than a message the view model
    /// invents: the decision is a value the regression pack can assert, and this is only its
    /// wording.
    static func reductionNotice(for decision: UpscaleDecision?) -> String? {
        guard let decision, decision.wasReduced, let used = decision.sizing else { return nil }

        switch (decision.requested, used) {
        case let (.preset(asked), .preset(actual)):
            return "Upscaled \(actual)× rather than \(asked)×, to stay within available memory."
        case let (_, .custom(width, height, _)):
            guard let width, let height else { return nil }
            return "Upscaled to \(width) × \(height), to stay within available memory."
        default:
            return "The upscale was reduced to stay within available memory."
        }
    }

    /// The store's key for the current selection.
    ///
    /// Takes the selection as a parameter so the caller can supply the effective one, which a
    /// caller inside the `$scaleSelection` sink must — see the 🚫 note at the store lookup in
    /// `processImage` for why no caller does so yet, and what it would take to change that.
    private func renderingKey(facesEnhanced: Bool, selection: ScaleSelection? = nil)
        -> RenderingKey?
    {
        let selection = selection ?? scaleSelection
        guard let inputURL, !selection.isOff else { return nil }
        return RenderingKey(
            assetID: inputURL.path,
            modelID: selectedModelName,
            sizing: renderingSizingDescription(for: selection),
            facesEnhanced: facesEnhanced)
    }

    private func heldRendering(facesEnhanced: Bool, selection: ScaleSelection? = nil) -> NSImage? {
        guard let key = renderingKey(facesEnhanced: facesEnhanced, selection: selection),
            let identity = renderings.held(for: key)
        else { return nil }

        if let image = renderedImages[identity.id] {
            renderings.markDisplayed(key)
            return image
        }
        return nil
    }

    private func hold(_ image: NSImage, facesEnhanced: Bool, displayed: Bool) {
        guard let key = renderingKey(facesEnhanced: facesEnhanced) else { return }
        let identity = RenderedImage(
            id: "\(key.assetID)|\(key.modelID)|\(key.sizing)|\(key.facesEnhanced)")
        renderedImages[identity.id] = image
        renderings.admit(identity, for: key)
        if displayed { renderings.markDisplayed(key) }
    }

    private func publish(
        _ output: GUIUpscaleResult,
        from run: UUID,
        faceEnhanceWasEnabled: Bool
    ) {
        guard activeRun == run else { return }
        activeRun = nil
        let image = NSImage(data: output.imageData)
        let preFaceImage = output.preFaceImageData.flatMap(NSImage.init(data:))

        result = image
        // Set before the data, so an observer of the data always sees the input it came from
        // rather than the input of the previous run.
        resultSource = output.source
        resultData = output.imageData
        noticeMessage = Self.reductionNotice(for: output.reduction)

        // A run with face enhancement produces both versions, because the un-enhanced image is
        // what the enhancement was applied to. A run without it produces only the one, so toggling
        // enhancement on afterwards is a real rebuild rather than a lookup.
        if let image {
            hold(image, facesEnhanced: faceEnhanceWasEnabled, displayed: true)
        }
        if faceEnhanceWasEnabled, let preFaceImage {
            hold(preFaceImage, facesEnhanced: false, displayed: false)
        }
        lastUpscaleModelName = output.resolvedModelName
        lastUpscaleWasAutoDetect = output.wasAutoDetect
        isProcessing = false
        progressMessage = ""
        showComparison = true
    }

    private func abandon(_ run: UUID, error: Error) {
        guard activeRun == run else { return }
        activeRun = nil
        isProcessing = false
        progressMessage = ""
        // Cancellation is not a failure: the run was replaced, and the replacement reports itself.
        guard !(error is CancellationError) else { return }
        report(error)
    }

    /// The options for a run, or nothing when no scale is selected and no run is due.
    private func coordinatorOptions(for selection: ScaleSelection) -> GUIUpscaleOptions? {
        let sizing: GUIUpscaleSizing
        switch selection {
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
