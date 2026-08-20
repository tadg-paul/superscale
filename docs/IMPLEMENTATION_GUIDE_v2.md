<!-- Version: 1.0 | Last updated: 2026-08-20 -->

# Superscale v2 Implementation Guide

This is the single design document for Superscale v2. It supersedes the earlier
v2 implementation plan and the withdrawn generation design. It exists to be
complete enough that a delivery cycle can generate its ticket tree directly from
it.

It is written on the premise that v2 is an **enhancement to a working
application**, not a new product built beside one. Every design decision below
was taken after reading the shipped v1 pipeline and the current SwiftUI app.

Companion documents:

- [FAL request reference](FAL_REQUEST_REFERENCE.md) is the durable catalogue of
  how to construct FAL API requests correctly. This guide references it rather
  than repeating it.
- [Legacy v1 documentation](v1/) records the original upscaler design that v2
  builds on.

## 1. Value Proposition

Superscale v2 is **curated artistic filters, finished at high resolution by
native on-device upscaling**.

A user drops a photograph, chooses "Film Noir", and receives a 4096-pixel noir
print. Neither half of that sentence is a product on its own:

- The filters alone produce roughly 1024-pixel images. Attractive, but not a
  deliverable.
- The upscaler alone is a utility. It has no creative intent.

The combination is the product. Cloud AI supplies the transformation; the
Neural Engine supplies the finish. This is what distinguishes Superscale from a
generic front end to an image API, and it is the axis every design decision
below is measured against.

The corpus of 86 curated filters is the product's content, not a convenience
feature. Its quality and its format are first-order concerns.

### What v2 is not

- Not a graphical client for an image-generation API.
- Not an image editor. The v1 principle stands: the app does one thing well,
  and that thing is now "apply a filter and finish it beautifully".
- Not a digital asset manager.

## 2. The Pipeline Model

The central correction in this guide. Earlier v2 work treated Upscale and
Generate as **peer modes** that a user shuttles images between. They are not
peers. They are **stages of one pipeline**, and upscaling is the terminal stage.

```
  Source
    │   a dropped or opened file, or an image generated from a prompt
    ▼
  Conditioning              [optional, automatic]
    │   local pre-upscale when the source is below model working resolution
    ▼
  Filter                    [optional, repeatable, cloud]
    │   FAL image-to-image transform at model working resolution
    ▼
  Finish                    [terminal, local]
    │   Real-ESRGAN through Core ML on the Neural Engine
    ▼
  Output
```

Two properties follow, and they are the whole point:

1. **Finishing is terminal.** A finished asset is never an input to another
   stage. Not to a filter, not to another finish.
2. **The working image is always pre-finish.** Finishing derives an output from
   the working image; it does not advance the working image.

This is the same principle the v1 pipeline already applies internally, one level
up. `docs/v1/architecture.md:192-196` establishes that resize-to-target happens
after all AI processing "so the model always operates at its native
resolution". v2 extends that reasoning across the cloud boundary: the filter
model must also operate at its native resolution, so it must never receive
finished pixels.

### Why finished pixels must never reach a filter

- FAL image models work at roughly 1024 pixels. A 4096-pixel input is
  downscaled on arrival, so every pixel the Neural Engine produced is discarded.
- Upload cost, latency, and memory are paid for data that is thrown away.
- Real-ESRGAN synthesizes detail. Sending synthesized detail back through a
  generative transform compounds artefacts.
- With face enhancement enabled, a second GFPGAN pass is applied over already
  restored faces.

### Conditioning: the legitimate pre-upscale

There is one case where upscaling correctly precedes a filter, and it is
categorically different from finishing.

When a source image is **below the filter model's working resolution**, the
filter has too little to work with. Conditioning uses the local upscaler to
bring the source up to that working resolution before the transform.

- Conditioning targets model working resolution. Finishing targets the user's
  requested output size.
- Conditioning is automatic and invisible. Finishing is user-controlled.
- A conditioned asset is a valid filter input. A finished asset is not.

