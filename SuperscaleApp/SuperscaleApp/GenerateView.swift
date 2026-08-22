// ABOUTME: Presents the v2 FAL generation workspace and generated-image actions.
// ABOUTME: Connects prompt packs, pricing confirmation, history, and local upscale handoff.

import AppKit
import FalGenerationKit
import SuperscaleUXCore
import SwiftUI

enum V2AppPaths {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Superscale", isDirectory: true)
    }

    static var generated: URL { root.appendingPathComponent("Generated", isDirectory: true) }
    static var history: URL { root.appendingPathComponent("History", isDirectory: true) }
}

struct GenerateView: View {
    @ObservedObject var settings: GenerationSettingsState
    @ObservedObject var coordinator: GenerationCoordinator
    @ObservedObject var pricing: GenerationPricingCoordinator
    let sessionStore: GenerationSessionStore
    let reopenedSession: GenerationSessionRecord?
    /// Takes the upscale input rather than a location, so the generated image is what gets
    /// processed regardless of what the view happens to be showing.
    let onSendToUpscale: (GUIUpscaleSource) -> Void
    let onOpenSettings: () -> Void
    let onSessionRecorded: (UUID) -> Void

    @State private var prompt = ""
    @State private var selectedPackID: String?
    @State private var selectedModelID = FalGenerationRequest.defaultModelID
    @State private var aspectRatio = "1:1"
    @State private var references: [URL] = []
    @State private var showCostConfirmation = false
    @State private var localError: String?
    @State private var lastRecordedPhase: String?
    @State private var lastSessionID: UUID?
    @State private var didLoadDefaults = false

