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
    @State private var faceInfoExpanded: Bool = false

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

                    if FaceModelRegistry.isInstalled {
                        Divider().padding(.horizontal, 16)
                        faceEnhanceRow
                    }
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Toggle("", isOn: $faceEnhance)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-enhance faces")
                        .font(.system(.body, weight: faceEnhance ? .semibold : .regular))

                    Text("GFPGAN v1.4")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        faceInfoExpanded.toggle()
                    }
                } label: {
                    Image(systemName: faceInfoExpanded ? "info.circle.fill" : "info.circle")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if faceInfoExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text("""
                        GFPGAN face enhancement detects faces in the upscaled image \
                        and enhances them using a dedicated neural network. Runs \
                        automatically on every upscale when enabled.
                        """)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("Non-commercial licence")
                            .font(.callout)
                            .fontWeight(.medium)
                    }

                    Text("""
                        This model contains components licensed under \
                        NVIDIA Source Code Licence (non-commercial) and \
                        CC BY-NC-SA 4.0. The licence applies to the model \
                        weights, not to output images.
                        """)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 50)
                .padding(.trailing, 16)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func modelRow(option: UpscaleViewModel.ModelOption) -> some View {
        let isSelected = option.id == selectedModelName
        let isExpanded = expandedModelID == option.id
        let detail = ModelSelectionSheet.modelDetails[option.id]

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

    // MARK: - Full model descriptions from CLI help text

    static let modelDetails: [String: String] = [
        "auto": """
            Automatically selects the best model for your image content \
            using Vision framework classification. Photographs use \
            realesrgan-x4plus; illustrations and anime use realesrgan-anime-6b.
            """,
        "realesrgan-x4plus": """
            Best for general photographs. Balanced sharpening and detail \
            preservation. RRDBNet architecture (23 residual blocks). The \
            default when no model is specified and the image is detected \
            as a photograph.
            """,
        "realesrgan-x2plus": """
            General photographs at 2× scale. Preserves more original \
            detail with less hallucination than 4× models. Use when \
            you need a lighter upscale or want to stay closer to the source.
            """,
        "realesrnet-x4plus": """
            PSNR-oriented variant — less aggressive sharpening, fewer \
            artefacts. Preferred for images where fidelity matters more \
            than perceived sharpness (e.g. medical, scientific).
            """,
        "realesrgan-anime-6b": """
            Optimized for anime and cel-shaded illustration. Preserves \
            flat colour regions and clean line art. 6-block RRDBNet \
            — lighter than the full 23-block photo models.
            """,
        "realesr-general-x4v3": """
            General scenes with SRVGGNetCompact architecture — faster \
            and lighter than x4plus. Good when speed matters more than \
            maximum quality.
            """,
        "realesr-general-wdn-x4v3": """
            Denoise variant of general-x4v3. Effective for old photographs, \
            grainy scans, and heavily compressed JPEG sources. Reduces \
            noise while upscaling.
            """,
    ]
}
