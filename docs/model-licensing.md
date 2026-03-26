<!-- Version: 0.3 | Last updated: 2026-03-26 -->

# Model licensing

## Summary

Superscale bundles AI model weights converted from the [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) project. This document records the licence status of each model.

## Real-ESRGAN models

The Real-ESRGAN repository is licensed under **BSD-3-Clause** (Copyright 2021, Xintao Wang). The model weights are distributed as GitHub release assets within the same repository, with no separate licence terms. The prevailing community interpretation — shared by [OpenModelDB](https://openmodeldb.info), [Upscayl](https://github.com/upscayl/upscayl), and downstream users — is that the BSD-3-Clause licence covers the weights.

**Note:** Xinntao has not explicitly confirmed this interpretation. [Issue #677](https://github.com/xinntao/Real-ESRGAN/issues/677) asking for clarification remains unanswered. The risk is assessed as low given community precedent and the author's clear intent to release the project under BSD-3-Clause.

### Per-model status

| Model | Scale | Licence | Redistribute? |
|-------|-------|---------|---------------|
| RealESRGAN_x4plus | 4× | BSD-3-Clause | Yes, with attribution |
| RealESRGAN_x2plus | 2× | BSD-3-Clause | Yes, with attribution |
| RealESRNet_x4plus | 4× | BSD-3-Clause | Yes, with attribution |
| RealESRGAN_x4plus_anime_6B | 4× | BSD-3-Clause | Yes, with attribution |
| realesr-animevideov3 | 4× | BSD-3-Clause | Yes, with attribution |
| realesr-general-x4v3 | 4× | BSD-3-Clause | Yes, with attribution |
| realesr-general-wdn-x4v3 | 4× | BSD-3-Clause | Yes, with attribution (not currently bundled) |
| GFPGAN (face enhancement) | n/a | Apache-2.0, but weights contain non-commercial components (StyleGAN2, DFDNet) | **No** — available as optional user download only. See [excluded models](#excluded-models) below. |

### Training data note

The models were trained on the DF2K + OST dataset. DIV2K (part of DF2K) restricts use to academic research. Whether this restriction flows through to model weights is an open legal question. The prevailing practice across the ML community — including major commercial products — treats model weights as separate artefacts governed by their own licence. Xinntao chose BSD-3-Clause.

## CoreML conversion

Converting `.pth` weights to `.mlpackage` format is a mechanical transformation (analogous to compiling source to binary). The original BSD-3-Clause licence carries over to the converted weights. Attribution is preserved in `THIRD_PARTY_LICENSES`.

## Excluded models

### GFPGAN (face enhancement)

GFPGAN (TencentARC) is **not included** in Superscale. While GFPGAN's own code is Apache-2.0, its pretrained weights embed components with restrictive licences:

- **StyleGAN2** (NVIDIA): non-commercial use only
- **DFDNet**: CC BY-NC-SA 4.0 (non-commercial, share-alike)

GFPGAN's Apache-2.0 licence explicitly carves out these third-party components. Redistributing GFPGAN weights in an open-source project carries meaningful legal risk.

## Downstream projects

Other projects that redistribute Real-ESRGAN model weights each choose their own project licence and include BSD-3-Clause attribution for the weights as a third-party component:

| Project | Project licence | Redistributes weights? | Approach |
|---------|----------------|----------------------|----------|
| [Upscayl](https://github.com/upscayl/upscayl) | AGPL-3.0 | Yes (bundled) | BSD-3-Clause notice in THIRD_PARTY |
| [video2x](https://github.com/k4yt3x/video2x) | AGPL-3.0 | Yes (bundled) | BSD-3-Clause notice in THIRD_PARTY |
| [ComfyUI](https://github.com/comfyanonymous/ComfyUI) | GPL-3.0 | Yes (via nodes) | BSD-3-Clause notice |
| [Cupscale](https://github.com/n00mkrad/cupscale) | MIT | Yes (bundled) | BSD-3-Clause notice |

BSD-3-Clause does not require downstream projects to adopt the same licence. The only obligations are: retain the copyright notice, retain the licence text, and do not use the author's name to endorse derivatives.

## Attribution

All converted models include attribution in [`THIRD_PARTY_LICENSES`](../THIRD_PARTY_LICENSES).

## See also

- [Real-ESRGAN LICENSE](https://github.com/xinntao/Real-ESRGAN/blob/master/LICENSE)
- [GFPGAN LICENSE](https://github.com/TencentARC/GFPGAN/blob/master/LICENSE)
- [OpenModelDB: Real-ESRGAN models](https://openmodeldb.info)
