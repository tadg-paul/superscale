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

/// The channel between the File menu and `MainView`.
///
/// **Why this exists.** `WorkspaceState` — the lock chain, the graph, everything a clear destroys —
/// is owned by `MainView`, not by the scene. So a menu command declared here cannot see whether
/// there is unsaved work, and cannot ask before discarding it.
///
/// The alternative was to hoist the workspace up to the scene so the menu could reach it directly.
/// That is a change to who owns the application's state, made in service of a menu item, and it
/// would put the decision about unsaved work in two places. **#143's rule is that every route to a
/// clear asks the same question** — the author named two routes, and a warning that fires on some
/// and not others teaches a habit that then fails. One owner, one decision; the menu sends a
/// request rather than performing an action.
///
/// **Counters, not booleans.** A `Bool` set to `true` and read back to `false` cannot express "the
/// user pressed Cmd+N twice": the second set is not a change, so `onChange` never fires. A
/// monotonic counter always changes.
///
/// Declared here rather than in a file of its own because this target is not a synchronized folder,
/// and hand-editing the project file to add one small type is a worse risk than the misfiling.
@MainActor
final class AppCommands: ObservableObject {
    /// Incremented when the user asks for a new, empty canvas.
    @Published private(set) var clearRequests = 0
    /// Incremented when the user asks to bring in another picture.
    @Published private(set) var openRequests = 0

    /// Incremented when the user asks to copy the picture on the canvas.
    @Published private(set) var copyRequests = 0
    /// Incremented when the user asks to paste a picture in.
    @Published private(set) var pasteRequests = 0

    func requestClear() { clearRequests += 1 }
    func requestOpen() { openRequests += 1 }
    func requestCopy() { copyRequests += 1 }
    func requestPaste() { pasteRequests += 1 }
}

