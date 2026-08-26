<!-- Version: 1.0 | Last updated: 2026-08-05 -->

# FAL Request Construction Reference

This is a durable catalogue of how to talk to the FAL image API correctly,
distilled from working reviews of two prior integrations: `pix` (Go CLI) and
`storyboard-gen` (Python GUI). It captures the language-independent domain
knowledge, the request shapes, the per-family quirks, and the hard-won lessons,
so the Swift implementation does not have to rediscover them from the original
Go and Python sources.

It is a reference, not a plan. ~~The target Swift design lives in the
generation design; how the current code diverges from it lives in the gap
analysis.~~ *(Those two documents were retired before the v2 delivery and are
not in the tree; the design of record is now `IMPLEMENTATION_GUIDE_v2.md` and
the as-built architecture is `ARCHITECTURE.md`. Sentence struck 2026-08-26
after a fresh-clone review found the dangling links.)* Facts below are observed
behaviours of the two reference clients, with source citations of the form
`pix:file:line` and `sg:file:line` (sg = storyboard-gen) so any claim can be
checked against the original.

Scope markers: **[MVP]** is needed for the first release; **[later]** is captured
for post-MVP features (multi-reference workflows, more model families, video) and
is not required now.

## Hosts And Endpoints

Two hosts, split by role:

- **Inference**: `https://fal.run/<endpoint>` for generation and edits.
- **Platform**: `https://api.fal.ai/v1/...` for pricing, account, reference
  upload, and the model catalogue.

`pix` derives the platform host from the inference host: when the inference base
is the default `fal.run`, pricing swaps to `api.fal.ai` (`pix:fal.go:48-54`).
`storyboard-gen` only ever touches the platform host directly for pricing
(`sg:pricing.py:134`); its inference goes through the `fal-client` SDK, which
hides the URLs.

| Purpose | Method + path | Host |
|---|---|---|
| Generate / edit | `POST /<endpoint>` | `fal.run` |
| Unit price | `GET /v1/models/pricing?endpoint_id=<m>` | `api.fal.ai` |
| Price estimate | `POST /v1/models/pricing/estimate` | `api.fal.ai` |
| Account balance | `GET /v1/account/billing?expand=credits` | `api.fal.ai` |
| Usage | `GET /v1/models/usage?expand=time_series` | `api.fal.ai` |
| Billing events | `GET /v1/models/billing-events` | `api.fal.ai` |
| Model catalogue | `GET /v1/models?category=<c>&status=active` | `api.fal.ai` |
| Reference upload | FAL storage upload (SDK `upload_file` in sg) | `api.fal.ai` |

## Authentication

- Header is always `Authorization: Key <token>`. The scheme prefix is literally
  `Key `, not `Bearer` (`pix:fal.go:71`, `sg:pricing.py:136`).
- The secret lives only in the header, never in a request body or URL.
- Two credentials (see [architecture](ARCHITECTURE.md) and generation design):
  a generation key for inference, upload, pricing, and catalogue; a separate
  account/admin key for the account endpoints. The account key never falls back
  to the generation key (`pix:config.go:157-198`). `storyboard-gen` used a single
  key (`sg:pricing.py:126`); the separation is `pix`'s and is the design chosen
  here.

## Submission And Download

- Generation is a **synchronous POST**; the response body already contains the
  finished `images[].url`. The image is then fetched in a **second hop**
  (`pix:fal.go:65-106`). `storyboard-gen`'s `fal_client.subscribe` wraps a
  queue-submit-then-poll internally but is used as one blocking call
  (`sg:providers/fal.py:868`).
- Timeouts in `pix`: generation 120s, platform calls 30s
  (`pix:genimg.go:352`, `pix:cost.go:183`). Neither client implements retries,
  backoff, or `429`/`Retry-After` handling; add these in the Swift port.
- **[later]** For slow models, FAL offers a queue endpoint with status polling.
  Neither reference hand-rolls it; `storyboard-gen`'s Google provider poll loop
  (`sg:providers/google.py:258-275`) is the template: poll on an interval, cap
  the wait, throw on timeout.

## Base Payload

Every generation request starts from a small base and is then merged with
family-specific fields:

- `prompt`: the composed prompt string.
- `num_images: 1`: both clients request a single image per call
  (`pix:genimg.go:278`).
- `output_format`: set from the desired output type so FAL returns the wanted
  format and no re-encode is needed (`pix:genimg.go:281-284`). `storyboard-gen`
  hard-sets `png`.

