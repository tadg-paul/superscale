# Superscale UX v2 Wireframes

These wireframes describe the first-pass v2 GUI shape before implementation.
They are intentionally low fidelity: the goal is to settle layout, navigation,
and workflow boundaries before writing SwiftUI.

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
|                                                                                |
| Pix import                                                                      |
| [Import readable pix settings]                                                 |
| Shell command key resolvers are not executed by the GUI.                       |
+--------------------------------------------------------------------------------+
```

Notes:

- Generation and account keys are separate controls.
- Account failure should not block generation-key validation.
- The UI should explicitly avoid executing command-based key resolvers imported
  from `pix` config.

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
