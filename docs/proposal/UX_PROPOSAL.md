# Pix UX Proposal

## Summary

Build the graphical pix experience inside the existing Superscale SwiftUI app, not as a Go GUI and not as a wholly independent first version.

The product should become a Mac-native image workspace:

1. Pick a canned prompt/filter with one click.
2. Generate or transform through a fast, cheap FAL model, defaulting to `xai/grok-imagine-image`.
3. Show the returned image as soon as the API response is available.
4. Offer immediate local enhancement through Superscale's Apple Silicon CoreML pipeline.
5. Preserve `pix` as the fast CLI and scripting surface.

This keeps the high-value local inference path where it already works: SwiftUI + SuperscaleKit + CoreML/Vision. The FAL generation layer is mostly HTTP, JSON, prompt state, and image display; that is straightforward to reimplement natively in Swift and does not justify embedding or driving a Go binary from the GUI.

## Recommendation

Use Superscale as the host application and add pix-style generation as a new workflow in the SwiftUI app.

Recommended project shape:

| Layer | Location | Technology | Purpose |
|---|---|---|---|
| CLI generation | `pix` repo | Go | Scriptable prompt-to-image, account/cost commands, regression-tested FAL behaviour |
| Native GUI host | `superscale` repo | SwiftUI | Mac image workspace and user-facing interactive UX |
| Local enhancement | `SuperscaleKit` | Swift + CoreML + Vision | Existing Apple Silicon upscaling, tiling, model cache, face enhancement |
| Remote generation module | new `FalGenerationKit` or `PixGenerationKit` in `superscale` | Swift + URLSession | FAL models, prompt filters, generation requests, account/cost display |
| Shared knowledge | docs and fixtures, not shared runtime code | Markdown/JSON/YAML | Endpoint mappings, prompt-pack format, default model policy |

Do not merge the repos yet. The repos have different strengths:

- `pix` is a small Go CLI with simple install, scriptability, and HTTP regression tests.
- `superscale` is a native Mac app with the GUI, CoreML, model cache, and image-processing pipeline.

Merging now would couple two release cadences and force either the CLI to absorb Swift app complexity or the app to carry Go build/runtime concerns. The better first step is a product integration inside Superscale, with `pix` remaining as the command-line companion.

## Why Not Build The UX On Pix?

Building on `pix` directly means one of these:

1. Add a web UI around the Go binary.
2. Add a desktop UI framework to the Go app.
3. Drive `pix` as a subprocess from SwiftUI.

All three are weaker than a native Superscale integration.

A web UI would be portable, but it would not naturally integrate with Superscale's native image pipeline, Keychain, drag-and-drop, save panels, comparison views, or CoreML progress model. A Go desktop framework would add a second GUI stack while still needing native bridges for the Superscale value-add. A subprocess bridge would be useful for prototyping but poor as the long-term product architecture: process boundaries make progress, cancellation, streaming state, errors, account display, and image handoff more awkward than direct Swift services.

Keep `pix` as the CLI. Reuse its behaviour and tests as a reference, not its binary as the GUI engine.

## Why Build In Superscale?

Superscale already has the pieces the UX needs:

- SwiftUI app shell with toolbar, image display, comparison view, drag-and-drop, progress overlay, save flow, and error presentation.
- `UpscaleViewModel` with async processing state, result image state, and reprocessing behaviour.
- `SuperscaleKit.Pipeline`, which already exposes a programmatic `process(input:output:)` API.
- Native Apple Silicon acceleration through CoreML/Vision.
- A product story that is stronger when generation and upscaling are together: cheap remote generation followed by fast local enhancement.

The new workflow can reuse these patterns rather than recreating them elsewhere.

## Proposed UX

Add a generation workspace to Superscale:

- A top-level segmented control or sidebar mode: `Generate`, `Upscale`, `Compare`.
- A prompt/filter strip with clickable canned prompt categories, for example `Portrait`, `Product`, `Concept`, `Poster`, `Photo`, `Texture`, `Repair`, `Stylize`.
- A prompt text area that is populated or amended by the selected canned prompt.
- A compact model selector defaulting to `xai/grok-imagine-image`, with cost shown near the model.
- A generate button with progress state and cancel support.
- A result canvas that displays the generated image immediately when FAL returns it.
- One-click actions: `Upscale`, `Enhance Faces`, `Compare`, `Save As`, `Use As Reference`.

Suggested first-screen layout:

```text
┌──────────────────────────────────────────────────────────────────────┐
│ Generate | Upscale | Compare       Model: Grok Imagine  Cost: $0.02 │
├──────────────────────────────────────────────────────────────────────┤
│ Portrait  Product  Poster  Photo  Texture  Repair  Stylize          │
│                                                                      │
│ Prompt editor                                                        │
│ [selected canned prompt + user text]                                 │
│                                                                      │
│ [Generate] [Use reference image...]                                  │
├──────────────────────────────────────────────────────────────────────┤
│ Generated image / progress / comparison result                       │
└──────────────────────────────────────────────────────────────────────┘
```

