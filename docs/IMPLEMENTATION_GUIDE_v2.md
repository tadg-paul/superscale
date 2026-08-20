<!-- Version: 2.0 | Last updated: 2026-08-20 -->

# Superscale v2: Solution Design and Implementation Guide

Superscale is a working macOS app that upscales images locally on the Neural
Engine. v2 adds a library of curated AI filters in front of that upscaler.

This is the single design document for that uplift. Wire-level FAL detail lives
in the [FAL request reference](FAL_REQUEST_REFERENCE.md); the original upscaler
design is in [v1](v1/).

---

## 1. What We Are Building

**Curated artistic filters, finished at high resolution by native on-device
upscaling.**

Drop a photograph, choose "Film Noir", get a 4096-pixel noir print.

Neither half is a product alone. The filters produce roughly 1024-pixel images,
which are not deliverables. The upscaler is a utility with no creative intent.
Together they are the product: cloud AI supplies the transformation, the Neural
Engine supplies the finish.

The 86 curated filters in `Sources/SuperscaleUXCore/Resources/PromptPacks/` are
the product's content, not a feature. They are owned by this repository.

v2 is not an image editor, not a client for an image API, and not an asset
manager. The v1 principle holds: do one thing well.

---

## 2. The Core Idea

Filtering and upscaling are **stages of one pipeline**, not parallel modes.
Upscaling is the last stage.

```
   Source ──▶ [Condition] ──▶ [Filter] ──▶ Finish ──▶ Output
              if too small     cloud       local, terminal
```

**Upscaling is terminal.** A finished image is never fed back into anything. It
is saved, revealed, compared, and nothing else.

Why this matters: FAL models work at roughly 1024 pixels. Sending a 4096-pixel
upscale to a filter throws away every pixel the Neural Engine produced, pays
upload cost for discarded data, compounds synthesized detail through a
generative transform, and runs a second face-restoration pass over already
restored faces.

This is v1's own logic extended one level up. `docs/v1/architecture.md:192-196`
already places resize after all AI processing "so the model always operates at
its native resolution". The filter model deserves the same treatment.

**Conditioning** is the one legitimate pre-upscale: when a source is below the
filter model's working resolution, the local upscaler brings it up first so the
filter has something to work with. It targets model resolution and is automatic.
Finishing targets the user's output size and is user-controlled.

### Base, candidate, lock

Filters are browsed, not stacked. Trying Film Noir then Japanese Woodblock must
apply the second filter to the **photograph**, not to the noir version.

- **Base** --- the fixed starting point. Filters always read from it.
- **Candidate** --- the current filter's result. Switching filters discards it and
  re-derives from the base.
- **Lock** --- the only action that promotes a candidate to become the new base.
  This is how deliberate stacking is expressed.

```
base ──filter A──▶ candidate A     switch filter, discard A
base ──filter B──▶ candidate B     re-derived from base, not from A
base ──lock B────▶ base' = B       filters now stack on top of B
```

The base is never a finished image, so filters always receive suitable input.

---

## 3. The Model

One structure enforces all of the above, so no developer has to remember it.

```swift
public enum AssetRole: String, Sendable {
    case source        // dropped, opened, or generated
    case conditioned   // pre-upscaled to reach model resolution
    case filtered      // output of a FAL transform
    case finished      // output of the terminal upscale
}

public struct Asset: Identifiable, Sendable {
    public let id: UUID
    public let role: AssetRole
    public let fileURL: URL
    public let pixelSize: CGSize
    public let parentID: UUID?          // lineage
    public let provenance: Provenance?  // filter, model, prompt, cost — never secrets
}
```

An `AssetGraph` in `SuperscaleUXCore` owns the assets, the base pointer, and the
candidate pointer. It is the only place these rules live:

| | Invariant |
|---|---|
| **I1** | A `finished` asset is never input to any stage. |
| **I2** | Filters read the **base**, never the candidate, never a finished asset. |
| **I3** | Switching filters re-derives from the base. Results never chain implicitly. |
| **I4** | Only an explicit **lock** moves the base, and never to a finished asset. |
| **I5** | Re-finishing derives from the working asset and writes a new file. It never consumes or overwrites a previous finished output. |
| **I6** | A finished asset is attributed to a session only if it descends from that session's lineage. Never by timing. |

Each is pure logic over the graph, testable without network or Core ML.

**Consequences.** Every filter switch is a new paid call, so cost must be
visible. The base is re-sent on each application, and uploaded reference URLs
expire, so they are not cached. Finishing never disturbs exploration.

---

## 4. What Exists Today

**The v1 foundation is sound and stays.** `SuperscaleKit` is a dependency-free
library with a pinned public API: tiling, Core ML inference, seven Real-ESRGAN
models with content-based auto-selection, a compiled-model cache, alpha
handling, and an SSIM quality gate against PyTorch references. The app has
drag-and-drop, a magnifier loupe, a slider comparison with zoom and minimap, an
info panel, and a face-model licence flow.

