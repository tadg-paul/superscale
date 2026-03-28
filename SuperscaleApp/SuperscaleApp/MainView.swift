// ABOUTME: Main window view for the Superscale GUI.
// ABOUTME: Contains drag-and-drop target, model picker, result display, and progress overlay.

import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: UpscaleViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .alert("Error", isPresented: showError, actions: {
            Button("OK") { viewModel.errorMessage = nil }
        }, message: {
            Text(viewModel.errorMessage ?? "")
        })
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            ModelPicker(selectedModelName: $viewModel.selectedModelName,
                        options: viewModel.modelOptions)

            Text("\(viewModel.nativeScale)×")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            if viewModel.result != nil {
                Button(viewModel.showComparison ? "Full View" : "Compare") {
                    viewModel.showComparison.toggle()
                }
                .disabled(viewModel.originalImage == nil)

                Button("Save As…") {
                    viewModel.saveAs()
                }
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
                ZStack {
                    ComparisonView(original: original, upscaled: upscaled)

                    DropTargetView(onDrop: viewModel.handleDrop)
                        .opacity(0.01)
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

    private var showError: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }
}
