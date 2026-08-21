#!/usr/bin/env python3

from __future__ import annotations

import argparse
from pathlib import Path

from artifact_sbom import atomic_write_set, canonical_bytes, generate, load_json


def main() -> int:
    parser = argparse.ArgumentParser(description="Create an exact-candidate Mac Companion artifact SBOM")
    parser.add_argument("candidate", type=Path, help="closed candidate-input JSON")
    parser.add_argument("--evidence-root", required=True, type=Path, help="root containing candidate artifact paths")
    parser.add_argument("--output-directory", required=True, type=Path, help="new evidence-set directory")
    arguments = parser.parse_args()
    index, composition, spdx = generate(load_json(arguments.candidate), arguments.evidence_root)
    atomic_write_set(arguments.output_directory, {
        "artifact-composition.json": canonical_bytes(composition),
        "artifact-sbom.spdx.json": canonical_bytes(spdx),
        "artifact-sbom-index.json": canonical_bytes(index),
    })
    print(arguments.output_directory / "artifact-sbom-index.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
