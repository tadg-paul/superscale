# Research: Reliable Workspace Actions

## Decision 1: Preserve text editing while making image shortcuts win

**Decision**: Keep the standard pasteboard command group and its native key equivalents. Insert a workspace responder in the key window's AppKit responder chain so an editable text responder handles Copy or Paste first and only an unhandled command reaches the canvas. Retain distinct `Copy Image` and `Paste Image` menu items for discoverability, but give them no duplicate key equivalents. Keep the picture-level Paste item disabled on a populated canvas and keep the second guard at import time.

**Rationale**: The current custom and standard commands compete for the same key equivalents, while current GUI tests invoke menu items rather than the shortcuts. Native responder routing preserves ordinary text and system-panel behaviour, then supplies canvas behaviour only when the standard chain does not consume the selector. It also avoids moving workspace ownership into the scene.

**Alternatives considered**:

- Replace the standard pasteboard group: rejected because it removes native text commands from application and system fields unless all responder behaviour is rebuilt.
- Put duplicate custom shortcuts before the standard group: rejected because disabled image items can swallow text shortcuts and enabled image items can pre-empt text editing.
- Leave duplicate custom shortcuts after the standard group: rejected because this is the current false-green design.
- Hoist `WorkspaceState` into the scene: rejected because a menu shortcut does not justify changing workspace ownership.

## Decision 2: Make the asset graph define Save All membership

**Decision**: Add a stable, de-duplicated export projection to `AssetGraph` and expose it through `WorkspaceState`. Membership is the held chain in order, including any promoted `raisedToMinimum` entry, plus a distinct unlocked candidate.

**Rationale**: The graph is the only authority for source, lock-chain order, and current candidate. Reading the strip or view-model display state would create a second, lossy opinion about which paid results exist.

**Alternatives considered**:

- Export only `lockedIterations`: rejected because a bare source and current unlocked candidate would be omitted.
- Scan the generated-output directory: rejected because it contains abandoned, historical, and temporary files that are not the active workspace.
- Export the current canvas only: rejected because it does not implement Save All.

## Decision 3: Process Save All sequentially through the existing coordinator

**Decision**: The view model exports one candidate at a time using its injected `GUIUpscaleCoordinator`, retains a cancellable batch task, and returns a structured summary.

**Rationale**: Sequential work bounds memory and makes progress intelligible. Reusing the injected coordinator keeps on-device processing, model reuse, cancellation, size ceilings, and GUI test substitution aligned with existing upscale behaviour. Cancellation preserves files already written, leaves remaining candidates unattempted, and avoids presenting a long local batch as unstoppable.

**Alternatives considered**:

- Parallel upscale of every iteration: rejected because simultaneous image pipelines can exceed memory limits and obscure progress and partial failure.
- Construct a second coordinator in `MainView`: rejected because it would bypass the established test seam and pipeline cache ownership.
- Temporarily select and display every iteration: rejected because export must not mutate navigation or canvas state.

## Decision 4: Save All writes PNG with deterministic collision avoidance

**Decision**: Export source, locks, and candidate as PNG in stable order. Derive names from source stem, role, and chain position; append a numeric suffix when a destination exists or is already reserved by the batch.

**Rationale**: PNG is lossless and avoids a per-image format prompt, which is necessary for a one-click batch. Pre-reserving names makes collisions deterministic and prevents later items in the same batch from overwriting earlier ones.

**Alternatives considered**:

- Ask for a format per image: rejected because it contradicts one-click Save All.
- Overwrite matching names: rejected by the specification.
- Timestamp-only names: rejected because they hide chain order and image role.

## Decision 5: Validate the output folder at action time

**Decision**: Reuse the preference store's writable-directory rule at the boundary of each save action. Save As may fall back visibly to Downloads; Save All stops and routes to Settings.

**Rationale**: A directory can disappear after startup. Rechecking at action time avoids silent redirection and failed batches while preserving a usable Save As dialog.

**Alternatives considered**:

- Trust the startup-loaded URL indefinitely: rejected because removable and deleted directories invalidate it.
- Silently send Save All to Downloads: rejected by the specification.

## Decision 6: Preserve the existing Grok builder and strengthen journey evidence

