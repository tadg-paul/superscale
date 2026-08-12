<!-- Version: 1.0 | Last updated: 2026-08-05 -->

# Superscale v2 Generation Subsystem --- Solution Design

This document is the detailed, explicit solution design for the FAL image
generation subsystem introduced in Superscale v2. It expands the FAL-related
sections of the [architecture](ARCHITECTURE.md) into an implementation-ready
specification and folds in the operational lessons learned from two prior FAL
integrations. It is the target design; the distance between it and the current
implementation is recorded separately in the
[generation gap analysis](GENERATION_GAP_ANALYSIS.md). The raw
request-construction catalogue these lessons draw on is the
[FAL request reference](FAL_REQUEST_REFERENCE.md).

## Purpose And Provenance

The generation subsystem gives the SwiftUI app a native text-to-image and
image-to-image workflow against the FAL platform, re-implemented directly in
Swift. Two adjacent projects are behavioural references only, never runtime
dependencies:

- **`pix`** (Go CLI): a proven, minimal FAL client. Source of the two-host
  split, the two-credential separation, the declarative per-family handler
  table, the explicit edit-sibling map, and the multi-envelope error parser.
- **`storyboard-gen`** (Python GUI): a more sophisticated multi-provider client.
  Source of the provider abstraction, the CDN reference-upload model, session
  price caching, the long-running poll loop pattern, and a body of hard-won FAL
  quirk knowledge.

Behaviour and lessons are ported into Swift. Neither project is executed,
embedded, or imported at runtime.

## Scope

**In scope (MVP):** FAL text-to-image and image-to-image generation; a
data-driven model registry; per-family request handlers; CDN reference upload;
a robust error taxonomy; best-effort pricing and account visibility; session
history; a cancellable generation coordinator; bundled prompt packs.

**Deferred (post-MVP):** Google and Replicate providers; a public provider
plugin architecture; user-authored prompt-pack editing; video generation;
the `@character` reference-token rewriting system from `storyboard-gen`; queue
submission for slow models (design allowance below, not MVP delivery).

## Module Boundary

Generation lives in GUI-only modules that the CLI must never import:

- `FalGenerationKit`: FAL HTTP client, model registry, request handlers,
  reference upload, pricing and account clients, response and error parsing,
  test fixtures.
- `SuperscaleUXCore`: GUI-facing orchestration --- the generation coordinator,
  prompt packs, session history, settings abstractions, and the handoff into
  `SuperscaleKit` for local upscaling.
- `Superscale` (CLI): local upscaling only, with no dependency on either module
  above.

The dependency rule is a hard constraint: generation code is GUI-only and
independently testable without the app.

## Credentials

Two distinct FAL credentials with separate lifecycles, each stored in the
Keychain:

- **Generation key**: authorizes generation, reference upload, pricing, and the
  model catalogue. Required for any generation.
- **Account/admin key**: authorizes balance, usage, and billing-event queries.
  It exposes more sensitive data and therefore **must never fall back to the
  generation key**. Its absence or failure is non-fatal to generation.

Both are sent as `Authorization: Key <token>` (the FAL scheme prefix is `Key `,
not `Bearer`). Secrets appear only in headers, never in request bodies, URLs, or
persisted session metadata.

Provenance: the two-key separation and the deliberate no-fallback rule come from
`pix` (`config.go` `resolveFALAccountKey`). `storyboard-gen` used a single key;
the separation is the safer design and is retained.

## Transport

### Hosts

Two base URLs, mirroring FAL's platform split:

- **Inference**: `https://fal.run/<endpoint>` for generation.
- **Platform**: `https://api.fal.ai/v1/...` for pricing, account, upload, and
  the model catalogue.

Both are injectable for testing so a single local stub can serve both roles.

### Submission model

The MVP baseline is a **synchronous POST** to `fal.run/<endpoint>` whose JSON
response already contains the finished image URLs, followed by a **separate
download hop** for the chosen image. This matches both reference clients.

