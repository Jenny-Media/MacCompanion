#!/usr/bin/env python3
"""Export the selected public sample captures; requires Pillow and the v10 source set."""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / "source/assets/screens"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-set", required=True, type=Path)
    args = parser.parse_args()
    manifest_path = OUTPUT / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    apertures = json.loads((args.source_set / "assets/bezel-apertures.json").read_text())

    # Validate every original before writing any export.
    for entry in manifest["exports"]:
        for relative, expected in (
            (entry["source"], entry["sourceSha256"]),
            ("assets/" + entry["frame"], entry["frameSha256"]),
        ):
            path = args.source_set / relative
            if digest(path) != expected:
                raise SystemExit(f"Source hash mismatch: {relative}")

    for entry in manifest["exports"]:
        screen = Image.open(args.source_set / entry["source"]).convert("RGBA")
        bezel = Image.open(args.source_set / "assets" / entry["frame"]).convert("RGBA")
        device = entry["frame"].removesuffix("-bezel.png")
        x, y, width, height = apertures[device]["screen"]
        if entry["rotatedFrame"]:
            bezel = bezel.transpose(Image.Transpose.ROTATE_90)
            x, y, width, height = y, apertures[device]["native"][0] - x - width, height, width
        if screen.size != (width, height):
            raise SystemExit(f"Screen and aperture differ: {entry['source']}")

        # Keep only the enclosed screen opening. A rectangular screen must not
        # protrude beyond the frame's rounded outer corners.
        enclosed = bezel.getchannel("A").point(lambda alpha: 255 if alpha > 0 else 0)
        ImageDraw.floodfill(enclosed, (0, 0), 128)
        enclosed = enclosed.point(lambda value: 255 if value == 0 else 0)
        content = Image.new("RGBA", bezel.size)
        content.paste(screen, (x, y))
        content.putalpha(enclosed)
        composed = Image.alpha_composite(content, bezel)
        composed.thumbnail((entry["width"], entry["height"]), Image.Resampling.LANCZOS)
        target = OUTPUT / entry["file"]
        composed.save(target, "WEBP", quality=87, method=6)
        entry.update(width=composed.width, height=composed.height,
                     bytes=target.stat().st_size, sha256=digest(target))
        print(f"Exported {target.name}: {composed.width} × {composed.height}")

    manifest["processing"] = (
        "Unmodified native screen clipped to the enclosed matching bezel aperture; "
        "frame rotated for Tabletop; proportional downscale and WebP compression."
    )
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
