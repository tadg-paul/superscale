// ABOUTME: Owns editable GUI settings state independently from SwiftUI presentation.
// ABOUTME: Saves separate credentials and validated non-secret generation defaults.

import Combine
import FalGenerationKit
import Foundation

@MainActor
public final class GenerationSettingsState: ObservableObject {
    @Published public var generationKey: String
    @Published public var accountAdministrationKey: String
    @Published public var outputFolder: URL?
    @Published public var costThreshold: Double
    @Published public var defaultModelID: String
    @Published public var defaultUpscaleModelID: String
    @Published public var defaultPromptPackID: String?
    @Published public private(set) var lastError: String?

    public let promptPackCatalogue: PromptPackCatalogue

    private let credentials: GenerationCredentialService
    private let preferencesStore: GenerationPreferencesStore

    public init(
        credentials: GenerationCredentialService,
        preferencesStore: GenerationPreferencesStore,
        promptPackCatalogue: PromptPackCatalogue,
        startupError: String? = nil
    ) {
        self.credentials = credentials
        self.preferencesStore = preferencesStore
        self.promptPackCatalogue = promptPackCatalogue

        let preferences = preferencesStore.load()
        var credentialError: String?
        do {
            generationKey = try credentials.generationKey() ?? ""
            accountAdministrationKey = try credentials.accountAdministrationKey() ?? ""
        } catch {
            generationKey = ""
            accountAdministrationKey = ""
            credentialError = error.localizedDescription
        }
        outputFolder = preferences.outputFolder
        costThreshold = preferences.costThreshold
        defaultModelID = preferences.defaultModelID
        defaultUpscaleModelID = preferences.defaultUpscaleModelID
        defaultPromptPackID = preferences.defaultPromptPackID
        lastError = startupError ?? credentialError
    }

    public var isGenerationConfigured: Bool {
        !generationKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var isAccountAdministrationConfigured: Bool {
        !accountAdministrationKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var isSaveEnabled: Bool {
        costThreshold.isFinite
            && costThreshold >= 0
            && !defaultModelID.isEmpty
            && !defaultUpscaleModelID.isEmpty
    }

    public func save() throws {
        do {
            try storeCredential(generationKey, slot: .generation)
            try storeCredential(accountAdministrationKey, slot: .accountAdministration)
            try preferencesStore.save(
                GenerationPreferences(
                    outputFolder: outputFolder,
                    costThreshold: costThreshold,
                    defaultModelID: defaultModelID,
                    defaultUpscaleModelID: defaultUpscaleModelID,
                    defaultPromptPackID: defaultPromptPackID
                )
            )
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    public func saveReportingErrors() {
        do {
            try save()
        } catch {
            if lastError == nil {
                lastError = error.localizedDescription
            }
        }
    }

    public func clearError() {
        lastError = nil
    }

    private func storeCredential(_ value: String, slot: CredentialSlot) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (slot, trimmed.isEmpty) {
        case (.generation, true):
            try credentials.removeGenerationKey()
        case (.generation, false):
            try credentials.setGenerationKey(trimmed)
        case (.accountAdministration, true):
            try credentials.removeAccountAdministrationKey()
        case (.accountAdministration, false):
            try credentials.setAccountAdministrationKey(trimmed)
        }
    }
}
