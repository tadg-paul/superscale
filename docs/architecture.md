<!-- Version: 0.5 | Last updated: 2026-03-26 -->

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
│  ┌─────────┐  ┌──────────────┐                  │
│  │  Image   │  │  Content     │                  │
│  │  Loader  │  │  Detector    │                  │
│  └────┬─────┘  └──────┬───────┘                  │
│       │               │                          │
│       ▼               ▼                          │
│  ┌──────────┐  ┌────────────────┐                │
│  │  Tiler   │  │  CoreML        │                │
│  │  (split) │──▶  Inference    │                │
│  └──────────┘  └───────┬────────┘                │
│                         │                        │
│  ┌──────────┐          │                         │
│  │  Tiler   │◀─────────┘                         │
│  │  (stitch)│                                    │
│  └────┬─────┘                                    │
│       │                                          │
│       ▼                                          │
│  ┌──────────────┐  ┌─────────┐                   │
│  │  Face         │  │  Image  │                   │
│  │  Enhancer     │──▶ Writer │                   │
│  └──────────────┘  └─────────┘                   │
└─────────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│  Model Management                               │
│  ┌────────────────┐  ┌────────────────────────┐ │
│  │ ModelRegistry   │  │ FaceModelRegistry      │ │
│  │ (7 bundled)     │  │ (optional GFPGAN)      │ │
│  └────────┬───────┘  └────────────────────────┘ │
│           │                                      │
│  ┌────────▼───────┐                              │
│  │ ModelCache      │                              │
│  │ (compiled       │                              │
│  │  .mlmodelc)     │                              │
│  └────────────────┘                              │
└─────────────────────────────────────────────────┘
```

## Components

### CLI layer

`SuperscaleCommand.swift` — uses Swift ArgumentParser. The root command is `Superscale` with flags for model selection, scale factor, output directory, face model download, cache management, and model listing.

**Responsibilities:**
- Parse and validate CLI arguments
- Resolve input/output paths
- Select model by name (`-m`) or auto-detect via `ContentDetector`
- Report progress to stderr
- Exit codes: 0 success, 1 error, 2 misuse

**Help system** (`HelpFormatter.swift`, `Pager.swift`) — ArgumentParser's built-in help is disabled (`helpNames: []`). A custom `-h`/`--help` flag generates a man-page-style manual with sections for usage, options, examples, model details, and licensing. `HelpFormatter` generates the text with optional ANSI colour (bold headers, underlined placeholders) based on terminal detection, `NO_COLOR`, and `TERM`. `Pager` resolves the pager from `MANPAGER` → `PAGER` → `less` → direct output, and only invokes it when stdout is a terminal and stdin is interactive.

### Pipeline

All source files are in `Sources/Superscale/`. The core processing sequence:

1. **ImageLoader** — reads input image via `CGImageSource`. Supports PNG, JPEG, TIFF, HEIC. Extracts dimensions, colour profile, and alpha channel.

2. **ContentDetector** — auto-detects whether an image is a photograph or illustration using colour diversity analysis and Vision framework classification. Selects the optimal model for the content type.

3. **Tiler** — splits the input image into overlapping tiles of configurable size (default 512px, 16px overlap). Large images cannot be processed in one pass due to memory constraints. Uses distance-weighted blending during reassembly to eliminate seam artefacts.

4. **CoreMLInference** — loads the `.mlpackage` model via `ModelCache`, creates a `VNCoreMLRequest`, runs each tile through the model. The model outputs a tile at `scale×` the input resolution. CoreML automatically dispatches to the Neural Engine, GPU, or CPU depending on hardware and model compatibility.

5. **Tiler (stitch)** — reassembles upscaled tiles into the final output image, blending overlap regions with distance-based weights.

6. **FaceEnhancer** — optional post-processing step. Uses `FaceDetector` (Vision framework) to locate faces, crops each with 1.5× padding, runs through the GFPGAN CoreML model at 512×512, and blends back with feathered edges. Runs automatically when the GFPGAN model is installed, skipped with `--no-face-enhance`.

7. **ImageWriter** — writes the output as PNG or JPEG, preserving the colour profile from the input.

### Model management

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

**FaceModelRegistry** — manages the optional GFPGAN face enhancement model, which is not bundled due to non-commercial licence terms. Handles download URL, installation status, and path resolution.

**Model resolution order** (searched in priority):
1. Models directory next to the executable (direct install)
2. Homebrew Cellar layout (`<prefix>/models/`)
3. User application support: `~/Library/Application Support/superscale/models/`
4. Working directory `./models/` (development)

**Model storage:**
- Bundled: all 7 Real-ESRGAN models are installed with the binary (Homebrew or `make install`)
- GFPGAN: downloaded to `~/Library/Application Support/superscale/models/` via `--download-face-model`

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
[ImageLoader: CGImageSource → CGImage 1024×1024 RGB + alpha]
    │
    ├──▶ [ContentDetector: photo or illustration → select model]
    │
    ▼
[Tiler: split into 512×512 tiles with 16px overlap]
    │
    ▼
[CoreML: each tile → model → 2048×2048 tile]
    │
    ▼
[Tiler: stitch tiles, distance-weighted blend → 4096×4096]
    │
    ▼
[FaceEnhancer: detect faces → GFPGAN → feathered blend (optional)]
    │
    ▼
[Alpha: upscale via bicubic, recombine (if present)]
    │
    ▼
[Resize: to target dims if --scale/--width/--height specified (CGContext .high)]
    │
    ▼
[ImageWriter: save as PNG/JPEG, preserve colour profile]
    │
    ▼
output_4x.png
```

## Target resolution

When `--scale` (float), `--width`, or `--height` is specified, a post-pipeline resize step adjusts the output to the requested dimensions. This happens after all AI processing (upscale, stitch, face enhance, alpha) so the model always operates at its native resolution.

The resize uses `CGContext` with `.high` interpolation quality (Lanczos). If the target exceeds the model's native scale, a warning is emitted but processing continues — AI upscale + interpolation is still better than pure interpolation.

## Alpha channel handling

If the input image has an alpha channel (transparency):

1. Extract the alpha channel as a separate greyscale image
2. Upscale the RGB channels through the model
3. Upscale the alpha channel via bicubic interpolation (fast, usually sufficient)
4. Recombine RGB + alpha into the output image

## Error handling

- Invalid input paths: fail immediately with descriptive message
- Unsupported image format: fail with list of supported formats
- Model not found: fail with instructions to install or download
- CoreML inference failure: fail with the MLModel error, suggest `--tile-size` reduction
- Output write failure: fail with filesystem error
- Face enhancement failure: log warning and preserve original face region

All errors go to stderr. Only `--list-models` and `--version` produce stdout output; progress reporting goes to stderr.

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