**The v2 generation work is built but bolted alongside.** The clients, Keychain
credentials, prompt loading, session store and generation coordinator are all
sound components. The problem is they form a parallel app sharing a window:
navigation is four peer modes, `GenerateView` shares no state with
`UpscaleViewModel`, and the handoff is a bare URL plus a `UUID` in view-local
`@State`.

The telling detail: **the integration API already exists and is dead code.**
`GUIUpscaleSource` distinguishes `.selectedFile` from `.generatedFile`,
`GUIUpscaleResult` carries that provenance back, and both
`GenerationCoordinator.upscaleSource` and
`GenerationSessionRecord.upscaleSource` exist to carry it across the seam. None
is called. The lineage plumbing was built, then bypassed. Section 3 revives it.

---

## 5. Defects To Fix

Found by reading the shipped code. Several cause data loss today.

| | Severity | Defect |
|---|---|---|
| **D1** | data loss | History "Send to Upscale" passes `preferredAssetURL` (`upscaledAssetURL ?? generatedAssetURL`), so an already-upscaled session re-upscales its own output and overwrites the original at the fixed `upscaled.<ext>` path. The correct accessor sits unused three lines above. |
| **D2** | data corruption | The write-back observer fires on any `resultData` change while `pendingSessionID` is set, so dropping an unrelated file after a handoff attributes that file's upscale to the generation session. |
| **D3** | confirmed, medium | **Every output has a one-pixel black border.** `Tiler.blendWeight` returns `min(left, right, top, bottom)`; at `x=0` that is zero, so edge pixels accumulate zero weight and keep their initialized zero (`Tiler.swift:156`). Measured on `Tests/visual_output/remy1_4x.png`: outermost row and column 100% black, inner rows 0%, source 0%. RT-087 misses it by sampling 20px inside. Affects every image v1 has produced. |
| **D4** | medium | 3 of 86 filters begin with a markdown header containing their filename, which is sent to FAL as prompt text. |
| **D5** | medium | Kit errors are not `LocalizedError`, so the GUI shows "The operation couldn't be completed. (SuperscaleKit.ImageIOError error 0.)" |
| **D6** | medium | The upscale has no cancellation at any level, though it is the long local operation. |
| **D7** | medium | GFPGAN, a non-commercially-licensed model, is silently applied to synthetic faces. |
| **D8** | low | `pendingSessionID` is never cleared on mode switch or new drop. |
| **D9** | low | `defaultUpscaleModelID` is honoured on the handoff path but not on drop. |

---

## 6. The Design

### 6.1 Modules

Unchanged in principle; the current boundaries are right.

- `SuperscaleKit` --- local processing, no knowledge of the cloud.
- `FalGenerationKit` --- FAL transport, model registry, handlers, reference
  upload, pricing, account, error parsing.
- `SuperscaleUXCore` --- the asset graph, stages, filter catalogue, history,
  settings.
- `SuperscaleApp` --- SwiftUI views.
- `Superscale` --- the CLI, local upscaling only, no dependency on the two above.
  This boundary is verified and must stay.

One correction: `V2AppPaths` currently lives inside `GenerateView.swift` while
the app entry point depends on it. Storage policy belongs in `SuperscaleUXCore`.

### 6.2 Stages

Local and cloud work become uniform:

```swift
protocol Stage {
    associatedtype Options
    func run(input: Asset, options: Options,
             progress: @Sendable (StageProgress) -> Void) async throws -> Asset
}
```

`ConditionStage` and `FinishStage` wrap `SuperscaleKit`; `FilterStage` wraps
`FalGenerationKit`. This collapses the two status models into one, so both the
cloud call and the local upscale report progress the same way and are cancelled
the same way.

### 6.3 Filters

