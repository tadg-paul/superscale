<!-- Version: 1.1 | Last updated: 2026-08-25 -->

# Superscale v2 End-to-End Design

> **Status (2026-08-25): historical design artefact, superseded in part.**
> This document predates the delivered MVP and is retained as the record of
> the journeys the design started from. What shipped differs materially: there
> are **no peer modes** --- Generate, History and mode navigation were removed
> by #87 in favour of one workspace (guide section 3.9, architecture "UX
> Structure") --- **text-to-image is excluded** from the MVP, and **live
> pricing is paused** in favour of grok's documented flat rate. Where this
> document and `IMPLEMENTATION_GUIDE_v2.md` disagree, the guide is the design
> of record; the criteria that bind are in `ACs.org`. Nothing here has been
> rewritten to match the build, deliberately: the deltas are themselves the
> record of what user contact changed.

This document defines the end-to-end interaction model for Superscale v2. Its
wireframes are intentionally low fidelity: they establish user journeys,
information architecture and workflow boundaries while leaving visual detail
open for iterative design.

## Product Boundary

Superscale is the native GUI and local-upscaling product. Cloud generation and
transformation are implemented directly in Swift against provider APIs. Pix
remains the companion CLI for scripted generation and transformations beyond
upscaling; Superscale does not execute Pix at runtime.

## End-to-End Journeys

### Local Upscale

1. An image is dropped, pasted or selected in Upscale.
2. The app resolves the local model and scale.
3. Processing runs through the existing Core ML pipeline.
4. The result can be compared, revealed or saved.

### Text-To-Image

1. Generate opens with the default model and optional prompt pack.
2. The user enters or adapts a prompt.
3. The app shows model identity, price state and relevant warnings.
4. Generation runs through the native Swift FAL client.
5. The downloaded image and session details become available together.
6. The result can be saved, retried, revealed or sent to Upscale.

### Reference-Image Transformation

1. Up to three reference images are added to Generate.
2. The selected model or handler explains incompatible options before payment.
3. The app submits the references and prompt through the model's edit path.
4. The resulting image follows the same output, history and upscale flow as a
   text-generated image.

### Generate-To-Upscale

1. A generated result is sent to Upscale with one action.
2. The same local coordinator used by dropped files processes the image.
3. The upscaled asset remains linked to its originating generation session.
4. The user can compare and save the final result without managing temporary
   files.

### History Recovery

1. History exposes generated, upscaled, failed and cancelled sessions.
2. Search and status filters narrow the session list.
3. Selection reveals safe metadata, outputs and available actions.
4. A prior session can return to Generate or send an available image to Upscale.

### Credentials And Degraded Cloud State

1. Settings manages generation and account-administration keys independently.
2. Missing generation credentials block paid generation with a path to Settings.
3. Missing or unauthorized account credentials affect account visibility only.
4. Unavailable pricing remains visible and follows the configured confirmation
   policy rather than silently presenting an estimate.

## Design Direction

Use one main Mac window with mode-level navigation. The app should not become a
landing page or a wizard. Users should always feel they are inside a working
image workspace.

Top-level modes:

- Upscale: existing local Superscale workflow.
- Generate: prompt, prompt packs, FAL model, references, cost, and output.
- History: prior generated and upscaled sessions.
- Settings: API keys, defaults, account state, prompt packs.

Generated images should move into local upscaling with one action.

## Main Window Shell

```text
+--------------------------------------------------------------------------------+
| Superscale                                                 [account] [settings] |
+------------+-------------------------------------------------------------------+
| Upscale    |  Mode toolbar                                                     |
| Generate   |  ---------------------------------------------------------------  |
| History    |                                                                   |
| Settings   |  Current mode content                                             |
|            |                                                                   |
|            |                                                                   |
|            |                                                                   |
|            |                                                                   |
|            |                                                                   |
+------------+-------------------------------------------------------------------+
| Status: ready | model/pricing messages | last output path                         |
+--------------------------------------------------------------------------------+
```

Notes:

- A sidebar is preferable to adding more controls to the current toolbar.
- Status remains visible so generation, pricing, and local processing errors do
  not need to dominate the canvas.
- The existing Upscale workflow can occupy the content area mostly unchanged.

## Generate Mode

```text
+--------------------------------------------------------------------------------+
| Generate                                      Model: Grok Imagine        $0.02? |
+--------------------------------------------------------------------------------+
| Prompt pack        | Prompt                                                    |
| [Portrait v]       | +------------------------------------------------------+  |
|                    | | A cinematic product photo of...                     |  |
| Filter options     | |                                                      |  |
| [ ] Preserve face  | +------------------------------------------------------+  |
| [ ] High detail    |                                                          |
|                    | Reference images                                          |
| Aspect             | +-------------+ +-------------+ +-------------+            |
| [1:1 v]            | | drop image  | | drop image  | | drop image  |            |
|                    | +-------------+ +-------------+ +-------------+            |
|                    |                                                          |
|                    | [Estimate cost] [Generate] [Cancel]                      |
+--------------------------------------------------------------------------------+
| Output preview                                                                  |
| +--------------------------------------------------+  +-----------------------+ |
| |                                                  |  | Session details       | |
| | generated image                                  |  | prompt pack           | |
| |                                                  |  | model endpoint        | |
| |                                                  |  | estimate / actual     | |
| +--------------------------------------------------+  | warnings              | |
|                                                       +-----------------------+ |
| [Send to Upscale] [Save As...] [Retry] [Reveal]                                |
+--------------------------------------------------------------------------------+
```

