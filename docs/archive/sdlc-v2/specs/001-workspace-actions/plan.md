# Implementation Plan: Reliable Workspace Actions

**Branch**: `master` | **Date**: 2026-09-04 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-workspace-actions/spec.md`

## Summary

Make the existing macOS workspace commands behave at the keyboard, add one-click batch export through the configured output folder, make category and search narrowing mutually exclusive, and prove that canvas state selects reference-free Grok generation or base-image editing. The implementation keeps the asset graph authoritative, keeps native upscale work on-device, preserves text editing, and strengthens GUI coverage so menu-item tests cannot stand in for shortcut tests.

## Technical Context

**Language/Version**: Swift 5.9 package manifest; Swift 5 language mode in the Xcode application target

**Primary Dependencies**: SwiftUI, AppKit, Combine, `SuperscaleUXCore`, `SuperscaleKit`, and `FalGenerationKit`; no new runtime dependency

**Storage**: UserDefaults for the existing default output-folder preference; Keychain for the unchanged FAL credential; file-backed workspace assets and PNG exports

**Testing**: XCTest for package units and XCUITest for macOS journeys, through `make test` and `make test-gui`; `make test-ssim` remains the separate quality gate

**Target Platform**: macOS 14 or later on Apple Silicon

**Project Type**: Native macOS desktop application with reusable Swift packages and a command-line sibling

**Performance Goals**: Shortcut routing and filter narrowing update in the initiating event cycle; Save All accepts one user action and is validated with 25 eligible images processed sequentially without blocking the window; 25 is not a hard workspace limit

**Constraints**: Local upscaling stays on-device; paid generation starts only on Apply; no provider call in regression tests; no source overwrite; existing 32-megapixel output ceiling and reduction notices remain authoritative; no additional model or format picker

**Scale/Scope**: One active workspace containing a source, an ordered lock chain, and at most one unlocked candidate; one configured output folder; the existing single Grok model family

## Constitution Check

*GATE: Passed before Phase 0 research. Re-checked after Phase 1 design.*

- **Defined specification**: PASS. `audits.md` records the current `audit-spec` PASS for the feature.
- **Brownfield authority**: PASS. The plan preserves `docs/ACs.org`, the v2 implementation guide, migrated tickets #141, #144, and #148, maintained tests, and current implementation evidence. The new specification explicitly supersedes menu-only shortcut evidence.
- **Local upscaling**: PASS. Save All reuses the on-device upscale coordinator. No local image is sent to a provider by export.
- **Deliberate paid work**: PASS. Generation and edit still begin only through Apply. Save, copy, paste, and export are local actions.
- **Licensing and dependencies**: PASS. No new model or runtime library is introduced. Existing artefact and service boundaries remain unchanged.
- **Ownership boundaries**: PASS. Product routing stays in the application and workspace model; FAL request shape stays in `FalGenerationKit`; local image processing stays in `SuperscaleKit` and the GUI coordinator.
- **Testing and traceability**: PASS. Package and GUI tests will carry feature requirement and regression identifiers. Real provider verification remains a bounded user test only.
- **Security gate**: PASS WITH PLANNED WORK. Add the missing repository-owned `make vulncheck` target using Trivy against committed Swift lockfiles. It is separate from `make test`, installs nothing, changes nothing, and fails for a missing scanner, unavailable advisory data, incomplete scanning, or any non-exempt finding.
- **Documentation**: PASS WITH PLANNED WORK. Reconcile the design, architecture, acceptance ledger, release-scope statement, and user-facing validation guide where this feature changes current claims.
- **Deviations**: None.

**Post-design re-check**: PASS. The data model, UI contracts, batch-export contract, generation-routing contract, and quickstart preserve every gate above. No unresolved clarification or constitutional conflict remains.

## Project Structure

### Documentation (this feature)

```text
specs/001-workspace-actions/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── validation.md
├── audits.md
├── contracts/
│   ├── batch-export.md
│   ├── generation-routing.md
│   └── workspace-commands.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Sources/
├── FalGenerationKit/
│   └── FalRequestBuilder.swift
└── SuperscaleUXCore/
    ├── AssetGraph.swift
    ├── GenerationPreferences.swift
    ├── WorkspaceModel.swift
    └── WorkspaceState.swift

