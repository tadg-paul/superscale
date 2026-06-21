# Superscale UX v2 Vision

Superscale UX v2 is a Mac-native image creation and enhancement workspace built on
the existing Superscale app. It should combine fast cloud image generation with
local Apple-hardware upscaling, so a user can move from prompt or reference image
to enhanced output without leaving the app.

This vision applies to the Superscale GUI project only. The existing
`superscale` CLI remains an upscaling tool and should not grow image generation
features as part of this work.

## Planning Docs

- `docs/v2/ARCHITECTURE.org`: target module boundaries, runtime flows, and
  PlantUML diagrams.
- `docs/v2/WIREFRAMES.org`: low-fidelity UX shape for the first implementation
  batch.
- `docs/v2/IMPLEMENTATION_PLAN.md`: phased build plan and default decisions for
  tickets.

## Product Thesis

The current Superscale app is good at a narrow task: local image upscaling with
snappy Core ML inference on Apple hardware. The `pix` project is good at a
different task: low-friction FAL image generation, model pricing, account
visibility, prompt reuse, and reference-image flows.

Putting those capabilities into one GUI creates a stronger product than either
tool alone:

- generate or edit images through a fast, cheap default cloud model such as
  `xai/grok-imagine-image`;
- apply pre-canned AI filters without asking users to learn model endpoints or
  payload details;
- upscale and compare outputs locally through Superscale immediately after
  generation;
- keep model cost, account balance, and generation history visible enough for
  users to avoid surprise spend;
- preserve the CLI as a reliable automation surface rather than turning it into
  a second product.

## Target Experience

The v2 app should feel like a native Mac creative utility, not a web console in
a wrapper. The first screen should be an actual workspace with clear modes for
local upscaling and AI generation.

Core workflows:

- Drag in an image and upscale it locally, as today.
- Enter a prompt, choose a canned filter, and generate an image through FAL.
- Add one to three reference images and run image-to-image edits.
- See the selected model, estimated cost, and account state before paid work is
  launched.
- Send any generated image directly into the Superscale upscale path.
- Compare original, generated, and upscaled outputs without manually managing
  temporary files.
- Save final outputs with predictable filenames and metadata.

## Source Projects

The v2 design should reuse lessons from adjacent, working codebases rather than
inventing the FAL layer from scratch again.

`../pix` should be the primary behavioural reference for:

- default model selection;
- FAL generation request shape;
- FAL pricing and estimate calls;
- separate generation and account keys;
- reference-image handling;
- prompt file and prompt picker concepts;
- model shorthand and endpoint resolution;
- dry-run and payload inspection semantics for tests and diagnostics.

`../storyboard-gen` should be the primary architectural reference for:

- provider and model registry structure;
- handler strategies for model-family quirks;
- GUI worker isolation for long-running generation jobs;
- cost display patterns;
- warning users when a chosen model ignores unsupported fields;
- separating orchestration from provider-specific payload construction.

The Swift implementation should port behaviours and tests, not embed either
project at runtime.

## Scope

V2 should add:

- a generation workspace inside the Superscale GUI;
- FAL generation support with a configurable default model;
- model registry and model-family handlers for generation/edit payloads;
- prompt packs for canned filters;
- FAL pricing and account visibility;
- Keychain-backed API key management;
- optional import from existing `pix` configuration;
- direct handoff from generated image to local Superscale processing;
- session history for generated and processed images.

V2 should not add:

- generation commands to the `superscale` CLI;
- live shell execution from the GUI for resolving API keys;
- bundling or redistributing cloud-generated models;
- paid FAL calls in automated tests;
- a general multi-provider abstraction before FAL support is stable.

## Split Recommendation

Do not split the repository into separate CLI and GUI projects for v2.

The better boundary is internal:

- keep `SuperscaleKit` as the local image processing and model-management layer;
- keep `Superscale` as the CLI executable for local upscaling;
- add GUI-only generation services that are consumed by `SuperscaleApp`;
- prevent the CLI target from importing or exposing the generation layer.

This keeps release, licensing, and model-management work simpler while still
protecting the CLI from GUI product drift. A project split should be reconsidered
only if the GUI becomes a substantially broader creative suite with a different
release cadence, entitlement profile, or support model from the CLI.

## Design Principles

- Local-first where Superscale already has an advantage.
- Cloud generation is explicit, cost-aware, and cancellable.
- Secrets are stored in Keychain, not config files.
- The app imports useful configuration from `pix`, but does not depend on `pix`
  at runtime.
- Prompt packs should be editable assets, not hard-coded UI strings.
- Account-key failures should degrade account and cost features, not block image
  generation when the generation key is valid.
- Model-specific quirks should live in handlers, not scattered through views.
- The app should have enough diagnostics to explain failed generations without
  exposing secrets.
