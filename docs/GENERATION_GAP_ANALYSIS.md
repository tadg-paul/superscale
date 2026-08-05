<!-- Version: 1.0 | Last updated: 2026-08-05 -->

# Generation Subsystem --- Built vs Target Gap Analysis

This document records the distance between the current generation
implementation and the target [generation design](GENERATION_DESIGN.md). It is
the bridge from the existing code to the design and is intended to seed the
delivery tickets once the delivery goals are agreed.

## Method

The current `FalGenerationKit` and `SuperscaleUXCore` generation sources were
read in full at commit `e356373`. Findings cite `file:line`. This pass audits
the FAL generation core (request construction, transport, model registry,
pricing, account, coordination, prompt packs). Session history and settings were
inspected only at module level and are flagged for a follow-up pass where noted.

## What Is Already Sound (Keep)

These decisions match the target design and should be preserved:

- **Module boundary holds.** The `Superscale` CLI imports neither
  `FalGenerationKit` nor `SuperscaleUXCore` (verified). Generation is GUI-only
  and independently testable.
- **Two-credential separation is in place.** `FalAccountClient` uses a distinct
  account key and maps `401` to unauthorized and `403` to an Admin-scope message
  (`FalAccountClient.swift:131-134,166-167`).
- **Secret redaction exists** across generation, pricing, and account clients
  (`FalGenerationClient.swift:148-153`, `FalPricingClient.swift:181-184`).
- **The kontext quirk is handled correctly**: its edit endpoint is the base
  endpoint, not `<model>/edit` (`FalRequestBuilder.swift:95-102`).
- **Cancellation already uses structured concurrency.** The coordinator cancels
  a `Task` rather than discarding a completed result
  (`GenerationCoordinator.swift:132-164`), which is ahead of the reference
  implementations.
- **Pricing and account endpoints are correct** (two hosts, `Key ` scheme,
  unit-price and estimate calls, billing/usage/events).
- **The prompt-pack loader is solid**: stable IDs, validation, composition,
  duplicate rejection (`PromptPacks.swift:52-175`).
- **Storage is app-managed** with content-type-to-extension mapping and atomic
  writes (`GenerationCoordinator.swift:79-104`).

## Gap Register

Severity key: **blocker** (feature does not work), **robustness** (works on the
happy path, fails on real-world inputs), **completeness** (missing specified
capability), **enhancement** (improvement over both reference clients).

| ID | Area | Current state | Target | Severity |
|---|---|---|---|---|
| G1 | Reference upload | References are passed straight through as strings into the payload; no upload exists anywhere in `Sources/` (`FalRequestBuilder.swift:56-60`, `GenerationModels.swift:53`) | Upload each local file to FAL CDN, pass the URL, never cache | **blocker** |
| G2 | Handler coverage | Only two families branch (`grok-imagine`, `kontext`); every other model throws `unsupportedModel` (`FalRequestBuilder.swift:85-106`) | Ordered handler list with a generic fallback, seeded for parity | **completeness** |
| G3 | Edit-sibling map | Default edit routing is the naive `"<model>/edit"` heuristic (`FalRequestBuilder.swift:90`) | Explicit sibling map for glm, seedream, emu, and future families | **robustness** |
| G4 | Model registry | Registry holds a single model; `GenerationModel` carries only id, name, provider (`GenerationModels.swift:22-45,10-20`) | Rich per-model schema (family, endpoints, channels, sizing, safety, required fields, pricing support) | **completeness** |
| G5 | Safety and required fields | No `safetyDefaults` or `requiredFields` are ever added; payload is prompt, `num_images`, sizing only (`FalRequestBuilder.swift:51-55`) | Family safety and required fields injected before user options, in fixed precedence | **robustness** |
| G6 | Error envelopes | Parser handles `message`, `detail` string, and nested `error.message`, with a 500-byte raw fallback (`FalGenerationClient.swift:155-173`) | Add FastAPI `detail` list with `loc`, gateway `error.type`, and prompt-echo trimming | **robustness** |
| G7 | Error taxonomy | Errors are transport-shaped (`invalidRequest`, `providerFailure`, ...) (`FalGenerationClient.swift:122-146`) | Map to the eight architecture error classes for actionable messaging | **completeness** |
| G8 | Pricing resilience | `pricing()` requires both unit price and estimate; either failure throws the whole call; no cache (`FalPricingClient.swift:45-50`) | Independent best-effort fetches, session cache including negatives | **robustness** |
| G9 | Transport resilience | Single `URLSession` call, no retries, no `429`/`Retry-After`, default timeouts (`FalGenerationClient.swift:60-111`) | Timeouts, bounded retry with backoff, `429` handling | **robustness** |
| G10 | Multi-image | Only the first returned image is used (`FalGenerationClient.swift:89`) | Surface all returned images | **enhancement** |
| G11 | Sizing | Requested aspect ratio is passed verbatim; no snapping, no per-family emission, no `output_format` (`FalRequestBuilder.swift:51-55`) | Snap to supported set, emit per `sizingMode`, set `output_format` | **completeness** |
| G12 | Edit-crop | No centre-crop for edit endpoints that ignore the requested aspect ratio | Centre-crop edit output to the requested ratio with tolerance | **robustness** |
| G13 | Queue path | Synchronous only | Queue submit and poll allowed for slow models (post-MVP, no architecture change) | **enhancement** |

## Not Yet Assessed

The following were confirmed present as modules and tests but not audited line by
line in this pass; a short follow-up review should confirm alignment before they
are scoped into delivery:

- session history and storage (`SessionStore`, `GenerationCloudStatus`, and
  `SessionStoreTests`);
- generation settings and preferences state
  (`GenerationSettingsState`, `GenerationPreferences`);
- the comparison of source, generated, and upscaled states in History.

## Suggested Delivery Slices

These slices group the gaps into coherent, independently testable units. They
are candidate ticket boundaries for MODE DELIVER, not yet tickets. Each would be
drafted, audited, and closed under the delivery lifecycle once the goal is
confirmed.

1. **Reference upload pipeline (unblocks image-to-image).** G1, plus per-family
   reference channel selection. Highest priority: without it, image-to-image
   does not function.
2. **Model registry and handler matrix.** G2, G3, G4, G5. The declarative
   registry and handler strategy, including the edit-sibling map and safety and
   required-field defaults.
3. **Error handling.** G6, G7. The multi-envelope parser and the mapping to the
   eight architecture error classes with redaction.
4. **Pricing and account resilience.** G8, and confirmation of non-fatal
   account degradation. Touches the existing pricing ticket area (#76).
5. **Transport hardening.** G9, and optionally the queue path (G13) if a slow
   model is admitted to the MVP set.
6. **Output fidelity.** G10, G11, G12. Multi-image, sizing and output format,
   and edit-crop.

Most of these fall within the scope of the existing FAL core ticket (#72); the
pricing slice touches #76. Whether they are delivered by revising those tickets
in place or by new hardening tickets is a delivery-planning decision to be taken
when the MODE DELIVER goals are set.

## Changelog

- **1.0 (2026-08-05):** Initial gap analysis of the generation subsystem against
  the target design, at commit `e356373`.