The corpus is vendored --- copied once, owned here, with no reference to any
external directory. Metadata moves into frontmatter so each filter is
self-contained:

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
Preserve the subject's identity, pose, expression...
```

This replaces deriving metadata by splitting filenames, which has nowhere to
record whether a filter needs an input image.

**Body convention**, following the strongest existing filters: transform
instruction, preserve clause, style direction, intended feel, avoid clause. No
markdown headers --- validated at load, which closes D4.

**Filter text is editable in flight.** The composed prompt appears in an
editable field before application; edits apply to that run and do not modify the
bundled filter. Saving user-authored filters remains deferred. This keeps the
product curated without making it rigid.

The picker reflects state: a filter requiring input is not offerable without a
base, and filters incompatible with the selected model are not shown.

### 6.4 Cloud

Detail is in the [FAL request reference](FAL_REQUEST_REFERENCE.md). What matters
here:

- **Image-to-image is the primary path.** 60 of 86 filters carry preserve
  clauses and 50 transform "the input image". Text-to-image is deferred.
- **References upload to FAL storage and pass as URLs**, replacing the base64
  data-URI encoding currently in `GenerateView`. Upload belongs in
  `FalGenerationKit`, not a view. Uploaded URLs are never cached.
- **Model differences live in declarative handlers** with an explicit
  edit-sibling map, not a naive `<model>/edit` rule.
- **Two keys**: a generation key and a separate account key that never falls
  back to it. A standing least-privilege principle, already implemented.
- **Pricing and account are best-effort** and never block a filter.
- **Edit endpoints often ignore requested aspect ratio**, so filter output is
  centre-cropped back to the base's aspect.

### 6.5 Constraints from the kit

- **Memory is the binding limit.** `Tiler.stitch` costs roughly 36 bytes per
  output pixel, all resident. 4096² is about 600 MB; 8192² about 2.4 GB. Tile
  size does not help. **Warn above 4096 on the long edge, refuse above 8192.**
  The natural design point --- a 1024-pixel filter output at 4× --- lands at 4096.
- **No in-memory entry point**; the pipeline is URL to URL, which suits the
  asset graph since it writes assets to disk anyway.
- **Model load costs ~3.2s per call** because `Pipeline` is not `Sendable` and a
  fresh one is built each time. Conditioning plus finishing would pay it twice.
- **Progress is unstructured strings** and the GUI already parses face counts
  out of message text.

The last three, plus cancellation and `LocalizedError`, are `SuperscaleKit`
changes. They are authorized.

### 6.6 Interface

The pipeline implies a workspace rather than four peer modes: a canvas showing
the working image, a filter picker, a lock control, finish controls, and a
lineage indicator. Merging Upscale and Generate into one Studio surface is the
recommendation, with History and Settings retained separately.

**This is out of scope for the delivery below** and remains open. The defects
are data-model defects and are fixed regardless of which interface is chosen.

Constraints either way: the v1 drop-and-upscale path stays immediate, finishing
reads as producing a result rather than advancing state, and cloud actions are
visibly distinct from local ones.

---

## 7. Delivery

Nine slices. Each is independently testable and becomes a ticket.

| | Slice | Content |
|---|---|---|
| 1 | **Asset graph** | `Asset`, `AssetRole`, lineage, base/candidate/lock. Enforce I1--I6. Revive the dead provenance API. Closes D1, D2, D8. First, because it stops active data loss. |
| 2 | **Stages** | The `Stage` protocol and `StageProgress`. Local and cloud behind one shape. Consolidate the two status models. |
| 3 | **Kit extensions** | Structured progress, cancellation in the tile loop, actor-confined reusable `Pipeline`, `LocalizedError`. **Fix D3, the black border**, with a regression test sampling the outermost row and column. Closes D3, D5, D6. Must not regress the SSIM gate. |
| 4 | **Filter catalogue** | Frontmatter across all 86, a frontmatter parser replacing filename-splitting, load validation, clean the 3 polluted bodies, compatibility filtering, editable prompt field. Closes D4. |
| 5 | **Reference upload** | FAL storage upload returning URLs, in `FalGenerationKit`. Replaces base64. |
| 6 | **Registry and handlers** | Declarative per-family handlers, edit-sibling map, safety and required fields, argument precedence, aspect snapping. |
| 7 | **Conditioning** | Automatic pre-upscale below model resolution, with the resolution cap applied and reported. |
| 8 | **Errors** | Multi-envelope parser, mapped taxonomy, redaction, one presentation surface replacing four. |
| 9 | **Pricing and account** | Independent best-effort fetches, session caching including negatives, non-fatal degradation. Closes D7, D9. |

Excluded and following separately: the interface change (6.6), output fidelity
polish, and release hardening.

### Testing

- **Invariants** are unit tests over the graph. No network, no Core ML.
- **Request construction** is pure logic and tested without the network --- the
  highest-value surface in both reference implementations.
- **Transport** is stubbed with `URLProtocol`. No test calls a paid endpoint.
- **The handoff** is tested through `GUIUpscaleProcessing` with a stub processor.
- **The SSIM gate is required on slice 3**, which touches the v1 core.
- **Manual release checks** stay human: one filter applied to a real image, one
  pricing check, one finished output saved.

---

## 8. Status and Open Items

Superseded v2 tickets #70 to #78 are closed; a fresh tree is raised from
section 7. Legacy tickets #55, #57, #66 and #69 remain valid and untouched.

**The test suite is currently failing** --- 143 tests, 1 failure. The failing test
must be identified and resolved before slice 3 touches the core.

Open, not blocking:

- **Interface structure** (6.6). Merge into one Studio workspace, or keep four
  modes with a corrected model beneath. Recommendation: merge.
- **Filter corpus revision.** 26 of 86 filters lack a preserve clause and read
  as style prompts rather than transforms. Authorial work.
- **The README** states images never leave the machine. True of local finishing,
  false once filtering ships. Needs correcting before release.

## Changelog

- **2.0 (2026-08-20):** Rewritten as a single solution design. Establishes
  filter-plus-finish, the pipeline with terminal upscaling, base/candidate/lock,
  the asset model and its invariants, the defect list, and a nine-slice
  delivery.
- **1.0 (2026-08-20):** First issue.
