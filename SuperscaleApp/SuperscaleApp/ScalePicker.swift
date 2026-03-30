// ABOUTME: Scale and resolution picker for the GUI toolbar.
// ABOUTME: Offers preset scales (2×, 4×, 8×) and custom resolution with optional stretch.

import SwiftUI

struct ScalePicker: View {
    @ObservedObject var viewModel: UpscaleViewModel

    enum FocusedField {
        case width, height
    }
    @FocusState private var focusedField: FocusedField?

    var body: some View {
        HStack(spacing: 8) {
            scaleButtons
            resolutionFields
        }
    }

    // MARK: - Scale buttons

    private var scaleButtons: some View {
        HStack(spacing: 2) {
            ForEach([2, 4, 8], id: \.self) { scale in
                Button {
                    viewModel.scaleMode = .preset(scale)
                    viewModel.showCustomFields = false
                    focusedField = nil
                } label: {
                    Text("\(scale)×")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
                .buttonStyle(.bordered)
                .tint(isPresetSelected(scale) ? .accentColor : nil)
                .help("Upscale \(scale)×")
            }

            Button {
                viewModel.showCustomFields.toggle()
                if viewModel.showCustomFields {
                    focusedField = .width
                } else {
                    focusedField = nil
                }
            } label: {
                Image(systemName: "ruler")
            }
            .buttonStyle(.bordered)
            .tint(viewModel.scaleMode == .custom ? .accentColor : nil)
            .help("Custom resolution")
        }
    }

    private func isPresetSelected(_ scale: Int) -> Bool {
        if case .preset(let s) = viewModel.scaleMode, s == scale {
            return true
        }
        return false
    }

    // MARK: - Resolution fields

    private var resolutionFields: some View {
        HStack(spacing: 4) {
            let isEditable = viewModel.showCustomFields

            TextField("W", text: widthBinding(editable: isEditable))
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(fieldStyle(isDefining: viewModel.definingDimension == .width))
                .multilineTextAlignment(.trailing)
                .disabled(!isEditable)
                .focused($focusedField, equals: .width)

            Text("×")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("H", text: heightBinding(editable: isEditable))
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(fieldStyle(isDefining: viewModel.definingDimension == .height))
                .multilineTextAlignment(.trailing)
                .disabled(!isEditable)
                .focused($focusedField, equals: .height)

            if isEditable {
                Toggle(isOn: $viewModel.stretchEnabled) {
                    Image(systemName: viewModel.stretchEnabled
                          ? "arrow.down.backward.and.arrow.up.forward.rectangle.fill"
                          : "arrow.down.backward.and.arrow.up.forward.rectangle")
                }
                .toggleStyle(.button)
                .help("""
                    Stretch: resize to exact width × height, ignoring aspect ratio. \
                    Without stretch, enter one dimension and the other is calculated \
                    automatically to preserve proportions.
                    """)
            }
        }
    }

    // MARK: - Bindings

    private func widthBinding(editable: Bool) -> Binding<String> {
        if editable {
            return Binding(
                get: { viewModel.customWidth },
                set: { viewModel.customWidth = capDimension($0) }
            )
        }
        return .constant(presetWidthString())
    }

    private func heightBinding(editable: Bool) -> Binding<String> {
        if editable {
            return Binding(
                get: { viewModel.customHeight },
                set: { viewModel.customHeight = capDimension($0) }
            )
        }
        return .constant(presetHeightString())
    }

    private func presetWidthString() -> String {
        if case .preset(let scale) = viewModel.scaleMode,
           let dims = viewModel.targetDimensions(forScale: scale) {
            return "\(dims.width)"
        }
        return ""
    }

    private func presetHeightString() -> String {
        if case .preset(let scale) = viewModel.scaleMode,
           let dims = viewModel.targetDimensions(forScale: scale) {
            return "\(dims.height)"
        }
        return ""
    }

    private func capDimension(_ value: String) -> String {
        let digits = value.filter { $0.isNumber }
        guard let val = Int(digits), val > viewModel.maxCustomDimension else {
            return digits
        }
        return "\(viewModel.maxCustomDimension)"
    }

    private func fieldStyle(isDefining: Bool) -> some ShapeStyle {
        if !viewModel.showCustomFields || viewModel.stretchEnabled || isDefining {
            return .primary
        }
        return .secondary
    }
}