## Endpoint Routing: Text vs Edit

- **No references** present: the endpoint is the model ID as-is (its
  text-to-image endpoint).
- **References** present: the endpoint becomes the model's **edit sibling**.
- The naive `"<model>/edit"` rule is insufficient. Both clients maintain an
  **explicit edit-sibling map** because real endpoints diverge
  (`pix:model_registry.go:24-40`, `sg:model_registry.py:129-157`, sg issue #128
  replaced the old suffix-stripping heuristic).

| Family | Edit routing | Note |
|---|---|---|
| `flux-pro/kontext` | edit endpoint **is** the base endpoint | appending `/edit` 404s; text-to-image needs a `/text-to-image` suffix |
| `glm-image` | `/image-to-image` | not `/edit` |
| `seedream` | rewrite `.../text-to-image` to `.../edit` | path rewrite, not suffix |
| `emu` | `/edit-image` | not `/edit` |
| default | `<model>/edit` | heuristic, only where it holds |

Some models are edit-only or text-only:

- **Kontext Dev** is image-to-image only and raises without a reference
  (`sg:providers/fal.py:633-638`).
- `flux-kontext/dev` does not accept `aspect_ratio` in image-to-image
  (`sg:providers/fal.py:630-632`).

## Reference-Image Channels **[later for multi-reference; MVP needs the basic case]**

The payload field carrying references differs per family. This is the detail most
easily lost, and it becomes load-bearing as reference workflows grow beyond MVP.

| Channel field | Shape | Used by |
|---|---|---|
| `image_url` | single URL string | single-reference families |
| `image_urls` | array of URL strings | multi-reference families |
| `reference_image_url` | single URL string | **flux-general only**; other Flux 1.x silently ignore references (`sg:providers/fal.py:672-679`) |
| `reference_image_urls` + `image_urls` | two arrays, dual channel | Ideogram Character (`sg:providers/fal.py:787-801`) |
| `elements[]` with `frontal_image_url` + `reference_image_urls` | array of element objects | Kling O3 (`sg:providers/fal.py:1037-1072`) |
| `subject_reference_image_url` | single URL string | MiniMax (`sg:providers/fal.py:1167-1169`) |

`pix` models the simple case with a per-handler `RefField`: singular fields send
`uris[0]` as a string, plural fields send the array
(`pix:model_handlers.go:213-225`).

### Reference Encoding: Upload, Not Inline

- `storyboard-gen` **uploads** each reference to FAL storage and passes the
  returned CDN URL (`sg:providers/fal.py:599`). This is the chosen approach.
- `pix` inlines a **base64 data URI** instead (`pix:genimg.go:442-450`); simpler,
  but it balloons request size and practically caps references at three. Not
  adopted.
