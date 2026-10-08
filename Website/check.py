#!/usr/bin/env python3
"""Check built routes, metadata, assets, and internal links before publishing."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parent / "dist"


class Page(HTMLParser):
    def __init__(self, path):
        super().__init__(convert_charrefs=True)
        self.path = path
        self.ids = set()
        self.links = []
        self.h1 = 0
        self.title = False
        self.description = False
        self.lang = False
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
        if tag == "img" and "alt" not in attrs:
            self.errors.append("Image missing alt attribute")
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
for route in ("index.html", "privacy/index.html", "support/index.html"):
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
if errors:
    raise SystemExit("\n".join(errors))
print(f"Website checks passed: {len(pages)} pages, metadata, local assets, and internal links")
