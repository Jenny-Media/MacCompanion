#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from validate_release_evidence import validate_manifest


REPOSITORY = Path(__file__).resolve().parents[1]
TARGET_ORDER = ("macOS", "iOS")


def command(*arguments: str) -> str:
    result = subprocess.run(
        arguments,
        cwd=REPOSITORY,
        check=True,
        capture_output=True,
        text=True,
        timeout=20,
    )
    output = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    if not output:
        raise RuntimeError(f"command produced no output: {' '.join(arguments)}")
    return "; ".join(output)


def git_revision() -> str:
    return command("git", "rev-parse", "--verify", "HEAD")


def git_dirty() -> bool:
    result = subprocess.run(
        ("git", "status", "--porcelain", "--untracked-files=normal"),
        cwd=REPOSITORY,
        check=True,
        capture_output=True,
        text=True,
        timeout=20,
    )
    return bool(result.stdout)


def first_line(*arguments: str) -> str:
    return command(*arguments).split("; ", maxsplit=1)[0]


def inside(root: Path, path: Path) -> bool:
    return path == root or root in path.parents


def file_reference(root: Path, path: Path) -> dict[str, object]:
    size = path.stat().st_size
    if size <= 0:
        raise ValueError(f"evidence file must not be empty: {path}")
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(chunk)
    return {
        "path": path.relative_to(root).as_posix(),
        "sha256": hasher.hexdigest(),
        "bytes": size,
    }


def collect_toolchain(targets: list[str]) -> dict[str, object]:
    sdk_versions: list[str] = []
    if "macOS" in targets:
        sdk_versions.append(
            f"macOS {command('xcrun', '--sdk', 'macosx', '--show-sdk-version')}"
        )
    if "iOS" in targets:
        sdk_versions.append(
            f"iOS {command('xcrun', '--sdk', 'iphoneos', '--show-sdk-version')}"
        )
    return {
        "xcodeVersion": command("xcodebuild", "-version"),
        "swiftVersion": first_line("xcrun", "swift", "--version"),
        "hostOSVersion": f"macOS {command('sw_vers', '-productVersion')}",
        "sdkVersions": sdk_versions,
    }


def write_atomically(path: Path, value: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        suffix=".tmp",
        dir=path.parent,
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o600)
        # A hard-link publication is an atomic no-clobber operation. Unlike
        # os.replace(), it cannot overwrite a file created after the caller's
        # preflight check.
        os.link(temporary, path, follow_symlinks=False)
        directory_descriptor = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_descriptor)
            temporary.unlink()
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
    finally:
        if temporary.exists():
            temporary.unlink()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create unsigned Mac Companion release evidence v0.1"
    )
    parser.add_argument("--evidence-root", required=True, type=Path)
    parser.add_argument("--output", default="release-evidence.json", type=Path)
    parser.add_argument("--validation-log", required=True, type=Path)
    parser.add_argument("--validation-status", required=True, choices=("passed", "failed"))
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument(
        "--target",
        action="append",
        required=True,
        choices=TARGET_ORDER,
        dest="targets",
    )
    arguments = parser.parse_args()

    evidence_root = arguments.evidence_root.resolve(strict=True)
    if not evidence_root.is_dir():
        raise ValueError("evidence root must be a directory")
    validation_log = arguments.validation_log.resolve(strict=True)
    if not validation_log.is_file() or not inside(evidence_root, validation_log):
        raise ValueError("validation log must be a file inside the evidence root")
    output = arguments.output
    if not output.is_absolute():
        output = evidence_root / output
    output = output.resolve(strict=False)
    if not inside(evidence_root, output):
        raise ValueError("output must remain inside the evidence root")
    if output.exists():
        raise FileExistsError(f"refusing to overwrite existing manifest: {output}")

    targets = [target for target in TARGET_ORDER if target in set(arguments.targets)]
    if len(targets) != len(arguments.targets):
        raise ValueError("targets must be unique")
    compatibility = {
        "capabilityProtocol": "0.1",
        "interactiveControl": "0.1",
        "localIPC": "0.1",
        "minimumMacOS": "26.0" if "macOS" in targets else None,
        "minimumIOS": "26.0" if "iOS" in targets else None,
    }
    manifest: dict[str, object] = {
        "schemaVersion": "0.1",
        "evidenceLevel": "unsignedConstruction",
        "product": "Mac Companion",
        "release": {
            "version": arguments.version,
            "buildNumber": arguments.build_number,
            "channel": "development",
            "targets": targets,
        },
        "compatibility": compatibility,
        "source": {
            "revision": git_revision(),
            "dirty": git_dirty(),
        },
        "toolchain": collect_toolchain(targets),
        "validation": [
            {
                "id": "repository-gate",
                "status": arguments.validation_status,
                "evidence": file_reference(evidence_root, validation_log),
            }
        ],
        "artifacts": [],
        "executables": [],
        "notarization": None,
        "sbom": None,
        "physicalScenarios": [],
        "promotion": None,
    }
    errors = validate_manifest(manifest)
    if errors:
        raise ValueError(f"generated manifest is invalid: {', '.join(sorted(errors))}")
    write_atomically(output, manifest)
    print(output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
