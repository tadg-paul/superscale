// ABOUTME: SwiftUI app entry point for Superscale GUI.
// ABOUTME: Configures the main window and menu commands.

import SwiftUI
import FalGenerationKit
import SuperscaleKit
import SuperscaleUXCore

// 🚫 `V2AppPaths` is removed by #116. It computed the application's storage locations, and it was
// the *second* place they were computed: `MainView` read it from a property initialiser while the
// entry point read it here, so a launch given a test root redirected some of the application's
// writes and not others. `StorageRoots` in `SuperscaleUXCore` is the one resolution now, which is
// also where `ARCHITECTURE.md` §"Target Module Boundary" says storage policy belongs.
//
// It had lived in `GenerateView` until #87 deleted that surface, and moved here then. That was the
// right direction and not far enough: application-level locations belong with neither a view nor
// an entry point, but with the module that owns storage.

@main
struct SuperscaleApp: App {
    @StateObject private var viewModel: UpscaleViewModel
    @StateObject private var settingsState: GenerationSettingsState
    @StateObject private var generationCoordinator: GenerationCoordinator
    private let sessionStore: GenerationSessionStore
    /// Every directory the application writes to, resolved once in `init`.
    private let storageRoots: StorageRoots

    init() {
        var startupError: String?

        // The storage root is decided once, here, before anything that writes is constructed.
        //
        // Every location the application writes to hangs off this one value, which is what AC116.1
        // requires. Resolving it a second time elsewhere is the defect #116 fixes: the workspace's
        // asset graph read `V2AppPaths` from a view's property initialiser, so a launch given a test
        // root redirected the coordinator and the session store and left the workspace writing into
        // the user's own application-support directory.
        //
        // The environment is read here rather than inside `StorageRoots`, so that honouring it stays
        // a decision this application makes under its own build conditions. A resolver reading the
        // environment itself would apply to release builds too.
        //
        // The root is honoured on its own, where the stubbed generation service below still also
        // requires `SUPERSCALE_UI_TEST_GENERATED_IMAGE`. Where the application keeps its files is a
        // separate question from whether the provider is stubbed, and coupling the two is what let
        // a launch redirect two of the three storage kinds and leave the third behind.
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let configuredRoot = environment["SUPERSCALE_UI_TEST_ROOT"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
#else
        let configuredRoot: URL? = nil
#endif
        let storageRoots = StorageRoots.resolved(configuredRoot: configuredRoot)
        self.storageRoots = storageRoots

        var credentialStorage: any CredentialStorage = KeychainCredentialStorage()
        var coordinator = GenerationCoordinator(outputDirectory: storageRoots.generated)
        var store = GenerationSessionStore(rootDirectory: storageRoots.history)
        var credentialVerifier = FalCredentialVerifier()
        var upscaleCoordinator = GUIUpscaleCoordinator()

#if DEBUG
        // Makes one subsystem fail on demand, so a GUI test can see where each failure is presented.
        // Without it neither can be made to fail from outside: the generation service is stubbed to
        // succeed and the upscale runs the real pipeline on a real fixture.
        //
        // **Named rather than a boolean**, because the two are not independent. The suite's fixture
        // is below the filterable minimum, so applying a filter raises it first — and a raise is an
        // upscale. A single flag failing both would fail the filter path at the raise, and a test
        // asserting that two subsystems reach the same surface would be comparing one subsystem
        // with itself.
        let failingSubsystem = environment["SUPERSCALE_UI_TEST_FAIL"]
        if failingSubsystem == "upscale" {
            upscaleCoordinator = GUIUpscaleCoordinator(processor: UITestFailingUpscaleProcessor())
        }
        if let configuredRoot,
           let generatedImagePath = environment["SUPERSCALE_UI_TEST_GENERATED_IMAGE"] {
            let generatedImage = URL(fileURLWithPath: generatedImagePath)
            credentialStorage = UITestCredentialStorage()
            // The generation service is already stubbed here; the verifier is stubbed for the same
            // reason. A GUI test pressing save would otherwise reach `api.fal.ai` for real, which
            // makes the suite depend on a network and on somebody else's uptime.
            credentialVerifier = FalCredentialVerifier(transport: UITestVerificationTransport())
            // The directories come from `storageRoots`, which already resolved from this same root.
            // Recomputing them here is how the workspace and the coordinator came to disagree.
            coordinator = GenerationCoordinator(
                service: UITestGenerationService(
                    imageURL: generatedImage,
                    // `provider` keeps failing both, so RT-98.14 is unchanged by #113 — it reaches
                    // the upload, which throws first. `generation` lets the upload succeed so the
                    // request itself can fail, which is the only route to the defect #113 reports
                    // and a route nothing could reach before.
                    failsUpload: failingSubsystem == "provider",
                    failsGeneration: failingSubsystem == "provider"
                        || failingSubsystem == "generation"),
                outputStore: GeneratedImageStore(directory: storageRoots.generated)
            )
            store = GenerationSessionStore(rootDirectory: storageRoots.history)
            do {
                try resetUITestRoot(configuredRoot)
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
                storageRoots: storageRoots,
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
            // The open panel, reachable whether or not a picture is already loaded.
            //
            // Guide 2.2 promises three import routes — drag and drop, the open panel, and paste —
            // and two of them disappeared the moment a picture arrived: `fileChooser` lives on the
            // empty-canvas drop target, and there was no Open command at all. That left dragging
            // from Finder as the only way to bring in a second picture, which is why the author
            // reported having to quit and relaunch between every test (#130).
            //
            // In the File menu rather than back on the canvas, because a canvas showing a
            // photograph is the wrong place for a button about a different photograph, and Cmd+O is
            // where a Mac user looks first.
            CommandGroup(after: .newItem) {
                Button("Open Image…") {
                    openImage()
                }
                .keyboardShortcut("o", modifiers: [.command])
                .accessibilityIdentifier("openImageCommand")
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

    /// Brings in a picture through the open panel, whatever is already on the canvas.
    ///
    /// The same panel `DropTargetView` presents, with the same accepted types, so the two routes
    /// cannot drift apart in what they will take. It goes through `viewModel.handleDrop` for the
    /// same reason: one path in, whichever way the user reached it.
    ///
    /// Bringing in a picture starts a new chain and releases the previous one's files (AC89.8).
    /// That is deliberate and unchanged — but it was previously unreachable without relaunching,
    /// which discarded the work anyway. It is reachable now, and the exposure is recorded on #130.
    private func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an image to upscale"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.handleDrop(urls: [url])
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

/// Counts the generation requests the stub has been asked to make.
///
/// **The only place that sees a request.** RT-122.2 asks whether one intent produces one paid call,
/// and a GUI test observes results rather than requests — a second request returning an identical
/// picture is one visible change and two charges, which is exactly the defect. Counting arrivals
/// would assert something else and pass against the bug.
///
/// A type of its own rather than a mutable field on the stub, because `GenerationServing` hands the
/// service around as a value and a `var` would be counting copies.
@MainActor
final class UITestRequestLedger {
    static let shared = UITestRequestLedger()
    private(set) var generationRequests = 0

    func recordGenerationRequest() {
        generationRequests += 1
    }
}

@MainActor
private struct UITestGenerationService: GenerationServing {
    let imageURL: URL
    /// Fails the upload, which `submitFilter` performs first.
    var failsUpload = false
    /// Fails the generation request, which is only reached when the upload succeeds.
    ///
    /// Separate flags because one flag could only ever exercise the *upload*: `submitFilter` uploads
    /// before it generates, so a single `fails` threw at the first call and execution never reached
    /// `generate`. RT-98.14 had been standing over the upload route alone and reading "Storage is
    /// unavailable", which is how a generation failure that never reached an alert survived #98.
    var failsGeneration = false

    /// Answers with a plausible provider URL and reaches no network.
    ///
    /// The suite's fixture is on disk and the provider is stubbed, so there is nothing to upload
    /// and nowhere to upload it to. What matters is that a reference URL comes back, because that
    /// is what the request carries.
    func uploadReference(fileURL: URL, fileName: String, apiKey: String) async throws -> URL {
        if failsUpload {
            throw FalFailure(kind: .provider, diagnostic: "Storage is unavailable. (ui-test)")
        }
        return URL(string: "https://v3.fal.media/files/ui-test/\(fileName)")
            ?? URL(fileURLWithPath: fileName)
    }

    func generate(_ request: FalGenerationRequest, apiKey: String) async throws -> FalGeneratedImage {
        // Counted before the failure branch: a request that the provider declines was still issued
        // and, against a real provider, still charged for.
        UITestRequestLedger.shared.recordGenerationRequest()
        if failsGeneration {
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
