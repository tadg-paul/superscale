// ABOUTME: The single Superscale workspace: the image on the canvas, the filters beside it.
// ABOUTME: Holds the base image a filter reads and the candidate a filter produced.

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
    /// The image a filter reads. Never the candidate, and never the upscaled rendering.
    @State private var baseImageURL: URL?

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
                    hasWorkingImage: baseImageURL != nil,
                    isApplying: generationCoordinator.phase == .generating,
                    onApply: applyFilter,
                    onCancel: generationCoordinator.cancel,
                    onOpenSettings: openSettings
                )
            }
            Divider()
            statusBar
        }
        .navigationTitle(windowTitle)
        .onAppear(perform: loadDefaults)
        .onChange(of: viewModel.inputURL) { _, url in
            // An image arriving by any route becomes the base a filter reads.
            if let url, url != candidateURL { baseImageURL = url }
        }
        .onChange(of: coordinatorOutputPath) { _, _ in adoptFilterResult() }
        .alert("Error", isPresented: showError, actions: {
            Button("OK") { viewModel.errorMessage = nil }
        }, message: {
            Text(viewModel.errorMessage ?? "")
        })
    }

    // MARK: - Canvas

    @ViewBuilder
    private var canvas: some View {
        if viewModel.isProcessing {
            ProgressOverlay(message: viewModel.progressMessage)
        } else if let upscaled = viewModel.result {
            if viewModel.showComparison, let original = viewModel.originalImage {
                ComparisonView(original: original, upscaled: upscaled)
                    .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDropProviders)
            } else {
                ZStack(alignment: .top) {
                    resultView(image: upscaled)
                    if !infoPanelDismissed {
                        InfoPanel(viewModel: viewModel, dismissed: $infoPanelDismissed)
                    }
                }
            }
        } else {
            DropTargetView(onDrop: viewModel.handleDrop)
        }
    }

    private func resultView(image: NSImage) -> some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(16)

            DropTargetView(onDrop: viewModel.handleDrop)
                .opacity(0.01)
        }
    }

    // MARK: - Applying a filter

    /// The candidate a filter produced, shown on the canvas while the base stays put.
    ///
    /// Applying always reads the base, so a second filter replaces this rather than compounding
    /// on it. Promoting a candidate to base is what Lock does, and Lock is slice 9b.
    private var candidateURL: URL? {
        generationCoordinator.output?.localURL
    }

    private var coordinatorOutputPath: String? {
        candidateURL?.path
    }

    private func applyFilter() {
        guard let baseImageURL else { return }
        do {
            let reference = try dataURL(for: baseImageURL)
            var workspace = WorkspaceModel(
                filters: selection.filters,
                workingImage: WorkingImage(referenceValue: reference, hasWorkingImage: true),
                isGenerationConfigured: settingsState.isGenerationConfigured
            )
            workspace.selection = selection
            guard let request = workspace.applyRequest() else { return }
            generationCoordinator.start(request, apiKey: settingsState.generationKey)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    /// Sends a filter result to the local upscale, so the canvas shows it the way it shows
    /// anything else: upscaled when a scale is selected, untouched when it is not.
    private func adoptFilterResult() {
        // The coordinator's own input carries its attribution. Constructing one here from a
        // location would be attribution by timing, which #86 closed.
        guard let source = generationCoordinator.upscaleSource else { return }
        upscale(source, arrival: .filterResult)
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

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
