#!/usr/bin/env python3
"""Check built routes, metadata, assets, and internal links before publishing."""
from html.parser import HTMLParser
import hashlib
import json
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parent / "dist"


class Page(HTMLParser):
    def __init__(self, path):
        super().__init__(convert_charrefs=True)
        self.path = path
        self.ids = set()
        self.links = []
        self.images = []
        self.h1 = 0
        self.title = False
        self.description = False
        self.lang = False
        self.robots = ""
        self.errors = []
        self.feed(path.read_text())

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if "id" in attrs:
            if attrs["id"] in self.ids:
                self.errors.append(f"Duplicate id: {attrs['id']}")
            self.ids.add(attrs["id"])
        if tag == "h1":
            self.h1 += 1
        if tag == "title":
            self.title = True
        if tag == "html":
            self.lang = bool(attrs.get("lang"))
        if tag == "meta" and attrs.get("name") == "description":
            self.description = bool(attrs.get("content"))
        if tag == "meta" and attrs.get("name", "").lower() == "robots":
            self.robots = attrs.get("content", "").lower()
        if tag == "img" and "alt" not in attrs:
            self.errors.append("Image missing alt attribute")
        if tag == "img":
            self.images.append(attrs)
        attribute = "href" if tag in {"a", "link"} else "src" if tag in {"img", "script"} else None
        if attribute and attrs.get(attribute):
            self.links.append(attrs[attribute])


def resolve(path, reference):
    url = urlsplit(reference)
    if url.scheme or url.netloc:
        return None, None
    location = unquote(url.path)
    target = ROOT / location.lstrip("/") if location.startswith("/") else path.parent / location
    if not location:
        target = path
    if target.is_dir():
        target /= "index.html"
    return target.resolve(), unquote(url.fragment)


pages = {path.resolve(): Page(path) for path in ROOT.rglob("*.html")}
errors = []
for route in ("index.html", "privacy/index.html", "support/index.html", "beta/index.html"):
    if (ROOT / route).resolve() not in pages:
        errors.append(f"Missing route: {route}")
for path, page in pages.items():
    name = path.relative_to(ROOT)
    errors.extend(f"{name}: {error}" for error in page.errors)
    if page.h1 != 1 or not (page.title and page.description and page.lang):
        errors.append(f"{name}: missing or duplicate heading/metadata")
    if "<!-- HEADER -->" in path.read_text() or "<!-- FOOTER -->" in path.read_text():
        errors.append(f"{name}: unexpanded shared fragment")
    for link in page.links:
        target, fragment = resolve(path, link)
        if target is None:
            continue
        if not target.is_file() or not target.is_relative_to(ROOT):
            errors.append(f"{name}: missing local target {link}")
        elif fragment and target in pages and fragment not in pages[target].ids:
            errors.append(f"{name}: missing anchor {link}")
beta = (ROOT / "beta/index.html").resolve()
if beta in pages:
    if not {"noindex", "nofollow"}.issubset({part.strip() for part in pages[beta].robots.split(",")}):
        errors.append("beta/index.html: missing search-index exclusion")
    if "https://testflight.apple.com/join/pFeKTuux" not in pages[beta].links:
        errors.append("beta/index.html: missing verified TestFlight invitation")
for path, page in pages.items():
    if path == beta:
        continue
    for link in page.links:
        target, _ = resolve(path, link)
        if target == beta:
            errors.append(f"{path.relative_to(ROOT)}: beta route must stay unlisted")
config = json.loads((ROOT.parent / "vercel.json").read_text())
beta_headers = [
    header
    for rule in config.get("headers", [])
    if rule.get("source") == "/beta(.*)"
    for header in rule.get("headers", [])
]
if not any(
    header.get("key", "").lower() == "x-robots-tag"
    and {"noindex", "nofollow", "noarchive"}.issubset(
        {part.strip().lower() for part in header.get("value", "").split(",")}
    )
    for header in beta_headers
):
    errors.append("beta route: missing X-Robots-Tag deployment header")

# Verify public image bytes and dimensions against the prepared source handoff.
# This catches missing exports, accidental replacements, and distorted markup.
manifest = json.loads((ROOT.parent / "source/assets/screens/manifest.json").read_text())
exports = {entry["file"]: entry for entry in manifest["exports"]}
for name, entry in exports.items():
    path = ROOT / "assets/screens" / name
    if not path.is_file():
        errors.append(f"Missing screenshot export: {name}")
        continue
    data = path.read_bytes()
    if len(data) != entry["bytes"] or hashlib.sha256(data).hexdigest() != entry["sha256"]:
        errors.append(f"Screenshot differs from its provenance manifest: {name}")
    # Transparent WebP exports have an extended header with canvas dimensions.
    if data[:4] != b"RIFF" or data[8:16] != b"WEBPVP8X":
        errors.append(f"Screenshot missing extended WebP header: {name}")
    else:
        size = (1 + int.from_bytes(data[24:27], "little"),
                1 + int.from_bytes(data[27:30], "little"))
        if size != (entry["width"], entry["height"]):
            errors.append(f"Screenshot dimensions differ from manifest: {name}")
for path, page in pages.items():
    for attrs in page.images:
        src = attrs.get("src", "")
        if src.startswith("/assets/screens/"):
            entry = exports.get(src.removeprefix("/assets/screens/"))
            if entry is None or (attrs.get("width"), attrs.get("height")) != (
                str(entry["width"]), str(entry["height"])
            ):
                errors.append(f"{path.relative_to(ROOT)}: screenshot aspect ratio missing or incorrect: {src}")

if errors:
    raise SystemExit("\n".join(errors))
print(f"Website checks passed: {len(pages)} pages, metadata, local assets, internal links, and {len(exports)} verified screenshot exports")
