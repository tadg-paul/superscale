// ABOUTME: Verifies independent credentials, persisted generation defaults, and settings state.
// ABOUTME: Exercises GUI settings behaviour without accessing Keychain or launching SwiftUI.

import FalGenerationKit
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
    //
    // 🚫 The cost-threshold half of this test is **superseded, not deleted**. #95 removes the
    // cost-confirmation control and the `costThreshold` preference behind it, following guide
    // section 6, so there is no longer a value to reject: three assertions that an invalid threshold
    // throws cannot be written against a field that does not exist. The output-folder half is
    // unaffected and stays. The test keeps its ID and its name records what it used to cover.
    func test_invalidOutputFoldersAndCostThresholdsAreRejected() {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let store = GenerationPreferencesStore(defaults: defaults, folderValidator: { _ in false })

        XCTAssertThrowsError(
            try store.save(
                GenerationPreferences(
                    outputFolder: URL(fileURLWithPath: "/invalid/output", isDirectory: true),
                    defaultModelID: "xai/grok-imagine-image",
                    defaultUpscaleModelID: "auto",
                    defaultPromptPackID: nil
                )
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("output folder"))
        }
    }

    /// A machine that ran an earlier build keeps a stored threshold until preferences are next
    /// written, and then does not.
    ///
    /// The alternative is leaving a value in the user's defaults that nothing reads, which a later
    /// reader then has to prove is dead.
    /// RT-103.5's companion condition, cited by #103 rather than duplicated there.
    ///
    /// This covers a defaults dictionary left over from an older build; RT-103.5 covers a fresh
    /// round trip. Between them they are AC103.2's two conditions.
    func test_theRetiredCostThresholdIsRemovedWhenPreferencesAreNextSaved() throws {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        defaults.set(0.08, forKey: "v2.generation.costThreshold")
        let store = GenerationPreferencesStore(defaults: defaults, folderValidator: { _ in true })

        try store.save(.defaults)

        XCTAssertNil(defaults.object(forKey: "v2.generation.costThreshold"))
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

    @MainActor
    func test_settingsStateSavesAndClearsCredentialsIndependently() throws {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let storage = InMemoryCredentialStorage()
        let credentials = GenerationCredentialService(storage: storage)
        let state = GenerationSettingsState(
            credentials: credentials,
            preferencesStore: GenerationPreferencesStore(defaults: defaults, folderValidator: { _ in true }),
            promptPackCatalogue: PromptPackCatalogue(packs: [])
        )

        state.generationKey = " generation-key "
        try state.saveGenerationCredential()
        XCTAssertEqual(try credentials.generationKey(), "generation-key")
        XCTAssertNil(try credentials.accountAdministrationKey())

        state.accountAdministrationKey = "admin-key"
        try state.saveAccountAdministrationCredential()
        XCTAssertEqual(try credentials.generationKey(), "generation-key")
        XCTAssertEqual(try credentials.accountAdministrationKey(), "admin-key")

        try state.clearGenerationCredential()
        XCTAssertEqual(state.generationKey, "")
        XCTAssertNil(try credentials.generationKey())
        XCTAssertEqual(try credentials.accountAdministrationKey(), "admin-key")

        try state.clearAccountAdministrationCredential()
        XCTAssertEqual(state.accountAdministrationKey, "")
        XCTAssertNil(try credentials.accountAdministrationKey())
    }

    // MARK: - What the badge is entitled to say

    @MainActor
    private func settingsState(
        verifier: FalCredentialVerifier,
        defaults: UserDefaults
    ) -> GenerationSettingsState {
        GenerationSettingsState(
            credentials: GenerationCredentialService(storage: InMemoryCredentialStorage()),
            preferencesStore: GenerationPreferencesStore(
                defaults: defaults, folderValidator: { _ in true }),
            promptPackCatalogue: PromptPackCatalogue(packs: []),
            credentialVerifier: verifier)
    }

    /// A verifier whose answer is decided by the stubbed status it is built with.
    @MainActor
    private func verifier(answering statusCode: Int) -> FalCredentialVerifier {
        FalCredentialVerifier(
            transport: StubVerificationTransport(statusCode: statusCode),
            baseURL: URL(string: "https://api.fal.ai") ?? URL(fileURLWithPath: "/"))
    }

    // RT-95.5
    //
    // The reported defect, at the level the badge reads from. A key that is merely present is not a
    // key that works, and the old badge could not tell the two apart.
    @MainActor
    func test_aStoredUncheckedKeyReadsAsStoredRatherThanWorking_RT095_5() throws {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let state = settingsState(verifier: verifier(answering: 200), defaults: defaults)

        XCTAssertEqual(state.generationKeyStatus, .absent, "before anything is entered")

        state.generationKey = "generation-key"
        try state.saveGenerationCredential()

        XCTAssertEqual(state.generationKeyStatus, .stored, "saved is not checked")
    }

    @MainActor
    func test_aCheckedKeyReadsAsWorkingAndARejectedOneCarriesTheReason() async throws {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        let accepted = settingsState(verifier: verifier(answering: 200), defaults: defaults)
        accepted.generationKey = "generation-key"
        try await accepted.saveAndVerifyGenerationKey()
        XCTAssertEqual(accepted.generationKeyStatus, .verified)

        let refused = settingsState(verifier: verifier(answering: 401), defaults: defaults)
        refused.generationKey = "generation-key"
        try await refused.saveAndVerifyGenerationKey()
        guard case let .rejected(reason) = refused.generationKeyStatus else {
            return XCTFail("\(refused.generationKeyStatus)")
        }
        XCTAssertFalse(reason.isEmpty)
    }

    /// An unreachable provider must not read as a rejection, or the user deletes a working key.
    @MainActor
    func test_anUnreachableProviderLeavesTheKeyStored() async throws {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let state = settingsState(verifier: verifier(answering: 503), defaults: defaults)

        state.generationKey = "generation-key"
        try await state.saveAndVerifyGenerationKey()

        XCTAssertEqual(state.generationKeyStatus, .stored)
    }

    // RT-95.17
    //
    // A verdict belongs to the key it was given. Without that, a tick earned by one key sits beside
    // another — the same lie this replaced, arriving only after the feature apparently worked.
    @MainActor
    func test_editingAVerifiedKeyReturnsItToUnverified_RT095_17() async throws {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let state = settingsState(verifier: verifier(answering: 200), defaults: defaults)

        state.generationKey = "generation-key"
        try await state.saveAndVerifyGenerationKey()
        XCTAssertEqual(state.generationKeyStatus, .verified)

        state.generationKey = "generation-key-with-a-typo"

        XCTAssertEqual(state.generationKeyStatus, .stored, "a different key, unchecked")

        // Typing the checked key back restores the verdict it earned: the verdict is about the key,
        // not about whether the field has been touched.
        state.generationKey = "generation-key"
        XCTAssertEqual(state.generationKeyStatus, .verified)
    }

    /// Clearing the key clears its verdict, rather than leaving a tick against nothing.
    @MainActor
    func test_clearingAVerifiedKeyLeavesNoVerdictBehind() async throws {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let state = settingsState(verifier: verifier(answering: 200), defaults: defaults)

        state.generationKey = "generation-key"
        try await state.saveAndVerifyGenerationKey()
        try state.clearGenerationCredential()

        XCTAssertEqual(state.generationKeyStatus, .absent)
    }

    // RT-95.14
    //
    // The asymmetry is deliberate: verifying the account key would mean calling an account or
    // billing endpoint, which is the surface this MVP has paused. Stored or absent is all that can
    // honestly be said about it, and this asserts the state offers nothing more.
    @MainActor
    func test_theAccountKeyCarriesNoVerificationState_RT095_14() async throws {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let state = settingsState(verifier: verifier(answering: 200), defaults: defaults)

        XCTAssertFalse(state.isAccountAdministrationConfigured)

        state.accountAdministrationKey = "admin-key"
        try state.saveAccountAdministrationCredential()
        XCTAssertTrue(state.isAccountAdministrationConfigured)

        // Verifying the generation key says nothing about the account key: the account row has no
        // verified state to reach, whatever the provider says about the other credential.
        state.generationKey = "generation-key"
        try await state.saveAndVerifyGenerationKey()
        XCTAssertEqual(state.generationKeyStatus, .verified)
        XCTAssertTrue(state.isAccountAdministrationConfigured, "still only stored or absent")
    }

    // RT-109.4
    //
    // A store that throws leaves the row saying "not configured".
    //
    // The badge is recorded only after the write returns, so the failing case is the one that proves
    // the ordering: a row that flipped to "stored" and *then* raised an error would have told the
    // user their key was safe before saying it was not.
    //
    // A unit test rather than a GUI one because there is no honest way to make the Keychain refuse
    // from XCUITest. `SUPERSCALE_UI_TEST_FAIL` induces `upscale` and `provider` failures only, and
    // adding a `keychain` mode would have the shipping app carry a failure injector to reach one
    // assertion that is reachable in-process.
    @MainActor
    func test_aStoreThatThrowsLeavesTheAccountRowSayingNotConfigured_RT109_4() {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let state = GenerationSettingsState(
            credentials: GenerationCredentialService(storage: RefusingCredentialStorage()),
            preferencesStore: GenerationPreferencesStore(
                defaults: defaults, folderValidator: { _ in true }),
            promptPackCatalogue: PromptPackCatalogue(packs: []))

        state.accountAdministrationKey = "admin-key"
        XCTAssertThrowsError(try state.saveAccountAdministrationCredential())

        XCTAssertEqual(state.accountAdministrationStatus, .absent,
                       "the row claimed a key the Keychain refused to hold")
        XCTAssertFalse(state.isAccountAdministrationConfigured)
    }

    // RT-109.5
    //
    // A key stored in an earlier session reads as stored on launch, with nobody pressing anything.
    //
    // This is the assertion that stops the cheapest wrong fix. Flipping a flag in the save button's
    // action satisfies "the badge changes on press" and fails here, because a flag resets on launch
    // and a Keychain read does not.
    @MainActor
    func test_anAccountKeyAlreadyStoredReadsAsStoredOnLaunch_RT109_5() throws {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let storage = InMemoryCredentialStorage()
        try storage.setValue("admin-key", for: .accountAdministration)

        let state = GenerationSettingsState(
            credentials: GenerationCredentialService(storage: storage),
            preferencesStore: GenerationPreferencesStore(
                defaults: defaults, folderValidator: { _ in true }),
            promptPackCatalogue: PromptPackCatalogue(packs: []))

        XCTAssertEqual(state.accountAdministrationStatus, .stored)
        XCTAssertTrue(state.isAccountAdministrationConfigured)
    }

    // RT-109.7
    //
    // Whitespace is not a credential. Saving a field holding only spaces removes the slot, and the
    // row goes back to "not configured" rather than reporting a key made of nothing.
    @MainActor
    func test_savingWhitespaceLeavesTheAccountRowNotConfigured_RT109_7() throws {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let storage = InMemoryCredentialStorage()
        let state = GenerationSettingsState(
            credentials: GenerationCredentialService(storage: storage),
            preferencesStore: GenerationPreferencesStore(
                defaults: defaults, folderValidator: { _ in true }),
            promptPackCatalogue: PromptPackCatalogue(packs: []))

        state.accountAdministrationKey = "admin-key"
        try state.saveAccountAdministrationCredential()
        XCTAssertEqual(state.accountAdministrationStatus, .stored)

        state.accountAdministrationKey = "   "
        try state.saveAccountAdministrationCredential()

        XCTAssertEqual(state.accountAdministrationStatus, .absent)
        XCTAssertFalse(state.isAccountAdministrationConfigured)
        XCTAssertNil(try storage.value(for: .accountAdministration),
                     "whitespace saved over a real key left it in the Keychain")
    }

    // RT-109.3, at the level the badge reads from.
    //
    // The GUI test of the same number presses the controls; this one fixes the rule, which is that
    // the row reports the Keychain and not the text box. Editing a saved key returns it to absent
    // because that text is not stored, and no press has stored it.
    @MainActor
    func test_editingASavedAccountKeyReturnsTheRowToNotConfigured_RT109_3() throws {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let state = GenerationSettingsState(
            credentials: GenerationCredentialService(storage: InMemoryCredentialStorage()),
            preferencesStore: GenerationPreferencesStore(
                defaults: defaults, folderValidator: { _ in true }),
            promptPackCatalogue: PromptPackCatalogue(packs: []))

        state.accountAdministrationKey = "admin-key"
        XCTAssertEqual(state.accountAdministrationStatus, .absent, "typed is not stored")

        try state.saveAccountAdministrationCredential()
        XCTAssertEqual(state.accountAdministrationStatus, .stored)

        state.accountAdministrationKey = "admin-key-edited"
        XCTAssertEqual(state.accountAdministrationStatus, .absent)
        XCTAssertTrue(state.isAccountAdministrationConfigured,
                      "a key is still held, so it can still be removed")

        try state.saveAccountAdministrationCredential()
        XCTAssertEqual(state.accountAdministrationStatus, .stored)
    }

    /// The check is visible while it is in flight, and not before or after.
    ///
    /// Pressing save previously produced no visible change at all, which reads as a broken button.
    @MainActor
    func test_theCheckIsVisibleWhileItIsInFlight() async throws {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let gate = VerificationGate()
        let state = settingsState(
            verifier: FalCredentialVerifier(
                transport: GatedVerificationTransport(gate: gate),
                baseURL: URL(string: "https://api.fal.ai") ?? URL(fileURLWithPath: "/")),
            defaults: defaults)

        state.generationKey = "generation-key"
        XCTAssertFalse(state.isVerifyingGenerationKey, "before the press")

        let check = Task { try await state.saveAndVerifyGenerationKey() }
        await gate.waitUntilAsked()
        XCTAssertTrue(state.isVerifyingGenerationKey, "while the provider is being asked")

        await gate.answer()
        try await check.value
        XCTAssertFalse(state.isVerifyingGenerationKey, "once the answer is in")
    }

    private let defaultsSuiteName = "GenerationSettingsTests"

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        return defaults
    }
}