Conditioning is implemented with the existing pipeline's target-dimension
support, which already fits an image inside a bounding box while preserving
aspect ratio (`Pipeline.resolveTargetDimensions`).

## 3. Asset Lineage

The pipeline model is enforced by data structure rather than by rules a
developer must remember.

Every image the app holds is an asset with a role and a parent:

```swift
public enum AssetRole: String, Sendable {
    case source        // dropped, opened, or generated from a prompt
    case conditioned   // locally pre-upscaled to reach model working resolution
    case filtered      // output of a FAL transform
    case finished      // output of the terminal local upscale
}

public struct Asset: Identifiable, Sendable {
    public let id: UUID
    public let role: AssetRole
    public let fileURL: URL
    public let pixelSize: CGSize
    public let parentID: UUID?
    public let provenance: Provenance?
}
```

`Provenance` records how a non-source asset was produced: the filter identifier,
the resolved model endpoint, the composed prompt, reference asset identifiers,
the cost estimate, and non-secret request diagnostics. It never contains
credentials.

### Base, candidate, and lock

Filters are explored, not accumulated. A user tries Film Noir, dislikes it,
tries Japanese Woodblock, and expects the second filter to apply to their
photograph, not to the noir version of it. Stacking is occasionally wanted, but
it must be deliberate.

The graph therefore holds two pointers rather than one:

- **Base** --- the fixed starting point for filter application. Initially the
  source, or the conditioned source. It does not move on its own.
- **Candidate** --- the result of applying the currently selected filter to the
  base. Transient. Selecting a different filter discards the previous candidate
  and re-derives from the base.

**Lock** is the only operation that promotes a candidate to become the new base.
After locking, subsequent filters apply on top of the locked result, which is
how deliberate stacking is expressed.

```
  base ──filter A──▶ candidate A          switch filter: discard candidate A
  base ──filter B──▶ candidate B          re-derived from base, not from A
  base ──lock B────▶ base' (= B)          now filters apply on top of B
```

The base is never a `finished` asset. Locking captures the filtered result at
model resolution, before any upscaling, so the base that filters consume is
always suitable input for a filter.

### Invariants

These are the contract. Each is independently testable.

- **I1 --- Terminal finish.** An asset with role `finished` is never the input to
  any stage. It may be saved, revealed, and compared, and nothing else.
- **I2 --- Filter input is the base.** The filter stage consumes the base asset,
  whose role is `source`, `conditioned`, or `filtered`. Never the candidate, and
  never a `finished` asset.
- **I3 --- Filter switching re-derives from the base.** Selecting a different
  filter replaces the candidate by re-deriving from the base. Filter results
  never chain implicitly.
- **I4 --- Lock is the only promotion.** The base changes only by an explicit
  lock, which requires an existing candidate, and never adopts a `finished`
  asset.
- **I5 --- Re-finish derives from the working asset** (the candidate if one
  exists, otherwise the base). Changing finish settings re-derives from it. It
  never consumes the previous finished output, and it never overwrites it in
  place.
- **I6 --- One writer per output.** A finished asset is written to a path derived
  from its own identity. Re-finishing produces a new file; it does not clobber a
  previous result.
- **I7 --- Session attribution is explicit.** A finished asset is associated with
  a session only when it descends from that session's lineage. Attribution is
  never inferred from timing or from "whatever finished most recently".

I1, I5, and I6 close the data-loss defect. I7 closes the cross-session
contamination defect. I2, I3, and I4 give the exploration behaviour above.

### Consequences

- **Every filter switch is a new paid call**, because each re-derives from the
  base. This is inherent to exploration and must be visible in the cost
  presentation, not hidden.
- **The base is re-sent on every filter application.** Uploaded reference URLs
  expire at the provider's discretion and are not cached (see the FAL request
  reference). A short-lived reuse of an upload for an unchanged base, falling
  back to re-upload when the provider rejects it, is a permissible optimization
  but not a correctness assumption.
- **Finishing does not disturb exploration.** A user may finish a candidate to
  inspect it at full resolution, then continue trying filters, because
  finishing never advances base or candidate.

