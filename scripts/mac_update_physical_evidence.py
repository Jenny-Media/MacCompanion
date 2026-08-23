#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import os
import re
import stat
from pathlib import Path
from typing import Any

from artifact_sbom import (
    ArtifactSBOMError,
    canonical_bytes,
    closed_pairs,
    parse_timestamp,
    resolve_inside,
    safe_relative_path,
)


SCHEMA = "maccompanion.mac-update-physical-evidence.v0.1"
PRODUCT = "Mac Companion"
APP_IDENTIFIER = "media.jenny.maccompanion"
UPDATE_CHECK_PROFILE = "maccompanion.user-initiated-full-update-check.v1"
MAX_RECORD_BYTES = 1024 * 1024
MAX_EVIDENCE_BYTES = 16 * 1024 * 1024
VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$")
BUILD = re.compile(r"^(?:0|[1-9][0-9]{0,17})$")
REVISION = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
TEAM = re.compile(r"^[A-Z0-9]{10}$")
MACOS_VERSION = re.compile(r"^[0-9]+\.[0-9]+(?:\.[0-9]+)?$")

ROOT_KEYS = {
    "schemaVersion",
    "product",
    "created",
    "machine",
    "sourceInstallation",
    "candidate",
    "cases",
}
MACHINE_KEYS = {"hardwareModel", "architecture", "macOSVersion"}
SOURCE_KEYS = {
    "version",
    "buildNumber",
    "bundleIdentifier",
    "teamIdentifier",
    "evidence",
}
CANDIDATE_KEYS = {
    "version",
    "buildNumber",
    "channel",
    "sourceRevision",
    "bundleIdentifier",
    "updateCheckProfile",
    "artifacts",
}
ARTIFACT_KEYS = {"id", "kind", "path", "sha256", "bytes"}
CASE_KEYS = {
    "id",
    "outcome",
    "observedVersion",
    "observedBuildNumber",
    "freshUser",
    "evidence",
}
REFERENCE_KEYS = {"path", "sha256", "bytes"}
ARTIFACT_ORDER = ("macApplication", "macDiskImage", "sparkleArchive")
CASE_PROFILE = (
    ("not-now", "sourceRunning", False),
    ("foreground-loss", "sourceRunning", False),
    ("control-active-denial", "sourceRunning", False),
    ("cleanup-uncertain-denial", "sourceRunning", False),
    ("forced-loss-before-quiescence", "sourceRunning", False),
    ("forced-loss-after-quiescence", "sourceRecovered", False),
    ("forced-loss-after-agent-stop", "sourceRecovered", False),
    ("successful-upgrade", "candidateRunning", False),
    ("forced-loss-after-installer-handoff", "candidateRunning", False),
    ("rollback", "sourceRunning", False),
    ("clean-user-upgrade", "candidateRunning", True),
    ("no-background-network", "candidateRunning", False),
)


class MacUpdatePhysicalEvidenceError(ValueError):
    pass


