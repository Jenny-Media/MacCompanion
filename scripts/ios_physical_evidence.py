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


SCHEMA = "maccompanion.ios-physical-evidence.v0.1"
PRODUCT = "Mac Companion"
APP_IDENTIFIER = "media.jenny.maccompanion.ios"
MAX_RECORD_BYTES = 1024 * 1024
MAX_EVIDENCE_BYTES = 16 * 1024 * 1024
REVISION = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
OS_VERSION = re.compile(r"^[0-9]+\.[0-9]+(?:\.[0-9]+)?$")

ROOT_KEYS = {"schemaVersion", "product", "created", "device", "candidate", "cases"}
DEVICE_KEYS = {"model", "architecture", "iOSVersion", "passcodeSet", "freshInstall"}
CANDIDATE_KEYS = {
    "version", "buildNumber", "channel", "sourceRevision", "bundleIdentifier", "artifact",
}
ARTIFACT_KEYS = {"id", "kind", "path", "sha256", "bytes"}
CASE_KEYS = {"id", "outcome", "observedVersion", "observedBuildNumber", "assertions", "evidence"}
REFERENCE_KEYS = {"path", "sha256", "bytes"}
CASE_PROFILE = (
    (
        "physical-pairing",
        "pairedObserveAndActReady",
        (
            "camera-permission-local-only", "qr-expiry-enforced",
            "host-fingerprint-pinned", "sas-matched-both-devices",
            "local-device-name-confirmed", "session-key-after-first-unlock-device-only",
            "approval-key-current-user-presence-set", "durable-before-paired",
            "observe-status-succeeds", "set-audio-muted-approved-and-observed",
        ),
    ),
    (
        "local-network-denial",
        "localUIAvailableRemoteDeniedThenRecovered",
        (
            "local-network-permission-denied", "no-route-published-while-denied",
            "pairing-authority-not-broadened", "local-recovery-guidance-visible",
            "settings-grant-recovers-route", "pinned-host-identity-unchanged",
        ),
    ),
    (
        "background-reconnect",
        "foregroundPinnedReconnectReady",
        (
            "paired-route-established", "background-entry-closes-interactive-control",
            "network-loss-retires-route", "pre-first-unlock-reconnect-denied",
            "post-first-unlock-session-key-needs-no-presence-prompt",
            "foreground-return-reconnects", "host-pin-revalidated",
            "pending-operation-not-replayed", "control-needs-fresh-presence",
        ),
    ),
)


class IOSPhysicalEvidenceError(ValueError):
    pass


def _closed(value: Any, keys: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise IOSPhysicalEvidenceError(f"{label} is not closed")
    return value


def _bounded_string(value: Any, label: str, maximum: int = 128) -> str:
    if (
        not isinstance(value, str) or not value
        or len(value.encode("utf-8")) > maximum
        or any(ord(character) < 32 or ord(character) == 127 for character in value)
    ):
        raise IOSPhysicalEvidenceError(f"{label} is not bounded")
    return value


def _reference(value: Any, label: str) -> dict[str, Any]:
    reference = _closed(value, REFERENCE_KEYS, label)
    try:
        safe_relative_path(reference.get("path"), f"{label} path")
    except ArtifactSBOMError as error:
        raise IOSPhysicalEvidenceError(f"{label} path is unsafe") from error
    byte_count = reference.get("bytes")
    digest = reference.get("sha256")
    if (
        not isinstance(byte_count, int) or isinstance(byte_count, bool)
        or not 0 < byte_count <= MAX_EVIDENCE_BYTES
        or not isinstance(digest, str) or SHA256.fullmatch(digest) is None
        or len(set(digest)) == 1
    ):
        raise IOSPhysicalEvidenceError(f"{label} binding is invalid")
    return dict(reference)


def _read_bounded_file(path: Path, maximum: int, label: str) -> bytes:
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0))
    except OSError as error:
        raise IOSPhysicalEvidenceError(f"{label} is unavailable") from error
    try:
        before = os.fstat(descriptor)
        if (
            not stat.S_ISREG(before.st_mode) or before.st_nlink != 1
            or not 0 < before.st_size <= maximum
        ):
            raise IOSPhysicalEvidenceError(f"{label} is not a bounded single-link file")
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
            raise IOSPhysicalEvidenceError(f"{label} changed during bounded read")
        return raw
    finally:
        os.close(descriptor)


def load_canonical_record(path: Path) -> tuple[dict[str, Any], bytes]:
    raw = _read_bounded_file(path, MAX_RECORD_BYTES, "iOS physical record")
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=closed_pairs)
    except (UnicodeDecodeError, json.JSONDecodeError, ArtifactSBOMError) as error:
        raise IOSPhysicalEvidenceError("iOS physical record is not duplicate-safe JSON") from error
    if not isinstance(value, dict) or raw != canonical_bytes(value):
        raise IOSPhysicalEvidenceError("iOS physical record is not canonical JSON")
    return value, raw


