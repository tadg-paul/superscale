// ABOUTME: The single Superscale workspace: the image on the canvas, the filters beside it.
// ABOUTME: Holds the base image a filter reads and the candidate a filter produced.

import FalGenerationKit
import SuperscaleKit
import SuperscaleUXCore
import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: UpscaleViewModel
    @ObservedObject var settingsState: GenerationSettingsState
    @StateObject private var generationCoordinator: GenerationCoordinator
    @State private var selection = FilterSelection()
    @State private var showAbout = false
    @State private var showFaceDownload = false
    @State private var infoPanelDismissed = false
    @State private var didLoadDefaults = false
    /// The workspace's state. The graph decides which asset is read and which is shown; the view
    /// model renders whichever one it is handed.
    @StateObject private var workspace = WorkspaceState(outputDirectory: V2AppPaths.generated)

    private let sessionStore: GenerationSessionStore

    init(
        viewModel: UpscaleViewModel,
        settingsState: GenerationSettingsState,
        generationCoordinator: GenerationCoordinator? = nil,
        sessionStore: GenerationSessionStore? = nil
    ) {
        self.viewModel = viewModel
        self.settingsState = settingsState
        _generationCoordinator = StateObject(
            wrappedValue: generationCoordinator
                ?? GenerationCoordinator(outputDirectory: V2AppPaths.generated)
        )
        self.sessionStore = sessionStore
            ?? GenerationSessionStore(rootDirectory: V2AppPaths.history)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                canvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // A container, not an element. Without this the identifier makes SwiftUI
                    // treat the canvas as one element and absorb the drop target, the image and
                    // the info panel, which is the defect #88 fixed in Settings.
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("workspaceCanvas")
                Divider()
                FilterPanel(
                    selection: $selection,
                    catalogueFailure: settingsState.lastError,
                    isGenerationConfigured: settingsState.isGenerationConfigured,
                    hasWorkingImage: workspace.graph.base != nil,
                    isApplying: generationCoordinator.phase == .generating,
                    canLock: workspace.canLock,
                    onApply: applyFilter,
                    onCancel: generationCoordinator.cancel,
                    onLock: lockCandidate
                )
            }
            if !workspace.lockedIterations.isEmpty {
                Divider()
                LockChainStrip(
                    iterations: workspace.lockedIterations,
                    onSelect: showIteration
                )
            }
            Divider()
            statusBar
        }
        .navigationTitle(windowTitle)
        .onAppear(perform: loadDefaults)
        .onChange(of: viewModel.inputURL) { _, url in adoptImportedImage(url) }
        .onChange(of: coordinatorOutputPath) { _, _ in adoptFilterResult() }
        .onChange(of: workspace.showsBase) { _, _ in displayChosenAsset() }
        // A setting change makes the info panel's summary stale, so it comes back to say what the
        // new setting will do.
        .onChange(of: viewModel.selectedModelName) { infoPanelDismissed = false }
        .onChange(of: viewModel.scaleSelection) { infoPanelDismissed = false }
        .onChange(of: viewModel.stretchEnabled) { infoPanelDismissed = false }
        .onChange(of: viewModel.faceEnhance) { infoPanelDismissed = false }
        .alert("Error", isPresented: showError, actions: {
            Button("OK") { viewModel.errorMessage = nil }
        }, message: {
            Text(viewModel.errorMessage ?? "")
        })
    }

    // MARK: - Canvas

    private var canvas: some View {
        ZStack(alignment: .top) {
            canvasContent
            // Progress sits *over* the image rather than in place of it. Replacing the picture
            // with a spinner threw away the thing the user came for and made a drop look as
            // though it had been ignored.
            if viewModel.isProcessing {
                ProgressOverlay(message: viewModel.progressMessage)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 24)
                    .accessibilityIdentifier("workingIndicator")
            }
            if !infoPanelDismissed && !viewModel.showComparison {
                InfoPanel(viewModel: viewModel, dismissed: $infoPanelDismissed)
            }
        }
    }

    /// What the canvas draws, decided by `CanvasContent`: the base always, the derivation when one
    /// exists and is what the user has chosen to look at, and the curtain when there are two
    /// different images to compare.
    @ViewBuilder
    private var canvasContent: some View {
        if let base = viewModel.originalImage {
            if viewModel.showComparison, let derived = derivedImage {
                ComparisonView(original: base, upscaled: derived)
                    .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDropProviders)
            } else {
                resultView(image: displayedImage ?? base)
            }
        } else {
            DropTargetView(onDrop: viewModel.handleDrop)
        }
    }

    /// The output of the last operation, when there is one.
    private var derivedImage: NSImage? {
        viewModel.result
    }

    /// The image on the canvas: the derivation unless the user has asked for the base.
    private var displayedImage: NSImage? {
        workspace.showsBase ? viewModel.originalImage : (derivedImage ?? viewModel.originalImage)
    }

    private func resultView(image: NSImage) -> some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(16)
                .accessibilityIdentifier("workingImage")

            DropTargetView(onDrop: viewModel.handleDrop)
                .opacity(0.01)
        }
    }

    // MARK: - Applying a filter

    private var coordinatorOutputPath: String? {
        generationCoordinator.output?.localURL.path
    }

    /// Adopts an image the user brought in as the graph's source, starting a new chain.
    private func adoptImportedImage(_ url: URL?) {
        guard let url,
              url != generationCoordinator.output?.localURL,
              url != currentlyDisplayedFileURL else { return }
        workspace.importImage(fileURL: url, pixelSize: importedPixelSize(url))
    }

    private func applyFilter() {
        // The graph decides what a filter reads: the base, never the candidate and never the
        // upscaled rendering. Asking it rather than reaching for what is on screen is the whole
        // point of the graph being the state.
        guard let input = try? workspace.graph.input(for: .filter),
              let asset = try? workspace.graph.asset(for: input) else { return }
        do {
            let reference = try dataURL(for: asset.fileURL)
            var request = WorkspaceModel(
                filters: selection.filters,
                workingImage: WorkingImage(referenceValue: reference, hasWorkingImage: true),
                isGenerationConfigured: settingsState.isGenerationConfigured
            )
            request.selection = selection
            guard let built = request.applyRequest() else { return }
            generationCoordinator.start(built, apiKey: settingsState.generationKey)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    /// Records a filter result as the candidate and shows it.
    private func adoptFilterResult() {
        // The coordinator's own input carries its attribution. Constructing one here from a
        // location would be attribution by timing, which #86 closed.
        guard let source = generationCoordinator.upscaleSource else { return }
        do {
            try workspace.recordFilter(
                named: selection.selectedID ?? "",
                fileURL: source.url,
                pixelSize: importedPixelSize(source.url),
                modelID: FalGenerationRequest.defaultModelID,
                prompt: selection.promptToApply,
                sessionID: source.sessionID
            )
        } catch {
            viewModel.errorMessage = error.localizedDescription
            return
        }
        upscale(source, arrival: .filterResult)
    }

    /// Promotes the candidate to base, so the next filter builds on it.
    private func lockCandidate() {
        do {
            let locked = try workspace.lock()
            try display(locked)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    /// Shows a locked iteration, so an earlier step can be returned to and saved.
    ///
    /// Viewing does not move the base: the chain is a record of what was made, and looking at an
    /// earlier entry is not the same as deciding to work from it again.
    private func showIteration(_ reference: AssetReference) {
        do {
            try display(reference)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    /// Shows whichever asset the workspace's toggle has chosen.
    private func displayChosenAsset() {
        guard let chosen = workspace.displayedAsset else { return }
        do {
            try display(chosen)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    /// Hands an asset to the view model, which renders it upscaled when a scale is selected and
    /// untouched when it is not.
    ///
    /// Resolved through the graph rather than by location, so an upscaled reference is refused
    /// here rather than being sent for a second upscale.
    private func display(_ reference: AssetReference) throws {
        let source = try GUIUpscaleSource(resolving: reference, in: workspace.graph)
        upscale(source, arrival: .filterResult)
    }

    private var currentlyDisplayedFileURL: URL? {
        guard let displayed = workspace.displayedAsset,
              let asset = try? workspace.graph.asset(for: displayed) else { return nil }
        return asset.fileURL
    }

    private func importedPixelSize(_ url: URL) -> CGSize {
        guard let image = NSImage(contentsOf: url) else { return .zero }
        return image.size
    }

    private func upscale(_ source: GUIUpscaleSource, arrival: ImageArrival) {
        viewModel.selectedModelName = WorkspaceModel.resolvedUpscaleModelID(
            preferred: settingsState.defaultUpscaleModelID,
            arrival: arrival,
            isKnown: { ModelRegistry.model(named: $0) != nil }
        )
        viewModel.upscale(source)
    }

    private func dataURL(for url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let mediaType: String
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": mediaType = "image/jpeg"
        case "heic": mediaType = "image/heic"
        case "tif", "tiff": mediaType = "image/tiff"
        default: mediaType = "image/png"
        }
        return "data:\(mediaType);base64,\(data.base64EncodedString())"
    }

    private func loadDefaults() {
        guard !didLoadDefaults else { return }
        didLoadDefaults = true
        selection = FilterSelection(filters: settingsState.promptPackCatalogue.packs)
        if let defaultFilterID = settingsState.defaultPromptPackID {
            selection.choose(defaultFilterID)
        }
    }


    // MARK: - Toolbar and status

    private var toolbar: some View {
        HStack(spacing: 12) {
            ModelPicker(selectedModelName: $viewModel.selectedModelName,
                        faceEnhance: $viewModel.faceEnhance,
                        options: viewModel.modelOptions)
                .accessibilityIdentifier("modelPicker")

            ScalePicker(viewModel: viewModel)

            faceEnhanceButton

            Spacer()

            // Flick between the filtered result and the image it was made from. A view choice
            // only: it stores nothing, so it is free and reversible, and it is unavailable when
            // there is no candidate to compare against.
            if workspace.canCompare {
                Toggle(isOn: $workspace.showsBase) {
                    Label(
                        workspace.showsBase ? "Showing Original" : "Showing Filtered",
                        systemImage: workspace.showsBase ? "photo" : "wand.and.stars"
                    )
                }
                .toggleStyle(.button)
                .help("Show the image this filter was applied to")
                .accessibilityIdentifier("filterToggle")
            }

            if viewModel.result != nil {
                Button(viewModel.showComparison ? "Full View" : "Compare") {
                    viewModel.showComparison.toggle()
                }
                .disabled(viewModel.originalImage == nil)
                .accessibilityIdentifier("compareButton")

                Button("Save As…") {
                    viewModel.saveAs(defaultDirectory: settingsState.outputFolder)
                }
                .accessibilityIdentifier("saveButton")
            }

            if infoPanelDismissed {
                Button {
                    infoPanelDismissed = false
                } label: {
                    Image(systemName: "text.bubble")
                }
                .help("Show info panel")
                .accessibilityIdentifier("infoPanelRestore")
            }

            Button {
                showAbout = true
            } label: {
                Image(systemName: "info.circle")
            }
            .help("About Superscale")
            .accessibilityIdentifier("aboutButton")
            .sheet(isPresented: $showAbout) {
                AboutView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColour)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .accessibilityIdentifier("appStatusBar")
    }

    private var statusText: String {
        if viewModel.isProcessing { return viewModel.progressMessage }
        switch generationCoordinator.phase {
        case .generating:
            return "Applying filter"
        case .failed(let message):
            return message
        case .cancelled:
            return "Filter cancelled"
        case .succeeded:
            return "Filter applied"
        case .idle:
            return settingsState.isGenerationConfigured
                ? "Ready · filters available · local upscale available"
                : "Ready · local upscale available · FAL key not configured"
        }
    }

    private var statusColour: Color {
        if viewModel.isProcessing || generationCoordinator.phase == .generating { return .orange }
        if case .failed = generationCoordinator.phase { return .red }
        return .green
    }

    private var faceEnhanceButton: some View {
        Button {
            if FaceModelRegistry.isInstalled {
                viewModel.faceEnhance.toggle()
            } else {
                showFaceDownload = true
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: viewModel.faceEnhance && FaceModelRegistry.isInstalled
                      ? "face.smiling.inverse" : "face.smiling")
                if viewModel.showButtonLabels {
                    Text("Face")
                        .font(.system(size: 11))
                }
            }
        }
        .foregroundStyle(viewModel.faceEnhance && FaceModelRegistry.isInstalled
                         ? Color.accentColor : Color.secondary)
        .help("Face enhancement (GFPGAN) — detects and enhances faces in upscaled images")
        .accessibilityIdentifier("faceEnhanceButton")
        .sheet(isPresented: $showFaceDownload) {
            FaceModelDownloadView(isPresented: $showFaceDownload) {
                viewModel.faceEnhance = true
            }
        }
    }

    private var windowTitle: String {
        if let url = viewModel.inputURL {
            return "Superscale — \(url.lastPathComponent)"
        }
        return "Superscale"
    }

    private func handleDropProviders(_ providers: [NSItemProvider]) -> Bool {
        let supportedExtensions = ["png", "jpg", "jpeg", "tiff", "tif", "heic"]
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                if supportedExtensions.contains(url.pathExtension.lowercased()) {
                    DispatchQueue.main.async {
                        viewModel.handleDrop(urls: [url])
                    }
                }
            }
        }
        return true
    }

    private var showError: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }
}

#Preview("Empty") {
    MainView(viewModel: UpscaleViewModel(), settingsState: previewSettingsState())
        .frame(width: 900, height: 600)
}

@MainActor
private func previewSettingsState() -> GenerationSettingsState {
    GenerationSettingsState(
        credentials: GenerationCredentialService(
            storage: KeychainCredentialStorage(service: "org.tigoss.superscale.preview")
        ),
        preferencesStore: GenerationPreferencesStore(),
        loadingCatalogue: { try PromptPackCatalogue.bundled() }
    )
}
