#!/usr/bin/env python3
# ABOUTME: Converts GFPGAN PyTorch weights to CoreML .mlpackage format.
# ABOUTME: Build-time tool — never a runtime dependency. Requires torch, gfpgan, coremltools.

"""Convert GFPGAN face enhancement model to CoreML .mlpackage format.

Usage:
    python convert_gfpgan.py [--input FILE] [--output DIR]

Prerequisites:
    pip install torch gfpgan coremltools

    Download GFPGANv1.4.pth from:
    https://github.com/TencentARC/GFPGAN/releases/download/v1.3.4/GFPGANv1.4.pth
"""

import argparse
import logging
import sys
from pathlib import Path

# Compatibility shim: basicsr imports torchvision.transforms.functional_tensor
# which was removed in torchvision 0.18. Alias it to the current module.
import torchvision.transforms.functional
sys.modules["torchvision.transforms.functional_tensor"] = (
    torchvision.transforms.functional
)

logging.basicConfig(
    level=logging.INFO,
    format="%(levelname)s: %(message)s",
    stream=sys.stderr,
)
log = logging.getLogger(__name__)

FACE_SIZE = 512  # GFPGAN operates on 512×512 face crops


class GFPGANWrapper:
    """Wraps the GFPGAN model for CoreML tracing.

    Handles:
    - Loading GFPGANv1.4 weights using the clean architecture
    - Pre-generating noise tensors (replacing in-model stochastic noise)
    - Post-processing: rescaling output from [-1,1] to [0,1] range
    """

    def __init__(self, model_path: str):
        import torch

        log.info("Loading GFPGAN from %s...", model_path)

        # Use the GFPGAN library to load the model
        from gfpgan.archs.gfpganv1_clean_arch import GFPGANv1Clean

        model = GFPGANv1Clean(
            out_size=FACE_SIZE,
            num_style_feat=512,
            channel_multiplier=2,
            decoder_load_path=None,
            fix_decoder=False,
            num_mlp=8,
            input_is_latent=True,
            different_w=True,
            narrow=1,
            sft_half=True,
        )

        # Load pretrained weights
        state_dict = torch.load(model_path, map_location="cpu")
        if "params_ema" in state_dict:
            state_dict = state_dict["params_ema"]
        elif "params" in state_dict:
            state_dict = state_dict["params"]
        model.load_state_dict(state_dict, strict=True)
        model.eval()

        self.model = model

    def create_traceable(self):
        """Create a traceable nn.Module wrapper with fixed noise and post-processing."""
        import torch
        import torch.nn as nn

        model = self.model

        class TraceableGFPGAN(nn.Module):
            def __init__(self, gfpgan):
                super().__init__()
                self.gfpgan = gfpgan

            def forward(self, x):
                # Run GFPGAN inference with fixed noise (randomize_noise=False
                # uses pre-registered buffers; CoreML cannot convert normal_())
                output = self.gfpgan(x, return_rgb=False, randomize_noise=False)
                # output is a tuple; take the first element (the enhanced face)
                if isinstance(output, (tuple, list)):
                    output = output[0]
                # Post-process: [-1, 1] → [0, 1]
                output = (output + 1.0) / 2.0
                output = output.clamp(0.0, 1.0)
                return output

        return TraceableGFPGAN(model)


def convert(input_path: str, output_dir: str) -> Path:
    """Convert GFPGAN .pth to CoreML .mlpackage."""
    import torch
    import coremltools as ct

    input_path = Path(input_path)
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    output_path = output_dir / "GFPGANv1.4.mlpackage"

    if output_path.exists():
        log.info("Output already exists: %s", output_path)
        return output_path

    # Load and wrap the model
    wrapper = GFPGANWrapper(str(input_path))
    traceable = wrapper.create_traceable()

    # Create dummy input (1, 3, 512, 512) in [-1, 1] range
    dummy_input = torch.randn(1, 3, FACE_SIZE, FACE_SIZE)

    log.info("Tracing model...")
    with torch.no_grad():
        traced = torch.jit.trace(traceable, dummy_input)

    log.info("Converting to CoreML...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.ImageType(
                name="input",
                shape=(1, 3, FACE_SIZE, FACE_SIZE),
                scale=1.0 / 127.5,
                bias=[-1.0, -1.0, -1.0],
            )
        ],
        outputs=[ct.ImageType(name="output")],
        minimum_deployment_target=ct.target.macOS14,
    )

    log.info("Saving to %s...", output_path)
    mlmodel.save(str(output_path))
    log.info("Done: %s", output_path)

    return output_path


def main():
    parser = argparse.ArgumentParser(
        description="Convert GFPGAN to CoreML .mlpackage"
    )
    parser.add_argument(
        "--input",
        default="checkpoints/GFPGANv1.4.pth",
        help="Path to GFPGANv1.4.pth (default: checkpoints/GFPGANv1.4.pth)",
    )
    parser.add_argument(
        "--output-dir",
        default="models",
        help="Output directory (default: models/)",
    )

    args = parser.parse_args()

    if not Path(args.input).exists():
        log.error(
            "Input file not found: %s\n"
            "Download from: https://github.com/TencentARC/GFPGAN/releases/download/v1.3.4/GFPGANv1.4.pth",
            args.input,
        )
        sys.exit(1)

    convert(args.input, args.output_dir)


if __name__ == "__main__":
    main()
