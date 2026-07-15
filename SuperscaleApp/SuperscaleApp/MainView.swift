// ABOUTME: Main window view for the Superscale GUI.
// ABOUTME: Contains drag-and-drop target, model picker, result display, and progress overlay.

import SuperscaleKit
import SuperscaleUXCore
import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: UpscaleViewModel
    @ObservedObject var settingsState: GenerationSettingsState
    @ObservedObject var pricingCoordinator: GenerationPricingCoordinator
    @ObservedObject var accountCoordinator: GenerationAccountCoordinator
    @StateObject private var navigation = AppNavigation()
    @StateObject private var generationCoordinator: GenerationCoordinator
    @State private var showAbout = false
    @State private var showFaceDownload = false
    @State private var infoPanelDismissed = false
    @State private var reopenedSession: GenerationSessionRecord?
    @State private var pendingSessionID: UUID?
    @State private var latestGenerationSessionID: UUID?

    private let sessionStore: GenerationSessionStore

    init(
        viewModel: UpscaleViewModel,
        settingsState: GenerationSettingsState,
        generationCoordinator: GenerationCoordinator? = nil,
        pricingCoordinator: GenerationPricingCoordinator? = nil,
        accountCoordinator: GenerationAccountCoordinator? = nil,
        sessionStore: GenerationSessionStore? = nil
    ) {
        self.viewModel = viewModel
        self.settingsState = settingsState
        self.pricingCoordinator = pricingCoordinator ?? GenerationPricingCoordinator()
        self.accountCoordinator = accountCoordinator ?? GenerationAccountCoordinator()
        _generationCoordinator = StateObject(
            wrappedValue: generationCoordinator
                ?? GenerationCoordinator(outputDirectory: V2AppPaths.generated)
        )
        self.sessionStore = sessionStore
            ?? GenerationSessionStore(rootDirectory: V2AppPaths.history)
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                sidebar
            } detail: {
                workspace
            }
            Divider()
            statusBar
        }
        .navigationTitle(windowTitle)
        .alert("Error", isPresented: showError, actions: {
            Button("OK") { viewModel.errorMessage = nil }
        }, message: {
            Text(viewModel.errorMessage ?? "")
        })
        .onChange(of: viewModel.resultData) { _, data in
            associateCompletedUpscale(data)
        }
        .onChange(of: viewModel.errorMessage) { _, message in
            if message != nil { pendingSessionID = nil }
        }
    }

    private var sidebar: some View {
        List(selection: selectedMode) {
            Section("Superscale") {
                ForEach(AppMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: icon(for: mode))
                        .tag(mode)
                        .accessibilityIdentifier("mode\(mode.rawValue)")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 220)
    }

    @ViewBuilder
    private var workspace: some View {
        switch navigation.selectedMode {
        case .upscale:
            upscaleWorkspace
        case .generate:
            GenerateView(
                settings: settingsState,
                coordinator: generationCoordinator,
                pricing: pricingCoordinator,
                sessionStore: sessionStore,
                reopenedSession: reopenedSession,
                onSendToUpscale: sendToUpscale,
                onOpenSettings: { navigation.select(.settings) },
                onSessionRecorded: { latestGenerationSessionID = $0 }
            )
        case .history:
            HistoryView(
                store: sessionStore,
                onOpenInGenerate: { session in
                    reopenedSession = session
                    navigation.select(.generate)
                },
                onSendToUpscale: { url, sessionID in
                    sendToUpscale(url, sessionID: sessionID)
                }
            )
        case .settings:
            SettingsView(
                state: settingsState,
                pricing: pricingCoordinator,
                account: accountCoordinator
            )
        }
    }

    private func sendToUpscale(_ url: URL, sessionID: UUID?) {
        pendingSessionID = sessionID ?? latestGenerationSessionID
        let preferredModel = settingsState.defaultUpscaleModelID
        if preferredModel == "auto" || ModelRegistry.model(named: preferredModel) != nil {
            viewModel.selectedModelName = preferredModel
        }
        viewModel.handleGeneratedImage(at: url)
        navigation.select(.upscale)
    }

    private func associateCompletedUpscale(_ data: Data?) {
        guard let data, let pendingSessionID else { return }
        do {
            _ = try sessionStore.associateUpscaledAsset(
                data,
                fileExtension: "png",
                withSessionID: pendingSessionID
            )
            self.pendingSessionID = nil
        } catch {
            viewModel.errorMessage = "Could not update generation history: \(error.localizedDescription)"
        }
    }

    private var upscaleWorkspace: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ZStack(alignment: .top) {
                content
                if !infoPanelDismissed && !viewModel.showComparison {
                    InfoPanel(viewModel: viewModel, dismissed: $infoPanelDismissed)
                }
            }
        }
        .onChange(of: viewModel.selectedModelName) { infoPanelDismissed = false }
        .onChange(of: viewModel.scaleMode) { infoPanelDismissed = false }
        .onChange(of: viewModel.stretchEnabled) { infoPanelDismissed = false }
        .onChange(of: viewModel.faceEnhance) { infoPanelDismissed = false }
    }

    private var selectedMode: Binding<AppMode?> {
        Binding(
            get: { navigation.selectedMode },
            set: { mode in
                if let mode {
                    DispatchQueue.main.async {
                        navigation.select(mode)
                    }
                }
            }
        )
    }

    private func icon(for mode: AppMode) -> String {
        switch mode {
        case .upscale:
            return "arrow.up.left.and.arrow.down.right"
        case .generate:
            return "sparkles"
        case .history:
            return "clock.arrow.circlepath"
        case .settings:
            return "gearshape"
        }
    }

    // MARK: - Toolbar

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
            Text(navigation.selectedMode.rawValue)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .accessibilityIdentifier("appStatusBar")
    }

    private var statusText: String {
        if viewModel.isProcessing { return viewModel.progressMessage }
        switch generationCoordinator.phase {
        case .generating:
            return "Generating with FAL"
        case .failed:
            return "Generation needs attention"
        case .cancelled:
            return "Generation cancelled"
        case .succeeded:
            return "Generated image ready"
        case .idle:
            return settingsState.isGenerationConfigured
                ? "Ready · FAL configured · local upscale available"
                : "Ready · local upscale available · FAL key not configured"
        }
    }

    private var statusColour: Color {
        if viewModel.isProcessing || generationCoordinator.phase == .generating { return .orange }
        if case .failed = generationCoordinator.phase { return .red }
        return .green
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isProcessing {
            ProgressOverlay(message: viewModel.progressMessage)
        } else if let upscaled = viewModel.result {
            if viewModel.showComparison, let original = viewModel.originalImage {
                ComparisonView(original: original, upscaled: upscaled)
                    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                        handleDropProviders(providers)
                    }
            } else {
                resultView(image: upscaled)
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

    // MARK: - Face enhance button

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
        .frame(width: 700, height: 500)
}

#Preview("Processing") {
    let vm = UpscaleViewModel()
    vm.isProcessing = true
    vm.progressMessage = "Processing tile 2 of 4..."
    return MainView(viewModel: vm, settingsState: previewSettingsState())
        .frame(width: 700, height: 500)
}

@MainActor
private func previewSettingsState() -> GenerationSettingsState {
    GenerationSettingsState(
        credentials: GenerationCredentialService(storage: KeychainCredentialStorage(service: "org.tigoss.superscale.preview")),
        preferencesStore: GenerationPreferencesStore(),
        promptPackCatalogue: (try? PromptPackCatalogue.bundled()) ?? PromptPackCatalogue(packs: [])
    )
}
