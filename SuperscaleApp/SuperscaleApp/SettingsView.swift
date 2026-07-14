// ABOUTME: Presents Keychain credentials and non-secret defaults for GUI generation workflows.
// ABOUTME: Keeps generation and account controls separate and exposes bundled prompt selection.

import AppKit
import FalGenerationKit
import SuperscaleKit
import SuperscaleUXCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: GenerationSettingsState

    var body: some View {
        Form {
            Section("FAL") {
                SecureField("Generation key", text: $state.generationKey)
                    .accessibilityIdentifier("generationKeyField")
                LabeledContent("Generation") {
                    credentialStatus(configured: state.isGenerationConfigured)
                }

                SecureField("Account/admin key", text: $state.accountAdministrationKey)
                    .accessibilityIdentifier("accountAdministrationKeyField")
                LabeledContent("Account state") {
                    credentialStatus(configured: state.isAccountAdministrationConfigured)
                }
                .accessibilityIdentifier("accountState")
            }

            Section("Defaults") {
                Picker("Generation model", selection: $state.defaultModelID) {
                    ForEach(GenerationModelRegistry.mvp.selectableModels, id: \.id) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .accessibilityIdentifier("defaultGenerationModelPicker")

                Picker("Upscale model", selection: $state.defaultUpscaleModelID) {
                    Text("Auto-detect").tag("auto")
                    ForEach(ModelRegistry.models, id: \.name) { model in
                        Text(model.displayName).tag(model.name)
                    }
                }
                .accessibilityIdentifier("defaultUpscaleModelPicker")

                HStack {
                    TextField("Output folder", text: outputFolderPath)
                        .accessibilityIdentifier("outputFolderField")
                    Button {
                        chooseOutputFolder()
                    } label: {
                        Label("Choose", systemImage: "folder")
                    }
                    .accessibilityIdentifier("chooseOutputFolderButton")
                }

                TextField(
                    "Cost confirmation threshold",
                    value: $state.costThreshold,
                    format: .number.precision(.fractionLength(2...4))
                )
                .accessibilityIdentifier("costThresholdField")
            }

            Section("Prompt Packs") {
                Picker("Bundled pack", selection: $state.defaultPromptPackID) {
                    Text("None").tag(nil as String?)
                    ForEach(state.promptPackCatalogue.packs, id: \.id) { pack in
                        Text("\(pack.category): \(pack.displayName)").tag(pack.id as String?)
                    }
                }
                .accessibilityIdentifier("defaultPromptPackPicker")
            }

            HStack {
                Spacer()
                Button("Save Settings") {
                    state.saveReportingErrors()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!state.isSaveEnabled)
                .accessibilityIdentifier("saveSettingsButton")
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(maxWidth: 720, alignment: .topLeading)
        .alert("Settings Error", isPresented: showError) {
            Button("OK") { state.clearError() }
        } message: {
            Text(state.lastError ?? "")
        }
        .accessibilityIdentifier("settingsWorkspace")
    }

    private func credentialStatus(configured: Bool) -> some View {
        Label(configured ? "Configured" : "Not configured", systemImage: configured ? "checkmark.circle" : "minus.circle")
            .foregroundStyle(configured ? Color.secondary : Color.orange)
    }

    private var outputFolderPath: Binding<String> {
        Binding(
            get: { state.outputFolder?.path ?? "" },
            set: { path in
                state.outputFolder = path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
            }
        )
    }

    private var showError: Binding<Bool> {
        Binding(
            get: { state.lastError != nil },
            set: { if !$0 { state.clearError() } }
        )
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            state.outputFolder = panel.url
        }
    }
}