    private let aspects = ["1:1", "16:9", "9:16", "4:3", "3:4"]

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader
            Divider()
            controls
            Divider()
            output
        }
        .onAppear {
            guard !didLoadDefaults else { return }
            didLoadDefaults = true
            selectedPackID = settings.defaultPromptPackID
            selectedModelID = settings.defaultModelID
            if let reopenedSession { apply(reopenedSession) }
        }
        .onChange(of: reopenedSession?.id) { _, _ in
            if let reopenedSession { apply(reopenedSession) }
        }
        .onChange(of: selectedModelID) { _, _ in
            pricing.reset()
        }
        .onChange(of: coordinator.phase) { _, phase in
            persist(phase)
        }
        .alert("Confirm generation cost", isPresented: $showCostConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Generate") { submitGeneration() }
        } message: {
            Text(costConfirmationMessage)
        }
        .alert("Generation Error", isPresented: showError) {
            Button("OK") { localError = nil }
        } message: {
            Text(localError ?? "")
        }
    }

    private var workspaceHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Generate").font(.title2).fontWeight(.semibold)
                Text("Create with FAL, then enhance locally")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(selectedModel?.displayName ?? selectedModelID, systemImage: "cpu")
                .foregroundStyle(.secondary)
            compactCostStatus
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var controls: some View {
        HStack(alignment: .top, spacing: 18) {
            Form {
                Picker("Prompt pack", selection: $selectedPackID) {
                    Text("None").tag(nil as String?)
                    ForEach(settings.promptPackCatalogue.packs, id: \.id) { pack in
                        Text("\(pack.category): \(pack.displayName)").tag(pack.id as String?)
                    }
                }
                .accessibilityIdentifier("generationPromptPackPicker")

                Picker("Model", selection: $selectedModelID) {
                    ForEach(GenerationModelRegistry.mvp.selectableModels, id: \.id) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .accessibilityIdentifier("generationModelPicker")

                Picker("Aspect", selection: $aspectRatio) {
                    ForEach(aspects, id: \.self) { Text($0).tag($0) }
                }
                .accessibilityIdentifier("generationAspectPicker")

                if let selectedPack {
                    Text(selectedPack.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(width: 250)

            VStack(alignment: .leading, spacing: 12) {
                Text("Prompt").font(.headline)
                TextEditor(text: $prompt)
                    .font(.body)
                    .frame(minHeight: 90, maxHeight: 130)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.35)))
                    .accessibilityIdentifier("generationPromptField")

                if !settings.isGenerationConfigured {
                    HStack {
                        Label("Add a FAL generation key before generating.", systemImage: "key")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Settings", action: onOpenSettings)
                            .accessibilityIdentifier("openGenerationSettings")
                    }
                }

                Text("Reference images").font(.headline)
                HStack(spacing: 10) {
                    ForEach(0..<GenerationReferenceSelection.maximumCount, id: \.self) { index in
                        referenceWell(index: index)
                    }
                }

                HStack(spacing: 10) {
                    costStatus
                        .accessibilityIdentifier("generationCostState")
                    Spacer()
                    Button("Estimate Cost") { estimateCost() }
                        .labelStyle(.titleAndIcon)
                        .accessibilityIdentifier("estimateCostButton")
                }

                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel", role: .cancel) { coordinator.cancel() }
                        .disabled(coordinator.phase != .generating)
                        .accessibilityIdentifier("cancelGenerationButton")
                    Button {
                        beginGeneration()
                    } label: {
                        Label("Generate", systemImage: "sparkles")
                    }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canGenerate)
                        .accessibilityIdentifier("generateButton")
                }
            }
            .padding(.vertical, 14)
            .padding(.trailing, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var output: some View {
        switch coordinator.phase {
        case .idle:
            ContentUnavailableView(
                "Ready to generate",
                systemImage: "sparkles",
                description: Text("Enter a prompt or choose a prompt pack. Add reference images for an edit.")
            )
        case .generating:
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text("Generating with FAL...").font(.headline)
                Text("You can cancel while the provider request is running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .cancelled:
            ContentUnavailableView("Generation cancelled", systemImage: "xmark.circle")
        case let .failed(message):
            ContentUnavailableView("Generation failed", systemImage: "exclamationmark.triangle", description: Text(message))
        case let .succeeded(generated):
            generatedOutput(generated)
        }
    }

    private func generatedOutput(_ generated: GeneratedOutput) -> some View {
        VStack(spacing: 0) {
            HSplitView {
                Group {
                    if let image = NSImage(contentsOf: generated.localURL) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(16)
                    } else {
                        ContentUnavailableView("Preview unavailable", systemImage: "photo")
                    }
                }
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Session details").font(.headline)
                            .accessibilityIdentifier("generatedSessionDetails")
                        detailRow("Prompt", PromptComposer.compose(pack: selectedPack, userPrompt: prompt))
                        detailRow("Model", selectedModel?.displayName ?? selectedModelID)
                        detailRow("Endpoint", selectedModelID)
                        detailRow("Prompt pack", selectedPack?.displayName ?? "None")
                        detailRow("Aspect", aspectRatio)
                        detailRow("References", "\(references.count)")
                        detailRow("Estimate", estimateDescription)
                        detailRow("File", generated.localURL.path)
                        if !generated.warnings.isEmpty {
                            Divider()
                            Label("Provider warnings", systemImage: "exclamationmark.triangle")
                                .font(.headline)
                            ForEach(Array(generated.warnings.enumerated()), id: \.offset) { _, warning in
                                Text(warningDescription(warning))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: 260, idealWidth: 310, maxWidth: 380)
            }
            Divider()
            HStack {
                Button {
                    if let source = coordinator.upscaleSource {
                        onSendToUpscale(source.associating(sessionID: lastSessionID))
                    }
                } label: {
                    Label("Send to Upscale", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("generatedSendToUpscale")
                Button { save(generated.localURL) } label: {
                    Label("Save As...", systemImage: "square.and.arrow.down")
                }
                    .accessibilityIdentifier("generatedSaveAs")
                Button { beginGeneration() } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                    .accessibilityIdentifier("generatedRetry")
                Button { reveal(generated.localURL) } label: {
                    Label("Reveal", systemImage: "folder")
                }
                    .accessibilityIdentifier("generatedReveal")
                Spacer()
            }
            .padding(14)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private func referenceWell(index: Int) -> some View {
        Button {
            if index < references.count {
                references.remove(at: index)
            } else {
                chooseReference()
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: index < references.count ? "photo.fill" : "plus")
                Text(index < references.count ? references[index].lastPathComponent : "Add image")
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.bordered)
        .help(index < references.count ? "Remove reference image" : "Choose reference image")
        .accessibilityIdentifier("referenceWell\(index + 1)")
    }

    @ViewBuilder
    private var costStatus: some View {
        switch pricing.state {
        case .idle:
            Text("Cost not estimated")
        case .loading:
            ProgressView().controlSize(.small)
            Text("Checking cost...")
        case let .available(pricing):
            Text("Est. \(pricing.estimatedCost, format: .currency(code: pricing.currency)) · \(pricing.unitPrice.amount, format: .currency(code: pricing.unitPrice.currency))/\(pricing.unitPrice.unit)")
        case let .unavailable(message):
            Text("Cost unavailable: \(message)")
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var compactCostStatus: some View {
        switch pricing.state {
        case let .available(value):
            Label(value.estimatedCost.formatted(.currency(code: value.currency)), systemImage: "dollarsign.circle")
                .monospacedDigit()
        case .loading:
            ProgressView().controlSize(.small)
        case .idle, .unavailable:
            Label("Not estimated", systemImage: "dollarsign.circle")
                .foregroundStyle(.secondary)
        }
    }

    private var canGenerate: Bool {
        settings.isGenerationConfigured
            && !PromptComposer.compose(pack: selectedPack, userPrompt: prompt).isEmpty
            && coordinator.phase != .generating
    }

    private var selectedPack: PromptPack? {
        selectedPackID.flatMap(settings.promptPackCatalogue.pack(id:))
    }

    private var selectedModel: GenerationModel? {
        GenerationModelRegistry.mvp.selectableModels.first { $0.id == selectedModelID }
    }

    private var estimatedCost: Double? {
        guard case let .available(pricing) = pricing.state else { return nil }
        return pricing.estimatedCost
    }

    private var estimateDescription: String {
        guard case let .available(value) = pricing.state else { return "Unavailable" }
        return value.estimatedCost.formatted(.currency(code: value.currency))
    }

    private var costConfirmationMessage: String {
        if let estimatedCost {
            return "The estimated cost is \(estimatedCost.formatted(.currency(code: "USD"))), above your configured threshold."
        }
        return "FAL pricing is unavailable. Continue without an estimate?"
    }

    private func chooseReference() {
        guard references.count < GenerationReferenceSelection.maximumCount else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            references.append(contentsOf: panel.urls.prefix(GenerationReferenceSelection.maximumCount - references.count))
        }
    }

    private func estimateCost() {
        let key = settings.generationKey
        let modelID = selectedModelID
        Task {
            await pricing.refresh(modelID: modelID, apiKey: key)
        }
    }

    private func beginGeneration() {
        let policy = GenerationCostPolicy(threshold: settings.costThreshold, confirmWhenUnavailable: true)
        if policy.decision(for: estimatedCost) == .requireConfirmation {
            showCostConfirmation = true
        } else {
            submitGeneration()
        }
    }

    private func submitGeneration() {
        do {
            let referenceValues = try references.map(dataURL)
            let request = FalGenerationRequest(
                prompt: PromptComposer.compose(pack: selectedPack, userPrompt: prompt),
                modelID: selectedModelID,
                aspectRatio: aspectRatio,
                referenceImageURLs: referenceValues
            )
            lastRecordedPhase = nil
            lastSessionID = nil
            coordinator.start(request, apiKey: settings.generationKey)
        } catch {
            localError = error.localizedDescription
        }
    }

    private func dataURL(for url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let mediaType: String
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": mediaType = "image/jpeg"
        case "heic": mediaType = "image/heic"
        case "tif", "tiff": mediaType = "image/tiff"
        default: mediaType = "image/png"
        }
        return "data:\(mediaType);base64,\(data.base64EncodedString())"
    }

    private func persist(_ phase: GenerationPhase) {
        let signature = phase.description
        guard signature != "idle", signature != "generating", lastRecordedPhase != signature else { return }
        let status: GenerationSessionStatus
        let diagnostic: String?
        let generatedAsset: URL?
        switch phase {
        case let .succeeded(output):
            status = .generated
            diagnostic = nil
            generatedAsset = output.localURL
        case let .failed(message):
            status = .failed
            diagnostic = message
            generatedAsset = nil
        case .cancelled:
            status = .cancelled
            diagnostic = nil
            generatedAsset = nil
        case .idle, .generating:
            return
        }
        do {
            let record = try sessionStore.record(
                GenerationSessionDraft(
                    prompt: PromptComposer.compose(pack: selectedPack, userPrompt: prompt),
                    modelID: selectedModelID,
                    estimatedCost: estimatedCost,
                    referencePaths: references.map(\.path),
                    timestamp: Date(),
                    status: status,
                    safeDiagnostic: diagnostic
                ),
                generatedAsset: generatedAsset,
                secrets: [settings.generationKey, settings.accountAdministrationKey]
            )
            lastSessionID = record.id
            onSessionRecorded(record.id)
            lastRecordedPhase = signature
        } catch {
            localError = "Could not save generation history: \(error.localizedDescription)"
        }
    }

    private func save(_ source: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = source.lastPathComponent
        panel.directoryURL = settings.outputFolder
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            localError = "Could not save generated image: \(error.localizedDescription)"
        }
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private var showError: Binding<Bool> {
        Binding(get: { localError != nil }, set: { if !$0 { localError = nil } })
    }

    private func apply(_ session: GenerationSessionRecord) {
        prompt = session.prompt
        selectedModelID = session.modelID
        references = session.referencePaths
            .map(URL.init(fileURLWithPath:))
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .prefix(GenerationReferenceSelection.maximumCount)
            .map { $0 }
        coordinator.reset()
        pricing.reset()
    }

    private func warningDescription(_ warning: FalGenerationWarning) -> String {
        switch warning {
        case let .extraReferencesIgnored(modelID, accepted, provided):
            return "\(modelID) accepted \(accepted) of \(provided) reference images."
        }
    }
}
