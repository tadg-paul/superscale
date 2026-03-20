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

Known issues:
    - coremltools' TorchScript converter has a bug in its _cast/_int handler
      that fails on numpy arrays with shape > 0. We monkey-patch this at
      conversion time.
    - GFPGAN's StyleGAN2 decoder uses grouped convolutions with dynamic batch
      shapes in ModulatedConv2d.forward(). Since we always infer with batch=1,
      we patch the forward to use static shapes for clean tracing.
    - The StyleGAN2 decoder requires FLOAT32 precision. fp16 produces flat
      (near-constant) output due to numerical instability in the modulated
      convolution's weight demodulation (rsqrt of sum of squares).
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


def _patch_coremltools():
    """Patch coremltools' _cast handler for numpy array compatibility.

    The upstream _cast function calls dtype(x.val) on numpy arrays, which
    fails with "only 0-dimensional arrays can be converted to Python scalars".
    We fix this by calling .item() first to extract the scalar.
    """
    import numpy as np
    import coremltools.converters.mil.frontend.torch.ops as ct_ops
    from coremltools.converters.mil import Builder as mb

    _get_inputs = ct_ops._get_inputs

    def patched_cast(context, node, dtype, dtype_name):
        inputs = _get_inputs(context, node, expected=1)
        x = inputs[0]
        if not (len(x.shape) == 0 or np.all([d == 1 for d in x.shape])):
            raise ValueError(
                "input to cast must be either a scalar or a length 1 tensor"
            )
        if x.can_be_folded_to_const():
            val = x.val
            if hasattr(val, "item"):
                val = val.item()
            if not isinstance(val, dtype):
                res = mb.const(val=dtype(val), name=node.name)
            else:
                res = x
        elif len(x.shape) > 0:
            x = mb.squeeze(x=x, name=node.name + "_item")
            res = mb.cast(x=x, dtype=dtype_name, name=node.name)
        else:
            res = mb.cast(x=x, dtype=dtype_name, name=node.name)
        context.add(res, node.name)

    ct_ops._cast = patched_cast
    log.info("Patched coremltools _cast handler")


def _patch_modulated_conv():
    """Patch ModulatedConv2d.forward for batch=1 static shapes.

    The upstream forward uses dynamic batch-dependent shapes in view() calls
    and grouped convolutions (groups=b). With batch=1, we can use static
    shapes and groups=1, which traces cleanly to CoreML.
    """
    import torch
    import torch.nn.functional as F
    from gfpgan.archs.stylegan2_clean_arch import ModulatedConv2d

    def forward_batch1(self, x, style):
        b, c, h, w = x.shape
        style = self.modulation(style).reshape(1, 1, c, 1, 1)
        weight = self.weight * style
        if self.demodulate:
            demod = torch.rsqrt(weight.pow(2).sum([2, 3, 4]) + self.eps)
            weight = weight * demod.reshape(1, self.out_channels, 1, 1, 1)
        weight = weight.reshape(
            self.out_channels, c, self.kernel_size, self.kernel_size
        )
        if self.sample_mode == "upsample":
            x = F.interpolate(
                x, scale_factor=2, mode="bilinear", align_corners=False
            )
        elif self.sample_mode == "downsample":
            x = F.interpolate(
                x, scale_factor=0.5, mode="bilinear", align_corners=False
            )
        b2, c2, h2, w2 = x.shape
        x = x.reshape(1, c2, h2, w2)
        out = F.conv2d(x, weight, padding=self.padding, groups=1)
        out = out.reshape(1, self.out_channels, out.size(2), out.size(3))
        return out

    ModulatedConv2d.forward = forward_batch1
    log.info("Patched ModulatedConv2d.forward for batch=1")


class GFPGANWrapper:
    """Wraps the GFPGAN model for CoreML tracing.

    Handles:
    - Loading GFPGANv1.4 weights using the clean architecture
    - Pre-generating noise tensors (replacing in-model stochastic noise)
    - Post-processing: rescaling output from [-1,1] to [0,255] range
    """

    def __init__(self, model_path: str):
        import torch

        log.info("Loading GFPGAN from %s...", model_path)

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

        state_dict = torch.load(model_path, map_location="cpu", weights_only=False)
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
                # Post-process: [-1, 1] → [0, 255] (matching Real-ESRGAN pattern)
                # CoreML ImageType with scale=1.0 expects pixel-range values.
                output = (output + 1.0) / 2.0
                output = output.clamp(0.0, 1.0)
                output = output * 255.0
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

    # Apply patches for coremltools and GFPGAN compatibility
    _patch_coremltools()
    _patch_modulated_conv()

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
        outputs=[ct.ImageType(name="output", scale=1.0)],
        minimum_deployment_target=ct.target.macOS14,
        # FLOAT32 required: StyleGAN2's modulated convolution uses rsqrt of
        # sum-of-squares for weight demodulation, which loses precision in fp16
        # and produces flat (near-constant) output.
        compute_precision=ct.precision.FLOAT32,
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