/// Answers a verification request with a fixed status and nothing else.
private struct StubVerificationTransport: FalHTTPTransport {
    let statusCode: Int

    func send(_ request: URLRequest) async throws -> FalHTTPResponse {
        FalHTTPResponse(statusCode: statusCode, headers: [:], body: Data("{}".utf8))
    }
}

/// Holds a verification request open until the test lets it finish.
///
/// The alternative is sleeping for a while and hoping, which is how a test that passes on this
/// machine fails on a slower one.
private actor VerificationGate {
    private var asked: CheckedContinuation<Void, Never>?
    private var hasBeenAsked = false
    private var released: CheckedContinuation<Void, Never>?
    private var hasBeenReleased = false

    func recordAsked() {
        hasBeenAsked = true
        asked?.resume()
        asked = nil
    }

    func waitUntilAsked() async {
        guard !hasBeenAsked else { return }
        await withCheckedContinuation { asked = $0 }
    }

    func answer() {
        hasBeenReleased = true
        released?.resume()
        released = nil
    }

    func waitForAnswer() async {
        guard !hasBeenReleased else { return }
        await withCheckedContinuation { released = $0 }
    }
}

private struct GatedVerificationTransport: FalHTTPTransport {
    let gate: VerificationGate

    func send(_ request: URLRequest) async throws -> FalHTTPResponse {
        await gate.recordAsked()
        await gate.waitForAnswer()
        return FalHTTPResponse(statusCode: 200, headers: [:], body: Data("{}".utf8))
    }
}

/// Storage that will not write, so a save can fail the way a locked Keychain fails.
private final class RefusingCredentialStorage: CredentialStorage {
    struct Refusal: Error {}

    private var values: [CredentialSlot: String] = [:]

    func value(for slot: CredentialSlot) throws -> String? {
        values[slot]
    }

    func setValue(_ value: String, for slot: CredentialSlot) throws {
        throw Refusal()
    }

    func removeValue(for slot: CredentialSlot) throws {
        throw Refusal()
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
