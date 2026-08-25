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
    @Published public var defaultModelID: String
    @Published public var defaultUpscaleModelID: String
    @Published public var defaultPromptPackID: String?
    @Published public private(set) var lastError: String?

    public let promptPackCatalogue: PromptPackCatalogue

    private let credentials: GenerationCredentialService
    private let preferencesStore: GenerationPreferencesStore
    private let credentialVerifier: FalCredentialVerifier

    public init(
        credentials: GenerationCredentialService,
        preferencesStore: GenerationPreferencesStore,
        promptPackCatalogue: PromptPackCatalogue,
        credentialVerifier: FalCredentialVerifier = FalCredentialVerifier(),
        startupError: String? = nil
    ) {
        self.credentials = credentials
        self.preferencesStore = preferencesStore
        self.promptPackCatalogue = promptPackCatalogue
        self.credentialVerifier = credentialVerifier

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
        credentialVerifier: FalCredentialVerifier = FalCredentialVerifier(),
        startupError: String? = nil
    ) {
        do {
            self.init(
                credentials: credentials,
                preferencesStore: preferencesStore,
                promptPackCatalogue: try load(),
                credentialVerifier: credentialVerifier,
                startupError: startupError
            )
        } catch {
            self.init(
                credentials: credentials,
                preferencesStore: preferencesStore,
                promptPackCatalogue: PromptPackCatalogue(packs: []),
                credentialVerifier: credentialVerifier,
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

    /// The exact key the verdict above was given.
    ///
    /// A verdict belongs to the key it was asked about, not to the field it was typed into. Holding
    /// the key alongside the answer is what stops a tick earned by one key sitting beside another —
    /// the same lie this replaced, arriving only after the feature apparently worked. Derived rather
    /// than reset on edit, so there is no ordering between a keystroke and a reply to get wrong.
    @Published public private(set) var verifiedKey: String?

    public var generationKeyStatus: CredentialStatus {
        let trimmed = generationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .absent }
        guard verifiedKey == trimmed else { return .stored }
        return generationKeyVerification
    }

    /// Records what the provider said about a particular key.
    public func recordGenerationKeyVerification(_ status: CredentialStatus, for key: String) {
        generationKeyVerification = status
        verifiedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether a check is in flight.
    ///
    /// Pressing save previously produced no visible change at all: the key went to the Keychain and
    /// the window looked exactly as it had. A check that reaches the network takes long enough for
    /// that silence to read as a broken button.
    @Published public private(set) var isVerifyingGenerationKey = false

    /// Stores the generation key, then asks the provider whether it works.
    ///
    /// The two are one act from the user's side — they pressed save — but two outcomes: the store
    /// can fail locally, and the provider can decline. A store that throws is surfaced as an error
    /// and no check is made, because there is nothing yet to check.
    ///
    /// An unreachable provider leaves the key `stored`, never `rejected`. `FalCredentialVerdict`
    /// keeps that distinction for the same reason: "we could not ask" and "the answer was no" differ
    /// by whether the user waits or deletes a working credential.
    public func saveAndVerifyGenerationKey() async throws {
        try saveGenerationCredential()
        let key = generationKey

        isVerifyingGenerationKey = true
        defer { isVerifyingGenerationKey = false }

        switch await credentialVerifier.verifyGenerationKey(key) {
        case .accepted:
            recordGenerationKeyVerification(.verified, for: key)
        case let .rejected(reason):
            recordGenerationKeyVerification(.rejected(reason: reason), for: key)
        case .unreachable:
            // Not an answer about the key, so nothing is recorded against it and the badge falls
            // back to `stored`.
            recordGenerationKeyVerification(.stored, for: key)
        }
    }

    public var isAccountAdministrationConfigured: Bool {
        !accountAdministrationKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var isSaveEnabled: Bool {
        !defaultModelID.isEmpty && !defaultUpscaleModelID.isEmpty
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
