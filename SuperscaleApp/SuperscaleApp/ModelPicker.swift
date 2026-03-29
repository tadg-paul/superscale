// ABOUTME: Model selection button in the toolbar.
// ABOUTME: Opens a modal sheet for choosing a model with full descriptions.

import SuperscaleKit
import SwiftUI

struct ModelPicker: View {
    @Binding var selectedModelName: String
    @Binding var faceEnhance: Bool
    let options: [UpscaleViewModel.ModelOption]
    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                Text(selectedLabel)
                    .lineLimit(1)
            }
        }
        .help("Choose the AI upscaling model")
        .sheet(isPresented: $showSheet) {
            ModelSelectionSheet(
                selectedModelName: $selectedModelName,
                faceEnhance: $faceEnhance,
                options: options,
                isPresented: $showSheet)
        }
    }

    private var selectedLabel: String {
        options.first { $0.id == selectedModelName }?.displayName ?? "Auto-detect"
    }
}

// MARK: - Model selection sheet

struct ModelSelectionSheet: View {
    @Binding var selectedModelName: String
    @Binding var faceEnhance: Bool
    let options: [UpscaleViewModel.ModelOption]
    @Binding var isPresented: Bool
    @State private var expandedModelID: String?
    @State private var showFaceDownload: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Text("Select Model")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(options) { option in
                        modelRow(option: option)
                        if option.id != options.last?.id {
                            Divider().padding(.horizontal, 16)
                        }
                    }

                    Divider().padding(.horizontal, 16)
                    faceEnhanceRow
                }
                .padding(.vertical, 8)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 480, height: 500)
    }

    // MARK: - Face enhancement row

    private var faceEnhanceRow: some View {
        HStack(spacing: 10) {
            Button {
                if FaceModelRegistry.isInstalled {
                    faceEnhance.toggle()
                } else {
                    showFaceDownload = true
                }
            } label: {
                Image(systemName: faceEnhance && FaceModelRegistry.isInstalled
                      ? "face.smiling.inverse" : "face.smiling")
                    .font(.title3)
                    .foregroundStyle(faceEnhance && FaceModelRegistry.isInstalled
                                     ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Face enhancement")
                    .font(.system(.body, weight: faceEnhance ? .semibold : .regular))
                Text(FaceModelRegistry.isInstalled ? "GFPGAN v1.4" : "Not installed — click to download")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .help("GFPGAN face enhancement — detects and enhances faces in upscaled images. Non-commercial licence (NVIDIA Source Code Licence, CC BY-NC-SA 4.0).")
        .sheet(isPresented: $showFaceDownload) {
            FaceModelDownloadView(isPresented: $showFaceDownload) {
                faceEnhance = true
            }
        }
    }

    private func modelRow(option: UpscaleViewModel.ModelOption) -> some View {
        let isSelected = option.id == selectedModelName
        let isExpanded = expandedModelID == option.id
        let detail = ModelSelectionSheet.detailText(for: option.id)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                // Radio button — selects model and closes sheet
                Button {
                    selectedModelName = option.id
                    isPresented = false
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 24)

                // Model name — toggles info expansion
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.displayName)
                        .font(.system(.body, weight: isSelected ? .semibold : .regular))

                    if option.id != "auto" {
                        Text(option.id)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if detail != nil {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedModelID = isExpanded ? nil : option.id
                        }
                    }
                }

                Spacer()

                if detail != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedModelID = isExpanded ? nil : option.id
                        }
                    } label: {
                        Image(systemName: isExpanded ? "info.circle.fill" : "info.circle")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if isExpanded, let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 50)
                    .padding(.trailing, 16)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    // MARK: - Model descriptions (from ModelRegistry, with auto-detect fallback)

    private static let autoDescription = """
        Automatically selects the best model for your image content \
        using Vision framework classification. Photographs use \
        realesrgan-x4plus; illustrations and anime use realesrgan-anime-6b.
        """

    static func detailText(for modelID: String) -> String? {
        if modelID == "auto" { return autoDescription }
        return ModelRegistry.model(named: modelID)?.detailedDescription
    }
}
