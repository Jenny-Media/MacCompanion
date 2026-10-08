#!/usr/bin/env python3
"""Export the approved artwork for the native apps and local website.

Only resamples the approved raster; there is no redrawing or creative editing.
Requires macOS's sips. Run from any directory after updating Branding/app-icon.png.
"""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Branding/app-icon.png"


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n")


def export(path, size):
    path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["sips", "--resampleHeightWidth", str(size), str(size),
                    str(SOURCE), "--out", str(path)], check=True,
                   stdout=subprocess.DEVNULL)


def main():
    metadata = {"version": 1, "author": "xcode"}
    for platform in ["Mac", "IOS"]:
        catalog = ROOT / f"Apps/MacCompanion{platform}/Assets.xcassets"
        write_json(catalog / "Contents.json", {"info": metadata})
        icon = catalog / "AppIcon.appiconset"
        images = []
        if platform == "IOS":
            export(icon / "AppIcon-1024.png", 1024)
            images.append({"filename": "AppIcon-1024.png", "idiom": "universal",
                           "platform": "ios", "size": "1024x1024"})
        else:
            for size in [16, 32, 128, 256, 512]:
                for scale in [1, 2]:
                    filename = f"AppIcon-{size}@{scale}x.png"
                    export(icon / filename, size * scale)
                    images.append({"filename": filename, "idiom": "mac",
                                   "scale": f"{scale}x", "size": f"{size}x{size}"})
        write_json(icon / "Contents.json", {"images": images, "info": metadata})
    for name, size in [("app-icon.png", 512), ("favicon.png", 64)]:
        export(ROOT / "Website/dist/assets" / name, size)
    print("Exported approved artwork for macOS, iOS, and Website/dist/assets.")


if __name__ == "__main__":
    main()
