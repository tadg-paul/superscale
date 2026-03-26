#!/usr/bin/env python3
# ABOUTME: Converts Real-ESRGAN PyTorch checkpoints (.pth) to CoreML (.mlpackage).
# ABOUTME: Build-time tool — never a runtime dependency. Requires torch and coremltools.

"""Convert Real-ESRGAN PyTorch models to CoreML .mlpackage format.

Usage:
    python convert_model.py MODEL_NAME [--input-dir DIR] [--output-dir DIR] [--tile-size N]
    python convert_model.py --all [--input-dir DIR] [--output-dir DIR]
    python convert_model.py --list
    python convert_model.py --help

Examples:
    # Convert default model
    python convert_model.py realesrgan-x4plus

    # Convert all models
    python convert_model.py --all --input-dir ./checkpoints --output-dir ./models

    # List supported models
    python convert_model.py --list

Prerequisites:
    pip install -r requirements-convert.txt

    Download .pth checkpoints from:
    https://github.com/xinntao/Real-ESRGAN/releases
"""

import argparse
import hashlib
import json
import logging
import sys
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="%(levelname)s: %(message)s",
    stream=sys.stderr,
)
log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Model catalogue — must match Sources/Superscale/ModelRegistry.swift
# ---------------------------------------------------------------------------

MODELS = {
    "realesrgan-x4plus": {
        "arch": "RRDBNet",
        "checkpoint": "RealESRGAN_x4plus.pth",
        "output": "RealESRGAN_x4plus.mlpackage",
        "params": {
            "num_in_ch": 3,
            "num_out_ch": 3,
            "num_feat": 64,
            "num_block": 23,
            "num_grow_ch": 32,
            "scale": 4,
        },
    },
    "realesrgan-x2plus": {
        "arch": "RRDBNet",
        "checkpoint": "RealESRGAN_x2plus.pth",
        "output": "RealESRGAN_x2plus.mlpackage",
        "params": {
            "num_in_ch": 3,
            "num_out_ch": 3,
            "num_feat": 64,
            "num_block": 23,
            "num_grow_ch": 32,
            "scale": 2,
        },
    },
    "realesrnet-x4plus": {
        "arch": "RRDBNet",
        "checkpoint": "RealESRNet_x4plus.pth",
        "output": "RealESRNet_x4plus.mlpackage",
        "params": {
            "num_in_ch": 3,
            "num_out_ch": 3,
            "num_feat": 64,
            "num_block": 23,
            "num_grow_ch": 32,
            "scale": 4,
        },
    },
    "realesrgan-anime-6b": {
        "arch": "RRDBNet",
        "checkpoint": "RealESRGAN_x4plus_anime_6B.pth",
        "output": "RealESRGAN_x4plus_anime_6B.mlpackage",
        "params": {
            "num_in_ch": 3,
            "num_out_ch": 3,
            "num_feat": 64,
            "num_block": 6,
            "num_grow_ch": 32,
            "scale": 4,
        },
    },
    "realesr-animevideov3": {
        "arch": "SRVGGNetCompact",
        "checkpoint": "realesr-animevideov3.pth",
        "output": "realesr-animevideov3.mlpackage",
        "params": {
            "num_in_ch": 3,
            "num_out_ch": 3,
            "num_feat": 64,
            "num_conv": 16,
            "upscale": 4,
            "act_type": "prelu",
        },
    },
    "realesr-general-x4v3": {
        "arch": "SRVGGNetCompact",
        "checkpoint": "realesr-general-x4v3.pth",
        "output": "realesr-general-x4v3.mlpackage",
        "params": {
            "num_in_ch": 3,
            "num_out_ch": 3,
            "num_feat": 64,
            "num_conv": 32,
            "upscale": 4,
            "act_type": "prelu",
        },
    },
    "realesr-general-wdn-x4v3": {
        "arch": "SRVGGNetCompact",
        "checkpoint": "realesr-general-wdn-x4v3.pth",
        "output": "realesr-general-wdn-x4v3.mlpackage",
        "params": {
            "num_in_ch": 3,
            "num_out_ch": 3,
            "num_feat": 64,
            "num_conv": 32,
            "upscale": 4,
            "act_type": "prelu",
        },
    },
}

