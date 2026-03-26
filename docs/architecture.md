<!-- Version: 0.3 | Last updated: 2026-03-26 -->

# Architecture

## Overview

Superscale is a Swift CLI application that uses CoreML to run Real-ESRGAN image upscaling models on Apple Silicon. The architecture separates concerns into three layers: CLI interface, processing pipeline, and model management.

## System diagram

```
┌─────────────────────────────────────────────────┐
│  CLI (ArgumentParser)                           │
│  superscale -s 4 -m general -o out/ input.png   │
└──────────────────────┬──────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│  Pipeline                                       │
│  ┌─────────┐  ┌──────────┐  ┌────────────────┐ │
│  │  Image   │  │  Tiler   │  │   CoreML       │ │
│  │  Loader  │──▶ (split)  │──▶  Inference    │ │
│  └─────────┘  └──────────┘  └───────┬────────┘ │
│                                      │          │
│  ┌─────────┐  ┌──────────┐          │          │
│  │  Image   │  │  Tiler   │◀─────────┘          │
│  │  Writer  │◀──(stitch)  │                     │
│  └─────────┘  └──────────┘                      │
└─────────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│  Model Manager                                  │
│  - Registry of available .mlpackage files       │
│  - Model metadata (scale, architecture, size)   │
│  - Download on first use (if not bundled)       │
└─────────────────────────────────────────────────┘
```

## Components

### CLI layer (`Commands/`)

Uses Swift ArgumentParser. The root command is `Superscale` with default upscale behaviour and future subcommands for model management.

**Responsibilities:**
- Parse and validate CLI arguments
- Resolve input/output paths
- Select model by name or alias
- Report progress to stderr
- Exit codes: 0 success, 1 error, 2 misuse

### Pipeline (`Pipeline/`)

The core processing sequence:

1. **ImageLoader** — reads input image via `CGImage` / `NSImage`. Supports PNG, JPEG, TIFF, HEIC. Extracts dimensions and colour profile.

2. **Tiler** — splits the input image into overlapping tiles of configurable size. Large images cannot be processed in one pass due to memory constraints. Tiles overlap to avoid seam artefacts; the overlap region is blended during reassembly.

3. **CoreMLInference** — loads the `.mlpackage` model via `ModelCache`, creates a `VNCoreMLRequest`, runs each tile through the model. The model outputs a tile at `scale×` the input resolution. CoreML automatically dispatches to the Neural Engine, GPU, or CPU depending on hardware and model compatibility.

4. **Tiler (stitch)** — reassembles upscaled tiles into the final output image, blending overlap regions.

5. **ImageWriter** — writes the output as PNG or JPEG, preserving the colour profile from the input where possible.

### Model manager (`Models/`)

**ModelRegistry** — a static catalogue of supported models with metadata:

```swift
struct ModelInfo {
    let name: String          // e.g. "realesrgan-x4plus"
    let displayName: String   // e.g. "General Photo (4×)"
    let scale: Int            // 2 or 4
    let tileSize: Int         // recommended tile size
    let filename: String      // e.g. "RealESRGAN_x4plus.mlpackage"
}
```

**Model resolution order:**
1. `--model-path` flag (explicit path to `.mlpackage`)
2. Bundled models in the application support directory
3. Download from GitHub release (if first-use download is enabled)

