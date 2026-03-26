<!-- Version: 0.2 | Last updated: 2026-03-26 -->

# Vision

## Purpose

Superscale is a native macOS CLI (and eventually GUI) for AI image upscaling on Apple Silicon, using CoreML to run Real-ESRGAN models on the Neural Engine and GPU.

## Problem

Real-ESRGAN is the de facto standard for AI image upscaling. But using it on a Mac is painful:

- The Python/PyTorch implementation runs on CPU only (no CUDA on Mac). A single 1024×1024 image at 4× takes 10+ minutes on an M3 Air and pins the CPU at 100%, generating enough heat to throttle the machine.
- The dependency chain is enormous: Python, pip, venv, PyTorch, torchvision, basicsr, numpy, opencv — each with its own version conflicts and compatibility shims.
- The ncnn-vulkan C++ port exists but is effectively unmaintained (last commit April 2022) and requires MoltenVK as a Vulkan-on-Metal translation layer.

Meanwhile, every M-series Mac ships with a Neural Engine — dedicated hardware specifically designed for running neural networks, sitting idle.

## Solution

Convert the Real-ESRGAN PyTorch models to CoreML format and run them natively through Apple's frameworks:

1. **One-time conversion** (build/release time): use `coremltools` to translate `.pth` weights to `.mlpackage` format
2. **Runtime**: a Swift CLI loads the CoreML model, feeds it image tiles, reassembles the output. Zero Python, zero third-party frameworks.
3. **Distribution**: a single binary + model files, installable via Homebrew

The Neural Engine handles the inference. The result is the same model, same quality, orders of magnitude faster.

## Workflow

```
superscale input.png                    # 4× upscale, writes input_4x.png
superscale -s 2 -o out/ photo.jpg       # 2× upscale to output directory
superscale -m anime -o out/ *.png       # Anime model, batch processing
```

## Design principles

1. **Native first.** Use Apple's frameworks (CoreML, Vision, AppKit) rather than cross-platform abstractions. This is a Mac tool for Mac users.
2. **Zero runtime dependencies.** The binary and model files are all you need. No Python, no pip, no Docker, no runtime downloads.
3. **CLI first, GUI second.** The CLI is the primary interface. A SwiftUI GUI will follow, sharing the same pipeline code.
4. **Same models, better runtime.** We don't train new models. We take the proven Real-ESRGAN weights and run them on better hardware.
5. **Honest about scope.** This is an upscaler, not an image editor. It does one thing well.

## Non-goals

- **Training models.** We convert and run existing weights. Training is a separate concern with different tools.
- **Cross-platform.** This is macOS-only by design. Linux/Windows users should use the Python or ncnn-vulkan versions.
- **Bundling GFPGAN.** GFPGAN (face enhancement) has non-commercial licence encumbrances (StyleGAN2, DFDNet). We do not bundle or redistribute it. It is available as an optional user-initiated download (`--download-face-model`) with explicit licence acceptance.
- **Video processing.** Out of scope for v1. May be added later as frame-by-frame processing.
- **Real-time preview.** Not a goal for the CLI. May be a goal for the GUI.

## Target platforms

- macOS 14+ (Sonoma and later)
- Apple Silicon only (M1, M2, M3, M4 families)
- Intel Macs are not supported — they lack the Neural Engine

## Delivery phases

1. **CoreML model conversion** — convert Real-ESRGAN models, validate output quality
2. **Proof of concept** — single image upscaled via CoreML in Swift
3. **CLI implementation** — full pipeline with tiling, batch processing, model selection
4. **Licensing review** — finalise licence before going public
5. **Distribution** — Homebrew formula, public repo
6. **Model download** — on-demand download of non-bundled models
7. **Face enhancement** — optional GFPGAN download
8. **macOS GUI** — SwiftUI drag-and-drop app
9. **macOS App Store** — App Store distribution
10. **iOS app** — iPhone and iPad
11. **iOS App Store** — iOS distribution

See [implementation plan](implementation-plan.md) for detail.

## Success criteria

- 1024×1024 image at 4× completes in under 30 seconds on an M3 Air
- Output quality is visually indistinguishable from the PyTorch reference
- `brew install superscale && superscale photo.png` works from zero to output
- Zero runtime dependencies beyond macOS system frameworks