# ---------------------------------------------------------------------------
# Architecture definitions — inline to avoid basicsr/realesrgan dependencies
# ---------------------------------------------------------------------------


def _build_model(arch: str, params: dict):
    """Construct a PyTorch model from architecture name and parameters."""
    import torch.nn as nn

    if arch == "RRDBNet":
        return _build_rrdbnet(**params)
    if arch == "SRVGGNetCompact":
        return _build_srvgg(**params)
    raise ValueError(f"Unknown architecture: {arch}")


def _build_rrdbnet(
    num_in_ch: int,
    num_out_ch: int,
    num_feat: int,
    num_block: int,
    num_grow_ch: int,
    scale: int,
):
    """Build an RRDBNet model (used by full-size Real-ESRGAN models)."""
    import torch
    import torch.nn as nn
    import torch.nn.functional as F

    class ResidualDenseBlock(nn.Module):
        def __init__(self, nf: int = 64, gc: int = 32):
            super().__init__()
            self.conv1 = nn.Conv2d(nf, gc, 3, 1, 1)
            self.conv2 = nn.Conv2d(nf + gc, gc, 3, 1, 1)
            self.conv3 = nn.Conv2d(nf + 2 * gc, gc, 3, 1, 1)
            self.conv4 = nn.Conv2d(nf + 3 * gc, gc, 3, 1, 1)
            self.conv5 = nn.Conv2d(nf + 4 * gc, nf, 3, 1, 1)
            self.lrelu = nn.LeakyReLU(negative_slope=0.2, inplace=True)

        def forward(self, x):
            x1 = self.lrelu(self.conv1(x))
            x2 = self.lrelu(self.conv2(torch.cat((x, x1), 1)))
            x3 = self.lrelu(self.conv3(torch.cat((x, x1, x2), 1)))
            x4 = self.lrelu(self.conv4(torch.cat((x, x1, x2, x3), 1)))
            x5 = self.conv5(torch.cat((x, x1, x2, x3, x4), 1))
            return x5 * 0.2 + x

    class RRDB(nn.Module):
        def __init__(self, nf: int, gc: int = 32):
            super().__init__()
            self.rdb1 = ResidualDenseBlock(nf, gc)
            self.rdb2 = ResidualDenseBlock(nf, gc)
            self.rdb3 = ResidualDenseBlock(nf, gc)

        def forward(self, x):
            out = self.rdb1(x)
            out = self.rdb2(out)
            out = self.rdb3(out)
            return out * 0.2 + x

    class RRDBNet(nn.Module):
        def __init__(self, in_ch, out_ch, nf, nb, gc, sc):
            super().__init__()
            self.scale = sc
            effective_in_ch = in_ch * 4 if sc == 2 else in_ch
            self.conv_first = nn.Conv2d(effective_in_ch, nf, 3, 1, 1)
            self.body = nn.Sequential(*[RRDB(nf, gc) for _ in range(nb)])
            self.conv_body = nn.Conv2d(nf, nf, 3, 1, 1)
            self.conv_up1 = nn.Conv2d(nf, nf, 3, 1, 1)
            self.conv_up2 = nn.Conv2d(nf, nf, 3, 1, 1)
            self.conv_hr = nn.Conv2d(nf, nf, 3, 1, 1)
            self.conv_last = nn.Conv2d(nf, out_ch, 3, 1, 1)
            self.lrelu = nn.LeakyReLU(negative_slope=0.2, inplace=True)

        def forward(self, x):
            if self.scale == 2:
                feat = F.pixel_unshuffle(x, 2)
            else:
                feat = x
            feat = self.conv_first(feat)
            body_feat = self.conv_body(self.body(feat))
            feat = feat + body_feat
            feat = self.lrelu(
                self.conv_up1(F.interpolate(feat, scale_factor=2, mode="nearest"))
            )
            feat = self.lrelu(
                self.conv_up2(F.interpolate(feat, scale_factor=2, mode="nearest"))
            )
            out = self.conv_last(self.lrelu(self.conv_hr(feat)))
            return out

    return RRDBNet(num_in_ch, num_out_ch, num_feat, num_block, num_grow_ch, scale)


