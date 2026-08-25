<!-- Version: 2.1 | Last updated: 2026-08-25 -->

# Superscale v2 Vision

## Purpose

Superscale v2 is a native Mac image creation and enhancement workspace. It
combines cloud image generation and transformation with fast local Core ML
upscaling, so an image can move from prompt or reference material to a finished,
high-resolution output without leaving the app.

The SwiftUI app is the product experience. The `superscale` CLI remains a small,
reliable convenience tool for scripted local upscaling. It does not become a
second generation interface. Users who need scripted image generation or
transformations beyond upscaling are directed to the `pix` CLI.

The original product direction is retained in [the v1 vision](v1/VISION.md).

## Where the Build Stands Against This Vision

*Added 2026-08-25.* This document describes the **end state** and is not
rewritten as pieces land. The v2 MVP (master #79, delivered 2026-08-25)
realizes the transform-and-enhance core: one workspace, 86 bundled filters
applied through `xai/grok-imagine-image/edit` with the working image as the
single reference, the lock chain, and native local upscaling under an area
ceiling. Deliberately not yet built, and tracked in the guide's section 6
exclusions: text-to-image from a bare prompt, multiple references, live
pricing and account visibility (grok ships at a documented flat rate),
additional providers, and user-saved filters. Current status and the
remaining-work map live in `IMPLEMENTATION_GUIDE_v2.md` section 8.

## Product Thesis

Superscale already provides fast local Real-ESRGAN processing on Apple hardware.
Pix provides a proven set of cloud-generation behaviours: low-friction FAL
requests, prompt reuse, reference-image transformations, model pricing and
account visibility. Superscale v2 brings those strengths into one native visual
workflow.

The combined product allows a user to:

- create an image from a prompt or a bundled transformation;
- transform an existing image using one or more references;
- understand the selected model and likely cost before paid work begins;
- inspect the generated result and its session details;
- send the result directly into local upscaling;
- compare relevant source, generated and upscaled states;
- recover, retry and save work through lightweight session history.

This is a creative utility rather than a provider console. Provider endpoints,
payload differences and account mechanics remain available when needed, but do
not dominate ordinary image work.

## End-State Experience

The finished v2 product feels like a coherent native Mac workspace, not a
collection of separate tools or a web application in a wrapper.

### Create And Transform

- Generate images from free-form prompts and reusable prompt packs.
- Apply pre-canned AI transformations without requiring endpoint knowledge.
- Use reference images for edits, variations and guided generation.
- Select models through human-readable capabilities while retaining access to
  endpoint and diagnostic detail.
- Support FAL directly and allow later Google and Replicate integrations where
  they materially broaden the workflow.

### Enhance Locally

- Preserve the current drag-and-drop local upscaling workflow.
- Send generated or transformed images to the same local processing path with
  one action.
- Use Real-ESRGAN through Core ML on Apple hardware.
- Keep optional GFPGAN installation and non-commercial licence acceptance
  separate and explicit.
- Compare source, generated and enhanced images without managing temporary files
  manually.

### Organize And Reuse

- Retain useful prompts, references, model choices, costs and output metadata.
- Recover generated and upscaled outputs through lightweight history.
- Retry or adapt a previous session without reconstructing it from scratch.
- Support user-managed prompt packs after the bundled format and workflow are
  proven.

### Stay Cost-Aware

- Present price estimates near the action that incurs cost.
- Distinguish generation credentials from account-administration credentials.
- Show balance, recent usage and billing information when available.
- Degrade pricing and account visibility independently from generation.
- Require meaningful confirmation when cost exceeds a configured threshold or
  cannot be estimated reliably.

## Native Provider Integration

Superscale v2 implements provider calls directly in Swift. It does not execute,
embed or depend on Pix or Storyboard Gen at runtime.

The Swift provider layer:

- constructs authenticated FAL generation, edit, pricing and account requests;
- encodes text and reference-image payloads according to model capabilities;
- parses provider responses and downloads output assets;
- isolates model-family differences in handlers rather than SwiftUI views;
- redacts secrets from diagnostics and persisted session metadata;
- exposes asynchronous, cancellable operations to the GUI;
- remains testable with local fixtures and without paid network calls.

Pix remains the primary behavioural reference for FAL semantics. The provider
and handler structure in Storyboard Gen remains a reference for future Google
and Replicate support. Behaviour and lessons are ported into Swift; the adjacent
applications are not runtime components.

## Product Boundaries

The repository remains shared while product responsibilities remain clear:

- `SuperscaleKit` owns local image processing and model management.
- `SuperscaleApp` owns the native visual product.
- GUI-only Swift services own generation, pricing, account and session
  orchestration.
- `Superscale` remains the scriptable local-upscale CLI and does not import GUI
  generation services.

The CLI identifies Pix as the companion CLI for generation and transformations
beyond Superscale's upscaling function. This signpost does not create a runtime
dependency between the tools.

A repository or product split should be reconsidered only if GUI and CLI release
cadence, entitlements, distribution or support requirements materially diverge.

## MVP For Superscale v2

The MVP is the smallest release that demonstrates the combined product, supports
credible human validation and provides a stable basis for detailed interaction
design. It is not the full end state.

> **Superseded as written --- 2026-08-25.** This MVP definition predates the
> author's ruling of 2026-08-23 (#79, log entry L14) that redefined the MVP
> around one workspace, and the delivered MVP differs from the list below in
> exactly the ways "Where the Build Stands" describes: **no modes** (one
> workspace; Generate and History are not surfaces), **no text-to-image**,
> **one reference** (the working image), **no cost estimates or account
> visibility** (a documented flat rate instead). The list is retained as the
> record of what was planned before user contact reshaped it; the delivered
> scope is `IMPLEMENTATION_GUIDE_v2.md` sections 2 and 6 and the criteria in
> `ACs.md`.

### MVP Capabilities

- One native app shell with Upscale, Generate, History and Settings modes.
- Existing local upscaling remains available as the default reliable workflow.
- FAL is the only cloud provider exposed in the product.
- `xai/grok-imagine-image` is the default generation model.
- Text-to-image generation works through direct Swift HTTP integration.
- Image-to-image generation supports up to three reference images.
- Bundled prompt packs provide the initial pre-canned transformations.
- The selected model, estimated cost and relevant warnings are visible before
  generation.
- Generation and account-administration keys have separate Keychain-backed
  lifecycles.
- Account and pricing failures do not block generation when the generation key
  remains valid.
- Generated output can be saved, revealed, retried or sent directly to Upscale.
- Generated output and its local upscale remain associated in plain-file and
  JSON session history.
- History supports recovery and auditability without becoming a digital asset
  manager.
- The GUI release includes required prompt resources and excludes credentials,
  account data and local session artefacts.

### MVP Exclusions

- Google and Replicate provider UI or release claims.
- A general public provider-plugin architecture.
- Importing or executing Pix configuration.
- User-authored prompt-pack editing inside the app.
- Generation commands in the `superscale` CLI.
- Full digital asset management, collaboration or cloud synchronization.
- Paid provider calls in the automated regression suite.

### MVP Human Validation

The MVP is ready for product iteration when a human reviewer can inspect a
prepared app and determine that:

- the four modes form one understandable image workflow;
- Generate makes prompt packs, prompting, model choice, references, cost and
  output actions understandable without provider expertise;
- paid actions and unavailable pricing or account states are clear without being
  alarmist;
- a generated image moves naturally into the familiar local Upscale workflow;
- History makes recent work recoverable without suggesting a full asset manager;
- Settings makes the two credential roles and saved defaults understandable;
- FAL-only MVP wording does not imply that future providers already ship;
- the overall direction is coherent enough to refine through detailed design
  rather than another architecture reset.

Real-provider release validation additionally covers one text-to-image
generation, one reference-image transformation, one pricing or account-state
check and one generated image saved after local upscaling. These checks require
human credentials and may incur provider charges.

## Detailed Design Runway

Detailed design builds from the MVP rather than reopening settled product
boundaries. It refines:

- the visual hierarchy and information density of each workspace;
- transformation discovery and prompt-pack organization;
- model selection, compatibility guidance and advanced controls;
- reference-image roles, ordering and replacement;
- progress, cancellation, retry and provider-error recovery;
- comparison among source, generated and upscaled states;
- History retention, search and session reopening;
- user-authored prompt-pack workflows;
- provider expansion after FAL behaviour is stable;
- keyboard access, accessibility and native Mac interaction conventions.

The starting interaction model is recorded in
[the end-to-end design](E2E_DESIGN.md). The
[implementation guide](IMPLEMENTATION_GUIDE_v2.md) is the current design of
record and supersedes the earlier implementation plan; the
[architecture](ARCHITECTURE.md) is revised to follow it.

## Design Principles

- **Native first.** Use Swift, SwiftUI, Core ML, Keychain and Apple platform
  conventions where they fit the product.
- **Local advantage, explicit cloud.** Keep local processing fast and immediate;
  make paid cloud work visible, cancellable and cost-aware.
- **One workflow, clear boundaries.** Generation and upscaling feel connected
  without coupling the CLI to cloud services.
- **Progressive disclosure.** Keep ordinary creative work simple while making
  model, cost and diagnostic detail available when needed.
- **Reusable intent.** Treat prompt packs and session metadata as product data,
  not hard-coded view behaviour.
- **Safe by default.** Store secrets in Keychain, redact diagnostics and never
  package local account or session state.
- **Honest scope.** Present shipped capabilities accurately and label future
  provider directions as future work.

## Success Measures

- A new user understands where to upscale, generate, find prior work and
  configure credentials without reading setup instructions.
- A generated result reaches a saved local upscale without manual temporary file
  management.
- Cost and model identity are visible before paid generation begins.
- Local upscaling retains the speed and quality expectations established by v1.
- The CLI remains useful for scripting local upscaling and clearly points to Pix
  for broader scripted transformations.
- The MVP supplies enough observable behaviour for human UX validation and enough
  product clarity for detailed v2 design.

## Changelog

- **2.0 (2026-08-05):** Established the canonical v2 end state, MVP boundary,
  native FAL integration, CLI responsibility and detailed-design runway.