## 4. What Exists Today

An accurate account of the codebase as read at commit `e9bbc92`. This section
exists because the previous design was written without it.

### 4.1 The v1 foundation is sound

`SuperscaleKit` is a dependency-free library with a pinned public API
(`Tests/SuperscaleTests/SuperscaleKitAPITests.swift` treats the surface as a
contract). Its pipeline is well ordered, well tested, and correct:

- Stage order is load, tile, infer, stitch, alpha, face enhance, recombine,
  resize, write, with resize strictly after all AI processing.
- Seven bundled Real-ESRGAN models, content-based auto-selection through
  `ContentDetector`, and a compiled-model cache.
- A regression pack plus an SSIM quality gate against PyTorch references at a
  0.90 threshold.

The v1 GUI is likewise a real application: drag and drop, a magnifier loupe and
a slider comparison with zoom, pan and minimap, an info panel, a model picker,
and a face-model download flow with licence acceptance.

### 4.2 The v2 generation work is built, and bolted alongside

`FalGenerationKit` and `SuperscaleUXCore` exist and contain sound components:
generation, pricing and account clients with correct endpoints and the two-key
separation; Keychain-backed credentials; a prompt-pack loader with validation;
a session store; and a generation coordinator with real structured-concurrency
cancellation.

The problem is not the components. It is that they form a parallel application
sharing a window with the upscaler:

- Navigation is four peer modes (`AppNavigation.swift`), expressing no pipeline.
- `GenerateView` and `HistoryView` share no state with `UpscaleViewModel`.
- The handoff is a bare file URL plus a `UUID` held in view-local `@State`.
- Three save paths, four file-open paths, four error alerts, two model pickers.
- Generate has a phase enum and a cancel button. Upscale, the long local
  operation, has neither.
- `ComparisonView` and `MagnifierView` are unreachable from Generate or History.
- A plain local upscale is never recorded in History, although History presents
  itself as covering local upscales.

Most tellingly, **the integration API this guide needs already exists and is
dead code**. `GUIUpscaleSource` distinguishes `.selectedFile` from
`.generatedFile`; `GUIUpscaleResult` carries that provenance back out;
`GenerationCoordinator.upscaleSource` and `GenerationSessionRecord.upscaleSource`
exist to hand a provenance-tagged source across the seam. None of them is
called by any view, and `UpscaleViewModel` never reads `GUIUpscaleResult.source`.
The lineage plumbing was designed, built, and then bypassed.

### 4.3 The filter corpus

86 curated filters are bundled at
`Sources/SuperscaleUXCore/Resources/PromptPacks/`. Measured against the corpus:

- 60 of 86 contain an explicit preserve clause.
- 50 of 86 refer to transforming "the input image".
- 3 of 86 begin with a markdown header containing their own filename.

The strongest filters follow a consistent five-part structure: transform
instruction, preserve clause, style direction, intended feel, and an avoid
clause. `image-lighting-film-noir.md` and `image-zeitgeist-solarpunk-civic.md`
are the reference examples. Others, such as
`image-print-japanese-woodblock.md`, are a single paragraph of style attributes
with no preserve or avoid clause, which reads as a text-to-image style prompt
rather than a transform.

This confirms a scoping correction: **image-to-image is the primary path**.
Earlier v2 work treated text-to-image as the default and reference images as an
add-on presented through "reference wells". For this product that is inverted.

## 5. Defect Register

Defects in shipped code, found by reading it, with evidence. These are
independent of the new design and several cause data loss today.

