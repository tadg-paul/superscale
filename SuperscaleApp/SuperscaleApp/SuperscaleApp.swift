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
    @StateObject private var viewModel: UpscaleViewModel
    @StateObject private var settingsState: GenerationSettingsState
    @StateObject private var generationCoordinator: GenerationCoordinator
    private let sessionStore: GenerationSessionStore

    init() {
        var startupError: String?

        var credentialStorage: any CredentialStorage = KeychainCredentialStorage()
        var coordinator = GenerationCoordinator(outputDirectory: V2AppPaths.generated)
        var store = GenerationSessionStore(rootDirectory: V2AppPaths.history)
        var credentialVerifier = FalCredentialVerifier()
        var upscaleCoordinator = GUIUpscaleCoordinator()

#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        // Makes both subsystems fail on demand, so a GUI test can see where each failure is
        // presented. Without it neither can be made to fail from outside: the generation service is
        // stubbed to succeed and the upscale runs the real pipeline on a real fixture.
        if environment["SUPERSCALE_UI_TEST_FAIL"] == "1" {
            upscaleCoordinator = GUIUpscaleCoordinator(processor: UITestFailingUpscaleProcessor())
        }
        if let rootPath = environment["SUPERSCALE_UI_TEST_ROOT"],
           let generatedImagePath = environment["SUPERSCALE_UI_TEST_GENERATED_IMAGE"] {
            let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            let generatedImage = URL(fileURLWithPath: generatedImagePath)
            credentialStorage = UITestCredentialStorage()
            // The generation service is already stubbed here; the verifier is stubbed for the same
            // reason. A GUI test pressing save would otherwise reach `api.fal.ai` for real, which
            // makes the suite depend on a network and on somebody else's uptime.
            credentialVerifier = FalCredentialVerifier(transport: UITestVerificationTransport())
            coordinator = GenerationCoordinator(
                service: UITestGenerationService(
                    imageURL: generatedImage,
                    fails: environment["SUPERSCALE_UI_TEST_FAIL"] == "1"),
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
                loadingCatalogue: { try PromptPackCatalogue.bundled() },
                credentialVerifier: credentialVerifier,
                startupError: startupError
            )
        )
        _viewModel = StateObject(
            wrappedValue: UpscaleViewModel(upscaleCoordinator: upscaleCoordinator))
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
            SettingsView(state: settingsState)
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
            viewModel.report(error)
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

/// Answers credential checks without a network.
///
/// The seeded key is accepted; anything else is refused, so a GUI test can reach either badge and
/// neither answer costs anything or depends on somebody else's uptime.
private struct UITestVerificationTransport: FalHTTPTransport {
    func send(_ request: URLRequest) async throws -> FalHTTPResponse {
        let offered = request.value(forHTTPHeaderField: "Authorization")
        let accepted = offered == "Key ui-test-generation-key"
        return FalHTTPResponse(
            statusCode: accepted ? 200 : 401, headers: [:], body: Data("{}".utf8))
    }
}

@MainActor
private struct UITestGenerationService: GenerationServing {
    let imageURL: URL
    var fails = false

    func generate(_ request: FalGenerationRequest, apiKey: String) async throws -> FalGeneratedImage {
        if fails {
            // A classified failure carrying the provider's own words, which is what a real one is.
            // Presented the same way as an upscale failure is the whole point of AC98.5.
            throw FalFailure(
                kind: .provider, diagnostic: "The provider rejected the request. (request ui-test)")
        }
        return FalGeneratedImage(
            remoteURL: imageURL,
            data: try Data(contentsOf: imageURL),
            contentType: "image/png",
            warnings: []
        )
    }
}

/// Fails every upscale, so a GUI test can see where an upscale failure is presented.
///
/// The upscale otherwise runs the real pipeline on a real fixture and succeeds, so there is no way
/// to make it fail from outside the process.
private struct UITestFailingUpscaleProcessor: GUIUpscaleProcessing {
    func process(
        inputURL: URL,
        options: GUIUpscaleOptions,
        onProgress: @escaping @Sendable (PipelineProgress) -> Void
    ) async throws -> GUIUpscaleProcessedImage {
        throw StageFailure.processingFailed(
            stage: "upscale", reason: "The upscale could not be completed.")
    }
}

// 🚫 `UITestPricingService` and `UITestAccountService` are removed by #89. They stubbed coordinators
// this issue stopped constructing, so nothing referenced them. AC89.7's third condition is that no
// pricing or account client is *constructed*, and leaving stubs behind for clients nobody builds is
// how a later reader concludes the feature is still wired. The real clients remain in
// `FalGenerationKit` for the version that needs them; what goes is the application's plumbing.

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