def _build_srvgg(
    num_in_ch: int,
    num_out_ch: int,
    num_feat: int,
    num_conv: int,
    upscale: int,
    act_type: str,
):
    """Build an SRVGGNetCompact model (used by compact/video models)."""
    import torch.nn as nn
    import torch.nn.functional as F

    class SRVGGNetCompact(nn.Module):
        def __init__(self, in_ch, out_ch, nf, nc, us, act):
            super().__init__()
            self.upscale = us
            self.body = nn.ModuleList()

            # First conv + activation
            self.body.append(nn.Conv2d(in_ch, nf, 3, 1, 1))
            self.body.append(self._make_act(act, nf))

            # Middle convs
            for _ in range(nc):
                self.body.append(nn.Conv2d(nf, nf, 3, 1, 1))
                self.body.append(self._make_act(act, nf))

            # Last conv (upscale via PixelShuffle)
            self.body.append(nn.Conv2d(nf, out_ch * (us**2), 3, 1, 1))
            self.upsampler = nn.PixelShuffle(us)

        @staticmethod
        def _make_act(act_type: str, num_feat: int) -> nn.Module:
            if act_type == "relu":
                return nn.ReLU(inplace=True)
            if act_type == "prelu":
                return nn.PReLU(num_parameters=num_feat)
            if act_type == "leakyrelu":
                return nn.LeakyReLU(negative_slope=0.1, inplace=True)
            raise ValueError(f"Unknown activation: {act_type}")

        def forward(self, x):
            out = x
            for layer in self.body:
                out = layer(out)
            out = self.upsampler(out)
            base = F.interpolate(
                x, scale_factor=self.upscale, mode="bilinear", align_corners=False
            )
            return out + base

    return SRVGGNetCompact(num_in_ch, num_out_ch, num_feat, num_conv, upscale, act_type)


# ---------------------------------------------------------------------------
# Conversion pipeline
# ---------------------------------------------------------------------------


def compute_sha256(path: Path) -> str:
    """Compute SHA256 hex digest of a file or directory (tar of contents)."""
    h = hashlib.sha256()
    if path.is_dir():
        # For directories (.mlpackage), hash all files sorted by relative path
        for child in sorted(path.rglob("*")):
            if child.is_file():
                h.update(child.read_bytes())
    else:
        h.update(path.read_bytes())
    return h.hexdigest()


