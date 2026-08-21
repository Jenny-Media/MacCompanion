#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import os
import re
import stat
from pathlib import Path
from typing import Any

from artifact_sbom import (
    ArtifactSBOMError,
    exact_keys,
    parse_canonical_json,
    parse_timestamp,
    resolve_inside,
    safe_relative_path,
)


SCHEMA = "maccompanion.signed-code-verification.v0.1"
PRODUCT = "Mac Companion"
MAX_BUNDLE_BYTES = 1024 * 1024
MAX_RAW_EVIDENCE_BYTES = 16 * 1024 * 1024
SHA1 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
MODE = re.compile(r"^[0-7]{4}$")
IDENTIFIER = re.compile(r"^[a-z0-9](?:[a-z0-9.-]{0,62}[a-z0-9])?$")
BUNDLE_IDENTIFIER = re.compile(r"^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$")
TEAM_IDENTIFIER = re.compile(r"^[A-Z0-9]{10}$")
CDHASH = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")

ROOT_KEYS = {
    "schemaVersion", "evidenceLevel", "product", "release", "source", "created",
    "artifactSBOM", "executable", "artifact",
    "artifactMember",
    "codeIdentity", "reportedChecks", "evidence",
}
RELEASE_KEYS = {"version", "buildNumber", "targets"}
SOURCE_KEYS = {"revision", "dirty"}
ARTIFACT_KEYS = {"id", "kind", "platform", "path", "sha256", "bytes"}
EXECUTABLE_KEYS = {
    "id", "role", "platform", "bundleIdentifier", "artifactID", "relativePath",
}
MEMBER_KEYS = {"path", "type", "mode", "bytes", "sha1", "sha256", "symlinkTarget"}
IDENTITY_KEYS = {"signingIdentifier", "teamIdentifier", "cdhash", "certificateSHA256"}
CHECK_KEYS = {"codesignVerify", "platformAssessment"}
EVIDENCE_KEYS = {
    "designatedRequirement", "entitlements", "codesignVerification", "platformAssessment",
}
REFERENCE_KEYS = {"path", "sha256", "bytes"}


class SignedCodeVerificationError(ValueError):
    pass


def _bounded_canonical_object(path: Path) -> tuple[dict[str, Any], bytes]:
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError as error:
        raise SignedCodeVerificationError("verification bundle is not a bounded regular file") from error
    try:
        before = os.fstat(descriptor)
        if (
            not stat.S_ISREG(before.st_mode)
            or before.st_size <= 0
            or before.st_size > MAX_BUNDLE_BYTES
        ):
            raise SignedCodeVerificationError("verification bundle is not a bounded regular file")
        chunks: list[bytes] = []
        remaining = MAX_BUNDLE_BYTES + 1
        while remaining > 0:
            chunk = os.read(descriptor, min(64 * 1024, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        raw = b"".join(chunks)
        after = os.fstat(descriptor)
        if (
            len(raw) > MAX_BUNDLE_BYTES
            or len(raw) != after.st_size
            or (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns, before.st_ctime_ns)
            != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns)
        ):
            raise SignedCodeVerificationError("verification bundle changed during read")
    finally:
        os.close(descriptor)
    try:
        value = parse_canonical_json(raw)
    except (ArtifactSBOMError, UnicodeError) as error:
        raise SignedCodeVerificationError("verification bundle is not canonical JSON") from error
    if not isinstance(value, dict):
        raise SignedCodeVerificationError("verification bundle must be an object")
    return value, raw


def load_bundle(path: Path) -> tuple[dict[str, Any], bytes]:
    return _bounded_canonical_object(path)


def _reference(value: Any, label: str) -> dict[str, Any]:
    try:
        reference = exact_keys(value, REFERENCE_KEYS, label)
        normalized = safe_relative_path(reference["path"], f"{label} path")
    except ArtifactSBOMError as error:
        raise SignedCodeVerificationError(str(error)) from error
    if (
        normalized != reference["path"]
        or not isinstance(reference["sha256"], str)
        or SHA256.fullmatch(reference["sha256"]) is None
        or not isinstance(reference["bytes"], int)
        or isinstance(reference["bytes"], bool)
        or reference["bytes"] <= 0
        or reference["bytes"] > MAX_RAW_EVIDENCE_BYTES
    ):
        raise SignedCodeVerificationError(f"invalid {label}")
    return reference


def _verify_reference(root: Path, reference: dict[str, Any]) -> None:
    try:
        resolved_root = root.resolve(strict=True)
        candidate = resolved_root / reference["path"]
        path = resolve_inside(resolved_root, reference["path"], must_exist=True)
        if candidate.absolute() != path:
            raise SignedCodeVerificationError("signed-code raw evidence path contains a symlink")
        descriptor = os.open(candidate, os.O_RDONLY | os.O_NOFOLLOW)
    except (ArtifactSBOMError, OSError) as error:
        raise SignedCodeVerificationError("signed-code raw evidence is unavailable") from error
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size != reference["bytes"]:
            raise SignedCodeVerificationError("signed-code raw evidence size mismatch")
        hasher = hashlib.sha256()
        size = 0
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            size += len(chunk)
            hasher.update(chunk)
        after = os.fstat(descriptor)
        if (
            size != metadata.st_size
            or (metadata.st_dev, metadata.st_ino, metadata.st_size, metadata.st_mtime_ns, metadata.st_ctime_ns)
            != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns)
            or hasher.hexdigest() != reference["sha256"]
        ):
            raise SignedCodeVerificationError("signed-code raw evidence digest mismatch")
    finally:
        os.close(descriptor)