SuperscaleApp/
├── SuperscaleApp/
│   ├── FilterPanel.swift
│   ├── MainView.swift
│   ├── SettingsView.swift
│   ├── SuperscaleApp.swift
│   └── UpscaleViewModel.swift
└── SuperscaleAppUITests/
    └── SuperscaleAppUITests.swift

Tests/
├── FalGenerationKitTests/
├── SuperscaleTests/
└── SuperscaleUXCoreTests/

Makefile
docs/
```

**Structure Decision**: Extend the existing three-module boundary. Ordered export membership belongs in `SuperscaleUXCore`; provider endpoint selection remains in `FalGenerationKit`; AppKit command routing, save panels, clipboard access, and batch file output remain in the macOS application target. Existing application files are extended because the Xcode target is not a synchronized folder and does not justify hand-editing project membership for small types.

## Design

### Native command routing

- Keep the standard pasteboard command group and its `Cmd+C` and `Cmd+V` equivalents. Add a workspace responder to the key window's native responder chain: an editable text responder handles the command first; only an unhandled Copy or Paste reaches the workspace responder and issues the existing monotonic request to `MainView`.
- Retain discoverable `Copy Image` and `Paste Image` menu items after the standard group, but remove their duplicate keyboard equivalents. These explicit picture items keep stable accessibility identifiers and canvas-only enabled state, while the standard Copy and Paste items represent text when text owns focus.
- The workspace responder validates Copy from `savableImage` and Paste from blank-canvas state. It becomes the canvas responder on a canvas click and the default responder on a blank workspace when no editor or modal panel owns focus.
- Save As is not a text-editing command: `Cmd+S` opens Save As even when an application prompt, search, or Settings field has focus. An already active modal system panel retains its native key handling and cannot open a nested Save As panel.
- Keep the picture-level Paste Image item visibly disabled whenever a picture is loaded, and retain the execution-time blank-canvas guard in `MainView`.
- On a blank canvas, keep Paste available regardless of clipboard contents. At execution time, inspect the advertised pasteboard types before decoding; accept PNG, JPEG, TIFF, or HEIC, and report any other advertised image type through the existing error surface without changing the graph.
- Bind Save As eligibility to `savableImage`, matching the toolbar, so `Cmd+S` works with scaling off.
- Add a Save All request to the same command channel and expose it in the File menu and beside Save As on the canvas.
- While Save All is active, disable New, Open, Open Recent, the canvas Clear Image control, drag and drop, Paste, Save As, Apply, Lock, iteration selection, the base-versus-candidate display toggle, scale, model, face enhancement, and repeated Save All. Guard the corresponding handlers as well as controls. These actions are discarded rather than queued; Cancel Save All is the only workspace mutation accepted until the batch ends. Search, prompt editing, comparison, and Settings may remain available because they do not alter the snapshotted batch.

### Ordered batch export

- Add one read-only asset-graph projection that returns the distinct held chain in order, followed by an unlocked candidate when it is not already in that chain. A promoted `raisedToMinimum` asset is a held-chain entry and is therefore eligible; it is labelled `prepared` in output names. Terminal upscale assets remain renderings rather than held-chain entries and are not separate export candidates.
- Give each candidate a source URL, graph role, export label, chain position, and descriptive stem. The labels are `source` for an imported or generated source, `prepared` for a minimum-resolution raise, `iteration` for a locked filtered asset, and `candidate` for an unlocked filtered asset. Do not expose graph internals or infer membership from the rendered strip.
- Run Save All sequentially through the view model's injected upscale coordinator. This preserves test substitution, bounded memory, on-device processing, progress reporting, face-enhancement choice, selected model, custom sizing, and the existing area ceiling.
- For every scaled candidate, invoke the coordinator directly and bypass `RenderingStore` and `renderedImages`. Those stores optimize the displayed rendering and carry the open #106 defect risk; they are not export authority.
- Snapshot the destination, scale, local model, face setting, custom dimensions, and export membership before the first item starts. Later Settings or prompt edits affect only future work.
- With scale off, decode and encode each source as PNG without an upscale. With a preset scale, apply that multiplier to each source. With custom stretch off, apply the selected defining dimension to each source and derive the other dimension from that source's aspect ratio. With custom stretch on, apply the absolute width and height to every source. Re-evaluate the existing per-image 8x dimension cap and 32-megapixel area ceiling for every candidate and retain each reduction notice.
- Reserve collision-safe destinations before writing. Use the descriptive stem first, then a numeric suffix. At the final write, require atomic creation without overwriting; a destination occupied after reservation becomes that candidate's reported failure.
- Continue after an individual failure. Return a summary containing saved source URLs, output URLs, and per-source diagnostics. Only successful source URLs join `savedSourceURLs`.
- Record save state for every successful export role, but preserve the existing clear-warning population: only unsaved locked iterations trigger that warning. A source or unlocked candidate does not widen the warning in this feature.
- Retain the batch task and expose Cancel Save All while it is active. Cancellation reaches the current on-device pipeline, keeps outputs already written, attempts no remaining candidates, and reports the saved, failed, and unattempted counts. Unattempted candidates remain unsaved.
- Reuse the identified canvas progress badge for `Saving N of M`; expose `batchSaveProgress` with the same value. Show the final `batchSaveSummary` in the status and notice area with saved, failed, and unattempted counts. Expose `saveAllCommand`, `saveAllButton`, and `cancelSaveAllButton` identifiers and meaningful enabled or progress values.

### Save-directory validity

- Keep the existing resolved Downloads default and Settings field.
- Extend preference loading with an output-folder state that retains both the raw stored URL and the resolved operational fallback: default, valid configured, or stale configured. Keep the existing resolved Downloads fallback but do not discard evidence that it replaced a stored path.
- Validate the raw configured directory at the moment Save As or Save All begins, not only when preferences load.
- Save As falls back to resolved Downloads. After the modal panel closes, show the identified `outputFolderWarning` in the workspace notice area with an `openOutputFolderSettings` Settings link; the warning is not presented behind the panel.
- Save All does not redirect a batch silently; it reports the stale preference and writes nothing until Settings contains a writable directory.

### Filter narrowing

- Centralize category selection in one action that clears `search` before toggling the category.
- Preserve the existing focus-driven category clear without changing `search`.
- Retain accessibility state on each chip so tests can prove that visible selection matches effective narrowing.

### Generation routing

- Keep `WorkspaceModel.generateRequest()` for an empty workspace and `WorkspaceModel.applyRequest()` for a populated workspace.
- Preserve the routing order in `MainView`: no base means reference-free generation; a populated workspace with an identical held result for the same base, model, and prompt-as-sent adopts that result with zero upload and zero provider request; every other populated workspace uploads exactly the base and uses edit.
- Keep `FalRequestBuilder` endpoint selection based on accepted reference count: zero uses `xai/grok-imagine-image`; one base reference uses `xai/grok-imagine-image/edit`.
- Add end-to-end GUI evidence that captures both reference-upload calls and the submitted request at the stubbed service seam. The blank route must record zero uploads and zero references. A populated route with no identical held result must record one upload of the base and one base reference. A repeated identical apply must record no additional upload or request. No metered provider is embedded in the suite.
- Treat provider success carrying an unreadable image as generation failure. Keep the prior graph intact and create neither a source nor candidate.
- Keep GUI completion helpers tied to the canvas's upscaled-rendering label and Lock availability. A current source check confirms `waitForUpscaleComplete` does not use Save As as its oracle; widening Save As therefore cannot satisfy the upscale wait early.

### Vulnerability gate

- Add `make vulncheck` as a separate, repeatable security target.
- Require a locally available Trivy executable; do not install it from the target.
- Require both the root and Xcode `Package.resolved` files. A missing lockfile fails closed and names the missing input.
- Scan each lockfile independently with Trivy's filesystem vulnerability scanner and name the input before each result. The two committed dependency sets may resolve different versions and do not need to be identical; both must scan successfully so neither the command-line nor Xcode application graph is hidden.
- Configure a non-zero exit for every finding and for scan or advisory-data failure. Add an exact exception file only if a human later approves a finding under the security standard; no blanket ignore is planned.
- Trivy officially parses Swift `Package.resolved` files, including transitive and development dependencies, during filesystem vulnerability scans.
- Invoke `make vulncheck` from both release and GUI-release flows immediately before their packaging or publication script, outside the behavioural `SKIP_TESTS` branch. A caller may attest prior regression tests but may not skip the current dependency-security gate.

## Complexity Tracking

No constitutional violation requires justification.
