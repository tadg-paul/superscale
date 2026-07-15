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
    let sessionStore: GenerationSessionStore
    let reopenedSession: GenerationSessionRecord?
    let onSendToUpscale: (URL, UUID?) -> Void

    @State private var prompt = ""
    @State private var selectedPackID: String?
    @State private var selectedModelID = FalGenerationRequest.defaultModelID
    @State private var aspectRatio = "1:1"
    @State private var references: [URL] = []
    @State private var pricingState: PricingState = .idle
    @State private var showCostConfirmation = false
    @State private var localError: String?
    @State private var lastRecordedPhase: String?
    @State private var lastSessionID: UUID?

    private let aspects = ["1:1", "16:9", "9:16", "4:3", "3:4"]

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            output
        }
        .onAppear {
            selectedPackID = reopenedSession == nil ? settings.defaultPromptPackID : selectedPackID
            selectedModelID = reopenedSession?.modelID ?? settings.defaultModelID
            if let reopenedSession { prompt = reopenedSession.prompt }
        }
        .onChange(of: reopenedSession?.id) { _, _ in
            guard let reopenedSession else { return }
            prompt = reopenedSession.prompt
            selectedModelID = reopenedSession.modelID
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

    private var controls: some View {
        HStack(alignment: .top, spacing: 20) {
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
            }
            .formStyle(.grouped)
            .frame(width: 260)

            VStack(alignment: .leading, spacing: 12) {
                Text("Prompt").font(.headline)
                TextEditor(text: $prompt)
                    .font(.body)
                    .frame(minHeight: 90, maxHeight: 130)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.35)))
                    .accessibilityIdentifier("generationPromptField")

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
                        .accessibilityIdentifier("estimateCostButton")
                }

                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel") { coordinator.cancel() }
                        .disabled(coordinator.phase != .generating)
                        .accessibilityIdentifier("cancelGenerationButton")
                    Button("Generate") { beginGeneration() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canGenerate)
                        .accessibilityIdentifier("generateButton")
                }
            }
            .padding(.vertical, 16)
            .padding(.trailing, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var output: some View {
        switch coordinator.phase {
        case .idle:
            ContentUnavailableView("No generated image", systemImage: "sparkles")
        case .generating:
            ProgressView("Generating with FAL...")
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
        VStack(spacing: 12) {
            if let image = NSImage(contentsOf: generated.localURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
            }
            HStack {
                Button("Send to Upscale") { onSendToUpscale(generated.localURL, lastSessionID) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("generatedSendToUpscale")
                Button("Save As...") { save(generated.localURL) }
                    .accessibilityIdentifier("generatedSaveAs")
                Button("Retry") { beginGeneration() }
                    .accessibilityIdentifier("generatedRetry")
                Button("Reveal") { reveal(generated.localURL) }
                    .accessibilityIdentifier("generatedReveal")
            }
            .padding(.bottom, 14)
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
        switch pricingState {
        case .idle:
            Text("Cost not estimated")
        case .loading:
            ProgressView().controlSize(.small)
            Text("Checking cost...")
        case let .available(pricing):
            Text("Est. \(pricing.estimatedCost, format: .currency(code: pricing.currency))")
        case let .unavailable(message):
            Text("Cost unavailable: \(message)")
                .foregroundStyle(.secondary)
                .lineLimit(1)
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

    private var estimatedCost: Double? {
        guard case let .available(pricing) = pricingState else { return nil }
        return pricing.estimatedCost
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
        pricingState = .loading
        let key = settings.generationKey
        let modelID = selectedModelID
        Task {
            do {
                pricingState = .available(try await FalPricingClient().pricing(modelID: modelID, apiKey: key))
            } catch {
                pricingState = .unavailable(error.localizedDescription)
            }
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
            lastRecordedPhase = signature
        } catch {
            localError = "Could not save generation history: \(error.localizedDescription)"
        }
    }

    private func save(_ source: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = source.lastPathComponent
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
}

private enum PricingState: Equatable {
    case idle
    case loading
    case available(FalPricing)
    case unavailable(String)
}