| ID | Severity | Defect |
|---|---|---|
| D1 | **data loss** | History "Send to Upscale" passes `preferredAssetURL`, which is `upscaledAssetURL ?? generatedAssetURL`. For an already-upscaled session this feeds the finished image back through the pipeline and writes the result over the same fixed `upscaled.<ext>` filename, destroying the original. The correct accessor, `upscaleSource`, is defined three lines above and never used. |
| D2 | **data corruption** | The upscale write-back observer fires on any change to `viewModel.resultData` while `pendingSessionID` is set. Sending a generated image to Upscale and then dropping an unrelated file attributes that unrelated upscale to the generation session. History then presents an unrelated image as the output of a prompt. |
| D3 | high | `pendingSessionID` is never cleared on mode switch, new drop, or reset; only on success or error. A stale identifier persists indefinitely. |
| D4 | high | Prompt bodies are loaded whole, so the 3 filters beginning with a filename header send that header to FAL as prompt text. |
| D5 | medium | Face enhancement defaults to on and is untouched by the handoff, so GFPGAN, a non-commercially-licensed model, is silently applied to synthetic faces. |
| D6 | medium | `SuperscaleKit` errors are not `LocalizedError`, and the GUI formats with `error.localizedDescription`, producing "The operation couldn't be completed. (SuperscaleKit.ImageIOError error 0.)" |
| D7 | medium | The upscale has no cancellation at any level. `Task.detached` is never stored, and the tile loop has no cancellation check. |
| D8 | medium | `defaultUpscaleModelID` is honoured only on the generated handoff path, not when a file is dropped. |
| D9 | low | GUI auto-detect hard-codes scale 4, so `realesrgan-x2plus` is never auto-selected in the app. |
| D10 | low | `HistoryView.saveSelected` ignores the configured output folder, unlike the other two save paths. |
| D11 | low | `dimensionCapWarning` is declared and never read or written. |
| D12 | low | An output path whose extension is neither png nor jpg silently receives PNG bytes under the wrong extension. |
| D13 | unverified | `Tiler.blendWeight` returns zero on the outermost row and column, which would leave a one-pixel transparent border. Inferred from code, not observed. Requires a deliberate check. |

## 6. Target Architecture

### 6.1 Module boundaries

Unchanged in principle from the current layout, which is correct:

- `SuperscaleKit` --- local processing. No knowledge of the cloud.
- `FalGenerationKit` --- FAL transport, model registry, request handlers,
  reference upload, pricing and account clients, error parsing, fixtures.
- `SuperscaleUXCore` --- orchestration: the asset graph, the stage coordinators,
  the filter catalogue, session history, settings.
- `SuperscaleApp` --- SwiftUI views and platform integration.
- `Superscale` --- the CLI, local upscaling only, with no dependency on
  `FalGenerationKit` or `SuperscaleUXCore`.

The CLI boundary is verified today and must remain so.

**Correction to the current layout:** `V2AppPaths` is defined inside
`GenerateView.swift` yet is depended on by the app entry point and `MainView`.
Storage location policy belongs in `SuperscaleUXCore`.

### 6.2 The asset graph

`SuperscaleUXCore` gains an `AssetGraph` that owns assets, their lineage, and
the base and candidate pointers. It is the single place invariants I1 to I7 are
enforced, and the single source of truth for what the user is looking at.

Stage coordinators become uniform. Each takes an input asset, performs work,
and returns a derived asset:

```swift
protocol Stage {
    associatedtype Options
    func run(input: Asset, options: Options,
             progress: @Sendable (StageProgress) -> Void) async throws -> Asset
}
```

Three implementations: `ConditioningStage` and `FinishStage` (both local, via
`SuperscaleKit`), and `FilterStage` (cloud, via `FalGenerationKit`).

This unifies the two status models. Both local and cloud stages report the same
`StageProgress` and are cancellable through the same mechanism, removing the
asymmetry where only the cloud stage can be cancelled.

### 6.3 Reusing what exists

The following existing components are reused rather than reimplemented, and the
duplication noted in section 4.2 is consolidated onto them:

- `GUIUpscaleCoordinator` and its `GUIUpscaleProcessing` protocol, which is
  already the injectable seam that lets the handoff be tested without Core ML.
- `GUIUpscaleSource`, extended to carry an asset identifier so provenance
  survives, replacing the bare-URL handoff.
- `ComparisonView` and `MagnifierView`, made reachable from every stage so a
  user can compare source against filtered, and filtered against finished.