The design must not foreclose **queue submission with status polling** for slow
models. The long-running pattern is specified now so it can be added without an
architecture change: submit to the queue endpoint, poll status on an interval
with a maximum wait, surface progress, and throw a timeout error on expiry. The
canonical shape is `storyboard-gen`'s Google operation poll loop
(`providers/google.py` `while not operation.done`). Under Swift structured
concurrency the poll loop is a cancellable `Task` using `Task.sleep`, not a
blocking wait.

### Resilience

The GUI is a foreground application and must not fail silently on transient
conditions. The transport layer adds, beyond what the reference CLIs implement:

- explicit per-request timeouts (generation longer than platform calls);
- bounded retries with backoff for idempotent GETs and transient 5xx;
- explicit `429` handling that honours `Retry-After`;
- cancellation propagated from the coordinator's `Task` into the in-flight
  `URLSession` call.

## Model Registry

The registry is data-driven and typed. Each model entry is richer than either
reference project (which spread capabilities across code and docs), so that
family behaviour is expressed once as data rather than as scattered conditionals.

Each `GenerationModel` entry describes:

| Field | Purpose |
|---|---|
| `id` | FAL endpoint identifier, e.g. `xai/grok-imagine-image` |
| `displayName` | Human-readable name for the picker |
| `family` | Handler-selection key |
| `textEndpoint` | Endpoint for text-to-image |
| `editEndpoint` | Endpoint for image-to-image, resolved via the edit-sibling map |
| `modes` | Supported modes: text-to-image, image-to-image |
| `referenceChannel` | Payload field for references (see handler table) |
| `referenceLimit` | Maximum accepted references |
| `sizingMode` | `preset`, `aspectRatio`, or `pixel` |
| `aspectRatios` | Supported aspect ratios, for snapping |
| `outputFormats` | Accepted output formats |
| `safetyDefaults` | Family safety options injected before user options |
| `requiredFields` | Fields FAL rejects the request without (e.g. ideogram `style`) |
| `pricingSupport` | Whether live pricing is expected |

The default model is `xai/grok-imagine-image` unless product testing selects
another. The registry seeds from the FAL image models needed for parity with the
reference clients; a live catalogue fetch (`GET api.fal.ai/v1/models`) may
augment the static set later, cached per session.

## Model-Family Handlers

Request construction uses a **handler strategy**, ported from the declarative
approach both reference clients converged on (`pix` `model_handlers.go`;
`storyboard-gen` `providers/fal.py` `_STILL_HANDLERS` with the configurable
`EditHandler`).

- Handlers are an **ordered list, most specific first, with a generic fallback
  last**. Selection is first-match-wins by family or endpoint substring.
- A handler is a value type carrying its configuration (reference channel,
  sizing mode, safety defaults, required fields, text-to-image suffix), not a
  bespoke subclass per model where configuration suffices.
- Bespoke handlers remain permitted where a family is genuinely special
  (dual reference channels, element arrays).

### Argument merge precedence

The final payload is composed in a fixed order so users can always override
defaults:

1. handler-built base arguments (prompt, sizing, references);
2. family `safetyDefaults`;
3. family `requiredFields`;
4. caller-supplied options (win over all defaults).

This precedence is a correctness contract, taken verbatim from
`storyboard-gen` (`providers/fal.py` argument merge) and `pix`.

### Edit-sibling resolution

When references are present, the endpoint becomes the model's edit sibling. The
naive `"<model>/edit"` rule is insufficient and must be backed by an **explicit
map**, because real FAL endpoints diverge:

| Family | Edit routing | Note |
|---|---|---|
| `flux-pro/kontext` | edit endpoint is the base endpoint | appending `/edit` 404s; text-to-image needs a `/text-to-image` suffix |
| `glm-image` | `/image-to-image` | not `/edit` |
| `seedream` | path rewrite `.../text-to-image` to `.../edit` | |
| `emu` | `/edit-image` | not `/edit` |
| default | `<model>/edit` | heuristic only where it holds |

Provenance: `pix` `model_registry.go` `editSiblings`; `storyboard-gen`
`model_registry.py` `EDIT_SIBLINGS` (which replaced suffix-stripping heuristics
after they proved brittle).

### Per-family payload quirks to encode