**Decision**: Do not duplicate endpoint selection. Keep zero references mapped to the default Grok generation route and a base reference mapped to its edit route. Preserve the existing local adoption of an identical held result before any upload or request. Extend the debug GUI service seam to record both upload calls and submitted requests within the test root, and treat an unreadable returned image as failure without graph mutation.

**Rationale**: Unit tests already cover request construction, and the existing UI journey only proves that an image appears. Recording at the stubbed service boundary proves which request the visible Apply action actually submitted without contacting FAL, while explicit call counts preserve the paid-work avoidance already implemented for repeated prompts.

**Alternatives considered**:

- Add a second UI control or model picker: rejected because the existing prompt UX and one-model MVP are explicit scope constraints.
- Assert source text or call a real provider in regression: rejected because neither is valid repeatable behavioural evidence.

## Decision 7: Add the missing Swift vulnerability gate

**Decision**: Use a repository-owned `make vulncheck` target backed by separate Trivy filesystem vulnerability scans of the committed root-package and Xcode-application lockfiles.

**Rationale**: The SDLC requires a separate dependency-security interface for deployable applications. Trivy's official Swift coverage documents `Package.resolved` support, including transitive and development dependencies. The two current locks resolve different versions of their shared package, so equality is not a safe proxy for coverage; scanning both names and checks both dependency graphs. The target must fail when either lock, Trivy, or advisory data is unavailable and must not install or mutate anything.

**Alternatives considered**:

- Add vulnerability scanning to `make test`: rejected because security scanning is a separate gate.
- Use an unconditional no-op because Trivy is not locally installed: rejected by the security standard.
- Require identical lockfile contents or package versions: rejected because the command-line and Xcode builds are separate resolved graphs and both can be scanned directly.
- Scan the OneOff package as deployed input: rejected because it is a segregated test harness and does not affect the application artefact.

## Decision 8: Freeze workspace mutation during Save All

**Decision**: Snapshot membership and processing configuration at batch start, then disable every action that can change the graph, displayed source, scale, model, or face setting until the batch finishes or is cancelled. This includes New, Open, Open Recent, the canvas Clear Image action, drag and drop, picture Paste, Save As, Apply, Lock, iteration selection, the base-versus-candidate display toggle, scale, model, face enhancement, and repeated Save All. Guard the handlers as well as the controls, and do not queue attempted changes.

**Rationale**: Reactive upscale controls share the same coordinator as batch export. Allowing them to run concurrently defeats the sequential memory bound and makes saved-state attribution depend on timing. A snapshot also lets harmless prompt, search, comparison, and Settings changes remain usable.

**Alternatives considered**:

- Apply changes to later batch items: rejected because one batch would contain mixed, timing-dependent configurations.
- Queue mutations after completion: rejected because delayed New, Open, or Paste actions could destroy the workspace unexpectedly.
- Construct a separate exporter coordinator: rejected because it duplicates pipeline ownership and memory pressure.

## Decision 9: Retain stale configured-folder identity

**Decision**: Extend preference loading with a state that carries the raw stored URL, effective fallback URL, and default, valid, or stale status.

**Rationale**: The inherited loader correctly falls back to Downloads but currently discards the evidence that a user-selected path failed validation. Save As needs the fallback and a visible warning; Save All must refuse silent redirection. Both behaviours require the raw choice to survive loading.

**Alternatives considered**:

- Read UserDefaults directly from each save action: rejected because it bypasses the repository's preference owner.
- Remove the existing fallback: rejected because it would regress first-run and recovery behaviour.
- Treat Downloads as the user's new configured choice: rejected because it silently rewrites intent.

## Resolved Unknowns

- **Blank canvas**: the workspace has no base image and shows the drop target.
- **Save All population**: the held chain in order, including a promoted minimum-resolution raise, then a distinct current candidate.
- **Save All format**: PNG.
- **Failure policy**: continue per image, summarize, and mark only successful images saved.
- **Mutation during Save All**: graph and processing mutations are disabled and discarded; only cancellation changes the active batch.
- **Stale output folder**: the raw configured path remains available for reporting even when Downloads is the operational fallback.
- **Prompt route**: no base means generation with no reference; a matching held result is adopted locally; any other base means edit with exactly that base.
- **Metered validation**: no real provider in automation; a later live user test is bounded and optional for regression closure.