def validate_bundle(
    value: dict[str, Any],
    *,
    release_executable: dict[str, Any],
    release_manifest: dict[str, Any],
    artifact_sbom_reference: dict[str, Any],
    artifact_binding: dict[str, Any],
    artifact_member: dict[str, Any],
    evidence_root: Path,
) -> None:
    try:
        root = exact_keys(value, ROOT_KEYS, "signed-code verification bundle")
        release = exact_keys(root["release"], RELEASE_KEYS, "verified release")
        source = exact_keys(root["source"], SOURCE_KEYS, "verified source")
        artifact = exact_keys(root["artifact"], ARTIFACT_KEYS, "verified artifact")
        executable = exact_keys(root["executable"], EXECUTABLE_KEYS, "verified executable")
        member = exact_keys(root["artifactMember"], MEMBER_KEYS, "verified artifact member")
        identity = exact_keys(root["codeIdentity"], IDENTITY_KEYS, "verified code identity")
        checks = exact_keys(root["reportedChecks"], CHECK_KEYS, "reported signed-code checks")
        evidence = exact_keys(root["evidence"], EVIDENCE_KEYS, "signed-code evidence")
    except ArtifactSBOMError as error:
        raise SignedCodeVerificationError(str(error)) from error
    if (
        root["schemaVersion"] != SCHEMA
        or root["evidenceLevel"] != "constructionCorrelation"
        or root["product"] != PRODUCT
    ):
        raise SignedCodeVerificationError("invalid signed-code verification identity")
    try:
        parse_timestamp(root["created"])
    except ArtifactSBOMError as error:
        raise SignedCodeVerificationError("invalid signed-code verification time") from error
    manifest_release = release_manifest.get("release", {})
    expected_release = {
        "version": manifest_release.get("version"),
        "buildNumber": manifest_release.get("buildNumber"),
        "targets": sorted(manifest_release.get("targets", [])),
    }
    if release != expected_release:
        raise SignedCodeVerificationError("signed-code release binding mismatch")
    expected_source = {
        "revision": release_manifest.get("source", {}).get("revision"),
        "dirty": release_manifest.get("source", {}).get("dirty"),
    }
    if source != expected_source or source.get("dirty") is not False:
        raise SignedCodeVerificationError("signed-code source binding mismatch")
    if artifact != {key: artifact_binding.get(key) for key in ARTIFACT_KEYS}:
        raise SignedCodeVerificationError("signed-code artifact binding mismatch")
    if _reference(root["artifactSBOM"], "artifact SBOM") != artifact_sbom_reference:
        raise SignedCodeVerificationError("signed-code artifact-SBOM binding mismatch")
    expected_executable = {
        key: release_executable.get(key)
        for key in EXECUTABLE_KEYS
    }
    if executable != expected_executable:
        raise SignedCodeVerificationError("signed-code executable binding mismatch")
    if (
        not isinstance(executable["id"], str)
        or IDENTIFIER.fullmatch(executable["id"]) is None
        or executable["role"] not in {"macApp", "agent", "cli", "iosApp", "other"}
        or executable["platform"] not in {"macOS", "iOS"}
        or not isinstance(executable["bundleIdentifier"], str)
        or BUNDLE_IDENTIFIER.fullmatch(executable["bundleIdentifier"]) is None
        or not isinstance(executable["artifactID"], str)
        or IDENTIFIER.fullmatch(executable["artifactID"]) is None
    ):
        raise SignedCodeVerificationError("invalid verified executable")
    try:
        member_path = safe_relative_path(member["path"], "verified member path")
    except ArtifactSBOMError as error:
        raise SignedCodeVerificationError(str(error)) from error
    expected_member = {
        "path": artifact_member.get("path"),
        "type": artifact_member.get("type"),
        "mode": artifact_member.get("mode"),
        "bytes": artifact_member.get("bytes"),
        "sha1": artifact_member.get("sha1"),
        "sha256": artifact_member.get("sha256"),
        "symlinkTarget": artifact_member.get("symlinkTarget"),
    }
    if member != expected_member or member_path != executable["relativePath"]:
        raise SignedCodeVerificationError("signed-code artifact-member binding mismatch")
    if (
        member["type"] != "regularFile"
        or not isinstance(member["mode"], str)
        or MODE.fullmatch(member["mode"]) is None
        or int(member["mode"], 8) & 0o111 == 0
        or not isinstance(member["bytes"], int)
        or isinstance(member["bytes"], bool)
        or member["bytes"] <= 0
        or not isinstance(member["sha1"], str)
        or SHA1.fullmatch(member["sha1"]) is None
        or not isinstance(member["sha256"], str)
        or SHA256.fullmatch(member["sha256"]) is None
        or member["symlinkTarget"] is not None
    ):
        raise SignedCodeVerificationError("invalid verified artifact member")
    if (
        identity["signingIdentifier"] != executable["bundleIdentifier"]
        or not isinstance(identity["teamIdentifier"], str)
        or TEAM_IDENTIFIER.fullmatch(identity["teamIdentifier"]) is None
        or not isinstance(identity["cdhash"], str)
        or CDHASH.fullmatch(identity["cdhash"]) is None
        or not isinstance(identity["certificateSHA256"], str)
        or SHA256.fullmatch(identity["certificateSHA256"]) is None
    ):
        raise SignedCodeVerificationError("invalid verified code identity")
    if executable["role"] == "macApp":
        expected_assessment = "gatekeeperAccepted"
    elif executable["platform"] == "macOS":
        expected_assessment = "embeddedNotApplicable"
    else:
        expected_assessment = "iosProvisioningReported"
    if checks != {"codesignVerify": True, "platformAssessment": expected_assessment}:
        raise SignedCodeVerificationError("signed-code checks did not pass exactly")
    references = [_reference(evidence[key], f"{key} evidence") for key in sorted(EVIDENCE_KEYS)]
    if len({reference["path"] for reference in references}) != len(references):
        raise SignedCodeVerificationError("signed-code raw evidence paths must be distinct")
    for reference in references:
        _verify_reference(evidence_root, reference)
