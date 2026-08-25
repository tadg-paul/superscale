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

    /// Builds the state around a catalogue that may not load.
    ///
    /// A corpus that will not load leaves the application with no filters and the reason to hand,
    /// and leaves everything local alone — section 2.8 of the implementation guide rules that when
    /// filters are unavailable, local upscaling works fully, and a corpus that will not load is
    /// that condition reached by another route. The handling lives here rather than in the app's
    /// entry point so that it is the same code the tests drive.
    public convenience init(
        credentials: GenerationCredentialService,
        preferencesStore: GenerationPreferencesStore,
        loadingCatalogue load: () throws -> PromptPackCatalogue,
        startupError: String? = nil
    ) {
        do {
            self.init(
                credentials: credentials,
                preferencesStore: preferencesStore,
                promptPackCatalogue: try load(),
                startupError: startupError
            )
        } catch {
            self.init(
                credentials: credentials,
                preferencesStore: preferencesStore,
                promptPackCatalogue: PromptPackCatalogue(packs: []),
                startupError: startupError ?? error.localizedDescription
            )
        }
    }

    public var isGenerationConfigured: Bool {
        !generationKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What is known about the generation key, as opposed to whether one is stored.
    ///
    /// The badge in Settings read from `isGenerationConfigured`, so a typo saved and showed a green
    /// tick. Verification is a separate act with a separate answer, and this holds it.
    @Published public private(set) var generationKeyVerification: CredentialStatus = .stored

    public var generationKeyStatus: CredentialStatus {
        isGenerationConfigured ? generationKeyVerification : .absent
    }

    /// Records what the provider said about the key currently held.
    public func recordGenerationKeyVerification(_ status: CredentialStatus) {
        generationKeyVerification = status
    }

    /// A key that has been edited is no longer the key that was checked.
    ///
    /// Without this, a tick earned by one key sits beside another — the same lie this replaced,
    /// arriving only after the feature apparently worked.
    public func generationKeyEdited() {
        generationKeyVerification = .stored
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
            try saveGenerationCredential()
            try saveAccountAdministrationCredential()
            try savePreferences()
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

    public func saveGenerationCredential() throws {
        try storeCredential(generationKey, slot: .generation)
        generationKey = generationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        lastError = nil
    }

    public func saveAccountAdministrationCredential() throws {
        try storeCredential(accountAdministrationKey, slot: .accountAdministration)
        accountAdministrationKey = accountAdministrationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        lastError = nil
    }

    public func clearGenerationCredential() throws {
        try credentials.removeGenerationKey()
        generationKey = ""
        lastError = nil
    }

    public func clearAccountAdministrationCredential() throws {
        try credentials.removeAccountAdministrationKey()
        accountAdministrationKey = ""
        lastError = nil
    }

    public func savePreferences() throws {
        try preferencesStore.save(currentPreferences)
        lastError = nil
    }

    private var currentPreferences: GenerationPreferences {
        GenerationPreferences(
            outputFolder: outputFolder,
            costThreshold: costThreshold,
            defaultModelID: defaultModelID,
            defaultUpscaleModelID: defaultUpscaleModelID,
            defaultPromptPackID: defaultPromptPackID
        )
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
