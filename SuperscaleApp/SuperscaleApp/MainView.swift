// ABOUTME: The single Superscale workspace: the image on the canvas, the filters beside it.
// ABOUTME: Holds the base image a filter reads and the candidate a filter produced.

import FalGenerationKit
import SuperscaleKit
import SuperscaleUXCore
import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: UpscaleViewModel
    @ObservedObject var settingsState: GenerationSettingsState
    @StateObject private var generationCoordinator: GenerationCoordinator
    @State private var selection = FilterSelection()
    @State private var showAbout = false
    @State private var showFaceDownload = false
    @State private var infoPanelDismissed = false
    /// The base's pixels, reloaded when the base changes rather than per body evaluation.
    @State private var loadedBaseImage: NSImage?
    /// What the view last asked the view model to show.
    ///
    /// Distinguishes the view's own display request from a picture the user brought in, which
    /// `adoptImportedImage` could not otherwise tell apart. #111.
    @State private var lastDisplayedURL: URL?
    // 🚫 `viewedIteration` is removed by #121. It was a second opinion about which iteration the
    // user was on, held in the view beside the graph's own answer, and keeping the two agreeing was
    // manual. The graph's candidate *is* the selected iteration as of guide 3.32, so the strip
    // reads that and there is nothing left to synchronise.
    @State private var didLoadDefaults = false
    /// The workspace's state. The graph decides which asset is read and which is shown; the view
    /// model renders whichever one it is handed.
    ///
    /// Its directory arrives through `init` rather than being resolved here. As a property
    /// initialiser reading `V2AppPaths` it was the application's second, unrelated answer to where
    /// storage lives, and a launch given a test root redirected the coordinator and the session
    /// store while this one went on writing to the user's application-support directory (#116).
    @StateObject private var workspace: WorkspaceState

    private let sessionStore: GenerationSessionStore

    /// - Parameter storageRoots: every directory this view's components write to. Required rather
    ///   than defaulted: a default would be a second resolution, which is the defect #116 fixes.
    init(
        viewModel: UpscaleViewModel,
        settingsState: GenerationSettingsState,
        storageRoots: StorageRoots,
        generationCoordinator: GenerationCoordinator? = nil,
        sessionStore: GenerationSessionStore? = nil
    ) {
        self.viewModel = viewModel
        self.settingsState = settingsState
        _workspace = StateObject(
            wrappedValue: WorkspaceState(outputDirectory: storageRoots.generated)
        )
        _generationCoordinator = StateObject(
            wrappedValue: generationCoordinator
                ?? GenerationCoordinator(outputDirectory: storageRoots.generated)
        )
        self.sessionStore = sessionStore
            ?? GenerationSessionStore(rootDirectory: storageRoots.history)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                canvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // A container, not an element. Without this the identifier makes SwiftUI
                    // treat the canvas as one element and absorb the drop target, the image and
                    // the info panel, which is the defect #88 fixed in Settings.
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("workspaceCanvas")
                    // The canvas says what it is showing, in its **label**.
                    //
                    // AC117.1 first asked for this as an `accessibilityValue`, and #117 records
                    // four measurements showing SwiftUI does not carry a value here: empty on this
                    // container, empty on the inner one, and empty on a shape declared an element
                    // of its own. The label is the channel this platform carries on a container
                    // declaring `children: .contain`, which is what guide 3.18 already said.
                    .accessibilityLabel(canvasAccessibilityLabel)
                Divider()
                FilterPanel(
                    selection: $selection,
                    catalogueFailure: settingsState.lastError,
                    isGenerationConfigured: settingsState.isGenerationConfigured,
                    hasWorkingImage: workspace.graph.base != nil,
                    isApplying: generationCoordinator.phase == .generating,
                    canLock: workspace.canLock,
                    onApply: applyFilter,
                    onCancel: generationCoordinator.cancel,
                    onLock: lockCandidate
                )
            }
            lockChainSection
            Divider()
            statusBar
        }
        .navigationTitle(windowTitle)
        .onAppear(perform: loadDefaults)
        .onChange(of: viewModel.inputURL) { _, url in adoptImportedImage(url) }
        .onChange(of: coordinatorOutputPath) { _, _ in adoptFilterResult() }
        .onChange(of: coordinatorFailureMessage) { _, message in reportFilterFailure(message) }
        .onChange(of: workspace.showsBase) { _, _ in displayChosenAsset() }
        // On appearance as well as on change. Driven by the change alone, a view recreated while a
        // base already exists — a window reopened, the scene rebuilt — would start with no loaded
        // image and nothing to observe, and silently fall back to the wrong picture.
        .onAppear(perform: reloadBaseImage)
        .onChange(of: workspace.graph.base) { _, _ in reloadBaseImage() }
        // A setting change makes the info panel's summary stale, so it comes back to say what the
        // new setting will do.
        .onChange(of: viewModel.selectedModelName) { infoPanelDismissed = false }
        .onChange(of: viewModel.scaleSelection) { infoPanelDismissed = false }
        .onChange(of: viewModel.stretchEnabled) { infoPanelDismissed = false }
        .onChange(of: viewModel.faceEnhance) { infoPanelDismissed = false }
        // The application's one failure surface. Identified so a test can assert that a filter
        // failure and an upscale failure arrive at the same place rather than at two that merely
        // look alike.
        .alert("Error", isPresented: showError, actions: {
            Button("OK") { viewModel.dismissError() }
                .accessibilityIdentifier("failureAlertDismiss")
        }, message: {
            Text(viewModel.errorMessage ?? "")
                .accessibilityIdentifier("failureAlertMessage")
        })
    }

    // MARK: - Canvas

    private var canvas: some View {
        ZStack {
            canvasContent

            // The info panel keeps the top. It is anchored by a `Spacer` beneath it rather than by
            // the stack's alignment, because the indicator below no longer shares that alignment.
            VStack(spacing: 8) {
                if !infoPanelDismissed && !viewModel.showComparison {
                    InfoPanel(viewModel: viewModel, dismissed: $infoPanelDismissed)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 16)

            // Progress sits *over* the image rather than in place of it. Replacing the picture with
            // a spinner threw away the thing the user came for and made a drop look as though it had
            // been ignored.
            //
            // It reports *any* work, not only the local upscale. The canvas watched `isProcessing`
            // alone, so a paid provider call ran for tens of seconds in silence while the status dot
            // and the filter panel both knew.
            //
            // **Centred, by #119.** It sat at the top until then, which AC90.13 specified and
            // RT-90.49 asserted; both are superseded by AC119.1. The two pieces of chrome were
            // stacked together at that point because as separate top-anchored children the info
            // panel drew over the indicator and hid it. Centring separates them by position rather
            // than by stacking, and RT-119.3 holds that they do not collide again.
            //
            // The indicator carries its own background, within its own bounds. Nothing is drawn
            // across the picture: a material applied here covered the whole canvas, because the
            // overlay used to be full-size. Centring puts the badge over the middle of the picture
            // rather than its edge, so that guarantee is doing more work than it was.
            if canvasWork.isBusy {
                ProgressOverlay(message: canvasWork.message)
                    .accessibilityIdentifier("workingIndicator")
            }
        }
    }

    /// The lock chain beneath the canvas, present whenever there are locked iterations.
    ///
    /// Extracted from `body` rather than inlined: with the viewing state's two extra arguments the
    /// whole view expression went past what the type-checker will attempt, and the compiler
    /// reported it against an unrelated line thirty rows away.
    @ViewBuilder
    private var lockChainSection: some View {
        if !workspace.lockedIterations.isEmpty {
            Divider()
            LockChainStrip(
                iterations: workspace.lockedIterations,
                // The graph's own answer, not a copy of it. The candidate is the selected
                // iteration; with none, the user is on the base and nothing is "being viewed".
                viewing: workspace.graph.candidate,
                onSelect: showIteration,
                onReturn: returnToCurrent
            )
        }
    }

    /// The canvas's accessibility label, carrying what it is currently displaying.
    ///
    /// Composed here rather than interpolated in `body`. Inline, it pushed the view expression past
    /// what the type-checker will attempt, and the compiler reported the failure against an
    /// unrelated line thirty lines away.
    private var canvasAccessibilityLabel: String {
        "Canvas showing \(displayedKind.reportedValue)"
    }

    /// What the canvas is currently displaying.
    ///
    /// Derived from `viewModel.result` rather than from `viewModel.isProcessing`, so the report
    /// follows the picture rather than the request. AC90.2 leaves the previous picture on screen
    /// while work runs, and a value that moved when a run *started* would tell the suite an upscale
    /// had finished before one had.
    private var displayedKind: CanvasKind {
        CanvasKind.of(
            hasImage: viewModel.originalImage != nil,
            showsBase: workspace.showsBase,
            hasCandidate: workspace.canCompare,
            hasUpscaledRendering: viewModel.result != nil
        )
    }

    /// Whether anything is happening, and what to call it.
    private var canvasWork: CanvasWork {
        CanvasWork.of(
            isUpscaling: viewModel.isProcessing,
            isApplyingFilter: generationCoordinator.phase == .generating,
            upscaleMessage: viewModel.progressMessage)
    }

    /// The picture the working image descends from, loaded when the base changes.
    ///
    /// Taken from the asset graph rather than from `viewModel.originalImage`, which `processImage`
    /// replaces with whatever it was last asked to upscale — so after a filter it holds the filter's
    /// own output, and the curtain compared that against its own upscale. Two pictures differing in
    /// resolution and nothing else, which is what "the before/after image is the same" was.
    ///
    /// Held in `@State` rather than computed in `body`: decoding it per evaluation reads a
    /// photograph from disk on every progress tick, every hover phase and every keystroke in the
    /// dimension fields.
    private var comparisonBase: NSImage? {
        loadedBaseImage ?? viewModel.originalImage
    }

    private func reloadBaseImage() {
        guard let url = workspace.baseFileURL else {
            loadedBaseImage = nil
            return
        }
        loadedBaseImage = NSImage(contentsOfFile: url.path)
    }

    /// What the canvas draws, decided by `CanvasContent`: the base always, the derivation when one
    /// exists and is what the user has chosen to look at, and the curtain when there are two
    /// different images to compare.
    @ViewBuilder
    private var canvasContent: some View {
        if let base = viewModel.originalImage {
            // Whether the two sides are one asset is `CanvasContent`'s decision, not this view's.
            //
            // A graph-based guard sat here and suppressed the curtain outright: the view model
            // performs its own upscales without recording them on the graph, so the graph's
            // displayed asset *is* the base, and "displayed equals base" read as nothing to
            // compare. The GUI suite caught it — the curtain stopped appearing at all — which no
            // package test could have, because the graph and the view model agree perfectly in
            // isolation and disagree only once both are running.
            if viewModel.showComparison, let derived = derivedImage, let against = comparisonBase {
                ComparisonView(original: against, upscaled: derived)
                    .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDropProviders)
            } else {
                resultView(image: displayedImage ?? base)
            }
        } else {
            DropTargetView(onDrop: viewModel.handleDrop)
        }
    }

    /// The output of the last operation, when there is one.
    ///
    /// An upscale rendering when one exists, and otherwise the filter result itself. A filter result
    /// **is** a derivation of the base, which is what AC94.3 says the curtain exists to compare, and
    /// binding this to `viewModel.result` alone meant the curtain was offered only after an upscale.
    /// The raise to the filterable minimum turns the scale off (AC96.1), so a user who filters an
    /// undersized picture is in exactly the state where no upscale ever runs and the comparison was
    /// never offered at all (#112).
    ///
    /// AC90.6's other half still holds: with nothing derived, this is `nil` and no curtain appears.
    private var derivedImage: NSImage? {
        if let upscaled = viewModel.result { return upscaled }
        guard workspace.canCompare, !workspace.showsBase else { return nil }
        return viewModel.originalImage
    }

    /// The image on the canvas: the derivation unless the user has asked for the base.
    private var displayedImage: NSImage? {
        workspace.showsBase ? viewModel.originalImage : (derivedImage ?? viewModel.originalImage)
    }

    private func resultView(image: NSImage) -> some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(16)
                .accessibilityIdentifier("workingImage")

            DropTargetView(onDrop: viewModel.handleDrop)
                .opacity(0.01)
        }
    }

    // MARK: - Applying a filter

    private var coordinatorOutputPath: String? {
        generationCoordinator.output?.localURL.path
    }

    /// The provider's own words when a generation request fails, and nil otherwise.
    ///
    /// Observed as the **message**, not as the phase. Observing `.failed` would re-raise the alert on
    /// every redraw that happened while the phase stayed failed; the message changes once per
    /// failure and returns to nil the moment anything else starts.
    private var coordinatorFailureMessage: String? {
        if case let .failed(message) = generationCoordinator.phase { return message }
        return nil
    }

    /// Puts a failed generation request on the application's one failure surface.
    ///
    /// The upload half of an apply already threw into `submitFilter`'s catch and reached
    /// `viewModel.report`. The request half did not: it set `phase = .failed`, and nothing in the
    /// view observed that at all — only `coordinatorOutputPath`, which is the success. `statusText`
    /// rendered the diagnostic because it reads the phase on every redraw, which is incidental
    /// rather than a presentation: an API error in caption type at the foot of the window, in the
    /// place reserved for ambient state (#113).
    ///
    /// AC98.5 asks that a failure reach the user through one surface whatever raised it, and the two
    /// halves of a single apply were reaching two. The status bar keeps ambient state — "Filter
    /// failed" — and the diagnostic goes where the upscale's does.
    private func reportFilterFailure(_ message: String?) {
        guard let message else { return }
        viewModel.report(message)
    }

    /// Adopts an image the user brought in as the graph's source, starting a new chain.
    private func adoptImportedImage(_ url: URL?) {
        guard let url,
              url != generationCoordinator.output?.localURL,
              url != currentlyDisplayedFileURL,
              // What the view itself last asked to show is not an import.
              //
              // This is the whole of #111. Viewing a locked iteration calls `display`, which sets
              // `viewModel.inputURL`, which fires this observer. The guard above compares against
              // the *workspace's* displayed asset, which is still the base or the candidate and
              // never the iteration being viewed, so it passed — and `importImage` ran, which by
              // AC89.8 starts a new chain. The strip's own condition then removed it, and the user
              // was stranded on the iteration they had opened.
              url != lastDisplayedURL else { return }
        // A new picture starts a new chain (AC89.8). The graph clears its own candidate and tip,
        // so nothing here needs resetting — which is the point of #121: there is no second copy of
        // that state left in the view to forget.
        workspace.importImage(fileURL: url, pixelSize: ImageDimensions.pixelSize(of: url))
    }

    /// Applies the selected filter, raising the base to the filterable minimum first if it falls
    /// short.
    ///
    /// The raise happens here rather than at import because guide 2.5 requires the floor to hold
    /// continuously: the base can change after import — a lock, a model change — and a check made
    /// only on the way in would satisfy AC96.1 while leaving the reported defect in place on every
    /// subsequent apply. This is the one place every submission passes through.
    private func applyFilter() {
        Task {
            if await raiseBaseToMinimumIfNeeded() {
                await submitFilter()
            }
        }
    }

    /// Raises the base to the floor, and reports whether the picture is ready to send.
    ///
    /// Returns `false` only where the raise was attempted and failed, so a caller does not submit a
    /// picture whose size it has just told the user was corrected.
    @MainActor
    private func raiseBaseToMinimumIfNeeded() async -> Bool {
        guard let decision = workspace.raiseToMinimumNeeded(), let scale = decision.scale else {
            return true
        }
        guard let input = try? workspace.graph.input(for: .filter),
              let asset = try? workspace.graph.asset(for: input),
              let source = try? GUIUpscaleSource(resolving: input, in: workspace.graph) else {
            return true
        }

        do {
            // Allocated before the work and promoted after it, as an upscale is: a raise that fails
            // must not leave the base pointing at a file nothing ever wrote.
            let allocation = try workspace.allocateRaiseToMinimum(
                pixelSize: decision.resultingSize, promote: false)
            // Through the view model, which owns the coordinator, so a stubbed processor is stubbed
            // for this work too. Constructing one here would be the same fault the reference upload
            // had: a seam that covers one call and not another.
            let bytes = try await viewModel.renderRaise(
                source, scale: scale, sourceSize: asset.pixelSize)
            try bytes.write(to: allocation.fileURL, options: .atomic)
            // Recorded at the size that was **produced**, not the size that was asked for. A model
            // whose native scale is lower than the one requested delivers less, and the area ceiling
            // can reduce a request outright — so a raise recorded at its target would claim a floor
            // it had not reached, and the next apply would not know to try again. AC96.2 requires
            // the floor to be re-enforced whenever a change drops the working image below it, and
            // this is what makes that check answer honestly.
            try workspace.adoptRaise(
                allocation.reference,
                producedSize: ImageDimensions.pixelSize(of: allocation.fileURL))

            // Guide 2.5's own reasoning: with the raised picture as the base and the scale off, the
            // application stops re-upscaling a picture that is already the size the provider wants.
            viewModel.turnScaleOff()
            viewModel.noticeMessage = decision.report
            return true
        } catch {
            viewModel.report(error)
            return false
        }
    }

    /// Uploads the base to the provider's storage and submits the filter against the URL it issued.
    ///
    /// **The reference is a URL the provider itself issued, and no request body carries image
    /// bytes.** It was a `data:` URL: a whole photograph base64-encoded into the JSON, which grows
    /// the body by a third of the file's size and is what AC92.1 exists to end.
    ///
    /// Uploaded afresh each time. A cached reference URL would be a second place the truth about
    /// the base lives, and the provider's storage is not the application's to reason about the
    /// lifetime of.
    @MainActor
    private func submitFilter() async {
        // The graph decides what a filter reads: the base, never the candidate and never the
        // upscaled rendering. Asking it rather than reaching for what is on screen is the whole
        // point of the graph being the state.
        guard let input = try? workspace.graph.input(for: .filter),
              let asset = try? workspace.graph.asset(for: input) else { return }
        do {
            // The **location**, not the bytes. Reading here meant synchronous disk I/O on the
            // thread drawing the window, so a large picture froze the interface every time Apply
            // was pressed. `FalStorageClient` is `Sendable` and not main-actor bound, so the same
            // read happens on the cooperative pool.
            //
            // Through the coordinator, whose service is the same seam `generate` goes through.
            // Constructing a client here reached `rest.fal.ai` from the GUI suite, because only the
            // *generation* half was stubbed — and nothing said so until a filter produced no
            // candidate to lock.
            let reference = try await generationCoordinator.uploadReference(
                fileURL: asset.fileURL,
                fileName: asset.fileURL.lastPathComponent,
                apiKey: settingsState.generationKey)

            var request = WorkspaceModel(
                filters: selection.filters,
                workingImage: WorkingImage(
                    referenceValue: reference.absoluteString, hasWorkingImage: true),
                isGenerationConfigured: settingsState.isGenerationConfigured
            )
            request.selection = selection
            guard let built = request.applyRequest() else { return }
            generationCoordinator.start(built, apiKey: settingsState.generationKey)
        } catch {
            // An upload that fails is a filter-stage failure, and the base and any candidate
            // survive it: nothing has been recorded, so there is no partial reference for a
            // generation request to pick up.
            viewModel.report(error)
        }
    }

    /// Records a filter result as the candidate and shows it.
    private func adoptFilterResult() {
        // The coordinator's own input carries its attribution. Constructing one here from a
        // location would be attribution by timing, which #86 closed.
        guard let source = generationCoordinator.upscaleSource else { return }
        // What was sent, recorded alongside what came back. Grok raises a short edge under 1024 to
        // its working size and squares the result, so a 3:4 photograph returns 1:1; without both
        // sizes the application cannot say whether it or the provider changed the shape.
        let sentSize = (try? workspace.graph.input(for: .filter))
            .flatMap { try? workspace.graph.asset(for: $0) }?
            .pixelSize
        let candidate: AssetReference
        do {
            candidate = try workspace.recordFilter(
                named: selection.selectedID ?? "",
                fileURL: source.url,
                pixelSize: ImageDimensions.pixelSize(of: source.url),
                modelID: FalGenerationRequest.defaultModelID,
                prompt: selection.promptToApply,
                sessionID: source.sessionID,
                sentSize: sentSize
            )
        } catch {
            viewModel.report(error)
            return
        }

        // AC96.5: a return whose shape differs from what was sent is **identifiable as such**, which
        // means the user can tell — not only that the graph knows. Recorded and never shown, the
        // criterion would be delivered to its tests and not to anybody using the application, which
        // is the fault this delivery found twice already.
        if workspace.reshapedByProvider(candidate) {
            viewModel.noticeMessage =
                "The filter returned a different shape from the picture that was sent."
        }

        upscale(source, arrival: .filterResult)
    }

    /// Promotes the candidate to base, so the next filter builds on it.
    private func lockCandidate() {
        do {
            let locked = try workspace.lock()
            try display(locked)
        } catch {
            viewModel.report(error)
        }
    }

    /// Selects a locked iteration, restoring the working context it was made in.
    ///
    /// **Selecting moves the base**, as of guide 3.32. It previously only changed what was drawn,
    /// on the reasoning that looking at an earlier entry is not the same as deciding to work from
    /// it. In use that turned out to be the wrong division: a user who scrolls back is deciding to
    /// work from there, and a filter applied next transformed the newest lock instead, because a
    /// filter reads the base and the base had not moved.
    ///
    /// The graph decides what that means. The view asks and then draws whatever the graph says is
    /// displayed, which is the point of this issue — there is no second opinion held here.
    private func showIteration(_ reference: AssetReference) {
        do {
            try workspace.selectIteration(reference)
            displayChosenAsset()
        } catch {
            viewModel.report(error)
        }
    }

    /// Returns to the newest locked iteration.
    ///
    /// The newest is the last of `lockedIterations`, which reads from the tip. Asking for it that
    /// way rather than exposing the tip keeps the pointer private: what a caller needs is the
    /// iteration, and the chain already names it. Through `Asset.reference`, because
    /// `AssetReference`'s initialiser is internal — AC89.4's encapsulation, which stops a caller
    /// outside the package inventing a reference for a file it happens to know about.
    ///
    /// Keeping the chain present was only half of what #111 asked for. Without a way back, a user
    /// who opens an iteration reaches every other iteration and never the picture they were
    /// working on, which is the same complaint relocated.
    private func returnToCurrent() {
        guard let newest = workspace.lockedIterations.last else { return }
        showIteration(newest.reference)
    }

    /// Shows whichever asset the workspace's toggle has chosen.
    private func displayChosenAsset() {
        guard let chosen = workspace.displayedAsset else { return }
        do {
            try display(chosen)
        } catch {
            viewModel.report(error)
        }
    }

    /// Hands an asset to the view model, which renders it upscaled when a scale is selected and
    /// untouched when it is not.
    ///
    /// Resolved through the graph rather than by location, so an upscaled reference is refused
    /// here rather than being sent for a second upscale.
    private func display(_ reference: AssetReference) throws {
        let source = try GUIUpscaleSource(resolving: reference, in: workspace.graph)
        // Recorded before the request, so the observer that fires from it can tell the view's own
        // display from a picture the user brought in. See `adoptImportedImage`.
        lastDisplayedURL = source.url
        upscale(source, arrival: .filterResult)
    }

    private var currentlyDisplayedFileURL: URL? {
        guard let displayed = workspace.displayedAsset,
              let asset = try? workspace.graph.asset(for: displayed) else { return nil }
        return asset.fileURL
    }

    // 🚫 `importedPixelSize` is removed by #100. It was the application's second way of measuring a
    // picture, private to this view and exercised by nothing, and for months it used `NSImage.size`
    // — which reports points adjusted by the file's stored resolution, so a 300 dpi photograph
    // measured a quarter of its true size. `ImageDimensions.pixelSize(of:)` is now the only one,
    // and it is covered by RT-100.7 to RT-100.9.

    private func upscale(_ source: GUIUpscaleSource, arrival: ImageArrival) {
        viewModel.selectedModelName = WorkspaceModel.resolvedUpscaleModelID(
            preferred: settingsState.defaultUpscaleModelID,
            arrival: arrival,
            isKnown: { ModelRegistry.model(named: $0) != nil }
        )
        viewModel.upscale(source)
    }

    // 🚫 `dataURL(for:)` is removed by #92. It encoded a whole photograph into the request body as
    // a `data:` URL, growing the body by a third of the file's size, and AC92.1 requires the
    // reference to be a URL the provider itself issued with no image bytes in any body.
    //
    // It also decided the media type from the **file extension**, which AC92.4 rules out: a PNG
    // named `.jpg` would have been declared as a JPEG. `FalStorageClient.contentType(of:)` reads
    // what the file contains, through `CGImageSourceGetType`.

    private func loadDefaults() {
        guard !didLoadDefaults else { return }
        didLoadDefaults = true
        selection = FilterSelection(filters: settingsState.promptPackCatalogue.packs)
        if let defaultFilterID = settingsState.defaultPromptPackID {
            selection.choose(defaultFilterID)
        }
    }


    // MARK: - Toolbar and status

    private var toolbar: some View {
        HStack(spacing: 12) {
            ModelPicker(selectedModelName: $viewModel.selectedModelName,
                        faceEnhance: $viewModel.faceEnhance,
                        options: viewModel.modelOptions,
                        scaleIsOff: viewModel.scaleSelection.isOff)
                .accessibilityIdentifier("modelPicker")

            ScalePicker(viewModel: viewModel)

            faceEnhanceButton

            Spacer()

            // Flick between the filtered result and the image it was made from. A view choice
            // only: it stores nothing, so it is free and reversible, and it is unavailable when
            // there is no candidate to compare against.
            if workspace.canCompare {
                Toggle(isOn: $workspace.showsBase) {
                    Label(
                        workspace.showsBase ? "Showing Original" : "Showing Filtered",
                        systemImage: workspace.showsBase ? "photo" : "wand.and.stars"
                    )
                }
                .toggleStyle(.button)
                .help("Show the image this filter was applied to")
                .accessibilityIdentifier("filterToggle")
            }

            // Offered whenever there is a derivation, which after #112 includes a filter result with
            // no upscale behind it. Bound to `viewModel.result` it was offered only after an
            // upscale, so a user who filtered an undersized picture — the state the raise to the
            // filterable minimum puts them in — was never offered the comparison at all.
            if derivedImage != nil {
                Button(viewModel.showComparison ? "Full View" : "Compare") {
                    viewModel.showComparison.toggle()
                }
                .disabled(viewModel.originalImage == nil)
                .accessibilityIdentifier("compareButton")
            }

            // Save is offered whenever there is a picture, not only when an *upscale* has produced
            // one. Bound to `result`, it disappeared with the scale off — and #96 puts every user
            // with a picture under 1024 pixels into that state, because raising it to the filterable
            // minimum turns the scale off. A filtered result just paid for could not be written to
            // disk. Compare stays bound to `result`, because with nothing derived there is nothing
            // to compare against.
            if viewModel.savableImage != nil {
                Button("Save As…") {
                    viewModel.saveAs(defaultDirectory: settingsState.outputFolder)
                }
                .accessibilityIdentifier("saveButton")
            }

            if infoPanelDismissed {
                Button {
                    infoPanelDismissed = false
                } label: {
                    Image(systemName: "text.bubble")
                }
                .help("Show info panel")
                .accessibilityIdentifier("infoPanelRestore")
            }

            Button {
                showAbout = true
            } label: {
                Image(systemName: "info.circle")
            }
            .help("About Superscale")
            .accessibilityIdentifier("aboutButton")
            .sheet(isPresented: $showAbout) {
                AboutView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColour)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                // Identified so the bar's contents are addressable rather than merely present. The
                // dot beside it is a `Circle` and stays decorative: the state it shows is in this
                // text, and a colour reaches nobody on its own.
                .accessibilityIdentifier("statusText")
            Spacer()
            // Something the user should know that is not a failure, so it sits here rather than
            // taking a click. An upscale reduced to fit memory is the first of these.
            if let notice = viewModel.noticeMessage {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    // The status bar is one line 26 points tall, so a long notice truncates. The
                    // whole sentence stays reachable on hover, and reaches the accessibility tree
                    // as the element's own value rather than only as rendered text.
                    .help(notice)
                    .accessibilityValue(notice)
                    .accessibilityIdentifier("noticeMessage")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        // A container, not an element. An identifier on a stack makes SwiftUI treat the stack as one
        // element and absorb everything in it, so the notice and the status text became unreachable
        // — to VoiceOver, not merely to a test. The D-2 rule of guide 3.9, found here a sixth time
        // and in code that predates it.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("appStatusBar")
    }

    private var statusText: String {
        if viewModel.isProcessing { return viewModel.progressMessage }
        switch generationCoordinator.phase {
        case .generating:
            return "Applying filter"
        case .failed:
            // Ambient state, not the diagnostic. The provider's own words go to the alert, which is
            // AC98.5's one surface; a caption at the foot of the window is where a user watching the
            // canvas for their result does not look, and it used to be the only place they appeared
            // (#113).
            return "Filter failed"
        case .cancelled:
            return "Filter cancelled"
        case .succeeded:
            return "Filter applied"
        case .idle:
            return settingsState.isGenerationConfigured
                ? "Ready · filters available · local upscale available"
                : "Ready · local upscale available · FAL key not configured"
        }
    }

    private var statusColour: Color {
        if viewModel.isProcessing || generationCoordinator.phase == .generating { return .orange }
        if case .failed = generationCoordinator.phase { return .red }
        return .green
    }

    /// Why the face control is or is not available, in words.
    ///
    /// Face enhancement is a stage of the upscale. With no scale selected there is no upscale for
    /// it to be a stage of, so the control is inert — and says so rather than offering a setting
    /// that changes nothing.
    private var faceEnhanceExplanation: String {
        viewModel.scaleSelection.isOff
            ? "Face enhancement applies to an upscale. Select a scale to enable it."
            : "Face enhancement (GFPGAN) — detects and enhances faces in upscaled images"
    }

    private var faceEnhanceButton: some View {
        Button {
            if FaceModelRegistry.isInstalled {
                viewModel.faceEnhance.toggle()
            } else {
                showFaceDownload = true
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: viewModel.faceEnhance && FaceModelRegistry.isInstalled
                      ? "face.smiling.inverse" : "face.smiling")
                if viewModel.showButtonLabels {
                    Text("Face")
                        .font(.system(size: 11))
                }
            }
        }
        .foregroundStyle(viewModel.faceEnhance && FaceModelRegistry.isInstalled
                         ? Color.accentColor : Color.secondary)
        // Face enhancement is a stage of the upscale. With no scale selected there is no upscale
        // for it to be a stage of, so the control is inert and says so rather than offering a
        // setting that changes nothing.
        .disabled(viewModel.scaleSelection.isOff)
        .help(faceEnhanceExplanation)
        // The reason is a **value**, not only a tooltip. AC93.3 requires the unavailability to be
        // visible rather than silent, and a `.help` string is a hover affordance: it reaches nobody
        // who is not holding a mouse still over the control, and nothing that asks the tree what
        // the state is. Guide 3.9's rule, applied to a disabled control's reason rather than to an
        // active control's state.
        .accessibilityValue(faceEnhanceExplanation)
        .accessibilityIdentifier("faceEnhanceButton")
        .sheet(isPresented: $showFaceDownload) {
            FaceModelDownloadView(isPresented: $showFaceDownload) {
                viewModel.faceEnhance = true
            }
        }
    }

    private var windowTitle: String {
        if let url = viewModel.inputURL {
            return "Superscale — \(url.lastPathComponent)"
        }
        return "Superscale"
    }

    private func handleDropProviders(_ providers: [NSItemProvider]) -> Bool {
        let supportedExtensions = ["png", "jpg", "jpeg", "tiff", "tif", "heic"]
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                if supportedExtensions.contains(url.pathExtension.lowercased()) {
                    DispatchQueue.main.async {
                        viewModel.handleDrop(urls: [url])
                    }
                }
            }
        }
        return true
    }

    private var showError: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )
    }
}

#Preview("Empty") {
    // A preview writes nowhere near the user's own storage. The root is passed explicitly for the
    // same reason `MainView` requires one: a default would be a second place storage is decided.
    MainView(
        viewModel: UpscaleViewModel(),
        settingsState: previewSettingsState(),
        storageRoots: StorageRoots(
            root: FileManager.default.temporaryDirectory
                .appendingPathComponent("SuperscalePreview", isDirectory: true)
        )
    )
    .frame(width: 900, height: 600)
}

@MainActor
private func previewSettingsState() -> GenerationSettingsState {
    GenerationSettingsState(
        credentials: GenerationCredentialService(
            storage: KeychainCredentialStorage(service: "org.tigoss.superscale.preview")
        ),
        preferencesStore: GenerationPreferencesStore(),
        loadingCatalogue: { try PromptPackCatalogue.bundled() }
    )
}
