// ABOUTME: Scale and resolution picker for the GUI toolbar.
// ABOUTME: Offers preset scales (2×, 4×, 8×) and custom resolution with optional stretch.

import SuperscaleUXCore
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
                    viewModel.choose(.preset(scale))
                    focusedField = nil
                } label: {
                    Text("\(scale)×")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
                .buttonStyle(.bordered)
                .tint(tint(for: .preset(scale)))
                .help(help(for: .preset(scale), label: "Upscale \(scale)×"))
                // The state travels as a value, not only as a colour. A tint reaches nobody: not
                // VoiceOver, and not a test trying to establish which scale is actually running.
                // That gap has now produced three separate untestable criteria in this delivery.
                .accessibilityValue(readoutDescription(for: .preset(scale)))
                .accessibilityIdentifier("scale\(scale)x")
            }

            Button {
                viewModel.choose(.custom)
                focusedField = viewModel.isActive(.custom) ? .width : nil
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "ruler")
                    if viewModel.showButtonLabels {
                        Text("Custom")
                            .font(.system(size: 11))
                    }
                }
            }
            .buttonStyle(.bordered)
            .tint(tint(for: .custom))
            .help(help(for: .custom, label: "Custom resolution"))
            .accessibilityValue(readoutDescription(for: .custom))
            .accessibilityIdentifier("scaleCustom")
        }
    }

    // MARK: - What each scale reads as

    /// The scale in effect is accented; one asked for but overruled is drawn back, and still
    /// pressable. Dimmed must not mean disabled, or a user whose upscale was reduced is stuck with
    /// it until they import a different picture.
    private func tint(for choice: ScaleSelection) -> Color? {
        switch viewModel.scaleReadout.state(of: choice) {
        case .inEffect: return .accentColor
        case .requestedNotInEffect: return .secondary
        case .inactive: return nil
        }
    }

    private func help(for choice: ScaleSelection, label: String) -> String {
        switch viewModel.scaleReadout.state(of: choice) {
        case .inEffect:
            return "Turn off upscaling"
        case .requestedNotInEffect:
            return "\(label) was requested. A smaller upscale is running to stay within memory."
        case .inactive:
            return label
        }
    }

    /// The same state as a value, which is what reaches VoiceOver and the test suite.
    private func readoutDescription(for choice: ScaleSelection) -> String {
        switch viewModel.scaleReadout.state(of: choice) {
        case .inEffect: return "in effect"
        case .requestedNotInEffect: return "requested, not in effect"
        case .inactive: return "inactive"
        }
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
                .accessibilityIdentifier("customWidth")

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
                .accessibilityIdentifier("customHeight")

            if isEditable {
                Toggle(isOn: $viewModel.stretchEnabled) {
                    HStack(spacing: 3) {
                        Image(systemName: viewModel.stretchEnabled
                              ? "arrow.down.backward.and.arrow.up.forward.rectangle.fill"
                              : "arrow.down.backward.and.arrow.up.forward.rectangle")
                        if viewModel.showButtonLabels {
                            Text("Stretch")
                                .font(.system(size: 11))
                        }
                    }
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
        if case .preset(let scale) = viewModel.scaleSelection,
           let dims = viewModel.targetDimensions(forScale: scale) {
            return "\(dims.width)"
        }
        return ""
    }

    private func presetHeightString() -> String {
        if case .preset(let scale) = viewModel.scaleSelection,
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
