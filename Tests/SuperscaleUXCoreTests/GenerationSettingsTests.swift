// ABOUTME: Verifies independent credentials, persisted generation defaults, and settings state.
// ABOUTME: Exercises GUI settings behaviour without accessing Keychain or launching SwiftUI.

import Foundation
import XCTest
@testable import SuperscaleUXCore

final class GenerationSettingsTests: XCTestCase {
    // RT-73.1
    func test_generationCredentialLifecycle() throws {
        let storage = InMemoryCredentialStorage()
        let credentials = GenerationCredentialService(storage: storage)

        XCTAssertNil(try credentials.generationKey())
        try credentials.setGenerationKey("generation-key")
        XCTAssertEqual(try credentials.generationKey(), "generation-key")
        try credentials.setGenerationKey("replacement-generation-key")
        XCTAssertEqual(try credentials.generationKey(), "replacement-generation-key")
        try credentials.removeGenerationKey()
        XCTAssertNil(try credentials.generationKey())
    }

    // RT-73.2
    func test_accountAdministrationCredentialHasAnIndependentLifecycle() throws {
        let storage = InMemoryCredentialStorage()
        let credentials = GenerationCredentialService(storage: storage)

        try credentials.setGenerationKey("generation-key")
        try credentials.setAccountAdministrationKey("admin-key")
        XCTAssertEqual(try credentials.generationKey(), "generation-key")
        XCTAssertEqual(try credentials.accountAdministrationKey(), "admin-key")
        try credentials.setAccountAdministrationKey("replacement-admin-key")
        XCTAssertEqual(try credentials.accountAdministrationKey(), "replacement-admin-key")

        try credentials.removeGenerationKey()
        XCTAssertNil(try credentials.generationKey())
        XCTAssertEqual(try credentials.accountAdministrationKey(), "replacement-admin-key")

        try credentials.removeAccountAdministrationKey()
        XCTAssertNil(try credentials.accountAdministrationKey())
    }

    // RT-73.3
    func test_nonSecretDefaultsPersistAcrossStoreReloads() throws {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let expected = GenerationPreferences(
            outputFolder: URL(fileURLWithPath: "/valid/output", isDirectory: true),
            costThreshold: 0.08,
            defaultModelID: "xai/grok-imagine-image",
            defaultUpscaleModelID: "realesrgan-x4plus",
            defaultPromptPackID: "image-design-architectural-drawing"
        )
        let firstStore = GenerationPreferencesStore(defaults: defaults, folderValidator: { _ in true })

        XCTAssertEqual(firstStore.load(), .defaults)
        try firstStore.save(expected)

        let reloadedStore = GenerationPreferencesStore(defaults: defaults, folderValidator: { _ in true })
        XCTAssertEqual(reloadedStore.load(), expected)
    }

    // RT-73.4
    func test_invalidOutputFoldersAndCostThresholdsAreRejected() {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let store = GenerationPreferencesStore(defaults: defaults, folderValidator: { _ in false })

        XCTAssertThrowsError(
            try store.save(
                GenerationPreferences(
                    outputFolder: URL(fileURLWithPath: "/invalid/output", isDirectory: true),
                    costThreshold: 0.05,
                    defaultModelID: "xai/grok-imagine-image",
                    defaultUpscaleModelID: "auto",
                    defaultPromptPackID: nil
                )
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("output folder"))
        }

        for invalidThreshold in [-0.01, .infinity, .nan] {
            XCTAssertThrowsError(
                try store.save(
                    GenerationPreferences(
                        outputFolder: nil,
                        costThreshold: invalidThreshold,
                        defaultModelID: "xai/grok-imagine-image",
                        defaultUpscaleModelID: "auto",
                        defaultPromptPackID: nil
                    )
                )
            ) { error in
                XCTAssertTrue(error.localizedDescription.contains("cost threshold"))
            }
        }
    }

    // RT-73.8
    @MainActor
    func test_settingsStateEnablesGenerationAndAccountFeaturesFromSeparateKeys() throws {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let state = GenerationSettingsState(
            credentials: GenerationCredentialService(storage: InMemoryCredentialStorage()),
            preferencesStore: GenerationPreferencesStore(defaults: defaults, folderValidator: { _ in true }),
            promptPackCatalogue: PromptPackCatalogue(packs: [])
        )

        XCTAssertFalse(state.isGenerationConfigured)
        XCTAssertFalse(state.isAccountAdministrationConfigured)
        XCTAssertTrue(state.isSaveEnabled)

        state.generationKey = "generation-key"
        try state.save()
        XCTAssertTrue(state.isGenerationConfigured)
        XCTAssertFalse(state.isAccountAdministrationConfigured)

        state.accountAdministrationKey = "admin-key"
        try state.save()
        XCTAssertTrue(state.isGenerationConfigured)
        XCTAssertTrue(state.isAccountAdministrationConfigured)

        state.generationKey = ""
        try state.save()
        XCTAssertFalse(state.isGenerationConfigured)
        XCTAssertTrue(state.isAccountAdministrationConfigured)
    }

    private let defaultsSuiteName = "GenerationSettingsTests"

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        return defaults
    }
}

private final class InMemoryCredentialStorage: CredentialStorage {
    private var values: [CredentialSlot: String] = [:]

    func value(for slot: CredentialSlot) throws -> String? {
        values[slot]
    }

    func setValue(_ value: String, for slot: CredentialSlot) throws {
        values[slot] = value
    }

    func removeValue(for slot: CredentialSlot) throws {
        values.removeValue(forKey: slot)
    }
}