The app should feel like an image tool, not a prompt-chat app. Prompt controls should be dense and direct; the image canvas should dominate.

## Canned Prompt Filters

Treat "filters" as prompt presets with metadata, not as hard-coded UI labels.

Recommended prompt-pack format:

```yaml
id: product-hero
label: Product
category: image
mode: text-to-image
model_hint: xai/grok-imagine-image
prompt: |
  Clean product photography, controlled studio lighting, high detail,
  neutral background, crisp edges.
negative_prompt: |
  blurry, warped text, extra objects
```

The GUI should load these from a prompt-pack directory and render each item as a clickable chip. Selecting a chip should update the prompt editor but not immediately call the API unless an explicit "generate on click" preference is enabled. This avoids accidental paid calls while still keeping the interaction fast.

`pix` can later learn the same prompt-pack format for CLI parity, but the GUI should not depend on the current `fzf` saved-prompt flow. The current pix flow is terminal-oriented; the GUI needs structured metadata, labels, categories, model hints, and thumbnails/history.

## Default Model

Default to `xai/grok-imagine-image` for the first GUI iteration because it matches the current pix config and the user's requirement for something fast and cheap.

The default should still be configurable:

- Global default model in app settings.
- Per-prompt `model_hint`.
- Last-used model persisted per workflow.
- Cost display before generation, matching pix's model-cost behaviour.

The app should not hard-code "cheap" as a permanent truth. Pricing changes. The GUI should display current model cost when available and allow the default to move later.

## Technical Design

### Swift Modules

Add a new Swift module in the Superscale package:

```text
Sources/
├── SuperscaleKit/          # existing local upscaling
├── PixGenerationKit/       # new FAL generation/account/prompt services
├── Superscale/             # existing CLI
└── SuperscaleApp/          # existing SwiftUI app
```

`PixGenerationKit` should contain:

| Type | Responsibility |
|---|---|
| `FalGenerationClient` | `URLSession` calls to `https://fal.run/{endpoint}` and image download |
| `FalModelClient` | model catalogue and pricing endpoints |
| `FalAccountClient` | optional balance/usage/billing event calls |
| `PromptPackStore` | load structured canned prompts |
| `GenerationRequest` | prompt, model, reference images, output format, dimensions |
| `GenerationResult` | returned image URL/data, model, cost, request id if available |
| `GenerationViewModel` | SwiftUI state, progress, cancellation, selected prompt/model/result |

This mirrors pix's current concerns without importing Go into the app.

### SwiftUI Integration

Add generation state beside the existing `UpscaleViewModel`, rather than overloading it immediately.

Recommended app-level state:

```swift
@StateObject private var generationViewModel = GenerationViewModel()
@StateObject private var upscaleViewModel = UpscaleViewModel()
```

The generated image handoff should be file-backed:

1. FAL returns an image URL or image bytes.
2. `GenerationViewModel` downloads it to a temporary image file and displays it as `NSImage`.
3. "Upscale" passes that temporary URL into `UpscaleViewModel.processImage(url:)` or a public wrapper around it.
4. SuperscaleKit writes the enhanced result to a second temporary file.
5. Save/export uses the existing save-panel pattern.

File-backed handoff keeps metadata, format, and existing pipeline APIs simple.

### Authentication

Do not require GUI users to edit `~/.config/pix/config.yaml`.

Recommended order:

1. Keychain-stored FAL generation key.
2. Keychain-stored FAL account/admin key.
3. Optional import from existing pix config for migration.
4. Environment variables only for development/debug builds.

For command-based secret retrieval, the GUI can support import rather than live execution. Running arbitrary configured shell commands from a sandboxed GUI is a different security and UX trade-off than doing so in a CLI.

### Account And Cost Display

Bring the useful parts of pix issue #19 into the GUI:

- Show model unit price near the model selector.
- Show estimated cost before generation when available.
- Show remaining account balance after successful generation if an account key is configured.
- Keep account/admin key separate from generation key.
- Make account failures non-fatal after successful image generation.

The GUI does not need to expose every `pix account` table view in the first iteration. A compact balance and recent-spend panel is enough.

### Reference Images And Transformations

Support both text-to-image and image-to-image:

- Drag an image into the generation workspace as a reference.
- Let prompt chips declare whether they are `text-to-image`, `image-to-image`, or both.
- Use FAL model catalogue categories the same way pix does: text prompts use `text-to-image`, reference workflows use `image-to-image`.
- Allow a generated image to become the next reference image for iteration.

This is where the pix workflow and Superscale workflow become a single creative loop.

## Options Considered

### Option A: Build The UX In Pix

**Stack:** Go backend plus webview/native wrapper.

Pros:

- Direct reuse of existing pix HTTP code.
- Pix CLI and GUI behaviour remain in one repo.
- Easier to share config and prompt loading.

