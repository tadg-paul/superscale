// ABOUTME: Presents Keychain credentials and non-secret defaults for GUI generation workflows.
// ABOUTME: Keeps generation and account controls separate and exposes bundled prompt selection.

import AppKit
import FalGenerationKit
import SuperscaleKit
import SuperscaleUXCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: GenerationSettingsState
    @ObservedObject var pricing: GenerationPricingCoordinator
    @ObservedObject var account: GenerationAccountCoordinator
    @State private var localError: String?
    @State private var notice: String?

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader
            Divider()
            Form {
                Section("FAL credentials") {
                    credentialRow(
                        title: "Generation key",
                        text: $state.generationKey,
                        configured: state.isGenerationConfigured,
                        fieldIdentifier: "generationKeyField",
                        save: saveGenerationKey,
                        clear: clearGenerationKey
                    )
                    HStack {
                        pricingSummary
                            .accessibilityIdentifier("generationPricingSummary")
                        Spacer()
                        Button {
                            Task { await pricing.refresh(modelID: state.defaultModelID, apiKey: state.generationKey) }
                        } label: {
                            Label("Check Pricing", systemImage: "dollarsign.circle")
                        }
                        .disabled(!state.isGenerationConfigured || pricing.state == .loading)
                        .accessibilityIdentifier("checkPricingButton")
                    }

                    credentialRow(
                        title: "Account/admin key",
                        text: $state.accountAdministrationKey,
                        configured: state.isAccountAdministrationConfigured,
                        fieldIdentifier: "accountAdministrationKeyField",
                        save: saveAccountKey,
                        clear: clearAccountKey
                    )
                    accountContent
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

                    LabeledContent("Confirm generation above") {
                        HStack(spacing: 4) {
                            Text("$")
                            TextField(
                                "Threshold",
                                value: $state.costThreshold,
                                format: .number.precision(.fractionLength(2...4))
                            )
                            .frame(width: 90)
                            .accessibilityIdentifier("costThresholdField")
                        }
                    }
                }

                Section("Prompt packs") {
                    Picker("Default pack", selection: $state.defaultPromptPackID) {
                        Text("None").tag(nil as String?)
                        ForEach(state.promptPackCatalogue.packs, id: \.id) { pack in
                            Text("\(pack.category): \(pack.displayName)").tag(pack.id as String?)
                        }
                    }
                    .accessibilityIdentifier("defaultPromptPackPicker")
                    Text("\(state.promptPackCatalogue.packs.count) bundled image filters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    if let notice {
                        Label(notice, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    Button {
                        saveDefaults()
                    } label: {
                        Label("Save Defaults", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!state.isSaveEnabled)
                    .accessibilityIdentifier("saveSettingsButton")
                }
            }
            .formStyle(.grouped)
        }
        .alert("Settings Error", isPresented: showError) {
            Button("OK") {
                localError = nil
                state.clearError()
            }
        } message: {
            Text(localError ?? state.lastError ?? "")
        }
        .accessibilityIdentifier("settingsWorkspace")
    }

    private var workspaceHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings").font(.title2).fontWeight(.semibold)
                Text("FAL access, local defaults, and prompt packs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func credentialRow(
        title: String,
        text: Binding<String>,
        configured: Bool,
        fieldIdentifier: String,
        save: @escaping () -> Void,
        clear: @escaping () -> Void
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                SecureField(title, text: text)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 260)
                    .accessibilityIdentifier(fieldIdentifier)
                Button(action: save) {
                    Image(systemName: "checkmark")
                }
                .help("Save \(title.lowercased())")
                .accessibilityIdentifier(
                    fieldIdentifier == "generationKeyField"
                        ? "saveGenerationKeyButton"
                        : "saveAccountKeyButton"
                )
                Button(role: .destructive, action: clear) {
                    Image(systemName: "trash")
                }
                .help("Remove \(title.lowercased())")
                .disabled(!configured)
                .accessibilityIdentifier(
                    fieldIdentifier == "generationKeyField"
                        ? "removeGenerationKeyButton"
                        : "removeAccountKeyButton"
                )
                Label(configured ? "Configured" : "Not configured",
                      systemImage: configured ? "checkmark.circle.fill" : "minus.circle")
                    .foregroundStyle(configured ? Color.green : Color.secondary)
                    .labelStyle(.iconOnly)
            }
        }
    }

    @ViewBuilder
    private var pricingSummary: some View {
        switch pricing.state {
        case .idle:
            Text("Pricing not checked").foregroundStyle(.secondary)
        case .loading:
            Label("Checking pricing", systemImage: "hourglass")
        case let .available(value):
            Text("\(value.unitPrice.amount.formatted(.currency(code: value.unitPrice.currency))) per \(value.unitPrice.unit); typical call \(value.estimatedCost.formatted(.currency(code: value.currency)))")
        case let .unavailable(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var accountContent: some View {
        HStack {
            accountSummary
                .accessibilityIdentifier("accountSummaryState")
            Spacer()
            Button {
                Task { await account.refresh(accountKey: state.accountAdministrationKey) }
            } label: {
                Label("Refresh Account", systemImage: "arrow.clockwise")
            }
            .disabled(!state.isAccountAdministrationConfigured || account.state == .loading)
            .accessibilityIdentifier("refreshAccountButton")
        }
        // The row is a container, not an element. An accessibility identifier on a stack makes
        // SwiftUI treat that stack as one element and absorb its children, which left the
        // summary and the refresh button unreachable to VoiceOver and to anything else that
        // addresses controls by identity. The pricing row above carries no identifier and its
        // button was always reachable, which is what isolated this.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("accountState")

        if case let .available(summary) = account.state, !summary.billingEvents.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent billing").font(.headline)
                ForEach(summary.billingEvents.prefix(5), id: \.requestID) { event in
                    HStack {
                        Text(event.endpointID).lineLimit(1)
                        Spacer()
                        Text(eventCost(event).formatted(.currency(code: summary.currency)))
                            .monospacedDigit()
                        Text(event.timestamp).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .font(.caption)
                }
            }
            .accessibilityIdentifier("billingEvents")
        }
    }

    @ViewBuilder
    private var accountSummary: some View {
        switch account.state {
        case .idle:
            Text("Account not loaded").foregroundStyle(.secondary)
        case .loading:
            Label("Loading account", systemImage: "hourglass")
        case let .available(summary):
            Text("\(summary.username) · \(summary.balance.formatted(.currency(code: summary.currency))) balance · \(summary.recentUsageCost.formatted(.currency(code: summary.currency))) recent usage")
        case let .unavailable(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
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
            get: { localError != nil || state.lastError != nil },
            set: {
                if !$0 {
                    localError = nil
                    state.clearError()
                }
            }
        )
    }

    private func eventCost(_ event: FalBillingEvent) -> Double {
        Double(event.costEstimateNanoUSD) / 1_000_000_000
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

    private func saveGenerationKey() {
        perform("Generation key saved") { try state.saveGenerationCredential() }
    }

    private func clearGenerationKey() {
        perform("Generation key removed") {
            try state.clearGenerationCredential()
            pricing.reset()
        }
    }

    private func saveAccountKey() {
        perform("Account key saved") { try state.saveAccountAdministrationCredential() }
    }

    private func clearAccountKey() {
        perform("Account key removed") {
            try state.clearAccountAdministrationCredential()
            account.reset()
        }
    }

    private func saveDefaults() {
        perform("Defaults saved") { try state.savePreferences() }
    }

    private func perform(_ success: String, operation: () throws -> Void) {
        do {
            try operation()
            notice = success
        } catch {
            localError = error.localizedDescription
        }
    }
}
