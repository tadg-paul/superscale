<!-- Version: 0.8 | Last updated: 2026-03-28 -->

# Testing

## Strategy

Testing follows TDD per project standards. All tests use XCTest and run via `make test` (`swift test`).

## Test types

| Type | Scope | Location | Speed |
|------|-------|----------|-------|
| Unit | Individual functions, model registry, path resolution | `Tests/SuperscaleTests/` | Fast (<1s) |
| Integration | Full pipeline with small test images | `Tests/SuperscaleTests/` | Medium (<10s) |
| End-to-end | CLI invocation via subprocess | `Tests/SuperscaleTests/` | Slow (<30s) |
| Quality | Output correctness and regression checks | `Tests/SuperscaleTests/` | Slow |
| SSIM quality gate | CoreML vs PyTorch reference comparison | `Tests/SuperscaleTests/` | Slow (~2.5 min) |

## Test structure

```
Tests/SuperscaleTests/
├── CLITests.swift                # End-to-end CLI subprocess tests
├── ContentDetectorTests.swift    # Content type detection heuristics
├── CoreMLTests.swift             # CoreML inference and model caching tests
├── FaceEnhancerTests.swift       # Face detection and enhancement
├── ImageIOTests.swift            # Image loading, format detection, alpha handling
├── LicensingTests.swift          # Licence and attribution validation
├── ManifestTests.swift           # Model manifest schema validation
├── ModelRegistryTests.swift      # Model lookup, metadata, --list-models status
├── PipelineTests.swift           # Full pipeline integration tests
├── SSIMTests.swift               # SSIM computation and quality regression
├── TilerTests.swift              # Tile splitting and stitching
├── Resources/references/         # PyTorch reference images for SSIM comparison
└── NEXT_IDS.txt                  # Test ID allocation
```

## Quality validation

Output quality is validated by inspection and automated checks:

1. Output image has the correct dimensions (input × scale factor)
2. Visual inspection — sharp detail, no tiling artefacts, no colour shifts
3. Automated regression: a known input image produces output that is pixel-identical (or within tolerance) across builds
4. **SSIM quality gate** — automated comparison of CoreML output against PyTorch reference images ([#34](https://github.com/tigger04/superscale/issues/34))

### SSIM quality regression testing

SSIM (Structural Similarity Index Measure) compares CoreML output against ground-truth PyTorch Real-ESRGAN output for a set of 7 test images. A score of 1.0 means identical; ≥ 0.90 passes. Any image scoring below 0.90 blocks `make release`. This catches quality regressions (colour shifts, sharpness loss, spatial rearrangement) that visual inspection might miss.

**Test separation:** The regression pack (`make test`) already takes ~5 minutes. RT-064 (the full pipeline SSIM comparison) adds another ~2.5 minutes — nearly 50% on top. To keep the development cycle from growing further, RT-064 runs via `make test-ssim` at release time, not during development. Fast SSIM unit tests (RT-062 reference existence, RT-063 SSIM computation correctness) remain in `make test`. `make release` runs both packs (~7.5 min total) — a failing SSIM gate blocks the release.

**SSIM test set:** All 7 test images. (`roundwood.jpg` was removed from the repo — it scored 0.826 due to the cumulative effect of photographic content, JPEG compression, and 4-tile processing, which would have required lowering the threshold and compromising the gate's sensitivity.)

**Reference images** are stored in `Tests/SuperscaleTests/Resources/references/` as PNG files named `{stem}_ref.png`. They are generated from the default model (`realesrgan-x4plus`) using the original PyTorch weights.

**Regenerating references** (requires PyTorch — dev-time only):
```bash
source .venv/bin/activate
pip install -r scripts/requirements-convert.txt
python scripts/generate_references.py
```

**Threshold:** SSIM ≥ 0.90 (configurable in `SSIMTests.swift`). The initial target of 0.95 proved too tight due to inherent differences between PyTorch CPU and CoreML Neural Engine pipelines — tiling strategy, padding mode, and JPEG quantisation all contribute to divergence. 0.90 balances sensitivity (flags real degradation) against tolerance (accepts legitimate pipeline differences). See the [SSIM findings](https://github.com/tigger04/superscale/issues/34#issuecomment-4143555309) for the full score breakdown per image.

**Alpha masking:** For RGBA images, 8×8 windows where ≥50% of pixels are transparent (alpha < 128) are excluded from the SSIM score. Without this, images with large transparent regions score artificially low because the RGB content behind transparent pixels differs between PyTorch (which composites against white via PIL) and CoreML (which strips alpha and processes raw RGB).

**Scope:** Default model only. GFPGAN and other models are excluded (face enhancement output is generative and requires a different validation approach).

## Test images

Test images in `Tests/images/` are real images of varying sizes and content types. They exercise different pipeline paths (single-tile vs multi-tile, opaque vs alpha, photo vs illustration, JPEG vs PNG).

No production images, copyrighted content, or user data in the test suite.

## Test IDs

Per project standards, all tests carry unique IDs:

| Prefix | Type | Run by |
|--------|------|--------|
| `RT-NNN` | Regression test | `make test` (or `make test-ssim` for RT-064) |
| `OT-NNN` | One-off test | `make test-one-off` |
| `UT-NNN` | User test | Manual |

IDs are allocated from `Tests/SuperscaleTests/NEXT_IDS.txt`.

## Visual testing

`make test-visual` upscales all images in `Tests/images/` and saves the results to `Tests/visual_output/` for manual inspection (UT-002 and similar user tests).

**Output directory:** `Tests/visual_output/` — gitignored, treated as ephemeral. Stale files from previous runs should be cleaned out before each run. The Makefile target handles this automatically.

**Originals** are copied with an `original_` prefix so before/after comparison is straightforward.

### Test images

| File | Type | Purpose |
|------|------|---------|
| `icon.png` | Icon (PNG, opaque) | Small sub-tile-size image, opaque |
| `icon2.png` | Icon (PNG, RGBA, 58% transparent) | Sub-tile-size, alpha channel, gradient colour |
| `icon3.png` | Icon (PNG, with alpha) | Sub-tile-size, alpha channel |
| `remy1.png` | Sketch (PNG, with alpha) | Illustration upscaling, alpha channel handling |
| `remy2.jpg` | Sketch (JPEG) | Illustration upscaling, JPEG format |
| `toby.jpg` | Dog photo | Photo upscaling (no human faces — control) |
| `vance-wilson.jpg` | Two people | Face enhancement validation |

### What to look for

- Sharp detail, no blurring
- No tiling artefacts (seams between tiles)
- No colour shifts
- Correct alpha channel preservation (PNG)
- Faces rendered naturally, not corrupted or blanked (see [#32](https://github.com/tigger04/superscale/issues/32))

## Makefile targets

```makefile
test            # swift test — regression tests (excludes slow SSIM gate)
test-ssim       # SSIM quality regression against PyTorch references (~2.5 min)
test-one-off    # Run one-off tests
test-visual     # Upscale test images for visual inspection
```

`make release` runs both `test` and `test-ssim` before tagging. If any SSIM test image scores below 0.90, the release is blocked.

## See also

- [Architecture](architecture.md) — component overview
- [Implementation plan](implementation-plan.md) — which phases introduce which tests
