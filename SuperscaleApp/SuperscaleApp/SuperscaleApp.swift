// ABOUTME: SwiftUI app entry point for Superscale GUI.
// ABOUTME: Configures the main window and menu commands.

import SwiftUI
import FalGenerationKit
import SuperscaleKit
import SuperscaleUXCore

/// Where the application keeps what it produces.
///
/// Lived in `GenerateView` until #87 deleted that surface. Application-level locations belong
/// with the application rather than with any one view.
enum V2AppPaths {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Superscale", isDirectory: true)
    }

    static var generated: URL { root.appendingPathComponent("Generated", isDirectory: true) }
    static var history: URL { root.appendingPathComponent("History", isDirectory: true) }
}

@main
struct SuperscaleApp: App {
    @StateObject private var viewModel = UpscaleViewModel()
    @StateObject private var settingsState: GenerationSettingsState
    @StateObject private var generationCoordinator: GenerationCoordinator
    @StateObject private var pricingCoordinator: GenerationPricingCoordinator
    @StateObject private var accountCoordinator: GenerationAccountCoordinator
    private let sessionStore: GenerationSessionStore

    init() {
        var startupError: String?

        var credentialStorage: any CredentialStorage = KeychainCredentialStorage()
        var coordinator = GenerationCoordinator(outputDirectory: V2AppPaths.generated)
        var pricing = GenerationPricingCoordinator()
        var account = GenerationAccountCoordinator()
        var store = GenerationSessionStore(rootDirectory: V2AppPaths.history)

#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let rootPath = environment["SUPERSCALE_UI_TEST_ROOT"],
           let generatedImagePath = environment["SUPERSCALE_UI_TEST_GENERATED_IMAGE"] {
            let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            let generatedImage = URL(fileURLWithPath: generatedImagePath)
            credentialStorage = UITestCredentialStorage()
            coordinator = GenerationCoordinator(
                service: UITestGenerationService(imageURL: generatedImage),
                outputStore: GeneratedImageStore(
                    directory: root.appendingPathComponent("Generated", isDirectory: true)
                )
            )
            pricing = GenerationPricingCoordinator(service: UITestPricingService())
            account = GenerationAccountCoordinator(service: UITestAccountService())
            store = GenerationSessionStore(
                rootDirectory: root.appendingPathComponent("History", isDirectory: true)
            )
            do {
                try resetUITestRoot(root)
                try seedUITestHistory(store: store, imageURL: generatedImage)
            } catch {
                startupError = "Could not prepare UI test fixtures: \(error.localizedDescription)"
            }
        }
#endif

        _settingsState = StateObject(
            wrappedValue: GenerationSettingsState(
                credentials: GenerationCredentialService(storage: credentialStorage),
                preferencesStore: GenerationPreferencesStore(),
                loadingCatalogue: { try PromptPackCatalogue.bundled() },
                startupError: startupError
            )
        )
        _generationCoordinator = StateObject(wrappedValue: coordinator)
        _pricingCoordinator = StateObject(wrappedValue: pricing)
        _accountCoordinator = StateObject(wrappedValue: account)
        sessionStore = store
    }

    var body: some Scene {
        WindowGroup {
            MainView(
                viewModel: viewModel,
                settingsState: settingsState,
                generationCoordinator: generationCoordinator,
                sessionStore: sessionStore
            )
                .frame(minWidth: 780, minHeight: 500)
        }
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Save As…") {
                    viewModel.saveAs(defaultDirectory: settingsState.outputFolder)
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(viewModel.result == nil)
            }
            // Prior sessions reach the user here rather than through a History surface. What a
            // user wants mid-session is the iteration in front of them; reaching older work is
            // what the File menu is for, and it is the native answer.
            CommandGroup(after: .newItem) {
                Menu("Open Recent") {
                    if recentSessions.isEmpty {
                        Text("No Recent Sessions")
                    } else {
                        ForEach(recentSessions) { session in
                            Button(recentTitle(session)) { open(session) }
                        }
                    }
                }
                .accessibilityIdentifier("openRecentMenu")
            }
        }

        // Settings is a scene, not a mode. Removing modes forces this, and it is the correct
        // destination anyway: Cmd+comma, its own window, and the workspace stays where it was.
        Settings {
            SettingsView(
                state: settingsState,
                pricing: pricingCoordinator,
                account: accountCoordinator
            )
            .frame(minWidth: 620, minHeight: 460)
        }
    }

    private var recentSessions: [GenerationSessionRecord] {
        let sessions = (try? sessionStore.sessions()) ?? []
        return WorkspaceModel.recentSessions(from: sessions)
    }

    private func recentTitle(_ session: GenerationSessionRecord) -> String {
        let prompt = session.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = prompt.split(separator: "\n").first.map(String.init) ?? prompt
        return firstLine.count > 60 ? String(firstLine.prefix(60)) + "…" : firstLine
    }

    private func open(_ session: GenerationSessionRecord) {
        do {
            // Resolved first so a session whose image has been deleted reports why. The source
            // itself comes from the record, which carries its own attribution.
            _ = try WorkspaceModel.workingImage(for: session)
            guard let source = session.upscaleSource else {
                throw WorkspaceError.sessionImageMissing(session.generatedAssetPath ?? "unknown path")
            }
            viewModel.upscale(source)
        } catch {
            // Session assets live in Application Support, which users clear out. A menu entry
            // whose image is gone reports why rather than doing nothing.
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

#if DEBUG
private final class UITestCredentialStorage: CredentialStorage {
    private var values: [CredentialSlot: String] = [
        .generation: "ui-test-generation-key",
        .accountAdministration: "ui-test-account-key",
    ]

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

@MainActor
private struct UITestGenerationService: GenerationServing {
    let imageURL: URL

    func generate(_ request: FalGenerationRequest, apiKey: String) async throws -> FalGeneratedImage {
        FalGeneratedImage(
            remoteURL: imageURL,
            data: try Data(contentsOf: imageURL),
            contentType: "image/png",
            warnings: []
        )
    }
}

private struct UITestPricingService: GenerationPricingServing {
    func pricing(modelID: String, apiKey: String) async throws -> FalPricing {
        FalPricing(
            unitPrice: FalUnitPrice(amount: 0.02, unit: "image", currency: "USD"),
            estimatedCost: 0.02,
            currency: "USD"
        )
    }
}

private struct UITestAccountService: GenerationAccountServing {
    func summary(accountKey: String) async throws -> FalAccountSummary {
        FalAccountSummary(
            username: "UI Test Account",
            balance: 12.50,
            currency: "USD",
            recentUsageCost: 0.04,
            billingEvents: [
                FalBillingEvent(
                    requestID: "ui-test-request",
                    endpointID: FalGenerationRequest.defaultModelID,
                    timestamp: "2026-07-15T00:00:00Z",
                    outputUnits: 1,
                    unitPrice: 0.02,
                    costEstimateNanoUSD: 20_000_000
                ),
            ]
        )
    }
}

private func seedUITestHistory(store: GenerationSessionStore, imageURL: URL) throws {
    guard try store.sessions().isEmpty else { return }
    _ = try store.record(
        GenerationSessionDraft(
            prompt: "History fixture",
            modelID: FalGenerationRequest.defaultModelID,
            estimatedCost: 0.01,
            referencePaths: [],
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            status: .generated,
            safeDiagnostic: nil
        ),
        generatedAsset: imageURL,
        secrets: []
    )
}

private func resetUITestRoot(_ root: URL) throws {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: root.path) {
        for item in try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            try fileManager.removeItem(at: item)
        }
    } else {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }
}
#endif
