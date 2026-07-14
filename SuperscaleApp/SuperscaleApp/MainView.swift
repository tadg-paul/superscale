// ABOUTME: Main window view for the Superscale GUI.
// ABOUTME: Contains drag-and-drop target, model picker, result display, and progress overlay.

import SuperscaleKit
import SuperscaleUXCore
import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: UpscaleViewModel
    @StateObject private var navigation = AppNavigation()
    @State private var showAbout = false
    @State private var showFaceDownload = false
    @State private var infoPanelDismissed = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            workspace
        }
        .navigationTitle(windowTitle)
        .alert("Error", isPresented: showError, actions: {
            Button("OK") { viewModel.errorMessage = nil }
        }, message: {
            Text(viewModel.errorMessage ?? "")
        })
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
            emptyWorkspace(for: .generate)
        case .history:
            emptyWorkspace(for: .history)
        case .settings:
            emptyWorkspace(for: .settings)
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
        .accessibilityIdentifier("upscaleWorkspace")
    }

    private func emptyWorkspace(for mode: AppMode) -> some View {
        ContentUnavailableView(mode.rawValue, systemImage: icon(for: mode))
            .accessibilityIdentifier("\(mode.rawValue.lowercased())Workspace")
    }

    private var selectedMode: Binding<AppMode?> {
        Binding(
            get: { navigation.selectedMode },
            set: { mode in
                if let mode {
                    navigation.select(mode)
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
                    viewModel.saveAs()
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
    MainView(viewModel: UpscaleViewModel())
        .frame(width: 700, height: 500)
}

#Preview("Processing") {
    let vm = UpscaleViewModel()
    vm.isProcessing = true
    vm.progressMessage = "Processing tile 2 of 4..."
    return MainView(viewModel: vm)
        .frame(width: 700, height: 500)
}