- `GeneratedImageStore`, generalized to store any derived asset.
- One file-open policy, one save policy, one error presentation surface.

### 6.4 Constraints inherited from SuperscaleKit

These are real and must shape the design rather than be discovered late.

- **Memory is the binding constraint, and it is in `Tiler.stitch`.** The
  stitcher allocates roughly 36 bytes per output pixel, all resident at once.
  A 1024-pixel filter output finished at 4x costs about 600 MB. A 2048-pixel
  source finished at 4x costs about 2.4 GB. Tile size does not help; it affects
  the inference working set, never the stitch buffer. **The design must cap
  effective output resolution deliberately and report the cap.**
- **There is no in-memory entry point.** The pipeline is URL to URL. Derived
  assets are written to disk before finishing, which the asset graph does
  anyway.
- **Model load costs roughly 3.2 seconds per call** in the GUI path, because
  `Pipeline` is not `Sendable` and a fresh one is constructed per call.
  Conditioning plus finishing would pay this twice. Confining a reusable
  `Pipeline` to an actor is the remedy, and it is a `SuperscaleKit` change.
- **Progress is unstructured strings**, and the GUI already parses the face
  count out of message text. `StageProgress` requires a structured progress
  callback in the kit rather than deeper string sniffing.
- **No cancellation exists in the kit.** The insertion point is the top of the
  tile loop.
- **Output metadata is dropped.** Stamping provenance into saved files requires
  changing `ImageWriter`, which currently passes no properties dictionary.

Three of these (structured progress, cancellation, a reusable `Pipeline`) are
genuine `SuperscaleKit` changes, not adapter changes. They are scoped
explicitly in section 10 rather than smuggled in.

## 7. The Filter Catalogue

The filter corpus is the product's content and needs a specification.

### 7.1 Required metadata

The app cannot currently know whether a filter needs an input image, which model
suits it, or how aspect ratio should be handled, because metadata is derived by
splitting the filename on hyphens. Each filter requires:

| Field | Purpose |
|---|---|
| `id` | Stable identifier, independent of filename |
| `name` | Display name |
| `category` | Grouping for the picker |
| `mode` | `imageToImage`, `textToImage`, or `both` |
| `requiresInput` | Whether a source image is mandatory |
| `models` | Preferred or required model endpoints, optional |
| `aspect` | `preserve` or a specific ratio |
| `body` | The prompt text, clean of headers |

### 7.2 Body conventions

The five-part structure the strongest filters already follow becomes the
documented convention: transform instruction, preserve clause, style direction,
intended feel, avoid clause. Filters lacking preserve and avoid clauses are
candidates for revision, which is authorial work and belongs to the human.

The body must contain no markdown headers. D4 is fixed by cleaning the three
affected files, and prevented by validating at load.

### 7.3 Ownership and metadata location

**The filter corpus is vendored into this repository wholesale.** The 86 files
under `Sources/SuperscaleUXCore/Resources/PromptPacks/` are the canonical
source. No path, build step, or runtime behaviour refers to an external
authoring directory. Filters are project content and are versioned with the
project.

Because the repository owns the corpus, **metadata lives in frontmatter in each
`.md` file**:

```markdown
---
id: lighting-film-noir
name: Film Noir
category: Lighting
mode: imageToImage
requiresInput: true
aspect: preserve
---
Transform the input image using film noir lighting.
...
```

A separate manifest was considered and rejected. Its only advantage was keeping
the `.md` files byte-identical to an external authoring source, which ownership
of the corpus removes. Frontmatter keeps a filter self-contained, makes adding
one a single-file operation, and cannot drift out of sync with its body.

### 7.4 Editable filter text

Free-form text-to-image generation is deferred, but a filter's prompt text is
**not** fixed at the point of use. The composed prompt is presented in an
editable field before application, and the user may adjust it.

- The filter body populates the field; edits apply to that application.
- Editing does not modify the bundled filter.
- The distinction from deferred user-authored filters is persistence: this is
  adjustment in flight, not creating a new saved filter.

