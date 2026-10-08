#!/usr/bin/env python3
"""Validate Mac Companion's local open-source policy bundle."""

from __future__ import annotations

import hashlib
import os
import stat
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
OFFICIAL_APACHE_2_SHA256 = (
    "cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30"
)
OFFICIAL_GPL_3_SHA256 = (
    "3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986"
)

REQUIRED_TEXT: dict[str, tuple[str, ...]] = {
    "NOTICE": (
        "Mac Companion",
        "Copyright 2026 Jenny Media LLC",
        "See TRADEMARKS.md.",
    ),
    "TRADEMARKS.md": (
        "draft for written legal review",
        "The GNU General Public License version 3",
        "does not grant permission",
        "Modified builds and forks",
        "distinct product",
        "official update channels",
        "Nothing in this policy limits uses allowed by applicable law.",
    ),
    "SECURITY.md": (
        "not operational until GitHub private vulnerability reporting is enabled",
        "Mac Companion has no externally supported release yet.",
        "Do not report suspected vulnerabilities in a public issue",
        "https://github.com/Jenny-Media/MacCompanion/security/advisories/new",
        "If that button is unavailable, private reporting is not operational.",
        "Do not attach real secrets",
    ),
    "CONTRIBUTING.md": (
        "not yet ready to accept external contributions",
        "available under GPL-3.0-only",
        "Developer Certificate of Origin",
        "Do not add a `Signed-off-by` line yet",
        "Follow `SECURITY.md`",
        "`CODE_OF_CONDUCT.md`",
    ),
    "CODE_OF_CONDUCT.md": (
        "prepared for maintainer and legal review",
        "respectful, inclusive, constructive, and safe",
        "private conduct-reporting route is not yet published",
        "external contribution intake",
    ),
    "README.md": (
        "[GPL-3.0 license](LICENSE)",
        "[Licensing and retained Apache notices](LICENSING.md)",
        "[Trademark policy](TRADEMARKS.md)",
        "[Security policy](SECURITY.md)",
        "[Contribution hold](CONTRIBUTING.md)",
        "[Community code of conduct](CODE_OF_CONDUCT.md)",
    ),
    "LICENSING.md": (
        "New Mac Companion contributions use GPL-3.0-only",
        "Existing code previously offered under Apache-2.0 retains that permission",
        "corresponding-source delivery arrangement",
        "does not reopen external contribution intake",
    ),
}


def fail(message: str) -> None:
    print(f"open-source policy validation failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_regular_file(relative_path: str) -> bytes:
    path = ROOT / relative_path
    try:
        metadata = os.lstat(path)
    except FileNotFoundError:
        fail(f"missing {relative_path}")
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
        fail(f"{relative_path} must be one regular single-link file")
    maximum_size = 512 * 1024 if relative_path == "README.md" else 64 * 1024
    if metadata.st_size == 0 or metadata.st_size > maximum_size:
        fail(f"{relative_path} has an invalid size")
    return path.read_bytes()


def main() -> None:
    license_bytes = read_regular_file("LICENSE")
    license_digest = hashlib.sha256(license_bytes).hexdigest()
    if license_digest != OFFICIAL_GPL_3_SHA256:
        fail("LICENSE is not the byte-exact GPL-3.0 text")
    apache_bytes = read_regular_file("LICENSES/Apache-2.0.txt")
    if hashlib.sha256(apache_bytes).hexdigest() != OFFICIAL_APACHE_2_SHA256:
        fail("retained Apache-2.0 text does not match the original license")

    for relative_path, required_fragments in REQUIRED_TEXT.items():
        raw = read_regular_file(relative_path)
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            fail(f"{relative_path} must be UTF-8")
        normalized_text = " ".join(text.split())
        for fragment in required_fragments:
            if " ".join(fragment.split()) not in normalized_text:
                fail(f"{relative_path} is missing required policy text: {fragment!r}")

    print("Open-source policy bundle validated.")


if __name__ == "__main__":
    main()