def convert_model(
    name: str,
    input_dir: Path,
    output_dir: Path,
    tile_size: int,
) -> Path:
    """Convert a single model from .pth to .mlpackage.

    Returns the path to the output .mlpackage directory.
    """
    import coremltools as ct
    import torch
    import torch.nn as nn

    spec = MODELS[name]
    checkpoint_path = input_dir / spec["checkpoint"]
    output_path = output_dir / spec["output"]

    if not checkpoint_path.exists():
        raise FileNotFoundError(
            f"Checkpoint not found: {checkpoint_path}\n"
            f"Download from: https://github.com/xinntao/Real-ESRGAN/releases"
        )

    log.info("Converting %s (%s)...", name, spec["arch"])
    log.info("  Checkpoint: %s", checkpoint_path)
    log.info("  Output:     %s", output_path)

    # 1. Build architecture and load weights
    model = _build_model(spec["arch"], spec["params"])
    state_dict = torch.load(str(checkpoint_path), map_location="cpu", weights_only=True)

    # Handle checkpoints that wrap state_dict in a 'params_ema' or 'params' key
    if "params_ema" in state_dict:
        state_dict = state_dict["params_ema"]
    elif "params" in state_dict:
        state_dict = state_dict["params"]

    model.load_state_dict(state_dict, strict=True)
    model.eval()
    log.info("  Loaded weights successfully")

    # 2. Wrap model to output [0, 255] range — coremltools 7+ requires
    #    scale=1.0 for output ImageType, so we clamp and scale inside the model
    class OutputScaler(nn.Module):
        def __init__(self, inner):
            super().__init__()
            self.inner = inner

        def forward(self, x):
            out = self.inner(x)
            out = torch.clamp(out, 0.0, 1.0)
            return out * 255.0

    wrapped = OutputScaler(model)
    wrapped.eval()

    # 3. Trace with example input
    scale = spec["params"].get("scale") or spec["params"].get("upscale", 4)
    example_input = torch.randn(1, 3, tile_size, tile_size)

    with torch.no_grad():
        traced = torch.jit.trace(wrapped, example_input)
    log.info("  Traced model with input shape [1, 3, %d, %d]", tile_size, tile_size)

    # 4. Convert to CoreML
    mlmodel = ct.convert(
        traced,
        inputs=[ct.ImageType(name="input", shape=example_input.shape, scale=1 / 255.0)],
        outputs=[ct.ImageType(name="output", scale=1.0)],
        minimum_deployment_target=ct.target.macOS14,
    )
    log.info("  CoreML conversion complete")

    # 4. Save
    output_dir.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(output_path))
    log.info("  Saved: %s", output_path)

    # 5. Validate — load back and confirm it doesn't error
    _ = ct.models.MLModel(str(output_path))
    sha = compute_sha256(output_path)
    log.info("  Validated OK  SHA256: %s", sha)

    return output_path


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert Real-ESRGAN PyTorch models to CoreML .mlpackage.",
        epilog="Download .pth checkpoints from https://github.com/xinntao/Real-ESRGAN/releases",
    )
    parser.add_argument(
        "model",
        nargs="?",
        choices=list(MODELS.keys()),
        help="Model to convert",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Convert all supported models",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List supported models and exit",
    )
    parser.add_argument(
        "--input-dir",
        type=Path,
        default=Path("checkpoints"),
        help="Directory containing .pth files (default: checkpoints/)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("models"),
        help="Output directory for .mlpackage files (default: models/)",
    )
    parser.add_argument(
        "--tile-size",
        type=int,
        default=512,
        help="Tile size for example input shape (default: 512)",
    )
    parser.add_argument(
        "--version",
        action="version",
        version="convert_model.py 0.1.0",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    if args.list:
        print("Supported models:")
        for name, spec in MODELS.items():
            arch = spec["arch"]
            scale = spec["params"].get("scale") or spec["params"].get("upscale", 4)
            print(f"  {name:<26s} {arch:<20s} {scale}×")
        return 0

    if not args.model and not args.all:
        log.error("Specify a model name or --all. Use --list to see options.")
        return 2

    names = list(MODELS.keys()) if args.all else [args.model]
    results: dict[str, str] = {}  # name → status

    for name in names:
        try:
            path = convert_model(name, args.input_dir, args.output_dir, args.tile_size)
            results[name] = f"OK → {path}"
        except FileNotFoundError as exc:
            log.error("%s", exc)
            results[name] = "SKIP (checkpoint not found)"
        except Exception as exc:
            log.error("Failed to convert %s: %s", name, exc)
            results[name] = f"FAIL ({exc})"

    # Summary
    print("\n--- Conversion Summary ---")
    for name, status in results.items():
        print(f"  {name:<26s} {status}")

    failures = sum(1 for s in results.values() if s.startswith("FAIL"))
    if failures > 0:
        log.error("%d conversion(s) failed", failures)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
