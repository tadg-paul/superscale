// ABOUTME: Contextual info panel displayed below the toolbar.
// ABOUTME: Shows dynamic summary of current model, scale, stretch, and face enhancement settings.

import SuperscaleKit
import SuperscaleUXCore
import SwiftUI

struct InfoPanel: View {
    @ObservedObject var viewModel: UpscaleViewModel
    @Binding var dismissed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier(identifier(for: line))
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
            .accessibilityIdentifier("infoPanelDismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(.top, 12)
    }

    /// The picture's own size, where one is loaded.
    ///
    /// `SizingLine` needs it to judge a request against the ceiling; with no picture there is
    /// nothing to judge, and it says so.
    private var sourceSize: CGSize? {
        guard let width = viewModel.inputWidth, let height = viewModel.inputHeight else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    private var lines: [String] {
        var result: [String] = []

        // Model — show auto-detected name after upscale
        let modelName = viewModel.selectedModelName
        if let lastModel = viewModel.lastUpscaleModelName {
            let model = ModelRegistry.model(named: lastModel)
            let displayName = model?.displayName ?? lastModel
            if viewModel.lastUpscaleWasAutoDetect {
                result.append("Model: \(displayName) (auto-detected)")
            } else {
                result.append("Model: \(displayName)")
            }
        } else if modelName == "auto" {
            result.append("Model: Auto-detect")
        } else if let model = ModelRegistry.model(named: modelName) {
            result.append("Model: \(model.displayName)")
        }

        // Face enhancement — immediately after model
        if viewModel.lastUpscaleFaceCount > 0 {
            let n = viewModel.lastUpscaleFaceCount
            result.append("\(n) face\(n == 1 ? "" : "s") enhanced (GFPGAN)")
        } else if viewModel.faceEnhance {
            result.append("Face enhancement enabled")
        }

        // Input dimensions
        if let w = viewModel.inputWidth, let h = viewModel.inputHeight {
            result.append("Input: \(w)×\(h)")
        }

        // Scale, from the one function that decides sizing rather than from arithmetic here.
        //
        // 🚫 The local `\(w * scale)×\(h * scale)` is removed by #108. It multiplied input by
        // scale and never consulted `UpscaleCeiling.decide`, so it reported the request as though
        // it were the outcome: a 3840×2160 photograph at 8x read "Scale: 4× → 15360×8640", which is
        // 132 megapixels against a 32-megapixel ceiling and an output nothing was going to produce.
        // The status bar, a few pixels away, reported the truth.
        //
        // The `.custom` branch did the same thing with the typed dimensions and went the same way.
        result.append(
            SizingLine.of(
                sourceSize: sourceSize,
                selection: viewModel.scaleSelection,
                customWidth: viewModel.customWidth,
                customHeight: viewModel.customHeight,
                stretch: viewModel.stretchEnabled,
                definesWidth: viewModel.definingDimension == .width
            )
        )

        // Stretch
        if viewModel.stretchEnabled && viewModel.scaleSelection == .custom {
            result.append("Stretch enabled — output ignores aspect ratio")
        }


        return result
    }

    private func identifier(for line: String) -> String {
        if line.hasPrefix("Model:") { return "infoModel" }
        if line.hasPrefix("Input:") { return "infoInput" }
        if line.hasPrefix("Scale:") || line.hasPrefix("Custom") { return "infoScale" }
        if line.contains("face") || line.hasPrefix("Face") { return "infoFace" }
        return "infoDetail"
    }
}
