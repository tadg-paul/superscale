# Superscale UX v2 Architecture

Superscale UX v2 extends the existing SwiftUI app with a GUI-only generation
workspace. The CLI remains focused on local upscaling and should not import the
generation layer.

## Current Shape

The repository currently has these relevant boundaries:

- `SuperscaleKit`: local upscaling pipeline, model registry, model downloads,
  Core ML execution, image processing, and face enhancement support.
- `Superscale`: CLI executable for local upscaling.
- `SuperscaleApp`: SwiftUI app built around `MainView` and `UpscaleViewModel`.

V2 should preserve those boundaries and add generation support beside the app,
not inside the CLI.

## Proposed Modules

The preferred target layout is:

- `SuperscaleKit`: unchanged public role for local processing.
- `FalGenerationKit`: FAL HTTP client, model registry, pricing/account clients,
  request builders, response parsers, and test fixtures.
- `SuperscaleUXCore`: GUI-facing orchestration, prompt packs, session history,
  settings abstractions, and handoff into `SuperscaleKit`.
- `SuperscaleApp`: SwiftUI views, view models, menus, and platform integration.
- `Superscale`: existing CLI executable, with no dependency on
  `FalGenerationKit` or `SuperscaleUXCore`.

If Xcode project integration makes a separate Swift package target awkward, the
same boundary can be expressed as app groups first. The important rule is that
generation code stays GUI-only and independently testable.

## Runtime Flow

Text-to-image generation:

1. User enters a prompt or selects a prompt pack preset.
2. `GenerationViewModel` resolves the selected model and prompt options.
3. `GenerationCoordinator` asks `PricingService` for a cached or live estimate.
4. User starts generation.
5. `FalGenerationClient` posts to the resolved FAL endpoint.
6. The first generated image is downloaded into app-managed storage.
7. The generated image appears in the workspace and can be saved or upscaled.

Image-to-image generation:

1. User adds up to three reference images.
2. `ReferenceImageEncoder` prepares image data for the selected handler.
3. The model handler builds the correct edit payload.
4. The normal generation, download, history, and upscale flow continues.

Generation-to-upscale handoff:

1. Generated output is stored as an image file in app-managed storage.
2. The GUI passes that file into a public app processing coordinator.
3. `SuperscaleKit` runs the existing local pipeline.
4. The app displays generated and upscaled outputs with comparison controls.

The current `UpscaleViewModel` owns much of the app processing flow. V2 should
extract a small GUI-facing processing coordinator or expose a controlled method
so generated files can enter the same path as dropped files without duplicating
pipeline code.

## FAL Client Layer

The FAL layer should be a small Swift service modelled on the working behaviour
in `pix`.

Generation client responsibilities:

- build `https://fal.run/{endpoint}` requests;
- send `Authorization: Key <generation-key>`;
- support text-to-image and image-to-image/edit payloads;
- parse image URLs from FAL responses;
- download generated assets;
- redact secrets in diagnostics.

Pricing client responsibilities:

- fetch live unit pricing for a model endpoint;
- request historical price estimates for specific payloads when supported;
- cache responses for the session;
- surface "price unavailable" without blocking generation.

Account client responsibilities:

- use a separate account/admin key;
- show balance, recent usage, and billing events when authorized;
- treat account-key failure as non-fatal for generation;
- clearly identify scope errors without leaking key material.

## Model Registry

Model metadata should be data-driven. The initial registry should include the
FAL image models needed for `pix` parity, with `xai/grok-imagine-image` as the
default candidate unless product testing chooses another default.

Each model entry should describe:

- user-facing name;
- endpoint ID;
- supported modes, such as text-to-image and image-to-image;
- accepted aspect ratios or image sizes;
- output formats;
- required and optional payload fields;
- edit sibling endpoint, when applicable;
- pricing support status;
- warnings for unsupported options.

The handler strategy used in `storyboard-gen` is the right pattern for model
families. Views should not know how to construct provider-specific payloads.

## Prompt Packs

Prompt packs provide the pre-canned AI filters. They should be repo assets or
bundled app resources with stable identifiers, names, descriptions, model
preferences, and prompt templates.

The prompt system should support:

- user-entered prompt text;
- preset prompts;
- optional prompt modifiers;
- reference-image requirements;
- model compatibility warnings;
- later user-defined prompt packs.

Prompt packs should not hard-code paid generation assumptions. The selected
model and pricing service should still determine the final cost estimate.

## Secrets And Settings

The GUI should store secrets in Keychain:

- FAL generation key;
- FAL account/admin key.

Import from `pix` configuration may be offered as a convenience, but the GUI
should not execute arbitrary shell commands from `pix` config. If `pix` resolves
keys through command entries, the GUI should ask the user to paste or choose the
key instead.

Non-secret settings can live in app preferences:

- default generation model;
- default upscale model;
- output directory;
- prompt pack selection;
- whether to show cost confirmations;
- session history retention.

## Storage

The app should keep generated and processed assets in app-managed storage before
the user saves final files. Session records should include:

- source prompt;
- selected model and endpoint;
- generated file URL;
- upscaled file URL, if any;
- reference images;
- cost estimate, if available;
- timestamp;
- non-secret request diagnostics.

This history enables comparison, retry, and auditability without logging API
keys or full account data.

## UX Structure

The main window should gain mode-level navigation rather than overloading the
existing upscaling toolbar.

Recommended top-level modes:

- Upscale: the current local workflow.
- Generate: prompt, prompt pack, model, references, cost, and output.
- History: prior generated and processed assets.
- Settings: API keys, defaults, prompt packs, and account state.

Generated images should be able to move into Upscale with one action. Upscale
results should also remain saveable through the existing save flow.

## Error Handling

Errors should be classified by source:

- missing generation key;
- missing or unauthorized account key;
- model endpoint unavailable;
- unsupported payload field;
- network failure;
- paid generation failure;
- download failure;
- local upscaling failure.

The app should show actionable user-facing errors and keep more detailed
diagnostics available for issue reports. Secrets must be redacted.

## Testing Strategy

Automated tests should not call paid FAL endpoints.

Recommended coverage:

- FAL request construction with `URLProtocol` or local HTTP fixtures;
- parsing successful and failed FAL responses;
- pricing and account response parsing;
- model registry resolution;
- handler payload construction;
- prompt pack loading and compatibility warnings;
- Keychain abstraction using test storage;
- generation coordinator cancellation and retry paths;
- GUI smoke tests for Generate, Upscale, Settings, and History paths.

Manual release checks should include one real FAL text-to-image generation, one
image-to-image generation, one pricing/account display check, and one generated
image upscaled locally.