This is the escape hatch that keeps the product curated without making it
rigid. It also means the composed prompt sent to the provider is whatever the
field contains, not the filter body read fresh from disk.

### 7.5 Compatibility

The filter picker must reflect the working state. A filter with
`requiresInput: true` is not offerable when there is no working asset, and the
picker must not present filters incompatible with the selected model. Both are
currently unenforced.

## 8. Cloud Integration

The wire-level detail lives in the
[FAL request reference](FAL_REQUEST_REFERENCE.md) and is not repeated. What
belongs here is how the filter stage uses it.

- **Image-to-image is the primary path.** The working asset is the reference;
  the filter body is the prompt. Text-to-image is the secondary path, used when
  a filter declares `textToImage` and there is no working asset.
- **References are uploaded to FAL storage and passed as URLs.** The current
  base64 data-URI encoding in `GenerateView` is replaced. Uploaded URLs are
  never cached, because they expire at the provider's discretion.
- **Reference upload belongs in `FalGenerationKit`**, not in a view.
- **Model family differences are handled by declarative handlers** with an
  explicit edit-sibling map, not by a naive `<model>/edit` rule.
- **Errors are parsed through the multi-envelope parser** and mapped to the
  error taxonomy, with secrets redacted and prompt echoes trimmed.
- **Pricing and account visibility are best-effort** and never block a filter.
  The two-key separation is retained as a standing least-privilege principle
  across the project's API integrations.
- **Edit endpoints frequently ignore the requested aspect ratio.** Filter output
  is centre-cropped back to the working asset's aspect with a small tolerance.

### The local-first promise

`README.md:5` states that images never leave the machine. That is the v1
promise and cloud filtering breaks it. The honest position, which the vision
document already frames as "local advantage, explicit cloud":

- Local finishing never leaves the machine, and that remains true and worth
  stating.
- Applying a cloud filter uploads the image. This must be visible at the point
  of action, not buried in settings.
- The README must be corrected. Leaving it as written is a false claim once
  filtering ships.

## 9. Workspace Design

The pipeline model implies a workspace, not four peer modes. The precise UI is a
product decision recorded in section 12; what follows is the recommendation and
the reasoning.

**Recommendation: merge Upscale and Generate into one Studio workspace, and
retain History and Settings as separate surfaces.**

Studio presents the working asset on a canvas, with:

- a source affordance (drop, open, or generate from a prompt);
- a filter picker over the 86 filters, categorized and searchable, filtered to
  what is applicable to the working state;
- a **lock** control that promotes the current candidate to become the base;
- finish controls (scale, model, face enhancement) carried over from the current
  Upscale toolbar;
- a lineage indicator showing the base, what filter is currently applied, and
  what has been locked;
- comparison available between any two points in the lineage, with base against
  candidate as the default pairing while exploring.

Filter switching is the primary interaction and must feel like browsing. Each
selection re-derives from the base, so the user compares filters against their
photograph rather than against each other's output. The lock control is what
turns an accepted result into the new starting point, and it is the only way the
base moves. It must be unmistakable, because it is the one action that changes
what subsequent filters consume.

This makes the value proposition legible in the interface: an image comes in, a
filter is chosen, a finished result comes out. It also removes the shuttling
between modes that the current design requires, and with it the fragile
cross-mode `@State` correlation that causes D2 and D3.

The alternative is to keep the four modes and fix only the model beneath them.
That is less disruptive and still closes every defect, because the defects are
data-model defects. It leaves the interface expressing a mental model the
product does not have.

Whichever is chosen, these hold:

- The v1 drop-and-upscale path must remain immediate and unchanged in
  character. A user who wants only an upscale must not be walked through
  filtering.
- Finishing is presented as producing a result, not as advancing state.
- Cloud actions are visibly distinct from local ones.

## 10. Delivery Plan

Ordered slices, each independently testable and each a candidate ticket. Order
reflects dependency and risk, not estimated size.