- Reference channel differs: `image_url` (single string) versus `image_urls`
  (array) versus `reference_image_url` (Flux general only) versus dual channels.
- Some families require fields or FAL returns HTTP 422 (ideogram `style: AUTO`).
- Some edit endpoints reject sizing parameters and must omit them.
- Safety defaults are family-specific (for example `enable_safety_checker`).

## Reference-Image Pipeline

References are uploaded to FAL's CDN and passed as URLs. **CDN upload is the
chosen approach.** `pix` inlines base64 data URIs, which is simpler but balloons
request size and memory and practically caps references at three;
`storyboard-gen` moved to CDN upload for good reasons and that path is adopted
here.

Pipeline for each reference:

1. Accept a local file URL from the reference well (drag-and-drop or picker).
2. Validate type by content, not extension alone.
3. Upload to FAL storage and obtain a CDN URL.
4. Place the URL in the family's reference channel, honouring the reference
   limit and warning when extras are dropped.

**Uploaded URLs must not be cached.** FAL CDN URLs expire at the provider's
discretion, so a reference is re-uploaded on each generation that uses it. This
is `storyboard-gen`'s lesson #123 (`providers/fal.py`) and is a hard rule.

Because some edit endpoints ignore the requested aspect ratio and return a
different one, generated output from an edit is centre-cropped to the requested
ratio with a small tolerance (`storyboard-gen` `generate.py` crop step).

## Sizing And Output Format

- The requested aspect ratio is **snapped to the family's supported set** before
  submission, then emitted in the family's `sizingMode`: a preset string
  (`landscape_16_9`), a raw `aspect_ratio` (`16:9`), or a literal pixel size
  (`1536x1024`).
- `output_format` is set from the desired output type so FAL returns the wanted
  format and the app avoids a re-encode. Format conversion, where still needed,
  uses `ImageIO`/`CoreGraphics`, never an external binary.

Provenance: `pix` `sizing.go`; `storyboard-gen` `providers/fal.py`
`ASPECT_RATIO_MAP`/`_PIXEL_SIZE_MAP`.

## Response Handling

- Parse the image array from the FAL response. **All returned images are
  surfaced**, not only the first, so the workspace can present a gallery when a
  model returns several.
- Download the selected image; take its content type from the download
  response; map content type to a file extension with a sensible default.
- Store into app-managed storage with a collision-safe name before the user
  saves a final file.

## Error Taxonomy

Errors are classified by source into the eight classes the architecture names,
each mapped to an actionable user-facing message while preserving redacted
diagnostics for issue reports:

1. missing generation key;
2. missing or unauthorized account key (including the 403 Admin-scope case);
3. model endpoint unavailable;
4. unsupported or rejected payload field;
5. network failure;
6. paid generation failure;
7. download failure;
8. local upscaling failure.

### Multi-envelope parser

FAL error bodies are not uniform. The parser reproduces every shape both
reference clients had to handle (`pix` `fal_errors.go`, itself ported from
`storyboard-gen` `errors.py`):

- gateway shape `{"error": {type, message, request_id}}`;
- top-level `{"message": ...}`;
- FastAPI validation `{"detail": ...}` as either a string or a list of
  `{msg, loc, ...}` objects, with `loc` joined to name the offending field
  (for example `body.image_url`) and integer array indices skipped;
- fallback raw body, truncated to bound the diagnostic.

### Redaction

- The secret is replaced wherever it might appear.
- Prompt echoes and argument dumps are trimmed (`storyboard-gen` cuts after
  `prompt was:` and `arguments=`), and the raw-body fallback is truncated so an
  echoed base64 reference payload cannot flood a diagnostic (`pix` 500-byte
  cap).

## Pricing

Pricing is best-effort and independent from generation and from itself:

- **Unit price** (`GET api.fal.ai/v1/models/pricing?endpoint_id=<m>`) and
  **historical estimate** (`POST .../pricing/estimate`) are fetched
  independently; the failure of one does not suppress the other. A model with no
  unit price still reports whatever is available rather than failing the whole
  pricing call.
- Responses are **cached for the session**, including negative results, to avoid
  re-hitting the API on every keystroke or reselection.