def _closed(value: Any, keys: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise MacUpdatePhysicalEvidenceError(f"{label} is not closed")
    return value


def _bounded_string(value: Any, label: str, maximum: int = 128) -> str:
    if (
        not isinstance(value, str)
        or not value
        or len(value.encode("utf-8")) > maximum
        or any(ord(character) < 32 or ord(character) == 127 for character in value)
    ):
        raise MacUpdatePhysicalEvidenceError(f"{label} is not a bounded string")
    return value


def _reference(value: Any, label: str) -> dict[str, Any]:
    reference = _closed(value, REFERENCE_KEYS, label)
    try:
        safe_relative_path(reference.get("path"), f"{label} path")
    except ArtifactSBOMError as error:
        raise MacUpdatePhysicalEvidenceError(f"{label} path is unsafe") from error
    byte_count = reference.get("bytes")
    digest = reference.get("sha256")
    if (
        not isinstance(byte_count, int)
        or isinstance(byte_count, bool)
        or not 0 < byte_count <= MAX_EVIDENCE_BYTES
        or not isinstance(digest, str)
        or SHA256.fullmatch(digest) is None
        or len(set(digest)) == 1
    ):
        raise MacUpdatePhysicalEvidenceError(f"{label} binding is invalid")
    return dict(reference)


def _read_bounded_file(path: Path, maximum: int, label: str) -> bytes:
    try:
        descriptor = os.open(
            path,
            os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0),
        )
    except OSError as error:
        raise MacUpdatePhysicalEvidenceError(f"{label} must be a bounded non-symlink file") from error
    try:
        before = os.fstat(descriptor)
        if (
            not stat.S_ISREG(before.st_mode)
            or before.st_nlink != 1
            or not 0 < before.st_size <= maximum
        ):
            raise MacUpdatePhysicalEvidenceError(f"{label} must be a bounded single-link file")
        chunks: list[bytes] = []
        remaining = maximum + 1
        while remaining > 0:
            chunk = os.read(descriptor, min(64 * 1024, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        raw = b"".join(chunks)
        after = os.fstat(descriptor)
        identity = lambda value: (
            value.st_dev,
            value.st_ino,
            value.st_mode,
            value.st_nlink,
            value.st_size,
            value.st_mtime_ns,
            value.st_ctime_ns,
        )
        if len(raw) != after.st_size or len(raw) > maximum or identity(before) != identity(after):
            raise MacUpdatePhysicalEvidenceError(f"{label} changed during bounded read")
        return raw
    finally:
        os.close(descriptor)


def load_canonical_record(path: Path) -> tuple[dict[str, Any], bytes]:
    raw = _read_bounded_file(path, MAX_RECORD_BYTES, "update matrix")
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=closed_pairs)
    except (UnicodeDecodeError, json.JSONDecodeError, ArtifactSBOMError) as error:
        raise MacUpdatePhysicalEvidenceError("update matrix is not duplicate-safe UTF-8 JSON") from error
    if not isinstance(value, dict) or raw != canonical_bytes(value):
        raise MacUpdatePhysicalEvidenceError("update matrix is not canonical JSON")
    return value, raw


def _release_artifacts(release_manifest: dict[str, Any]) -> list[dict[str, Any]]:
    artifacts = release_manifest.get("artifacts")
    if not isinstance(artifacts, list):
        raise MacUpdatePhysicalEvidenceError("release artifacts are unavailable")
    result: list[dict[str, Any]] = []
    for kind in ARTIFACT_ORDER:
        matches = [item for item in artifacts if isinstance(item, dict) and item.get("kind") == kind]
        if len(matches) != 1:
            raise MacUpdatePhysicalEvidenceError(f"release must contain exactly one {kind}")
        result.append({key: matches[0].get(key) for key in ARTIFACT_KEYS})
    return result


def _verify_reference(root: Path, reference: dict[str, Any]) -> None:
    candidate = root / reference["path"]
    if candidate.is_symlink():
        raise MacUpdatePhysicalEvidenceError("physical evidence path contains a symlink")
    try:
        resolved = resolve_inside(root, reference["path"], must_exist=True)
    except (ArtifactSBOMError, KeyError) as error:
        raise MacUpdatePhysicalEvidenceError("physical evidence file is unavailable") from error
    if candidate.absolute() != resolved:
        raise MacUpdatePhysicalEvidenceError("physical evidence path contains a symlink")
    raw = _read_bounded_file(resolved, MAX_EVIDENCE_BYTES, "physical evidence")
    digest = hashlib.sha256(raw).hexdigest()
    byte_count = len(raw)
    if (digest, byte_count) != (reference["sha256"], reference["bytes"]):
        raise MacUpdatePhysicalEvidenceError("physical evidence file binding mismatch")


def validate_record(
    value: Any,
    *,
    release_manifest: dict[str, Any],
    evidence_root: Path | None = None,
    verify_files: bool = False,
) -> dict[str, Any]:
    root = _closed(value, ROOT_KEYS, "update matrix")
    if root.get("schemaVersion") != SCHEMA or root.get("product") != PRODUCT:
        raise MacUpdatePhysicalEvidenceError("update matrix identity is invalid")
    try:
        parse_timestamp(root.get("created"))
    except ArtifactSBOMError as error:
        raise MacUpdatePhysicalEvidenceError("update matrix creation time is invalid") from error

    machine = _closed(root.get("machine"), MACHINE_KEYS, "test machine")
    _bounded_string(machine.get("hardwareModel"), "hardware model", 96)
    if machine.get("architecture") != "arm64":
        raise MacUpdatePhysicalEvidenceError("test architecture is unsupported")
    if not isinstance(machine.get("macOSVersion"), str) or MACOS_VERSION.fullmatch(machine["macOSVersion"]) is None:
        raise MacUpdatePhysicalEvidenceError("test macOS version is invalid")

    release = release_manifest.get("release")
    source = release_manifest.get("source")
    compatibility = release_manifest.get("compatibility")
    if not all(isinstance(item, dict) for item in (release, source, compatibility)):
        raise MacUpdatePhysicalEvidenceError("release manifest cannot bind an update matrix")
    if source.get("dirty") is not False or not isinstance(source.get("revision"), str) or REVISION.fullmatch(source["revision"]) is None:
        raise MacUpdatePhysicalEvidenceError("release source is not clean and exact")

    candidate = _closed(root.get("candidate"), CANDIDATE_KEYS, "candidate")
    expected_candidate = {
        "version": release.get("version"),
        "buildNumber": release.get("buildNumber"),
        "channel": release.get("channel"),
        "sourceRevision": source.get("revision"),
        "bundleIdentifier": APP_IDENTIFIER,
        "updateCheckProfile": compatibility.get("macUserInitiatedUpdateCheckProfile"),
        "artifacts": _release_artifacts(release_manifest),
    }
    if candidate != expected_candidate:
        raise MacUpdatePhysicalEvidenceError("candidate does not match the release manifest")
    if candidate["channel"] not in {"beta", "stable"} or candidate["updateCheckProfile"] != UPDATE_CHECK_PROFILE:
        raise MacUpdatePhysicalEvidenceError("candidate is not eligible for the physical update matrix")

    source_installation = _closed(root.get("sourceInstallation"), SOURCE_KEYS, "source installation")
    source_version = source_installation.get("version")
    source_build = source_installation.get("buildNumber")
    if (
        not isinstance(source_version, str)
        or VERSION.fullmatch(source_version) is None
        or not isinstance(source_build, str)
        or BUILD.fullmatch(source_build) is None
        or not isinstance(candidate.get("buildNumber"), str)
        or BUILD.fullmatch(candidate["buildNumber"]) is None
        or int(source_build) >= int(candidate["buildNumber"])
        or source_installation.get("bundleIdentifier") != APP_IDENTIFIER
        or not isinstance(source_installation.get("teamIdentifier"), str)
        or TEAM.fullmatch(source_installation["teamIdentifier"]) is None
    ):
        raise MacUpdatePhysicalEvidenceError("source installation is invalid or not older")
    references = [_reference(source_installation.get("evidence"), "source installation evidence")]

    cases = root.get("cases")
    if not isinstance(cases, list) or len(cases) != len(CASE_PROFILE):
        raise MacUpdatePhysicalEvidenceError("update matrix has the wrong case set")
    for item, (case_id, outcome, fresh_user) in zip(cases, CASE_PROFILE):
        case = _closed(item, CASE_KEYS, f"update case {case_id}")
        expected_version = candidate["version"] if outcome == "candidateRunning" else source_version
        expected_build = candidate["buildNumber"] if outcome == "candidateRunning" else source_build
        if (
            case.get("id") != case_id
            or case.get("outcome") != outcome
            or case.get("observedVersion") != expected_version
            or case.get("observedBuildNumber") != expected_build
            or case.get("freshUser") is not fresh_user
        ):
            raise MacUpdatePhysicalEvidenceError(f"update case {case_id} does not match its closed outcome")
        references.append(_reference(case.get("evidence"), f"update case {case_id} evidence"))
    paths = [reference["path"] for reference in references]
    if len(paths) != len(set(paths)):
        raise MacUpdatePhysicalEvidenceError("update matrix evidence paths must be distinct")
    if verify_files:
        if evidence_root is None:
            raise MacUpdatePhysicalEvidenceError("file verification requires an evidence root")
        resolved_root = evidence_root.resolve(strict=True)
        for reference in references:
            _verify_reference(resolved_root, reference)
    elif evidence_root is not None:
        raise MacUpdatePhysicalEvidenceError("evidence root requires file verification")
    return root