Cons:

- Weak integration with Superscale's SwiftUI/CoreML pipeline.
- Adds a second GUI stack.
- Harder native Mac polish.
- Eventually still needs Swift/AppKit bridging for the strongest local-inference value.

Recommendation: do not choose this for the main UX.

### Option B: Extend Superscale

**Stack:** SwiftUI + `SuperscaleKit` + new Swift FAL generation module.

Pros:

- Best native Mac UX.
- Direct access to CoreML, Vision, AppKit, Keychain, drag-and-drop, and save panels.
- Existing app already displays images and handles long-running image processing.
- Strongest product positioning: remote cheap generation plus local high-quality enhancement.

Cons:

- FAL client behaviour must be ported from Go to Swift.
- Some duplication with pix's HTTP/account/pricing logic.
- Superscale's product identity broadens from "upscaler" to "image workspace".

Recommendation: choose this.

### Option C: Independent New Project

**Stack:** SwiftUI app, depending on SuperscaleKit as a package and implementing FAL generation separately.

Pros:

- Clean product boundary.
- Avoids overloading Superscale's existing UX.
- Could still use SuperscaleKit directly.

Cons:

- More release, packaging, signing, docs, and support surface.
- The value-add still depends on Superscale, so separation may be artificial.
- Requires making SuperscaleKit easy to consume externally before the product has proven itself.

Recommendation: defer. This may become right if the generation UX grows into a distinct product.

## Migration And Reuse Plan

Keep pix and Superscale separate at first, but align them deliberately.

1. Define prompt-pack schema in docs and implement it in the Superscale GUI.
2. Port the minimal FAL generation/pricing/account client behaviour from pix into Swift.
3. Add GUI settings for FAL keys, default model, prompt-pack path, and account-balance display.
4. Add one-click handoff from generated result to SuperscaleKit upscale.
5. Later, teach pix CLI to read the same prompt-pack format.
6. Later, extract shared prompt packs into a small data repo or package if both tools actively use them.

Do not try to share runtime code between Go and Swift. Share API contracts, fixtures, prompt packs, and behaviour tests where useful.

## Implementation Phases

### Phase 1: Prototype In Superscale

- Add `PixGenerationKit` with a minimal FAL generation client.
- Add Keychain-backed generation key setting.
- Add `Generate` view with prompt chips, prompt editor, model default, and result image display.
- Default model: `xai/grok-imagine-image`.
- No account view yet; just generate and display.

### Phase 2: Prompt Packs And Cost

- Add structured prompt-pack loading.
- Add model price lookup and display.
- Add account balance after generation when account key is present.
- Add generation history for the current app session.

### Phase 3: Superscale Handoff

- Add "Upscale generated image" action.
- Reuse `SuperscaleKit.Pipeline` through the existing view model or a new shared processing coordinator.
- Show before/after compare using the existing comparison UI.
- Preserve generated original and upscaled result for save/export.

### Phase 4: Reference Workflows

- Add reference-image drop zone for image-to-image transforms.
- Allow generated images to become references.
- Add prompt chips for transformations such as repair, relight, stylize, and product cleanup.

### Phase 5: CLI Parity

- Add prompt-pack support to pix.
- Keep `pix gen` as the scriptable interface to the same prompt/filter vocabulary.
- Keep account and cost behaviour aligned with GUI terminology.

## Open Decisions

- Product name: keep "Superscale" and add a Generate mode, or rename the GUI to a broader image-workspace name.
- Prompt-pack storage: app bundle defaults plus user directory, or user directory only.
- Whether generation should require an explicit button press after chip selection, or support an opt-in "generate on click" mode.
- Whether generated images are stored in app history by default or only in temporary storage until saved.
- Whether account/billing panels belong in the first GUI release.
- Whether to publish `SuperscaleKit` as a stable external library later.

## Risks

| Risk | Mitigation |
|---|---|
| Superscale product scope becomes too broad | Keep first UI as a separate `Generate` mode and preserve the existing upscale workflow |
| Go and Swift FAL clients drift | Treat pix as reference behaviour; add Swift tests with local HTTP stubs matching pix cases |
| GUI accidentally causes paid API calls | Require explicit Generate click by default; show model/cost before generation |
| Account/admin key sensitivity | Store in Keychain; keep generation and account keys separate |
| FAL model/pricing changes | Fetch live catalogue/pricing; make defaults configurable |
| Temporary image handoff loses metadata | Save downloaded/generated image to a real temp file with known format before SuperscaleKit processing |

## Final Recommendation

Build the UX in Superscale, using SwiftUI and a new Swift FAL generation module. Keep pix as the CLI and behavioural reference.

This gives the best user-facing product: fast/cheap remote generation where that makes sense, followed immediately by native Apple Silicon upscaling where Superscale already has a real advantage. It also avoids forcing a Go CLI to become a Mac GUI framework or forcing a SwiftUI app to shell out to a CLI for core product actions.
