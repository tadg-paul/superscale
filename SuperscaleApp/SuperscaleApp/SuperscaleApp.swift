// ABOUTME: SwiftUI app entry point for Superscale GUI.
// ABOUTME: Configures the main window and menu commands.

import SwiftUI
import FalGenerationKit
import SuperscaleKit
import SuperscaleUXCore

@main
struct SuperscaleApp: App {
    @StateObject private var viewModel = UpscaleViewModel()
    @StateObject private var settingsState: GenerationSettingsState
    @StateObject private var generationCoordinator: GenerationCoordinator
    private let sessionStore: GenerationSessionStore

    init() {
        let catalogue: PromptPackCatalogue
        var startupError: String?
        do {
            catalogue = try PromptPackCatalogue.bundled()
            startupError = nil
        } catch {
            catalogue = PromptPackCatalogue(packs: [])
            startupError = error.localizedDescription
        }

        var credentialStorage: any CredentialStorage = KeychainCredentialStorage()
        var coordinator = GenerationCoordinator(outputDirectory: V2AppPaths.generated)
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
                promptPackCatalogue: catalogue,
                startupError: startupError
            )
        )
        _generationCoordinator = StateObject(wrappedValue: coordinator)
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
                    viewModel.saveAs()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(viewModel.result == nil)
            }
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
