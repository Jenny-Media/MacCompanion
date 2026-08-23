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


SCHEMA = "maccompanion.mac-lifecycle-physical-evidence.v0.1"
PRODUCT = "Mac Companion"
APP_IDENTIFIER = "media.jenny.maccompanion"
UPDATE_CHECK_PROFILE = "maccompanion.user-initiated-full-update-check.v1"
MAX_RECORD_BYTES = 1024 * 1024
MAX_EVIDENCE_BYTES = 16 * 1024 * 1024
REVISION = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
MACOS_VERSION = re.compile(r"^[0-9]+\.[0-9]+(?:\.[0-9]+)?$")

ROOT_KEYS = {"schemaVersion", "product", "created", "machine", "candidate", "cases"}
MACHINE_KEYS = {"hardwareModel", "architecture", "macOSVersion"}
CANDIDATE_KEYS = {
    "version", "buildNumber", "channel", "sourceRevision", "bundleIdentifier",
    "updateCheckProfile", "artifacts",
}
ARTIFACT_KEYS = {"id", "kind", "path", "sha256", "bytes"}
CASE_KEYS = {
    "id", "outcome", "observedVersion", "observedBuildNumber", "freshUser",
    "assertions", "evidence",
}
REFERENCE_KEYS = {"path", "sha256", "bytes"}
ARTIFACT_ORDER = ("macApplication", "macDiskImage", "sparkleArchive")
CASE_PROFILE = (
    (
        "quarantine-launch", "candidateRunning", True,
        (
            "quarantine-present", "gatekeeper-accepted", "no-bypass-used",
            "official-identity-observed",
        ),
    ),
    (
        "clean-install", "candidateReady", True,
        (
            "prior-product-state-absent", "explicit-enablement-confirmed",
            "login-roles-running", "agent-authenticated-ready",
            "local-administration-available",
        ),
    ),
    (
        "permission-revocation", "candidateLocallyManageableRemoteDenied", False,
        (
            "screen-recording-revoked", "accessibility-revoked",
            "capture-denied", "input-denied", "remote-ingress-denied",
            "local-administration-available", "regrant-requires-local-action",
        ),
    ),
    (
        "complete-uninstall", "productRemoved", False,
        (
            "remote-access-disabled-first", "login-roles-unregistered",
            "listener-absent", "pairings-revoked", "product-data-removed",
            "privileged-helper-absent", "reinstall-does-not-restore-authority",
        ),
    ),
)


class MacLifecyclePhysicalEvidenceError(ValueError):
    pass


def _closed(value: Any, keys: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise MacLifecyclePhysicalEvidenceError(f"{label} is not closed")
    return value


def _bounded_string(value: Any, label: str, maximum: int = 128) -> str:
    if (
        not isinstance(value, str) or not value
        or len(value.encode("utf-8")) > maximum
        or any(ord(character) < 32 or ord(character) == 127 for character in value)
    ):
        raise MacLifecyclePhysicalEvidenceError(f"{label} is not bounded")
    return value


def _reference(value: Any, label: str) -> dict[str, Any]:
    reference = _closed(value, REFERENCE_KEYS, label)
    try:
        safe_relative_path(reference.get("path"), f"{label} path")
    except ArtifactSBOMError as error:
        raise MacLifecyclePhysicalEvidenceError(f"{label} path is unsafe") from error
    byte_count = reference.get("bytes")
    digest = reference.get("sha256")
    if (
        not isinstance(byte_count, int) or isinstance(byte_count, bool)
        or not 0 < byte_count <= MAX_EVIDENCE_BYTES
        or not isinstance(digest, str) or SHA256.fullmatch(digest) is None
        or len(set(digest)) == 1
    ):
        raise MacLifecyclePhysicalEvidenceError(f"{label} binding is invalid")
    return dict(reference)


def _read_bounded_file(path: Path, maximum: int, label: str) -> bytes:
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0))
    except OSError as error:
        raise MacLifecyclePhysicalEvidenceError(f"{label} is unavailable") from error
    try:
        before = os.fstat(descriptor)
        if (
            not stat.S_ISREG(before.st_mode) or before.st_nlink != 1
            or not 0 < before.st_size <= maximum
        ):
            raise MacLifecyclePhysicalEvidenceError(f"{label} is not a bounded single-link file")
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
            value.st_dev, value.st_ino, value.st_mode, value.st_nlink,
            value.st_size, value.st_mtime_ns, value.st_ctime_ns,
        )
        if len(raw) != after.st_size or len(raw) > maximum or identity(before) != identity(after):
            raise MacLifecyclePhysicalEvidenceError(f"{label} changed during bounded read")
        return raw
    finally:
        os.close(descriptor)


def load_canonical_record(path: Path) -> tuple[dict[str, Any], bytes]:
    raw = _read_bounded_file(path, MAX_RECORD_BYTES, "lifecycle matrix")
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=closed_pairs)
    except (UnicodeDecodeError, json.JSONDecodeError, ArtifactSBOMError) as error:
        raise MacLifecyclePhysicalEvidenceError("lifecycle matrix is not duplicate-safe JSON") from error
    if not isinstance(value, dict) or raw != canonical_bytes(value):
        raise MacLifecyclePhysicalEvidenceError("lifecycle matrix is not canonical JSON")
    return value, raw


