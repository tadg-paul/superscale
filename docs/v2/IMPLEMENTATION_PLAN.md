# Superscale UX v2 Implementation Plan

This plan describes how to build the Superscale GUI into a v2 image generation
and upscaling workspace. It does not add image generation to the `superscale`
CLI.

## Recommendation

Build v2 inside the existing repository and app, with stronger internal target
boundaries. Do not split the CLI and GUI into separate projects yet.

The split that matters now is dependency direction:

- the CLI can continue depending on `SuperscaleKit`;
- the GUI can depend on `SuperscaleKit` plus new generation and UX services;
- generation services must not become a dependency of the CLI.

Revisit a repository or product split after v2 only if GUI release cadence,
distribution, entitlements, or support needs materially diverge from the CLI.

## Phase 0: Product And Boundary Confirmation

- Confirm that v2 scope applies to the Superscale GUI only.
- Keep the existing CLI contract focused on local upscaling.
- Decide whether new generation services are Swift package targets or Xcode app
  groups with test targets.
- Define the initial default generation model and fallback policy.
- Choose the initial set of prompt packs and reference-image workflows.

Deliverables:

- updated v2 docs;
- dependency boundary decision;
- first cut of model and prompt-pack inventory.

## Phase 1: Prepare The Existing App For Handoff

- Extract or expose a GUI-safe processing coordinator around the existing
  upscaling path.
- Ensure dropped files and generated files can enter the same local pipeline.
- Preserve current Upscale behaviour and wording except where v2 UI explicitly
  adds new modes.
- Keep `SuperscaleKit` as the local processing layer.

Validation:

- existing CLI tests continue to pass;
- current GUI drag-and-drop upscaling still works;
- generated-file handoff can be tested with a local fixture image before FAL is
  integrated.

## Phase 2: Add FAL Generation Core

- Port the proven FAL generation semantics from `pix` into Swift.
- Add endpoint resolution, request construction, response parsing, and image
  download services.
- Support text-to-image first.
- Add image-to-image/edit request construction after the text path is stable.
- Redact secrets in all diagnostics.

Validation:

- local HTTP fixture tests for request method, URL, headers, and payload;
- response parsing tests for successful and failed FAL responses;
- no paid network calls in automated tests.

## Phase 3: Add Model Registry And Handlers

- Create a data-driven FAL model registry.
- Use handler strategies for model-family request differences.
- Include the `pix` feature set first, with `xai/grok-imagine-image` as the
  initial default candidate unless testing chooses otherwise.
- Pull model-family lessons from `storyboard-gen`, especially edit sibling
  handling and unsupported-option warnings.

Validation:

- model shorthand and endpoint resolution tests;
- handler payload tests for text and reference-image workflows;
- compatibility-warning tests for unsupported fields.

## Phase 4: Add Secrets, Settings, And Pix Import

- Store FAL generation and account keys in Keychain.
- Keep account/admin key separate from the generation key.
- Add settings for default generation model, output location, and cost prompts.
- Offer safe import from `pix` config where values can be read directly.
- Do not execute shell commands from imported `pix` config.

Validation:

- Keychain abstraction tests with an in-memory test store;
- settings persistence tests;
- import tests for supported `pix` config shapes;
- explicit tests that command-based key entries are not executed by the GUI.

## Phase 5: Build The Generate Workspace

- Add a Generate mode to the SwiftUI app.
- Provide prompt entry, prompt-pack selection, model selection, reference image
  wells, cost estimate, and generate/cancel controls.
- Show generation progress and downloaded output.
- Allow generated output to be sent directly into local upscaling.

Validation:

- GUI smoke test for the Generate screen;
- generation coordinator tests for start, cancel, success, and failure;
- manual fixture flow from generated image to local upscaling.

## Phase 6: Add Pricing And Account Visibility

- Port `pix` pricing and account behaviours into Swift services.
- Fetch live model pricing when available.
- Estimate payload cost when the provider supports it.
- Show balance and recent usage when an account/admin key is configured.
- Treat account failures as non-fatal for generation.

Validation:

- fixture tests for pricing and estimate responses;
- fixture tests for billing, usage, and billing-event responses;
- UI states for no key, unauthorized key, unavailable pricing, and valid
  account data.

## Phase 7: Add Prompt Packs And Filters

- Define bundled prompt packs for the pre-canned AI filters.
- Associate prompt packs with compatible models and reference requirements.
- Allow prompt packs to combine with user prompt text.
- Keep prompt packs editable as resources rather than compiled control flow.

Validation:

- prompt-pack loading tests;
- compatibility and missing-reference warning tests;
- manual review of generated payloads using dry-run-style diagnostics.

## Phase 8: Add History And Comparison

- Store generation sessions and local upscale results in app-managed storage.
- Add a History mode with generated, upscaled, and saved outputs.
- Preserve prompt, model, estimate, reference-image, and timestamp metadata.
- Reuse or extend the existing comparison UI for generated versus upscaled
  outputs.

Validation:

- session persistence tests;
- metadata redaction tests;
- GUI smoke test for opening a history item and sending it to Upscale.

## Phase 9: Release Hardening

- Confirm GUI packaging includes new resources and excludes secrets.
- Confirm release scripts distinguish CLI and GUI artefacts correctly.
- Add manual release checklist steps for one real FAL generation and one local
  upscale of generated output.
- Confirm the CLI remains generation-free.

Validation:

- `make test` for shared and CLI code;
- GUI build through the existing app release path;
- manual FAL smoke test outside CI;
- release artefact inspection for bundled prompt packs and absence of secrets.

## Risks And Mitigations

- FAL API drift: isolate endpoint and payload handling behind handlers and keep
  fixture tests close to known provider responses.
- Cost surprises: show estimates when available and allow cost confirmation
  before generation.
- Secret leakage: centralize key storage and diagnostic redaction.
- UI overload: use modes rather than adding generation controls to the current
  upscaling toolbar.
- CLI product drift: enforce dependency boundaries and keep generation out of
  the executable target.
- Reimplementing too much from adjacent projects: port behaviour and fixtures
  from `pix` and `storyboard-gen` before designing new abstractions.

## Open Decisions

- Whether `FalGenerationKit` should be a Swift package target immediately or an
  app-internal module first.
- Whether the first v2 release should support only FAL, or include a provider
  protocol shaped for later providers.
- Which prompt packs should ship by default.
- Whether history should be plain files plus JSON metadata or a small local
  database.
- Whether cost confirmation is always shown or only shown above a configurable
  threshold.
