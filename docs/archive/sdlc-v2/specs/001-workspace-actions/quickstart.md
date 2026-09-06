# Validation Quickstart: Reliable Workspace Actions

## Prerequisites

- macOS 14 or later on Apple Silicon.
- Xcode and Swift toolchain compatible with the repository.
- Repository models already provisioned through the existing project workflow.
- Trivy available locally for the separate vulnerability gate.
- No FAL credential is required for automated tests; GUI generation uses the controlled local substitute.

## Package Regression Suite

Run the maintained package suite:

```bash
make test
```

Expected outcome: all package tests pass, including export population, filename collision, save-state, preference validation, and generation-route coverage.

## GUI Regression Suite

Run the maintained macOS GUI suite:

```bash
make test-gui
```

Expected outcome:

- `Cmd+C` copies the displayed test image to the pasteboard.
- `Cmd+V` imports the seeded clipboard image only on the blank canvas.
- Text copy and paste remain native inside prompt, search, settings, and system-panel fields.
- `Cmd+S` opens Save As when scaling is off as well as when an upscale exists.
- `Cmd+S` opens Save As while prompt, search, or Settings text has focus; an active system panel does not open a nested panel.
- A stale configured folder remains identifiable: Save As falls back then shows the Settings route, while Save All writes nothing.
- One Save All action writes the exact active-workspace population, including a promoted minimum-resolution raise, to the configured test directory; cancellation preserves completed files and leaves the remainder unattempted.
- While Save All runs, New, Open, Open Recent, canvas Clear Image, drag and drop, picture Paste, Save As, Apply, Lock, iteration selection, the base-versus-candidate display toggle, scale, model, face, and repeated Save All remain disabled and are not replayed after completion.
- Custom sizing is recalculated against each source's aspect ratio and per-image limits.
- Scaled batch outputs are produced directly and do not reuse the display rendering cache.
- A destination created after name reservation is not overwritten and is reported as that item's failure.
- Choosing a category clears the search field; focusing search clears the category while preserving query text.
- The blank-canvas Apply journey records zero uploads and zero references; a populated-canvas journey without a matching held result records one base upload and the base reference; repeated identical Apply records no additional upload or request.
- A provider success response with unreadable image data reports failure and creates neither a source nor a candidate.
- Existing progress, unsaved-warning, `Cmd+N`, scale, face, lock-chain, and filter-search regressions still pass.
- The clear warning remains scoped to locked iterations after Save All bookkeeping.
- Upscale completion remains identified from canvas rendering state, and filter completion from Lock availability; Save As state is not used as either oracle.

## Vulnerability Gate

Run the application dependency scan separately from behavioural tests:

```bash
make vulncheck
```

Expected outcome: Trivy reports the root package lock and Xcode application lock as separate committed inputs and exits successfully only when both scans are complete and no non-exempt vulnerability is found. The locks may contain different resolved versions. A missing lock, missing scanner, or unavailable advisory data is a gate failure, not a skipped pass.

## Human Validation

After automated gates pass, use the built application for the judgement-dependent checks recorded in `validation.md`:

- Paste a copied Superscale image into a different Mac application.
- Confirm Save As opens in the configured directory and Save All needs one action.
- Confirm Settings makes the default directory understandable and changeable.
- If a live provider check is authorized, generate once from a blank canvas and edit once with a loaded base. Record the bounded calls; do not add them to any repeatable suite.