def _release_artifacts(release_manifest: dict[str, Any]) -> list[dict[str, Any]]:
    artifacts = release_manifest.get("artifacts")
    if not isinstance(artifacts, list):
        raise MacLifecyclePhysicalEvidenceError("release artifacts are unavailable")
    result: list[dict[str, Any]] = []
    for kind in ARTIFACT_ORDER:
        matches = [item for item in artifacts if isinstance(item, dict) and item.get("kind") == kind]
        if len(matches) != 1:
            raise MacLifecyclePhysicalEvidenceError(f"release must contain exactly one {kind}")
        result.append({key: matches[0].get(key) for key in ARTIFACT_KEYS})
    return result


def _verify_reference(root: Path, reference: dict[str, Any]) -> None:
    candidate = root / reference["path"]
    if candidate.is_symlink():
        raise MacLifecyclePhysicalEvidenceError("lifecycle evidence path contains a symlink")
    try:
        resolved = resolve_inside(root, reference["path"], must_exist=True)
    except ArtifactSBOMError as error:
        raise MacLifecyclePhysicalEvidenceError("lifecycle evidence is unavailable") from error
    if candidate.absolute() != resolved:
        raise MacLifecyclePhysicalEvidenceError("lifecycle evidence path contains a symlink")
    raw = _read_bounded_file(resolved, MAX_EVIDENCE_BYTES, "lifecycle evidence")
    if (hashlib.sha256(raw).hexdigest(), len(raw)) != (reference["sha256"], reference["bytes"]):
        raise MacLifecyclePhysicalEvidenceError("lifecycle evidence binding mismatch")


def validate_record(
    value: Any,
    *,
    release_manifest: dict[str, Any],
    evidence_root: Path | None = None,
    verify_files: bool = False,
) -> dict[str, Any]:
    root = _closed(value, ROOT_KEYS, "lifecycle matrix")
    if root.get("schemaVersion") != SCHEMA or root.get("product") != PRODUCT:
        raise MacLifecyclePhysicalEvidenceError("lifecycle matrix identity is invalid")
    try:
        parse_timestamp(root.get("created"))
    except ArtifactSBOMError as error:
        raise MacLifecyclePhysicalEvidenceError("lifecycle matrix creation time is invalid") from error
    machine = _closed(root.get("machine"), MACHINE_KEYS, "test machine")
    _bounded_string(machine.get("hardwareModel"), "hardware model", 96)
    if machine.get("architecture") != "arm64":
        raise MacLifecyclePhysicalEvidenceError("test architecture is unsupported")
    if not isinstance(machine.get("macOSVersion"), str) or MACOS_VERSION.fullmatch(machine["macOSVersion"]) is None:
        raise MacLifecyclePhysicalEvidenceError("test macOS version is invalid")

    release = release_manifest.get("release")
    source = release_manifest.get("source")
    compatibility = release_manifest.get("compatibility")
    if not all(isinstance(item, dict) for item in (release, source, compatibility)):
        raise MacLifecyclePhysicalEvidenceError("release manifest cannot bind lifecycle evidence")
    if source.get("dirty") is not False or not isinstance(source.get("revision"), str) or REVISION.fullmatch(source["revision"]) is None:
        raise MacLifecyclePhysicalEvidenceError("release source is not clean and exact")
    candidate = _closed(root.get("candidate"), CANDIDATE_KEYS, "candidate")
    expected_candidate = {
        "version": release.get("version"), "buildNumber": release.get("buildNumber"),
        "channel": release.get("channel"), "sourceRevision": source.get("revision"),
        "bundleIdentifier": APP_IDENTIFIER,
        "updateCheckProfile": compatibility.get("macUserInitiatedUpdateCheckProfile"),
        "artifacts": _release_artifacts(release_manifest),
    }
    if candidate != expected_candidate:
        raise MacLifecyclePhysicalEvidenceError("candidate does not match the release manifest")
    if candidate["channel"] not in {"beta", "stable"} or candidate["updateCheckProfile"] != UPDATE_CHECK_PROFILE:
        raise MacLifecyclePhysicalEvidenceError("candidate is not promotion eligible")

    cases = root.get("cases")
    if not isinstance(cases, list) or len(cases) != len(CASE_PROFILE):
        raise MacLifecyclePhysicalEvidenceError("lifecycle matrix has the wrong case set")
    references: list[dict[str, Any]] = []
    for item, (case_id, outcome, fresh_user, assertions) in zip(cases, CASE_PROFILE):
        case = _closed(item, CASE_KEYS, f"lifecycle case {case_id}")
        removed = outcome == "productRemoved"
        if (
            case.get("id") != case_id or case.get("outcome") != outcome
            or case.get("observedVersion") != (None if removed else candidate["version"])
            or case.get("observedBuildNumber") != (None if removed else candidate["buildNumber"])
            or case.get("freshUser") is not fresh_user
            or case.get("assertions") != list(assertions)
        ):
            raise MacLifecyclePhysicalEvidenceError(f"lifecycle case {case_id} is not exact")
        references.append(_reference(case.get("evidence"), f"lifecycle case {case_id} evidence"))
    paths = [reference["path"] for reference in references]
    if len(paths) != len(set(paths)):
        raise MacLifecyclePhysicalEvidenceError("lifecycle evidence paths must be distinct")
    if verify_files:
        if evidence_root is None:
            raise MacLifecyclePhysicalEvidenceError("file verification requires an evidence root")
        resolved_root = evidence_root.resolve(strict=True)
        for reference in references:
            _verify_reference(resolved_root, reference)
    elif evidence_root is not None:
        raise MacLifecyclePhysicalEvidenceError("evidence root requires file verification")
    return root