@main
struct SuperscaleApp: App {
    @StateObject private var viewModel: UpscaleViewModel
    @StateObject private var settingsState: GenerationSettingsState
    @StateObject private var generationCoordinator: GenerationCoordinator
    /// File-menu commands, delivered to the view that owns the state they act on (#143, #145).
    @StateObject private var commands = AppCommands()
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
                sessionStore: sessionStore,
                commands: commands
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
            // **Cmd+N clears rather than opening a second window (#145).**
            //
            // `replacing:`, not `after:`. Left alone, AppKit's own New Window survives and opens a
            // second window onto the *same* `WorkspaceState` and `UpscaleViewModel` — two windows,
            // one model, so whatever the second appears to show is the first one's state. The author
            // saw that and chose this route over multi-window support, which would need a graph, a
            // lock chain and a filter cache per window.
            //
            // It sends a request rather than clearing, because whether there is unsaved work to
            // warn about is a question only `MainView` can answer.
            // **The scale and face shortcuts (#147), in a menu rather than bound invisibly.**
            //
            // The author asked for *"2x and 4x superscale toggle, maybe cmd+2 and cmd+4? and face
            // model toggle choose a key binding"* and accepted Cmd+2, Cmd+4, Cmd+8 and Cmd+Shift+F.
            //
            // A menu because he has now twice reported a feature missing that existed but could not
            // be found — #130's Open Image and #135's clear. A shortcut with no menu entry is the
            // same mistake with no surface at all.
            //
            // **Cmd+8 is an assumption**, recorded for validation: he named 2x and 4x, and 8x is a
            // third preset that would look arbitrary left unbound.
            //
            // **Cmd+Shift+F, not Cmd+F**, which is Find by universal convention and is the wrong
            // thing to take in an application with a filter search field.
            // **Copy and paste (#144), his second raising, with the guard he asked for.**
            //
            // *"cmd should only allow paste on blank canvas"*, and the reason he gave the first
            // time: *"otherwise if we hit it by mistake, the existing image will be lost."* Cmd+V is
            // hit by muscle memory, and the cost of getting it wrong is a lock chain paid for at a
            // provider.
            //
            // **Refused rather than warned**, unlike #143's clear. A paste onto a working canvas is
            // almost certainly a mistake, and the cheapest correct answer to a mistake is for
            // nothing to happen — the menu item is simply disabled, so there is nothing to dismiss.
            //
            // Guide 2.2 has promised paste as one of three import routes since v2 was specified and
            // it has never existed. This closes that too.
            // **`after:`, not `replacing:`, and that distinction cost a run.** Replacing the
            // pasteboard group removes the standard Cut, Copy, Paste and Select All *for every text
            // field in the application* — including the open panel's "Go to folder" field, which the
            // GUI suite types into. Two tests then failed with `loadTestImage` timing out at 133
            // seconds, which reads as an unrelated harness problem rather than as a menu change.
            //
            // These are additional commands about the picture, not replacements for text editing.
            CommandGroup(after: .pasteboard) {
                Button("Copy Image") { commands.requestCopy() }
                    .keyboardShortcut("c", modifiers: [.command])
                    .disabled(viewModel.originalImage == nil)
                    .accessibilityIdentifier("copyImageCommand")
                Button("Paste Image") { commands.requestPaste() }
                    .keyboardShortcut("v", modifiers: [.command])
                    // The guard, stated where the user meets it. Enabled only on a blank canvas.
                    .disabled(viewModel.originalImage != nil)
                    .accessibilityIdentifier("pasteImageCommand")
            }
            CommandMenu("Image") {
                // Toggles, matching the buttons exactly: the scale controls are a toggle group and
                // pressing the active choice clears it (AC82.7). A shortcut that only ever *set* a
                // scale would be a different control wearing the same name.
                Button("Upscale 2x") { viewModel.choose(.preset(2)) }
                    .keyboardShortcut("2", modifiers: [.command])
                    .disabled(viewModel.originalImage == nil)
                    .accessibilityIdentifier("scale2xCommand")
                Button("Upscale 4x") { viewModel.choose(.preset(4)) }
                    .keyboardShortcut("4", modifiers: [.command])
                    .disabled(viewModel.originalImage == nil)
                    .accessibilityIdentifier("scale4xCommand")
                Button("Upscale 8x") { viewModel.choose(.preset(8)) }
                    .keyboardShortcut("8", modifiers: [.command])
                    .disabled(viewModel.originalImage == nil)
                    .accessibilityIdentifier("scale8xCommand")

                Divider()

                // Disabled on the same two conditions as the button on the canvas: face enhancement
                // is a stage of the upscale, so with no scale selected there is nothing for it to be
                // a stage of (AC93.3), and with the model absent there is nothing to enable. A
                // shortcut that silently sets a flag the interface will not honour is worse than no
                // shortcut.
                Button("Face Enhancement") { viewModel.faceEnhance.toggle() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(viewModel.scaleSelection.isOff || !FaceModelRegistry.isInstalled)
                    .accessibilityIdentifier("faceEnhanceCommand")
            }
            CommandGroup(replacing: .newItem) {
                Button("New") {
                    commands.requestClear()
                }
                .keyboardShortcut("n", modifiers: [.command])
                .accessibilityIdentifier("newCanvasCommand")
            }
            // The open panel, reachable whether or not a picture is already loaded.
            //
            // Also a request now, and for the same reason: the author asked to be warned *"before we
            // clear any images with cmd+o (or cmd+n)"*, and this route replaces the working picture
            // exactly as the other two do.
            CommandGroup(after: .newItem) {
                Button("Open Image…") {
                    commands.requestOpen()
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
    /// 🚫 Moved to `MainView.presentOpenPanel()` by #143, not deleted for tidiness.
    ///
    /// Opening replaces the working picture, and the author asked to be warned before that happens
    /// *"with cmd+o (or cmd+n)"*. Whether there is unsaved work to warn about is a question about
    /// the lock chain, which `MainView` owns and this scene cannot see — so the decision and the
    /// panel had to travel together. The command here sends a request instead.
    ///
    /// The properties this carried still hold and now hold there: the same panel `DropTargetView`
    /// presents, the same accepted types, and one path in through `viewModel.handleDrop` whichever
    /// way the user reached it (AC89.8).
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
