// ABOUTME: Contextual info panel displayed below the toolbar.
// ABOUTME: Shows dynamic summary of current model, scale, stretch, and face enhancement settings.

import SuperscaleKit
import SwiftUI

struct InfoPanel: View {
    @ObservedObject var viewModel: UpscaleViewModel
    @Binding var dismissed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }

            Button {
                dismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(.top, 12)
    }

    private var lines: [String] {
        var result: [String] = []

        // Model
        let modelName = viewModel.selectedModelName
        if modelName == "auto" {
            result.append("Model: Auto-detect")
        } else if let model = ModelRegistry.model(named: modelName) {
            result.append("Model: \(model.displayName) (\(model.name))")
        }

        // Scale
        switch viewModel.scaleMode {
        case .preset(let scale):
            if let w = viewModel.inputWidth, let h = viewModel.inputHeight {
                result.append("Scale: \(scale)× → \(w * scale)×\(h * scale)")
            } else {
                result.append("Scale: \(scale)×")
            }
        case .custom:
            let w = viewModel.customWidth
            let h = viewModel.customHeight
            if viewModel.stretchEnabled {
                result.append("Custom: \(w)×\(h) (stretch)")
            } else if viewModel.definingDimension == .width, !w.isEmpty {
                result.append("Custom width: \(w)px")
            } else if !h.isEmpty {
                result.append("Custom height: \(h)px")
            } else {
                result.append("Custom resolution: enter width or height")
            }
        }

        // Stretch
        if viewModel.stretchEnabled && viewModel.scaleMode == .custom {
            result.append("Stretch enabled — output ignores aspect ratio")
        }

        // Face enhancement
        if viewModel.faceEnhance {
            result.append("Face enhancement enabled (GFPGAN)")
        }

        // Post-upscale summary
        if let result_img = viewModel.result,
           let w = viewModel.inputWidth, let h = viewModel.inputHeight {
            let rep = result_img.representations.first
            let outW = rep?.pixelsWide ?? Int(result_img.size.width)
            let outH = rep?.pixelsHigh ?? Int(result_img.size.height)
            let modelLabel = modelName == "auto" ? "auto-detected model" : modelName
            result.append("Upscaled \(w)×\(h) → \(outW)×\(outH) using \(modelLabel)")
        }

        return result
    }
}
