<!-- Version: 1.1 | Last updated: 2026-03-26 -->

# Implementation plan

## Overview

Delivery is phased. Each phase produces a working, testable increment. Phases are sequential unless noted otherwise.

## Execution order

Issues should be tackled in this order. Where multiple issues share a step number, they can be worked in parallel.

| Step | Issue | Description | Depends on | Status |
|------|-------|-------------|------------|--------|
| 1 | [#2](https://github.com/tigger04/superscale/issues/2) | Model storage strategy (decision) | — | **closed** |
| 1 | [#3](https://github.com/tigger04/superscale/issues/3) | Phase 1: CoreML model conversion | — | **closed** |
| 2 | [#18](https://github.com/tigger04/superscale/issues/18) | Model artefact management (sync, release) | #2, #3 | **closed** |
| 2 | [#4](https://github.com/tigger04/superscale/issues/4) | Phase 2: Proof of concept | #3 | **closed** |
| 3 | [#6](https://github.com/tigger04/superscale/issues/6) | Phase 3a: Image I/O | #4 | **closed** |
| 3 | [#7](https://github.com/tigger04/superscale/issues/7) | Phase 3b: Tiling engine | #4 | **closed** |
| 3 | [#8](https://github.com/tigger04/superscale/issues/8) | Phase 3c: CoreML inference + model registry | #4 | **closed** |
| 4 | [#9](https://github.com/tigger04/superscale/issues/9) | Phase 3d: Pipeline integration | #6, #7, #8 | **closed** |
| 5 | [#10](https://github.com/tigger04/superscale/issues/10) | Phase 3e: CLI polish | #9 | **closed** |
| 6 | [#5](https://github.com/tigger04/superscale/issues/5) | Phase 4: Licensing review | — (gate before #12) | **closed** |
| 7 | [#12](https://github.com/tigger04/superscale/issues/12) | Phase 5: Distribution (Homebrew) | #5, #10, #18 | **closed** |
| 8 | [#13](https://github.com/tigger04/superscale/issues/13) | Phase 6: Model download (on-demand) | #12 | **closed** (folded into #12) |
| 9 | [#1](https://github.com/tigger04/superscale/issues/1) | Phase 7: Face enhancement (GFPGAN) | #11 | **closed** |
| — | [#33](https://github.com/tigger04/superscale/issues/33) | Compiled model caching | — | **closed** |
| — | [#35](https://github.com/tigger04/superscale/issues/35) | --list-models shows face model | — | **closed** |
| — | [#34](https://github.com/tigger04/superscale/issues/34) | SSIM quality regression testing | — | open (future enhancement) |
| 10 | [#14](https://github.com/tigger04/superscale/issues/14) | Phase 8: macOS SwiftUI GUI | #11 | open |
| 11 | [#15](https://github.com/tigger04/superscale/issues/15) | Phase 9: macOS App Store | #14 | open |
| 11 | [#16](https://github.com/tigger04/superscale/issues/16) | Phase 10: iOS app | #14 | open |
| 12 | [#17](https://github.com/tigger04/superscale/issues/17) | Phase 11: iOS App Store | #16 | open |

[#11](https://github.com/tigger04/superscale/issues/11) is the Phase 3 tracking issue — it is complete when #6–#10 are all closed.

## Roadmap

```
#2 Model storage decision ──┐                    ✓ closed
                             │
#3 Phase 1: Model conversion─┤                   ✓ closed
    │                        │
    ├──▶ #4  Phase 2: PoC   │                    ✓ closed
    │        │               │
    │        ├──▶ #6  3a: Image I/O  ──┐         ✓ closed
    │        ├──▶ #7  3b: Tiling  ─────┤         ✓ closed
    │        └──▶ #8  3c: Inference  ──┤         ✓ closed
    │                                  │
    │                    #9  3d: Pipeline ────    ✓ closed
    │                                  │
    │                    #10 3e: CLI polish ──    ✓ closed
    │                                  │
    └──▶ #18 Model artefact mgmt ─────┤          ✓ closed
                                       │
              #5  Phase 4: Licensing ──┤          ✓ closed
                                       │
                         #12 Phase 5: Distribution  ✓ closed
                                       │
                         #13 Phase 6: Model download ✓ closed (folded into #12)
                                       │
                         #1  Phase 7: Face enhancement ✓ closed
                                       │
                         #33 Model caching ──────── ✓ closed
                         #35 --list-models face ──── ✓ closed
                                       │
                         #14 Phase 8: macOS GUI
                               │       │
                               │       ▼
                               │  #15 Phase 9: macOS App Store
                               │
                               └──▶ #16 Phase 10: iOS app
                                        │
                                        ▼
                                   #17 Phase 11: iOS App Store
```

---

## Phase 1: CoreML model conversion — [#3](https://github.com/tigger04/superscale/issues/3)

**Goal:** Convert RealESRGAN_x4plus (the default model) from PyTorch to CoreML and validate that the conversion works.

**Tasks:**
1. Create Python conversion script (`scripts/convert_model.py`)
2. Set up conversion venv with torch, coremltools, basicsr
3. Convert RealESRGAN_x4plus.pth → RealESRGAN_x4plus.mlpackage
4. Convert remaining models (x2plus, anime, general, compact variants)
5. Document the conversion process so it's reproducible

**Artefacts:** `.mlpackage` files for all supported models, conversion script.

**Risk:** CoreML may not support all operations used by Real-ESRGAN architectures. RRDBNet uses standard convolutions and upsampling which CoreML handles well. The compact SRVGGNetCompact architecture needs verification.

**Milestone:** At least one model successfully converted to CoreML format.

---

## Phase 2: Proof of concept — [#4](https://github.com/tigger04/superscale/issues/4)

**Goal:** Prove that a CoreML-converted model can upscale an image in Swift and that the output quality is acceptable.

**Tasks:**
1. Minimal Swift script that loads the `.mlpackage` and runs a single small image through it
2. Visual inspection of output quality (correct resolution, no artefacts, sharp detail)
3. Measure inference time on Apple Silicon (target: 1024×1024 at 4× in under 30 seconds on M3 Air)
4. Document any quality or compatibility issues

**Artefacts:** Working proof of concept. Benchmark numbers. Sample output images.

**Milestone:** One image successfully upscaled via CoreML with acceptable quality.

---

## Phase 3: CLI implementation — [#11](https://github.com/tigger04/superscale/issues/11)

**Goal:** A complete, usable CLI that upscales images using CoreML.

This is the largest phase, tracked via sub-issues:

### Phase 3a: Image I/O — [#6](https://github.com/tigger04/superscale/issues/6)

- **ImageLoader** — read input images (PNG, JPEG, TIFF, HEIC) via CGImage
- **ImageWriter** — write output preserving colour profile
- Alpha channel extraction and recombination

### Phase 3b: Tiling engine — [#7](https://github.com/tigger04/superscale/issues/7)

- **Tiler** — split large images into overlapping tiles of configurable size
- Stitch upscaled tiles with overlap blending
- Configurable tile size (`--tile-size`)

### Phase 3c: CoreML inference — [#8](https://github.com/tigger04/superscale/issues/8)

- **CoreMLInference** — load `.mlpackage`, run prediction per tile
- **ModelRegistry** — catalogue of supported models with metadata
- Model resolution (bundled, user path, download)

### Phase 3d: Pipeline integration — [#9](https://github.com/tigger04/superscale/issues/9)

- Wire Image I/O → Tiler → Inference → Tiler → Image I/O
- Progress reporting to stderr (tile N of M)
- Error handling with clear messages

### Phase 3e: CLI polish — [#10](https://github.com/tigger04/superscale/issues/10)

- Batch processing — multiple input files, directory input
- All CLI flags working end-to-end
- `--list-models`, `--help`, `--version` (scaffolded, needs wiring)

**Artefacts:** Working `superscale` binary. Test suite for each component.

**Milestone:** `superscale input.png` produces correct output, end to end.

---

## Phase 4: Licensing review — [#5](https://github.com/tigger04/superscale/issues/5)

**Goal:** Finalise the project licence before going public.

Licensing is a gate — it must be resolved before distribution (Phase 5). The project currently uses MIT as a placeholder.

**Tasks:**
1. Review licence options given model weight licences (BSD-3-Clause from Real-ESRGAN)
2. Decide on project licence (MIT, BSD-3-Clause, Apache-2.0, or other)
3. Ensure THIRD_PARTY_LICENSES is complete and accurate
4. Legal review of GFPGAN download approach (we don't redistribute, user downloads from upstream)
5. Update LICENSE file

**Artefacts:** Final LICENSE file.

**Note:** Downstream projects (Upscayl, video2x, ComfyUI, Cupscale) each choose their own licence and include BSD-3-Clause notice for Real-ESRGAN weights as a third-party component. BSD-3-Clause does not require downstream projects to adopt it. See [model licensing](model-licensing.md).

**Milestone:** Licence finalised and documented.

---

## Phase 5: Distribution — [#12](https://github.com/tigger04/superscale/issues/12)

**Goal:** Homebrew formula, release automation, public-ready packaging.

**Prerequisite:** Phase 4 (licensing review) must be complete.

**Tasks:**
1. Homebrew formula (`Formula/superscale.rb`)
2. `make release` automation (tag, build, push, update formula, push tap)
3. Model storage strategy decided and implemented (see [issue #2](https://github.com/tigger04/superscale/issues/2))
4. README quickstart verified end-to-end
5. `brew install superscale && superscale photo.png` works from zero
6. Set GitHub repo to public

**Artefacts:** `brew tap tigger04/tap && brew install superscale` works.

**Milestone:** A non-developer can install and use Superscale via Homebrew.

---

## Phase 6: Model download — [#13](https://github.com/tigger04/superscale/issues/13)

**Goal:** Support models that aren't bundled, downloaded on demand.

**Tasks:**
1. Model manifest (JSON) listing available models and download URLs
2. First-use download with progress indicator
3. SHA256 verification of downloaded models
4. `superscale --download-models` to pre-fetch all models
5. Model storage location (decided in Phase 5, see [issue #2](https://github.com/tigger04/superscale/issues/2))

**Artefacts:** Model download infrastructure. Manifest file.

**Milestone:** `superscale -m anime input.png` auto-downloads the anime model on first use.

---

## Phase 7: Face enhancement (GFPGAN) — [#1](https://github.com/tigger04/superscale/issues/1)

**Goal:** Optional GFPGAN face enhancement as a user-initiated download.

**Tasks:**
1. Investigate CoreML conversion of GFPGAN architecture
2. `superscale --download-face-model` with licence notice and confirmation
3. `superscale --face-enhance input.png` runs face enhancement after upscaling
4. Clear error if model not downloaded
5. GFPGAN weights excluded from all distribution artefacts

**Artefacts:** Face enhancement pipeline. Download with licence notice.

**Dependency:** Tracked in [issue #1](https://github.com/tigger04/superscale/issues/1).

**Risk:** GFPGAN's architecture (StyleGAN2 + UNet) is more complex than RRDBNet. CoreML conversion may require workarounds or may not be feasible, in which case we'd need an alternative approach.

**Milestone:** `superscale --face-enhance portrait.png` produces visibly improved faces.

---

## Phase 8: macOS SwiftUI GUI — [#14](https://github.com/tigger04/superscale/issues/14)

**Goal:** A native macOS app for drag-and-drop image upscaling.

**Tasks:**
1. Extract shared code into SuperscaleKit library target
2. SwiftUI app target in the same Swift package
3. Drag-and-drop image input
4. Before/after preview with comparison slider
5. Model and scale selection
6. Progress indicator
7. Batch queue with thumbnail previews
8. Settings (default model, output format, output directory)
9. App icon and polish

**Artefacts:** `Superscale.app` distributed as DMG or via Homebrew Cask.

**Milestone:** A non-technical user can upscale an image by dragging it onto the app.

---

## Phase 9: macOS App Store — [#15](https://github.com/tigger04/superscale/issues/15)

**Goal:** Distribute the macOS GUI via the Mac App Store.

**Tasks:**
1. App Store provisioning, certificates, entitlements
2. App sandboxing compliance (file access, network for model download)
3. App Store review guidelines compliance
4. Privacy policy, app description, screenshots
5. Model bundling strategy for App Store (must be self-contained or use on-demand resources)
6. Pricing decision (free, paid, freemium)
7. Submit for review

**Artefacts:** App Store listing.

**Risk:** App Store sandboxing restricts filesystem access. `~/Library/Application Support/superscale/` is accessible under sandbox, but downloading models at runtime requires the network entitlement. The Homebrew CLI and App Store GUI may need different model delivery strategies (on-demand resources vs direct download).

**Milestone:** Superscale available on the Mac App Store.

---

## Phase 10: iOS app — [#16](https://github.com/tigger04/superscale/issues/16)

**Goal:** Bring Superscale to iPhone and iPad.

**Tasks:**
1. Adapt SuperscaleKit for iOS (CoreML works on iOS, but image I/O differs)
2. iOS SwiftUI interface — photo picker, share sheet integration
3. Memory management for large images on devices with less RAM
4. Tile size tuning for iOS Neural Engine (different performance profile)
5. Photos extension (upscale from within the Photos app)
6. iPad-specific layout

**Artefacts:** iOS app target.

**Risk:** iPhone RAM constraints. A 1024×1024 → 4096×4096 upscale produces a large intermediate buffer. Tile-based processing helps but needs careful memory management. Older devices (A-series chips) may be too slow.

**Milestone:** Superscale runs on iPhone, producing the same output as the Mac version.

---

## Phase 11: iOS App Store — [#17](https://github.com/tigger04/superscale/issues/17)

**Goal:** Distribute the iOS app via the App Store.

**Tasks:**
1. iOS App Store provisioning
2. On-demand resources for model files (avoid bloating the app download)
3. App Store review guidelines compliance
4. Screenshots for iPhone and iPad
5. Pricing (may differ from macOS)
6. Submit for review

**Artefacts:** iOS App Store listing.

**Milestone:** Superscale available on the iOS App Store.

---

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 0.1 | 2026-03-18 | Initial 5-phase plan |
| 0.2 | 2026-03-18 | Expanded to 11 phases: added proof of concept, face enhancement, licensing, App Store, and iOS phases |
| 0.3 | 2026-03-18 | Reordered: licensing (Phase 4) now gates distribution (Phase 5). Broke Phase 3 into sub-phases (3a–3e). Removed PyTorch comparison from Phase 2. Added model storage strategy cross-reference. |
| 0.4 | 2026-03-18 | Added issue index and linked all phases to GitHub issues (#1–#17). Allocated test IDs RT-008–RT-031 and UT-001–UT-006. |
| 0.5 | 2026-03-18 | Replaced issue index with execution order table showing dependencies. Integrated #2 and #18 into roadmap. Added dependency graph. |
| 0.6 | 2026-03-18 | Added status column to execution order. Marked #2, #3, #18 as closed. Updated roadmap with completion markers. |
| 0.7 | 2026-03-18 | Marked #4 (PoC) and #5 (licensing) as implemented. |
| 0.8 | 2026-03-19 | Phase 3 complete — closed #6, #7, #8, #9, #10. CLI fully functional. |
| 0.9 | 2026-03-19 | Phase 5 implemented — release script, Homebrew formula, first release v0.2.0. |
| 1.0 | 2026-03-19 | Auto-detect content type (#22). All models bundled (#12). README/docs updated (#23). Face enhancement scaffolding (#1). Closed #13 (folded into #12). |
| 1.1 | 2026-03-26 | Closed #4 (PoC), #5 (licensing), #12 (distribution), #1 (face enhancement). Added #33 (model caching), #35 (--list-models face model), #34 (SSIM — future). Updated statuses and roadmap. |

## See also

- [Vision](VISION.md) — project goals
- [Architecture](architecture.md) — system design
- [Testing](testing.md) — test strategy
- [Model licensing](model-licensing.md) — licence status of model weights