- Units are normalized; an uncostable unit yields "unavailable" rather than a
  misleading figure.
- Pricing uses the generation key. A pricing failure never blocks generation.

Provenance: `pix` `cost.go` (independent best-effort reporting);
`storyboard-gen` `pricing.py` (session cache including negatives, unit
normalization).

## Account Visibility

- Uses the separate account/admin key.
- Surfaces balance, recent usage, and recent billing events when authorized.
- Maps `401` to unauthorized and `403` to an Admin-scope message without leaking
  key material.
- Every account failure is non-fatal: the generation and pricing surfaces
  continue to function and the account panel degrades independently.

## Session History And Storage

- App-managed storage holds generated and upscaled assets before the user saves
  final files. The store is plain image files plus JSON metadata; no database.
- A session record links a generation to its prompt, model and endpoint,
  reference images, cost estimate, timestamp, and non-secret diagnostics, and
  associates the generated asset with any local upscale of it.
- History supports reopening a session, sending a generated image to Upscale,
  saving, revealing in Finder, and **comparing source, generated, and upscaled
  states** using the existing comparison UI.
- History is for recovery and auditability, not digital asset management. No API
  keys or full account data are ever written to it.

## Generation Coordination

- A `@MainActor` coordinator owns the generation phase state machine (idle,
  generating, succeeded, cancelled, failed) and publishes it to the UI.
- Long-running work runs in a structured-concurrency `Task`; cancellation is
  real, propagated into the in-flight request, not a discarded result. This
  already improves on `storyboard-gen`'s cooperative `QThread` model, whose
  in-flight call could not be interrupted; that limitation is not carried over.
- Retry re-triggers a generation from the current inputs.

## Prompt Packs

- Prompt packs are the pre-canned AI filters: bundled app resources with stable
  identifiers, display names, categories, a prompt body, and model
  compatibility metadata.
- A pack composes with user-entered prompt text rather than replacing it.
- Loading rejects malformed or duplicate packs with actionable, secret-free
  diagnostics.
- User-authored packs are deferred until the bundled format is proven. The
  `@character` token rewriting in `storyboard-gen` is intentionally out of MVP
  scope.

## Testing Strategy

Automated tests never call paid FAL endpoints. The approach both reference
projects proved is adopted:

- **Mock the transport, unit-test argument construction directly.** The handler
  matrix, edit-sibling resolution, sizing emission, reference-channel selection,
  and prompt composition are pure logic and are tested without any network, the
  highest-value test surface in both reference clients.
- **Stub HTTP with `URLProtocol`** (the Swift equivalent of `pix`'s
  `httptest.Server` and `storyboard-gen`'s `fal_client` mock) for request
  construction, response parsing, pricing, account, upload, and the error
  envelopes.
- **Assert no secret leakage** in diagnostics, as both reference suites do.
- **GUI smoke tests** cover Generate, Upscale, Settings, and History paths.
- **Manual release checks** (human, may incur charges): one text-to-image
  generation, one image-to-image generation, one pricing/account check, and one
  generated image upscaled locally.

## Design Decisions Ledger

| Decision | Choice | Source |
|---|---|---|
| Reference encoding | CDN upload, never cached | storyboard-gen #123 |
| Credentials | Two keys, account never falls back | pix |
| Transport baseline | Sync POST plus download | pix, storyboard-gen |
| Slow-model path | Queue poll allowed, not MVP | storyboard-gen (Google) |
| Handler model | Declarative, ordered, first-match | pix, storyboard-gen |
| Edit routing | Explicit sibling map | pix, storyboard-gen |
| Argument precedence | base, safety, required, user | storyboard-gen |
| Error parsing | Multi-envelope plus redaction | pix (from storyboard-gen) |
| Pricing | Independent, best-effort, cached | pix, storyboard-gen |
| Multi-image | Surface all returned images | improvement on both |
| Resilience | Retry, 429, real cancellation | improvement on both |

## Changelog

- **1.0 (2026-08-05):** Initial solution design consolidating the FAL
  integration lessons from `pix` and `storyboard-gen` into the target Swift
  design for the v2 generation subsystem.