Notes:

- Cost is close to the Generate action, not hidden in Settings.
- Reference wells make image-to-image obvious without requiring a separate mode.
- Prompt packs sit beside prompt text because they alter intent, not output
  handling.
- The generated output is first-class, but local upscaling is one click away.

## Upscale Mode

```text
+--------------------------------------------------------------------------------+
| Upscale                  Model: Real-ESRGAN 4x+        Scale: 4x    [Face] [?] |
+--------------------------------------------------------------------------------+
|                                                                                |
|                 Drop an image, choose a generated image, or paste               |
|                                                                                |
|        +----------------------------------------------------------------+      |
|        |                                                                |      |
|        |                       image preview                            |      |
|        |                                                                |      |
|        +----------------------------------------------------------------+      |
|                                                                                |
| [Compare] [Save As...] [Reveal]                                                |
+--------------------------------------------------------------------------------+
```

Notes:

- This should preserve the current upscaling behaviour.
- Generated images enter through the same processing coordinator as dropped
  files.
- Face enhancement keeps the existing noncommercial-license acceptance flow.

## History Mode

```text
+--------------------------------------------------------------------------------+
| History                         [All] [Generated] [Upscaled]        [Search]   |
+--------------------------------------------------------------------------------+
| +---------------------+ +---------------------+ +---------------------+        |
| | thumbnail           | | thumbnail           | | thumbnail           |        |
| | Grok Imagine        | | Grok Imagine Edit   | | Local upscale       |        |
| | today 14:05         | | today 13:48         | | yesterday 18:12     |        |
| | $0.02 estimate      | | price unavailable   | | Real-ESRGAN 4x+     |        |
| +---------------------+ +---------------------+ +---------------------+        |
|                                                                                |
| Selected session                                                                |
| +-------------------------------------+ +------------------------------------+ |
| | image                               | | prompt / model / references       | |
| |                                     | | estimate / warnings / file paths  | |
| +-------------------------------------+ +------------------------------------+ |
| [Open in Generate] [Send to Upscale] [Save As...] [Reveal]                     |
+--------------------------------------------------------------------------------+
```

Notes:

- History is not a DAM. It is a session recovery and audit surface.
- Metadata must redact secrets.
- Failed and cancelled attempts may be useful if they include safe diagnostics.

## Settings Mode

```text
+--------------------------------------------------------------------------------+
| Settings                                                                       |
+--------------------------------------------------------------------------------+
| FAL                                                                            |
| Generation key        [************************] [Update] [Test]               |
| Account/admin key     [************************] [Update] [Test]               |
| Account state         Balance available / usage unavailable                    |
|                                                                                |
| Defaults                                                                       |
| Generation model      [xai/grok-imagine-image v]                              |
| Upscale model         [Auto v]                                                 |
| Output folder         [~/Pictures/Superscale v] [Choose]                      |
| Cost confirmation     [Above threshold v] [0.05]                              |
|                                                                                |
| Prompt packs                                                                   |
| [Bundled packs] [Import pack...]                                               |
+--------------------------------------------------------------------------------+
```

Notes:

- Generation and account keys are separate controls.
- Account failure should not block generation-key validation.
- ~~Pix configuration import and command-resolver handling.~~ Removed from v2
  scope; credentials and defaults are entered directly in Settings.

## First Ticket Batch Implications

The first implementation batch should build toward these visible UX paths:

- app shell with mode navigation;
- Generate mode without paid network calls, backed by fixtures;
- Settings key-management screen with test storage;
- prompt-pack loading and model selection;
- generated-file handoff into existing local upscale flow;
- History mode backed by plain files and JSON metadata.

Anything outside those paths should be deferred unless it blocks the core
workflow.

## Human Design Validation

The MVP presentation should place each journey in a representative, ready-to-
inspect state. Human review determines whether:

- navigation presents one coherent image workspace;
- generation controls communicate intent, references, model and cost clearly;
- output actions make the local-upscale handoff obvious;
- History supports recovery without resembling a full asset manager;
- Settings distinguishes credential roles and defaults;
- warnings and degraded cloud states are understandable without being alarmist;
- the structure is suitable for iterative visual and interaction design.

## Changelog

- **1.0 (2026-08-05):** Promoted the v2 wireframes and added canonical
  end-to-end journeys, product boundaries and human-validation outcomes.
