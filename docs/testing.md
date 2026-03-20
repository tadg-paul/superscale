<!-- Version: 0.5 | Last updated: 2026-03-20 -->

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

## Test structure

```
Tests/SuperscaleTests/
├── CLITests.swift                # End-to-end CLI subprocess tests
├── CoreMLTests.swift             # CoreML inference tests (skip when model not available)
├── LicensingTests.swift          # Licence and attribution validation
├── ManifestTests.swift           # Model manifest schema validation
├── ModelRegistryTests.swift      # Model lookup, metadata, --list-models status
├── TilerTests.swift              # Tile splitting and stitching (planned)
├── ImageLoaderTests.swift        # Image reading, format detection (planned)
├── ImageWriterTests.swift        # Output writing, format options (planned)
├── QualityTests.swift            # Output vs reference comparison (planned)
├── Resources/
│   ├── test_input_64x64.png      # Minimal test image (planned)
│   ├── test_input_alpha.png      # Image with alpha channel (planned)
│   └── reference_output_4x.png   # Known-good reference output (planned)
└── NEXT_IDS.txt                  # Test ID allocation
```

## Quality validation

Output quality is validated by inspection and automated checks:

1. Output image has the correct dimensions (input × scale factor)
2. Visual inspection — sharp detail, no tiling artefacts, no colour shifts
3. Automated regression: a known input image produces output that is pixel-identical (or within tolerance) across builds

Formal PSNR metrics may be added later if needed. The primary quality gate is visual correctness.

## Test images

Test images are small (64×64 or 128×128) synthetic images to keep the test suite fast. Quality validation uses a single 256×256 natural image with a known-good reference output.

No production images, copyrighted content, or user data in the test suite.

## Test IDs

Per project standards, all tests carry unique IDs:

| Prefix | Type | Run by |
|--------|------|--------|
| `RT-NNN` | Regression test | `make test` |
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
| `remy1.png` | Sketch (PNG, with alpha) | Illustration upscaling, alpha channel handling |
| `remy2.jpg` | Sketch (JPEG) | Illustration upscaling, JPEG format |
| `roundwood.jpg` | Landscape photo | General photo upscaling |
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
test            # swift test (all regression tests)
test-one-off    # Run one-off tests
test-visual     # Upscale test images for visual inspection
```

## See also

- [Architecture](architecture.md) — component overview
- [Implementation plan](implementation-plan.md) — which phases introduce which tests
