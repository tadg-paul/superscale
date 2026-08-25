// ABOUTME: Presents Keychain credentials and non-secret defaults for GUI generation workflows.
// ABOUTME: Keeps generation and account controls separate and exposes bundled prompt selection.

import AppKit
import FalGenerationKit
import SuperscaleKit
import SuperscaleUXCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: GenerationSettingsState
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
                        status: state.generationKeyStatus,
                        isChecking: state.isVerifyingGenerationKey,
                        fieldIdentifier: "generationKeyField",
                        save: saveGenerationKey,
                        clear: clearGenerationKey
                    )
                    // 🚫 The pricing summary, the Check Pricing control, the account summary, the
                    // Refresh Account control and the billing list are removed by #89. Section 6
                    // of the implementation guide takes the pricing client, the account client,
                    // the session cache and the cost-confirmation policy out of MVP scope: grok is
                    // a known flat rate, held as a documented constant beside Apply. Controls left
                    // in place would have gone on contacting a provider the MVP excludes, which is
                    // what made the removal this slice's business rather than a tidy-up.
                    //
                    // This supersedes the "account state" part of AC73.5. The credential fields,
                    // the defaults and the filter selection it also names are unaffected.

                    credentialRow(
                        title: "Account/admin key",
                        text: $state.accountAdministrationKey,
                        // The account key carries no verification state: verifying it would mean
                        // calling an account or billing endpoint, which is the surface the MVP has
                        // paused. Stored or absent is all that can honestly be said about it.
                        status: state.isAccountAdministrationConfigured ? .stored : .absent,
                        isChecking: false,
                        fieldIdentifier: "accountAdministrationKeyField",
                        save: saveAccountKey,
                        clear: clearAccountKey
                    )
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

                    // 🚫 The cost-confirmation threshold is removed by #95. Section 6 of the
                    // implementation guide takes the cost-confirmation policy out of MVP scope
                    // along with the pricing and account clients, and grok is a known flat rate
                    // held as a documented constant beside Apply. Nothing consulted this value:
                    // it was a control that asked the user to configure a decision the
                    // application no longer makes. Its stored preference goes with it.
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
        status: CredentialStatus,
        isChecking: Bool,
        fieldIdentifier: String,
        save: @escaping () -> Void,
        clear: @escaping () -> Void
    ) -> some View {
        LabeledContent {
            HStack(spacing: 8) {
                // A `TextField`, not a `SecureField`. A FAL key is a bearer credential rather than
                // a password recited from memory, and masking it prevents the one check anybody
                // performs on a pasted key: looking at it. Where it is *stored* is unchanged — the
                // Keychain — and so is the rule that it travels only in a request header.
                TextField(title, text: text)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 260)
                    // Hidden, not renamed. The field took `title` as its own label and macOS drew
                    // it beside the field, so every row said its name twice.
                    .labelsHidden()
                    .accessibilityIdentifier(fieldIdentifier)
                Button(action: save) {
                    Image(systemName: "checkmark")
                }
                .help("Save \(title.lowercased())")
                .disabled(isChecking)
                .accessibilityIdentifier(
                    fieldIdentifier == "generationKeyField"
                        ? "saveGenerationKeyButton"
                        : "saveAccountKeyButton"
                )
                Button(role: .destructive, action: clear) {
                    Image(systemName: "trash")
                }
                .help("Remove \(title.lowercased())")
                .disabled(!status.isPresent || isChecking)
                .accessibilityIdentifier(
                    fieldIdentifier == "generationKeyField"
                        ? "removeGenerationKeyButton"
                        : "removeAccountKeyButton"
                )
                if isChecking {
                    // Pressing save previously changed nothing visible: the key went to the
                    // Keychain and the window looked exactly as it had. A check that reaches the
                    // provider takes long enough for that silence to read as a broken button.
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityElement()
                        .accessibilityIdentifier("generationKeyCheckingIndicator")
                        .accessibilityLabel("Checking the generation key")
                } else {
                    credentialStatusBadge(for: status)
                        .accessibilityIdentifier(
                            fieldIdentifier == "generationKeyField"
                                ? "generationKeyStatusBadge"
                                : "accountKeyStatusBadge"
                        )
                }
            }
        } label: {
            // The row's own name, identified so a test can assert there is exactly one of it. The
            // count would otherwise depend on how SwiftUI reports a hidden field label.
            Text(title)
                .accessibilityIdentifier(
                    fieldIdentifier == "generationKeyField"
                        ? "generationKeyLabel"
                        : "accountKeyLabel"
                )
        }
    }

    /// What the badge says, and what it means.
    ///
    /// It previously read from whether a key was *stored*, so a typo saved and showed green. Green
    /// now means the provider accepted it. "Stored" is a third state and not a failure: it is what
    /// a key looks like before anyone has asked, and what it returns to when the provider cannot be
    /// reached — the difference between "we could not ask" and "the answer was no" being the
    /// difference between a user waiting and a user deleting a working key.
    private func credentialStatusBadge(for status: CredentialStatus) -> some View {
        // Declared as one element with an explicit label and value rather than left as a `Label`
        // with `.iconOnly`, because what an icon-only label contributes to the accessibility tree
        // is a rendering detail and this state has to be readable — by VoiceOver, and by a test
        // asking what the badge says. Colour alone reaches neither.
        Image(systemName: status.badgeSymbol)
            .foregroundStyle(badgeTint(for: status))
            .help(status.badgeDescription)
            .accessibilityElement()
            .accessibilityLabel("Credential status")
            .accessibilityValue(status.badgeDescription)
    }

    /// Colour accompanies the badge's value; it never carries it alone.
    private func badgeTint(for status: CredentialStatus) -> Color {
        switch status {
        case .absent, .stored:
            return .secondary
        case .verified:
            return .green
        case .rejected:
            return .red
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

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            state.outputFolder = panel.url
        }
    }

    /// Saves the key and then asks the provider whether it works.
    ///
    /// One press, two outcomes. The notice reports the store, which is what the press did; the badge
    /// reports the provider's answer when it arrives, which is a separate claim and used to be told
    /// as if it were the same one.
    private func saveGenerationKey() {
        Task {
            do {
                try await state.saveAndVerifyGenerationKey()
                notice = "Generation key saved"
            } catch {
                localError = error.localizedDescription
            }
        }
    }

    private func clearGenerationKey() {
        perform("Generation key removed") { try state.clearGenerationCredential() }
    }

    private func saveAccountKey() {
        perform("Account key saved") { try state.saveAccountAdministrationCredential() }
    }

    private func clearAccountKey() {
        perform("Account key removed") { try state.clearAccountAdministrationCredential() }
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