**Model storage:**
- Bundled: installed to the Cellar with the binary (Homebrew), or `~/Library/Application Support/superscale/models/`
- Downloaded: `~/Library/Application Support/superscale/models/`
- See [issue #2](https://github.com/tigger04/superscale/issues/2) for the full storage strategy decision

### Compiled model cache (`ModelCache`)

CoreML `.mlpackage` files are a source format. At load time, `MLModel.compileModel(at:)` translates them into a device-optimized `.mlmodelc` bundle. `ModelCache` persists these compiled bundles so the compilation step is not repeated on every run.

**Cache location:** `~/Library/Application Support/superscale/compiled/`

**Cache invalidation:** The modification date of the source `.mlpackage` directory is stored as a cache key alongside each `.mlmodelc`. When the source changes (e.g. via `brew upgrade`), the key mismatches and the model is recompiled. The `--clear-cache` CLI flag forces recompilation of all models.

**Performance context (benchmarked on M3 Air, March 2026):**

| Operation | Time |
|-----------|------|
| `MLModel.compileModel(at:)` — compile `.mlpackage` → `.mlmodelc` | 0.18s |
| `MLModel(contentsOf:)` — load compiled model into memory | 3.2s |
| Total cold load (compile + load) | 3.4s |
| Total cached load (load only) | 3.2s |

For the current Real-ESRGAN models (RRDBNet / SRVGGNetCompact), the compilation step is only ~5% of total load time. The dominant cost is loading and initializing the model weights, which happens regardless of caching. The net saving is approximately **180ms per model load**.

The caching infrastructure is retained because:

1. Heavier model architectures (e.g. if larger or more complex models are added in future) may have a more expensive compilation step where the saving becomes significant.
2. The overhead of caching is negligible — a single `copyItem` on first load, a single `fileExists` + string comparison on subsequent loads.
3. The architecture is in place for the GUI phases (8–11), where any reduction in launch time matters more than in a CLI.

### Conversion tooling (`scripts/`)

**`convert_model.py`** — a Python script (used at build/release time only, never at runtime) that:

1. Loads a PyTorch `.pth` checkpoint
2. Reconstructs the RRDBNet or SRVGGNetCompact architecture
3. Converts to CoreML using `coremltools`
4. Validates the output against the PyTorch reference
5. Saves as `.mlpackage`

This script requires a Python venv with `torch`, `coremltools`, and `basicsr`. It runs once per model per release, not at runtime.

## Data flow

```
input.png
    │
    ▼
[CGImage: 1024×1024 RGB]
    │
    ▼
[Tiler: split into 512×512 tiles with 32px overlap]
    │
    ▼
[CoreML: each tile → model → 2048×2048 tile]
    │
    ▼
[Tiler: stitch tiles, blend overlaps → 4096×4096]
    │
    ▼
[ImageWriter: save as PNG/JPEG]
    │
    ▼
output_4x.png
```

## Alpha channel handling

If the input image has an alpha channel (transparency):

1. Extract the alpha channel as a separate greyscale image
2. Upscale the RGB channels through the model
3. Upscale the alpha channel via bicubic interpolation (fast, usually sufficient)
4. Recombine RGB + alpha into the output image

An optional `--alpha-model` flag can run the alpha channel through the AI model too, at the cost of additional processing time.

## Error handling

- Invalid input paths: fail immediately with descriptive message
- Unsupported image format: fail with list of supported formats
- Model not found: fail with instructions to install or download
- CoreML inference failure: fail with the MLModel error, suggest `--tile-size` reduction
- Output write failure: fail with filesystem error

All errors go to stderr. The binary produces no stdout output except when `--quiet` is not set (progress reporting).

## Future: GUI layer

The SwiftUI GUI will share the `Pipeline/` and `Models/` layers. The CLI and GUI are separate targets in the same Swift package, importing a shared `SuperscaleKit` library.

```
Package.swift
├── SuperscaleKit (library)    ← Pipeline + Models
├── superscale (executable)    ← CLI, depends on SuperscaleKit
└── Superscale (executable)    ← GUI, depends on SuperscaleKit
```

## External dependencies

| Dependency | Type | Licence |
|-----------|------|---------|
| Swift ArgumentParser | Swift package | Apache-2.0 |
| CoreML | System framework | macOS built-in |
| Vision | System framework | macOS built-in |
| CoreImage | System framework | macOS built-in |
| coremltools | Python (build-time only) | BSD-3-Clause |

## See also

- [Vision](VISION.md) — project goals and non-goals
- [Testing](testing.md) — test strategy
- [Implementation plan](implementation-plan.md) — phased delivery
- [Model licensing](model-licensing.md) — licence status of model weights
