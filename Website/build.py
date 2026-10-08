#!/usr/bin/env python3
"""Build the static site from its authoritative source files."""
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "source"
OUTPUT = ROOT / "dist"
OUTPUT.mkdir(exist_ok=True)
for path in SOURCE.rglob("*"):
    if path.is_file() and path.name not in {"header.html", "footer.html"}:
        target = OUTPUT / path.relative_to(SOURCE)
        target.parent.mkdir(parents=True, exist_ok=True)
        if path.suffix == ".html":
            text = path.read_text()
            for part in ("header", "footer"):
                text = text.replace(f"<!-- {part.upper()} -->", (SOURCE / f"{part}.html").read_text())
            target.write_text(text)
        else:
            shutil.copyfile(path, target)
print("Built Mac Companion website in Website/dist")