- **Hard rule: never cache an uploaded reference URL.** FAL CDN URLs expire at
  the provider's discretion, so a reference is re-uploaded on every call that
  uses it (`sg:providers/fal.py:1020-1022`, sg issue #123).
- Single-reference families accept only one reference; extras are dropped with a
  warning (`sg:providers/fal.py:591-596`, `pix:model_handlers.go:216-217`).
- Validate references by content, not extension alone; `pix` validated by
  extension (`.jpg/.jpeg/.png/.webp/.gif`) which is weaker
  (`pix:genimg.go:424-439`).

### The Initiate Exchange

Probed live on 2026-08-25 (#107) after the first real GUI attempt failed. This
section documents the exchange from the wire, not from an SDK's source; the
transcript is on #107, and OT-107.1 to OT-107.3 in the one-off package re-prove
it on demand.

- `POST https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3`,
  with the key as `Authorization: Key <token>` and a JSON body carrying
  `file_name` and `content_type`.
- **`storage_type` accepts `fal-cdn` and `fal-cdn-v3`; `gcs` is rejected** with
  HTTP 4xx and body `{"detail":"Invalid storage type"}`. The parameter may be
  omitted, and the API then defaults to the CDN --- but the client sends
  `fal-cdn-v3` explicitly rather than leaning on a server default that can
  change without any signal on our side. `gcs` shipped in the client for the
  whole delivery and no stubbed test could know: this section did not exist,
  so the value had nothing to be checked against.
- The response carries `upload_url` (a signed address to PUT the bytes to) and
  `file_url` (the CDN address the generation request references). Both point at
  `*.fal.media`. The signature travels in the upload URL's query, so the PUT
  itself sends no credential of ours.
- Error bodies are JSON with a `detail` field; the parser reads it and the
  sentence the user sees is built from it, which is how "invalid storage type"
  reached the author as words rather than as a status code.

## Sizing

- The requested aspect ratio is chosen (explicit flag, else a reference's
  intrinsic ratio, else `1:1`) and **snapped to a supported set**:
  `{9:16, 1:1, 4:3, 16:9}` (`pix:sizing.go:19`, `sg:models.py:65`).
- It is then emitted per the family's sizing mode:
  - **preset** string, e.g. `landscape_16_9`;
  - raw **`aspect_ratio`**, e.g. `16:9`;
  - literal **pixel** `image_size`, e.g. `1536x1024`
  (`pix:sizing.go:144-160`, `sg:providers/fal.py:20-32`).
- Quirk preserved for parity: `4:3` maps to `1536x1024`, which is actually 3:2
  (`pix:sizing.go:32-34`).
- **Some edit endpoints reject sizing parameters** and must omit them
  (`edit_accepts_sizing = false`, e.g. grok-imagine-image, reve)
  (`sg:providers/fal.py:413-414`).
- **Edit endpoints often ignore the requested aspect ratio** and return a
  different one, so edit output is **centre-cropped** to the requested ratio
  with roughly 1% tolerance (`sg:generate.py:190-193`).

## Safety And Required Fields

- **Safety defaults** are family-specific, for example `enable_safety_checker:
  false` or kontext `safety_tolerance: "6"` (`pix:model_handlers.go`).
- **Required fields** are fields FAL rejects the request without; for example
  ideogram needs `style: AUTO` or returns HTTP 422
  (`pix:model_handlers.go:80,88`).

### Argument Merge Precedence

The payload is composed in a fixed order so user options always win
(`sg:providers/fal.py:853-860`, `pix`):

1. handler-built base arguments (prompt, sizing, references);
2. family safety defaults;
3. family required fields;
4. caller-supplied options.

This ordering is a correctness contract, not a convenience.

## Prompt-Token Rewriting **[later]**

`storyboard-gen` rewrites `@character` tokens in the prompt per family
(`sg:providers/fal.py:940-1008`). Out of MVP scope, but the rules are worth
keeping for when character-reference workflows are added:

- Kling O3 -> `@ElementN`;
- O1 Image -> `@ImageN` (uppercase);
- Flux 2 Pro -> `@imageN` (lowercase);
- everything else -> strip the `@`.
- When no tokens are present but a tag prefix applies, auto-prepend
  `@TagN is <description>.` lines.
- Google strips tokens entirely.

## Per-Family Gotcha Catalogue

Model families seen across the two clients, with the specific facts each encodes.
Family selection is by ordered, most-specific-first substring match with a
generic fallback last (`pix:model_handlers.go:192-206`,
`sg:providers/fal.py:485-524`).

| Family | Facts to encode |
|---|---|
| `flux-pro/kontext` (Pro/Max/Dev) | base endpoint is the edit endpoint; `/text-to-image` suffix for T2I; Dev is i2i-only; dev rejects `aspect_ratio` in i2i; `safety_tolerance: "6"` |
| `ideogram/v3`, `ideogram/character` | ideogram requires `style: AUTO` or 422; Character uses dual reference channels |
| `flux-general` | only family where `reference_image_url` works; other Flux 1.x ignore refs |
| `flux-2`, `flux-2/pro` | Flux 2 Pro needs lowercase `@imageN` tokens |
| `seedream` | edit sibling is a path rewrite of `text-to-image` to `edit` |
| `emu-3.5` | edit sibling is `/edit-image` |
| `glm-image` | edit sibling is `/image-to-image` |
| `grok-imagine-image` (`xai/…`) | MVP default; edit endpoint rejects sizing params |
| `reve` | edit endpoint rejects sizing params |
| `nano-banana`, `gpt-image`, `hunyuan-image`, `recraft`, `instant-character` | present in the `pix` handler table; port their `RefField`/`Sizing`/safety config when admitted |
| Kling O3, MiniMax (video/advanced) **[later]** | `elements[]` and `subject_reference_image_url` channels; video duration typing varies by family |

## Response Handling

- Still response: `images[]`; an empty array is treated as a safety-filter
  rejection with an actionable message (`sg:providers/fal.py:880-884`).
- `pix` downloads only `images[0]` even though the schema is an array
  (`pix:fal.go:97`); the Swift port should **surface all returned images**.
- Take the content type from the download response and map it to a file
  extension with a sensible default; store with a collision-safe name.

## Error Envelopes

FAL error bodies are not uniform. Reproduce every shape both clients handle
(`pix:fal_errors.go:31-51`, `sg:errors.py:9-91`; `pix`'s parser was ported from
`storyboard-gen`):

1. gateway `{"error": {type, message, request_id}}`;
2. top-level `{"message": ...}`;
3. FastAPI validation `{"detail": ...}` as a **string or a list** of
   `{msg, loc, ...}`; join `loc` to name the field (`body.image_url`) and skip
   integer array indices (`pix:fal_errors.go:91-136`);
4. fallback: the raw body, **truncated** (pix caps at 500 bytes) to stop an
   echoed base64 reference payload flooding the diagnostic
   (`pix:fal_errors.go:46-49`).

Redaction: replace the secret wherever it might appear, and trim prompt echoes
and argument dumps (`storyboard-gen` cuts after `prompt was:` and `arguments=`,
`sg:errors.py:42-49`).

## Pricing Requests

- **Unit price**: `GET /v1/models/pricing?endpoint_id=<m>` returns
  `prices[0].{unit_price, unit, currency}` (`pix:fal.go:115-149`).
- **Estimate**: `POST /v1/models/pricing/estimate` with
  `{"estimate_type": "historical_api_price", "endpoints": {"<m>": {"call_quantity": 1}}}`
  returns `total_cost` (`pix:fal.go:151-195`).
- Both use the generation key. Fetch them **independently and best-effort**: a
  missing unit price must not suppress the estimate, and neither must block
  generation (`pix:cost.go`).
- **Cache per session, including negative results** (`storyboard-gen` caches
  `None` too, `sg:pricing.py:14,131,165`); `pix` does not cache and re-hits every
  call.
- Normalize units to `image` / `second` / `megapixel`; an uncostable unit is
  "unavailable", not a guessed figure (`sg:pricing.py:82-111`). A `megapixel`
  estimate assumes roughly 1 MP per image (`sg:pricing.py:223-224`).
- `storyboard-gen` also keeps a static price table for non-FAL providers and a
  per-project override that short-circuits the network (`sg:pricing.py:25-79`).

## Account Requests

- All on `api.fal.ai` with the **account/admin key**:
  `GET /v1/account/billing?expand=credits`,
  `GET /v1/models/usage?expand=time_series`,
  `GET /v1/models/billing-events` (`pix:fal_account.go:70-166`).
- `403` means the key lacks Admin scope; surface that specifically without
  leaking key material (`pix:fal_account.go:196-197`).
- Convert `cost_estimate_nano_usd` to USD by dividing by 1e9
  (`pix:account.go:255`).
- Account failure is non-fatal: generation and pricing continue and the account
  panel degrades on its own.

## Model Catalogue **[later]**

`pix` fetches a live catalogue: `GET /v1/models?category=<c>&status=active` for
`text-to-image` and `image-to-image` in parallel, dedupes (t2i wins), and sorts
by id (`pix:models.go:212-315`). Each entry is `endpoint_id` plus metadata
(`display_name`, `description`, `category`, `status`, `tags`, `model_url`,
`license_type`). The Swift registry may seed statically for MVP and augment from
this catalogue later, cached per session.

## Provenance Summary

| Concern | Primary reference | Note |
|---|---|---|
| Wire protocol (POST, download, hosts, auth, errors) | `pix` | SDK-free Go, matches the raw HTTP the Swift port writes |
| Two-key separation | `pix` | `storyboard-gen` used one key |
| Provider abstraction, async worker | `storyboard-gen` | `providers/base.py`, the architectural spine |
| Declarative handlers, edit-sibling map | both | `storyboard-gen`'s configurable `EditHandler` is the evolved form |
| Reference upload (CDN, no cache) | `storyboard-gen` | issue #123 |
| Reference channel taxonomy | `storyboard-gen` | dual channels, `elements[]`, subject refs |
| Prompt-token rewriting | `storyboard-gen` | `@character` system, post-MVP |
| Pricing chain + session cache | `storyboard-gen` | `pix` has no cache |
| Sizing snap + per-family emission | both | |
| Multi-image, retries, real cancellation | improvement | absent or weaker in both |

## Changelog

- **1.0 (2026-08-05):** Initial reference distilled from the `pix` and
  `storyboard-gen` FAL integration reviews.