**Slices 1 to 9 are the confirmed scope of this delivery.** Slices 10 to 12 are
recorded for continuity and are explicitly excluded; they follow as separate
work once the spine is proven.

**Slice 1 --- Asset graph and invariants.** Introduce `Asset`, `AssetRole`,
lineage, and the base/candidate pointers with lock in `SuperscaleUXCore`.
Enforce I1 to I7.
Revive the dead provenance API by extending `GUIUpscaleSource` to carry an asset
identifier and making `UpscaleViewModel` read `GUIUpscaleResult.source`. Closes
D1, D2, D3. This slice is first because every later slice depends on it, and
because it stops active data loss.

**Slice 2 --- Stage unification.** Introduce the `Stage` protocol and
`StageProgress`. Move local upscaling behind `FinishStage` and cloud
transformation behind `FilterStage`. Consolidate the two status models onto one.
Requires the `SuperscaleKit` changes in slice 3 to be complete for progress and
cancellation.

**Slice 3 --- SuperscaleKit extensions.** Structured progress reporting,
cancellation checks in the tile loop, and an actor-confined reusable `Pipeline`.
Conform kit errors to `LocalizedError`. Closes D6, D7, and removes the string
sniffing. This is a change to the tested v1 core and must not regress the SSIM
gate.

**Slice 4 --- Filter catalogue.** Add frontmatter to all 86 filters, replace the
filename-splitting metadata derivation with a frontmatter parser, validate at
load (rejecting markdown headers in bodies), clean the three polluted bodies,
add compatibility filtering to the picker, and present the composed prompt in an
editable field. Closes D4. This slice makes the product's content first-class.

**Slice 5 --- Reference upload.** Move reference encoding out of the view and into
`FalGenerationKit` as a FAL storage upload returning URLs, with no caching.
Replaces the base64 data-URI path.

**Slice 6 --- Model registry and handlers.** The declarative per-family handler
table, the explicit edit-sibling map, safety and required-field defaults, the
argument merge precedence, and aspect snapping. Sourced from the FAL request
reference.

**Slice 7 --- Conditioning stage.** Automatic pre-upscale when the source is
below model working resolution, with the resolution cap from section 6.4
applied and reported.

**Slice 8 --- Error taxonomy.** The multi-envelope parser, mapping to the error
classes, redaction, and one error presentation surface replacing four.

**Slice 9 --- Pricing and account resilience.** Independent best-effort fetches,
session caching including negative results, and confirmed non-fatal degradation.

**Slice 10 --- Workspace.** *(Excluded from this delivery.)* The interface change
left open in section 12, plus
making comparison reachable from every stage and recording local finishes in
History.

**Slice 11 --- Output fidelity and hygiene.** *(Excluded from this delivery.)*
Surface all returned images, honour
the output folder consistently, honour the default upscale model on drop,
correct auto-detect scale, and address D5, D8, D9, D10, D11, D12. Verify D13.

**Slice 12 --- Release hardening.** *(Excluded from this delivery.)* Resource
bundling, credential exclusion,
honest release wording, README correction, and the manual provider checks.

## 11. Testing Strategy

The v1 approach is sound and extends naturally.

- **Invariants are unit-tested directly.** I1 to I7 are pure logic over the
  asset graph and require no network and no Core ML. Attempting to filter a
  finished asset must be impossible to express or must throw.
- **Request construction is unit-tested without the network.** The handler
  matrix, edit-sibling resolution, aspect snapping, reference channel selection,
  and prompt composition are pure functions. This was the highest-value test
  surface in both reference implementations.
- **Transport is stubbed with `URLProtocol`**, covering response parsing,
  pricing, account, upload, and every error envelope. No test calls a paid
  endpoint.
- **The handoff is tested through `GUIUpscaleProcessing`** with a stub
  processor, as the existing coordinator tests already do, so lineage behaviour
  is verified without Core ML.
- **The SSIM quality gate must not regress.** Slice 3 changes the v1 core;
  `make test-ssim` is a required gate on that slice specifically.
