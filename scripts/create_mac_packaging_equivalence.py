#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import sys
import tempfile
from pathlib import Path

from artifact_sbom import (
    ArtifactSBOMError,
    canonical_bytes,
    digest_file,
    resolve_inside,
    safe_relative_path,
    validate_bundle,
)
from mac_packaging_equivalence import (
    IDENTIFIER,
    MacPackagingEquivalenceError,
    build_receipt,
    inspect_dmg,
    validate_receipt,
)


def atomic_publish(path: Path, content: bytes) -> None:
    if path.exists() or path.is_symlink():
        raise FileExistsError(f"refusing to overwrite packaging receipt: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        suffix=".tmp",
        dir=path.parent,
    )
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.link(temporary, path, follow_symlinks=False)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
            temporary.unlink()
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if temporary.exists():
            temporary.unlink()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create exact-candidate Mac Companion packaging-equivalence evidence"
    )
    parser.add_argument("index", type=Path, help="canonical artifact-sbom-index.json")
    parser.add_argument("--evidence-root", required=True, type=Path)
    parser.add_argument("--dmg-artifact-id", required=True)
    parser.add_argument("--dmg-path", required=True)
    parser.add_argument("--created", required=True)
    parser.add_argument(
        "--output",
        default="validation/mac-packaging-equivalence.json",
        type=Path,
    )
    parser.add_argument(
        "--allow-readonly-mount",
        action="store_true",
        help="explicitly authorize a noninteractive read-only DMG mount",
    )
    arguments = parser.parse_args()

    if not arguments.allow_readonly_mount:
        parser.error("generation requires --allow-readonly-mount")
    if IDENTIFIER.fullmatch(arguments.dmg_artifact_id) is None:
        raise MacPackagingEquivalenceError("invalid DMG artifact ID")

    evidence_root = arguments.evidence_root.resolve(strict=True)
    if not evidence_root.is_dir():
        raise MacPackagingEquivalenceError("evidence root must be a directory")
    index_path = arguments.index
    if not index_path.is_absolute():
        index_path = evidence_root / index_path
    index_path = index_path.resolve(strict=True)
    if index_path.name != "artifact-sbom-index.json":
        raise MacPackagingEquivalenceError("artifact SBOM index has the wrong name")
    if index_path != evidence_root and evidence_root not in index_path.parents:
        raise MacPackagingEquivalenceError("artifact SBOM index escapes evidence root")
    index, composition = validate_bundle(
        index_path,
        evidence_root=evidence_root,
        verify_archives=True,
    )
    if arguments.dmg_artifact_id in {artifact["id"] for artifact in index["artifacts"]}:
        raise MacPackagingEquivalenceError("DMG artifact ID collides with artifact SBOM")

    dmg_relative = safe_relative_path(arguments.dmg_path, "DMG artifact path")
    dmg_path = resolve_inside(evidence_root, dmg_relative, must_exist=True)
    dmg_sha256, dmg_bytes = digest_file(dmg_path)
    dmg_artifact = {
        "id": arguments.dmg_artifact_id,
        "kind": "macDiskImage",
        "path": dmg_relative,
        "sha256": dmg_sha256,
        "bytes": dmg_bytes,
    }
    dmg_entries, dmg_layout = inspect_dmg(
        dmg_path,
        expected_sha256=dmg_sha256,
        expected_bytes=dmg_bytes,
        allow_readonly_mount=True,
    )
    final_index, final_composition = validate_bundle(
        index_path,
        evidence_root=evidence_root,
        verify_archives=True,
    )
    if final_index != index or final_composition != composition:
        raise MacPackagingEquivalenceError("artifact SBOM changed during DMG inspection")
    confirmed_dmg = digest_file(dmg_path)
    if confirmed_dmg != (dmg_sha256, dmg_bytes):
        raise MacPackagingEquivalenceError("DMG changed after platform inspection")
    index = final_index
    composition = final_composition
    index_sha256, index_bytes = digest_file(index_path)
    artifact_reference = {
        "path": index_path.relative_to(evidence_root).as_posix(),
        "sha256": index_sha256,
        "bytes": index_bytes,
    }
    receipt = build_receipt(
        index=index,
        composition=composition,
        artifact_sbom_reference=artifact_reference,
        dmg_artifact=dmg_artifact,
        dmg_entries=dmg_entries,
        dmg_layout=dmg_layout,
        created=arguments.created,
    )
    release_manifest = {
        "release": index["release"],
        "source": index["source"],
        "artifacts": [*index["artifacts"], dmg_artifact],
        "executables": [],
    }
    validate_receipt(
        receipt,
        index=index,
        composition=composition,
        artifact_sbom_reference=artifact_reference,
        release_manifest=release_manifest,
        observed_dmg_entries=dmg_entries,
        observed_dmg_layout=dmg_layout,
    )
    publication_index, publication_composition = validate_bundle(
        index_path,
        evidence_root=evidence_root,
        verify_archives=True,
    )
    if publication_index != index or publication_composition != composition:
        raise MacPackagingEquivalenceError("artifact SBOM changed before receipt publication")
    if digest_file(index_path) != (index_sha256, index_bytes):
        raise MacPackagingEquivalenceError("artifact SBOM index changed before publication")
    if digest_file(dmg_path) != (dmg_sha256, dmg_bytes):
        raise MacPackagingEquivalenceError("DMG changed before receipt publication")

    output = arguments.output
    if not output.is_absolute():
        output = evidence_root / output
    output = output.resolve(strict=False)
    if output == evidence_root or evidence_root not in output.parents:
        raise MacPackagingEquivalenceError("receipt output escapes evidence root")
    atomic_publish(output, canonical_bytes(receipt))
    print(output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ArtifactSBOMError, MacPackagingEquivalenceError, OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
