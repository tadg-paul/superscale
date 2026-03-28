#!/usr/bin/env python3
# ABOUTME: Generates PyTorch reference images for SSIM quality regression testing.
# ABOUTME: Runs Real-ESRGAN inference on test images and saves ground-truth outputs.

"""Generate PyTorch reference images for SSIM quality regression testing.

Usage:
    python generate_references.py [--model MODEL] [--input-dir DIR] [--output-dir DIR]
    python generate_references.py --help

Examples:
    # Generate references for the default model
    python generate_references.py

    # Specify checkpoint location
    python generate_references.py --checkpoint-dir ./checkpoints

Prerequisites:
    pip install -r requirements-convert.txt

    Download .pth checkpoints from:
    https://github.com/xinntao/Real-ESRGAN/releases
"""

import argparse
import logging
import sys
from pathlib import Path

import numpy as np

logging.basicConfig(
    level=logging.INFO,
    format="%(levelname)s: %(message)s",
    stream=sys.stderr,
)
log = logging.getLogger(__name__)

# Re-use model definitions and architecture builders from convert_model.py.
sys.path.insert(0, str(Path(__file__).parent))
from convert_model import MODELS, _build_model  # noqa: E402


def load_image(path: Path) -> np.ndarray:
    """Load an image as a float32 numpy array in [0, 1] range, RGB, HWC."""
    from PIL import Image

    img = Image.open(path).convert("RGB")
    return np.array(img, dtype=np.float32) / 255.0


def save_image(array: np.ndarray, path: Path) -> None:
    """Save a float32 [0, 1] HWC RGB array as PNG."""
    from PIL import Image

    clamped = np.clip(array, 0, 1)
    uint8 = (clamped * 255).round().astype(np.uint8)
    Image.fromarray(uint8).save(str(path))


def upscale_pytorch(
    image: np.ndarray,
    model_name: str,
    checkpoint_dir: Path,
    tile_size: int = 512,
) -> np.ndarray:
    """Upscale an image using the PyTorch Real-ESRGAN model.

    Args:
        image: Input image as float32 [0, 1] HWC RGB array.
        model_name: Model name from MODELS catalogue.
        checkpoint_dir: Directory containing .pth files.
        tile_size: Tile size for processing (to manage memory).

    Returns:
        Upscaled image as float32 [0, 1] HWC RGB array.
    """
    import torch

    spec = MODELS[model_name]
    checkpoint_path = checkpoint_dir / spec["checkpoint"]

    if not checkpoint_path.exists():
        raise FileNotFoundError(
            f"Checkpoint not found: {checkpoint_path}\n"
            f"Download from: https://github.com/xinntao/Real-ESRGAN/releases"
        )

    # Build and load model.
    model = _build_model(spec["arch"], spec["params"])
    state_dict = torch.load(str(checkpoint_path), map_location="cpu", weights_only=True)

    if "params_ema" in state_dict:
        state_dict = state_dict["params_ema"]
    elif "params" in state_dict:
        state_dict = state_dict["params"]

    model.load_state_dict(state_dict, strict=True)
    model.eval()

    scale = spec["params"].get("scale") or spec["params"].get("upscale", 4)

    # Convert HWC to NCHW tensor.
    tensor = torch.from_numpy(image).permute(2, 0, 1).unsqueeze(0)

    h, w = image.shape[:2]

    # Process in tiles if the image is large enough.
    if h <= tile_size and w <= tile_size:
        # Pad to tile_size if needed (reflection padding, matching CoreML pipeline).
        pad_h = max(tile_size - h, 0)
        pad_w = max(tile_size - w, 0)
        if pad_h > 0 or pad_w > 0:
            # Reflection padding requires pad < dimension. Use replicate
            # for dimensions where reflection would fail, then reflect
            # where possible.
            tensor = torch.nn.functional.pad(
                tensor, (0, pad_w, 0, pad_h), mode="replicate"
            )

        with torch.no_grad():
            output = model(tensor)

        # Crop away padding.
        output = output[:, :, : h * scale, : w * scale]
    else:
        # Tile-based processing for images larger than tile_size.
        # Mirrors the CoreML pipeline's tiling approach.
        overlap = 16
        out_h = h * scale
        out_w = w * scale
        output = torch.zeros(1, 3, out_h, out_w)
        scaled_overlap = overlap * scale

        tiles_y = list(range(0, h, tile_size - overlap))
        tiles_x = list(range(0, w, tile_size - overlap))

        for ty in tiles_y:
            for tx in tiles_x:
                # Extract tile.
                end_y = min(ty + tile_size, h)
                end_x = min(tx + tile_size, w)
                tile = tensor[:, :, ty:end_y, tx:end_x]

                # Pad if undersized.
                th, tw = tile.shape[2], tile.shape[3]
                pad_h_t = max(tile_size - th, 0)
                pad_w_t = max(tile_size - tw, 0)
                if pad_h_t > 0 or pad_w_t > 0:
                    tile = torch.nn.functional.pad(
                        tile, (0, pad_w_t, 0, pad_h_t), mode="replicate"
                    )

                with torch.no_grad():
                    tile_out = model(tile)

                # Crop padding from output.
                tile_out = tile_out[:, :, : th * scale, : tw * scale]

                # Place into output (simple overwrite — last tile wins in overlap).
                oy = ty * scale
                ox = tx * scale
                oh = th * scale
                ow = tw * scale
                output[:, :, oy : oy + oh, ox : ox + ow] = tile_out

    # Convert back to HWC numpy.
    result = output.squeeze(0).permute(1, 2, 0).clamp(0, 1).numpy()
    return result


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Generate PyTorch reference images for SSIM quality testing.",
    )
    parser.add_argument(
        "--model",
        default="realesrgan-x4plus",
        choices=list(MODELS.keys()),
        help="Model to use (default: realesrgan-x4plus)",
    )
    parser.add_argument(
        "--input-dir",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "Tests" / "images",
        help="Directory containing test images",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=(
            Path(__file__).resolve().parent.parent
            / "Tests"
            / "SuperscaleTests"
            / "Resources"
            / "references"
        ),
        help="Output directory for reference images",
    )
    parser.add_argument(
        "--checkpoint-dir",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "checkpoints",
        help="Directory containing .pth checkpoint files",
    )
    parser.add_argument(
        "--version",
        action="version",
        version="generate_references.py 0.1.0",
    )
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)

    if not args.input_dir.exists():
        log.error("Input directory does not exist: %s", args.input_dir)
        return 1

    args.output_dir.mkdir(parents=True, exist_ok=True)

    # Find all test images.
    extensions = {".png", ".jpg", ".jpeg"}
    images = sorted(
        p for p in args.input_dir.iterdir()
        if p.suffix.lower() in extensions and p.is_file()
    )

    if not images:
        log.error("No images found in %s", args.input_dir)
        return 1

    log.info("Generating references for %d images with model %s", len(images), args.model)

    for img_path in images:
        log.info("  Processing %s...", img_path.name)
        image = load_image(img_path)

        output = upscale_pytorch(
            image,
            model_name=args.model,
            checkpoint_dir=args.checkpoint_dir,
        )

        # Save as PNG regardless of input format.
        out_name = img_path.stem + "_ref.png"
        out_path = args.output_dir / out_name
        save_image(output, out_path)
        log.info("    → %s (%d×%d)", out_path.name, output.shape[1], output.shape[0])

    log.info("Done. References saved to %s", args.output_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
