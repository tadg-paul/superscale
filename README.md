# Superscale

AI image upscaling that runs locally on your Mac, using Apple's Neural Engine — dedicated ML hardware built into every M-series chip. Images never leave your machine, CPU and GPU stay free, and a 1024×1024 image upscales 4× in seconds.

## Quickstart

```bash
brew install tigger04/tap/superscale
superscale photo.png
```

## Usage

```bash
# Upscale an image — auto-detects best model
superscale photo.png

# Specify scale factor and output directory
superscale -s 2 -o upscaled/ photo.png

# Fractional scale (e.g. make image 2.4× larger)
superscale -s 2.4 photo.png

# Target resolution — fit within 4096×4096 preserving aspect ratio
superscale --width 4096 --height 4096 photo.png

# Target resolution — stretch to exact dimensions
superscale --width 1920 --height 1080 --stretch photo.png

# Process multiple images at once
superscale -o output/ *.png

# Override model selection
superscale -m realesrgan-anime-6b illustration.png

# Use denoising model for old/grainy photos
superscale -m realesr-general-wdn-x4v3 old_photo.jpg

# List available models (including face enhancement status)
superscale --list-models

# Clear compiled model cache (forces recompilation on next use)
superscale --clear-cache
```

## Models

Seven models are bundled, auto-selected by content type (photo, illustration, anime) using Apple's Vision framework. Override with `-m`:

| CLI name (`-m`) | Scale | Best for |
|---|---|---|
| `realesrgan-x4plus` | 4× | General photos (default) |
| `realesrgan-x2plus` | 2× | General photos, lighter upscale |
| `realesrnet-x4plus` | 4× | Photos, PSNR-oriented (less sharpening) |
| `realesrgan-anime-6b` | 4× | Anime/illustration |
| `realesr-animevideov3` | 4× | Anime video frames |
| `realesr-general-x4v3` | 4× | General scenes, compact model |
| `realesr-general-wdn-x4v3` | 4× | General scenes with denoise — effective for old photos, grainy images, or heavily compressed sources |

All seven bundled models are Real-ESRGAN weights, licensed under BSD-3-Clause (Copyright Xintao Wang, 2021). See [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES) and [model licensing](docs/model-licensing.md).

## Face Enhancement (optional)

GFPGAN face enhancement is not bundled due to its non-commercial licence. To install it:

```bash
superscale --download-face-model
```

The face model cannot be installed non-interactively. Running `--download-face-model` presents the licence terms; you must accept them manually before the download proceeds. This is intentional: the [NVIDIA Source Code License](https://github.com/NVlabs/stylegan2/blob/master/LICENSE.txt) and [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) components require informed, affirmative acceptance and are non-commercial only.

Once installed, face enhancement runs automatically on every upscale. Use `--no-face-enhance` to skip it.

The licence applies to the model weights, not to output images. See [model licensing](docs/model-licensing.md) for details.

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon (M1–M5+)

No other dependencies. Everything runs on built-in system frameworks.

**x86 Caveat:** Superscale requires Apple Silicon and won't run on older Intel-based Macs or Linux. A good alternative for x86 is [Upscayl](https://github.com/upscayl/upscayl).

## Install

### Homebrew (recommended)

```bash
brew install tigger04/tap/superscale
```

### From source

Requires Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/tigger04/superscale.git
cd superscale
make install
```

## Makefile Targets

| Target | Description |
|---|---|
| `make build` | Download models (if needed) + build release binary |
| `make test` | Run regression tests (excludes slow SSIM quality gate) |
| `make test-ssim` | Run SSIM quality regression against PyTorch references (~2.5 min) |
| `make install` | Build + symlink to `~/.local/bin` |
| `make release` | Tag, build CLI, push, update Homebrew formula (runs both test packs) |
| `make release-gui` | Build GUI .app, package DMG, update Homebrew cask |
| `make release-models` | Upload model artefacts to GitHub Release |
| `make download-models` | Download missing models from GitHub release |
| `make convert-models` | Run PyTorch → CoreML conversion (dev only) |
| `make clean` | Remove build artefacts |
| `make sync` | Git add, commit, pull, push |

## Documentation

| Document | Description |
|---|---|
| [Vision](docs/VISION.md) | Project goals, non-goals, and design philosophy |
| [Architecture](docs/architecture.md) | System design, data flow, component overview |
| [Testing](docs/testing.md) | Test strategy, coverage, and conventions |
| [Implementation plan](docs/implementation-plan.md) | Phased delivery plan |
| [Model licensing](docs/model-licensing.md) | Licence status of bundled model weights |

## Licence

MIT. Copyright Taḋg Paul.

Bundled model weights (Real-ESRGAN) are BSD-3-Clause (Copyright Xintao Wang, 2021). See [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES).

The optional GFPGAN face model is not bundled and contains non-commercial components (StyleGAN2, DFDNet). The licence applies to the model weights, not to output images. See [model licensing](docs/model-licensing.md).