- **Secret leakage is asserted against**, as both reference suites do.
- **Manual release checks** remain human and may incur charges: one filter
  applied to a real image, one text-to-image generation, one pricing or account
  check, and one finished output saved.

## 12. Decisions Taken

Settled. Each was a product decision and each is now closed.

1. **Delivery scope: slices 1 to 9.** Slices 10 (workspace), 11 (output fidelity
   and hygiene) and 12 (release hardening) are excluded from this delivery and
   follow separately.
2. **Filter corpus is vendored.** The repository owns the 86 filters; nothing
   refers to an external authoring directory. See section 7.3.
3. **Filter metadata lives in frontmatter.** Ownership of the corpus removes the
   only argument for a separate manifest. See section 7.3.
4. **Filter text is editable in flight.** The composed prompt is presented in an
   editable field before application. Persisting user-authored filters remains
   deferred. See section 7.4.
5. **Text-to-image is deferred.** The release is filter-first. Generating from a
   bare prompt with no source image is out of scope.
6. **Output resolution cap.** Finished output is warned above 4096 pixels on the
   long edge and refused above 8192. The stitcher costs roughly 36 bytes per
   output pixel, all resident: 4096 squared is about 600 MB, 8192 squared about
   2.4 GB. The natural design point is a 1024-pixel filter output finished at
   4x, which lands at 4096.
7. **`SuperscaleKit` public API changes are authorized** for slice 3, covering
   structured progress, cancellation, an actor-confined reusable `Pipeline`, and
   `LocalizedError` conformance. This authorization is recorded here because
   such changes would otherwise require a mandatory architecture stop.
8. **Existing v2 tickets are closed and replaced.** See section 13.

### Still open, not blocking this delivery

- **Workspace structure** (slice 10, excluded from scope). Merge Upscale and
  Generate into a single Studio workspace, or retain four modes with a corrected
  model beneath. Recommendation stands: merge, for the reasons in section 9.
- **Filter corpus revision.** 26 of 86 filters lack a preserve clause and read
  as text-to-image style prompts. Revising them is authorial work and sits
  outside any delivery scope.

## 13. Existing Tickets

Nine v2 tickets (#70 to #78) specify the superseded four-mode design and are
already implemented against it. Their components are largely sound; their
specifications are misframed. Four legacy tickets (#14, #46, #47, #48) use an
obsolete acceptance-criteria format, #47 is redundant with #73, and three (#15,
#16, #17) are outside the v2 scope.

**Decision: #70 to #78 are closed as superseded**, each with a comment linking
this guide, and a fresh ticket tree is generated from section 10. Patching nine
misframed specifications is more work than replacing them, and the implemented
code is not discarded by doing so --- slices 1 to 9 build on it.

The legacy tickets are unaffected by this delivery. #55 (signing), #57
(XCUITest), #66 (divider contrast) and #69 (Apache-2.0) remain valid and are
untouched. #14, #46, #47 and #48 need rewriting or retirement, and #15, #16 and
#17 remain out of scope; none is addressed here.

## 14. Risks

| Risk | Mitigation |
|---|---|
| Slice 3 regresses the tested v1 core | SSIM gate required on that slice; kit changes are additive |
| Memory ceiling reached on large finishes | Explicit cap decided in section 12, reported not silent |
| Filter corpus quality varies | Documented body convention; revision flagged as authorial work |
| Workspace change disrupts the v1 upscale flow | The drop-and-upscale path is a stated constraint in section 9 |
| Cloud dependency undermines the local-first promise | Explicit disclosure at the point of action; README corrected |
| FAL model families drift | Declarative registry and handlers; behaviour pinned by fixture tests |
| Provider costs during development | No automated test calls a paid endpoint |

## Changelog

- **1.0 (2026-08-20):** First issue. Establishes the filter-plus-finish value
  proposition, the pipeline model with terminal finishing, the asset lineage
  invariants, an as-built assessment of the existing application, a defect
  register, the filter catalogue specification, and a twelve-slice delivery
  plan. Supersedes the v2 implementation plan and the withdrawn generation
  design.