def _release_artifact(release_manifest: dict[str, Any]) -> dict[str, Any]:
    artifacts = release_manifest.get("artifacts")
    matches = [item for item in artifacts or [] if isinstance(item, dict) and item.get("kind") == "iosArchive"]
    if len(matches) != 1:
        raise IOSPhysicalEvidenceError("release must contain exactly one iosArchive")
    return {key: matches[0].get(key) for key in ARTIFACT_KEYS}


def _verify_reference(root: Path, reference: dict[str, Any]) -> None:
    candidate = root / reference["path"]
    if candidate.is_symlink():
        raise IOSPhysicalEvidenceError("iOS evidence path contains a symlink")
    try:
        resolved = resolve_inside(root, reference["path"], must_exist=True)
    except ArtifactSBOMError as error:
        raise IOSPhysicalEvidenceError("iOS evidence is unavailable") from error
    if candidate.absolute() != resolved:
        raise IOSPhysicalEvidenceError("iOS evidence path contains a symlink")
    raw = _read_bounded_file(resolved, MAX_EVIDENCE_BYTES, "iOS evidence")
    if (hashlib.sha256(raw).hexdigest(), len(raw)) != (reference["sha256"], reference["bytes"]):
        raise IOSPhysicalEvidenceError("iOS evidence binding mismatch")


def validate_record(
    value: Any,
    *,
    release_manifest: dict[str, Any],
    evidence_root: Path | None = None,
    verify_files: bool = False,
) -> dict[str, Any]:
    root = _closed(value, ROOT_KEYS, "iOS physical record")
    if root.get("schemaVersion") != SCHEMA or root.get("product") != PRODUCT:
        raise IOSPhysicalEvidenceError("iOS physical record identity is invalid")
    try:
        parse_timestamp(root.get("created"))
    except ArtifactSBOMError as error:
        raise IOSPhysicalEvidenceError("iOS physical record creation time is invalid") from error
    device = _closed(root.get("device"), DEVICE_KEYS, "physical device")
    _bounded_string(device.get("model"), "device model", 96)
    if (
        device.get("architecture") != "arm64" or device.get("passcodeSet") is not True
        or device.get("freshInstall") is not True
        or not isinstance(device.get("iOSVersion"), str)
        or OS_VERSION.fullmatch(device["iOSVersion"]) is None
    ):
        raise IOSPhysicalEvidenceError("physical device posture is invalid")

    release = release_manifest.get("release")
    source = release_manifest.get("source")
    if not isinstance(release, dict) or not isinstance(source, dict):
        raise IOSPhysicalEvidenceError("release manifest cannot bind iOS evidence")
    if source.get("dirty") is not False or not isinstance(source.get("revision"), str) or REVISION.fullmatch(source["revision"]) is None:
        raise IOSPhysicalEvidenceError("release source is not clean and exact")
    candidate = _closed(root.get("candidate"), CANDIDATE_KEYS, "iOS candidate")
    expected = {
        "version": release.get("version"), "buildNumber": release.get("buildNumber"),
        "channel": release.get("channel"), "sourceRevision": source.get("revision"),
        "bundleIdentifier": APP_IDENTIFIER, "artifact": _release_artifact(release_manifest),
    }
    if candidate != expected:
        raise IOSPhysicalEvidenceError("iOS candidate does not match the release manifest")
    if candidate["channel"] not in {"beta", "stable"} or "iOS" not in release.get("targets", []):
        raise IOSPhysicalEvidenceError("iOS candidate is not promotion eligible")

    cases = root.get("cases")
    if not isinstance(cases, list) or len(cases) != len(CASE_PROFILE):
        raise IOSPhysicalEvidenceError("iOS physical record has the wrong case set")
    references: list[dict[str, Any]] = []
    for item, (case_id, outcome, assertions) in zip(cases, CASE_PROFILE):
        case = _closed(item, CASE_KEYS, f"iOS case {case_id}")
        if (
            case.get("id") != case_id or case.get("outcome") != outcome
            or case.get("observedVersion") != candidate["version"]
            or case.get("observedBuildNumber") != candidate["buildNumber"]
            or case.get("assertions") != list(assertions)
        ):
            raise IOSPhysicalEvidenceError(f"iOS case {case_id} is not exact")
        references.append(_reference(case.get("evidence"), f"iOS case {case_id} evidence"))
    paths = [reference["path"] for reference in references]
    if len(paths) != len(set(paths)):
        raise IOSPhysicalEvidenceError("iOS evidence paths must be distinct")
    if verify_files:
        if evidence_root is None:
            raise IOSPhysicalEvidenceError("file verification requires an evidence root")
        resolved_root = evidence_root.resolve(strict=True)
        for reference in references:
            _verify_reference(resolved_root, reference)
    elif evidence_root is not None:
        raise IOSPhysicalEvidenceError("evidence root requires file verification")
    return root
