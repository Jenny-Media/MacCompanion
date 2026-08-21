#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import os
import re
import stat
import unicodedata
from pathlib import Path
from typing import Any

from artifact_sbom import ArtifactSBOMError, exact_keys, parse_canonical_json, safe_relative_path


SCHEMA = "maccompanion.signing-policy.v0.1"
PRODUCT = "Mac Companion"
MAX_POLICY_BYTES = 4 * 1024 * 1024
MAX_ARTIFACTS = 2
MAX_OBJECTS = 1024
MAX_ARCHITECTURES = 2048
MAX_ENTITLEMENT_TOP_LEVEL_KEYS = 128
MAX_ENTITLEMENT_KEYS = 4096
MAX_ENTITLEMENT_NODES = 8192
MAX_ENTITLEMENT_DEPTH = 4
MAX_ENTITLEMENT_CHILDREN = 64
MAX_ENTITLEMENT_KEY_BYTES = 128
MAX_ENTITLEMENT_STRING_BYTES = 1024
MAX_ENTITLEMENT_TOTAL_STRING_BYTES = 512 * 1024
SAFE_INTEGER = 9_007_199_254_740_991

IDENTIFIER = re.compile(r"^[a-z0-9](?:[a-z0-9.-]{0,126}[a-z0-9])?$")
BUNDLE_IDENTIFIER = re.compile(r"^[A-Za-z0-9-]{1,63}(?:\.[A-Za-z0-9-]{1,63})+$")
VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$")
BUILD = re.compile(r"^(?:0|[1-9][0-9]{0,17})$")
REVISION = re.compile(r"^[0-9a-f]{40}$")
TEAM_IDENTIFIER = re.compile(r"^[A-Z0-9]{10}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
SHA1 = re.compile(r"^[0-9a-f]{40}$")

ROOT_KEYS = {
    "schemaVersion", "policyID", "policyRevision", "product", "release", "source",
    "artifactSBOM", "signedCodeGraph", "officialSigners", "declaredExecutables", "artifacts",
}
RELEASE_KEYS = {"version", "buildNumber", "channel", "targets"}
SOURCE_KEYS = {"revision", "dirty"}
REFERENCE_KEYS = {"path", "sha256", "bytes"}
SIGNER_KEYS = {"platform", "trustProfile", "teamIdentifier", "leafCertificateSHA256"}
EXECUTABLE_KEYS = {"id", "role", "platform", "bundleIdentifier", "artifactID", "relativePath"}
ARTIFACT_POLICY_KEYS = {
    "artifact", "subjectRoot", "verificationProfile", "thirdPartyAllowlist", "objects",
}
ARTIFACT_KEYS = {"id", "kind", "platform", "path", "sha256", "bytes"}
THIRD_PARTY_KEYS = {"path", "memberSHA256"}
OBJECT_KEYS = {
    "path", "member", "ownerBundlePath", "bundleMainFor", "declaredExecutableIDs",
    "signerClass", "architectures",
}
MEMBER_KEYS = {"path", "type", "mode", "bytes", "sha1", "sha256", "symlinkTarget"}
ARCHITECTURE_KEYS = {"cpuType", "cpuSubtype", "sliceSHA256", "identity", "signature", "entitlements"}
IDENTITY_KEYS = {
    "signingIdentifier", "teamIdentifier", "codeDirectories", "leafCertificateSHA256",
    "designatedRequirementDataSHA256",
}
CODE_DIRECTORY_KEYS = {"hashType", "cdhash", "codeDirectorySHA256"}
SIGNATURE_KEYS = {"trustProfile", "requireHardenedRuntime", "requireSecureTimestamp"}
ENTITLEMENT_ABSENT_KEYS = {"mode"}
ENTITLEMENT_EXACT_KEYS = {"mode", "entries"}
ENTITLEMENT_ENTRY_KEYS = {"key", "value"}

VERIFICATION_PROFILES = {"macOSDeveloperID", "iosArchiveConstructionOnly"}
TRUST_PROFILES = {"developerIDApplication", "iosArchiveConstructionOnly"}
SIGNER_CLASSES = {"firstParty", "thirdParty"}


class SigningPolicyError(ValueError):
    pass


class SigningPolicyDigestMismatch(SigningPolicyError):
    pass


def _closed(value: Any, keys: set[str], label: str) -> dict[str, Any]:
    try:
        return exact_keys(value, keys, label)
    except ArtifactSBOMError as error:
        raise SigningPolicyError(str(error)) from error


def _bounded_nfc(value: Any, label: str, maximum: int, *, ascii_only: bool = False) -> str:
    if not isinstance(value, str) or not value:
        raise SigningPolicyError(f"{label} must be a bounded nonempty string")
    try:
        raw = value.encode("ascii" if ascii_only else "utf-8")
    except (UnicodeEncodeError, AttributeError) as error:
        raise SigningPolicyError(f"{label} uses an invalid encoding") from error
    if len(raw) > maximum or value != unicodedata.normalize("NFC", value):
        raise SigningPolicyError(f"{label} is not bounded NFC text")
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        raise SigningPolicyError(f"{label} contains control characters")
    return value


def _identifier(value: Any, label: str) -> str:
    if not isinstance(value, str) or IDENTIFIER.fullmatch(value) is None:
        raise SigningPolicyError(f"{label} is invalid")
    return value


def _bundle_identifier(value: Any, label: str) -> str:
    if (
        not isinstance(value, str)
        or len(value.encode("utf-8")) > 255
        or BUNDLE_IDENTIFIER.fullmatch(value) is None
    ):
        raise SigningPolicyError(f"{label} is invalid")
    return value


def _safe_path(value: Any, label: str) -> str:
    try:
        path = safe_relative_path(value, label)
    except ArtifactSBOMError as error:
        raise SigningPolicyError(str(error)) from error
    return path


def _reference(value: Any, label: str) -> dict[str, Any]:
    reference = _closed(value, REFERENCE_KEYS, label)
    _safe_path(reference["path"], f"{label} path")
    if not isinstance(reference["sha256"], str) or SHA256.fullmatch(reference["sha256"]) is None:
        raise SigningPolicyError(f"{label} digest is invalid")
    if not isinstance(reference["bytes"], int) or isinstance(reference["bytes"], bool) or reference["bytes"] <= 0:
        raise SigningPolicyError(f"{label} byte count is invalid")
    return reference


def _artifact(value: Any) -> dict[str, Any]:
    artifact = _closed(value, ARTIFACT_KEYS, "signing-policy artifact")
    _identifier(artifact["id"], "signing-policy artifact ID")
    if artifact["kind"] not in {"macApplication", "iosArchive"}:
        raise SigningPolicyError("signing-policy artifact kind is invalid")
    expected_platform = "macOS" if artifact["kind"] == "macApplication" else "iOS"
    if artifact["platform"] != expected_platform:
        raise SigningPolicyError("signing-policy artifact platform is invalid")
    _safe_path(artifact["path"], "signing-policy artifact path")
    if not isinstance(artifact["sha256"], str) or SHA256.fullmatch(artifact["sha256"]) is None:
        raise SigningPolicyError("signing-policy artifact digest is invalid")
    if not isinstance(artifact["bytes"], int) or isinstance(artifact["bytes"], bool) or artifact["bytes"] <= 0:
        raise SigningPolicyError("signing-policy artifact byte count is invalid")
    return artifact


class _EntitlementBudget:
    def __init__(self) -> None:
        self.keys = 0
        self.nodes = 0
        self.string_bytes = 0

    def charge_key(self, key: Any) -> str:
        value = _bounded_nfc(key, "entitlement key", MAX_ENTITLEMENT_KEY_BYTES, ascii_only=True)
        self.keys += 1
        if self.keys > MAX_ENTITLEMENT_KEYS:
            raise SigningPolicyError("entitlement key count exceeds the policy bound")
        return value

    def charge_node(self) -> None:
        self.nodes += 1
        if self.nodes > MAX_ENTITLEMENT_NODES:
            raise SigningPolicyError("entitlement node count exceeds the policy bound")

    def charge_string(self, value: Any) -> str:
        text = _bounded_nfc(value, "entitlement string", MAX_ENTITLEMENT_STRING_BYTES)
        self.string_bytes += len(text.encode("utf-8"))
        if self.string_bytes > MAX_ENTITLEMENT_TOTAL_STRING_BYTES:
            raise SigningPolicyError("entitlement string bytes exceed the policy bound")
        return text


def _entitlement_node(value: Any, budget: _EntitlementBudget, depth: int) -> None:
    if depth > MAX_ENTITLEMENT_DEPTH:
        raise SigningPolicyError("entitlement node exceeds the depth bound")
    if not isinstance(value, dict) or "type" not in value:
        raise SigningPolicyError("entitlement value must be a tagged node")
    budget.charge_node()
    kind = value["type"]
    if kind == "boolean":
        node = _closed(value, {"type", "value"}, "Boolean entitlement node")
        if not isinstance(node["value"], bool):
            raise SigningPolicyError("Boolean entitlement node is invalid")
    elif kind == "integer":
        node = _closed(value, {"type", "value"}, "integer entitlement node")
        integer = node["value"]
        if not isinstance(integer, int) or isinstance(integer, bool) or not -SAFE_INTEGER <= integer <= SAFE_INTEGER:
            raise SigningPolicyError("integer entitlement node is invalid")
    elif kind == "string":
        node = _closed(value, {"type", "value"}, "string entitlement node")
        budget.charge_string(node["value"])
    elif kind == "array":
        node = _closed(value, {"type", "values"}, "array entitlement node")
        children = node["values"]
        if not isinstance(children, list) or len(children) > MAX_ENTITLEMENT_CHILDREN:
            raise SigningPolicyError("array entitlement node exceeds the child bound")
        for child in children:
            _entitlement_node(child, budget, depth + 1)
    elif kind == "dictionary":
        node = _closed(value, {"type", "entries"}, "dictionary entitlement node")
        _entitlement_entries(node["entries"], budget, depth + 1, top_level=False)
    else:
        raise SigningPolicyError("entitlement node type is invalid")


def _entitlement_entries(value: Any, budget: _EntitlementBudget, depth: int, *, top_level: bool) -> None:
    maximum = MAX_ENTITLEMENT_TOP_LEVEL_KEYS if top_level else MAX_ENTITLEMENT_CHILDREN
    if not isinstance(value, list) or len(value) > maximum:
        raise SigningPolicyError("entitlement entries exceed the collection bound")
    keys: list[str] = []
    for item in value:
        entry = _closed(item, ENTITLEMENT_ENTRY_KEYS, "entitlement entry")
        keys.append(budget.charge_key(entry["key"]))
        _entitlement_node(entry["value"], budget, depth)
    if keys != sorted(keys) or len(set(keys)) != len(keys):
        raise SigningPolicyError("entitlement entries are not uniquely sorted")


def _entitlements(value: Any, budget: _EntitlementBudget) -> None:
    if not isinstance(value, dict) or value.get("mode") not in {"absent", "exact"}:
        raise SigningPolicyError("entitlement policy mode is invalid")
    if value["mode"] == "absent":
        _closed(value, ENTITLEMENT_ABSENT_KEYS, "absent entitlement policy")
    else:
        exact = _closed(value, ENTITLEMENT_EXACT_KEYS, "exact entitlement policy")
        _entitlement_entries(exact["entries"], budget, 1, top_level=True)


def validate_policy(value: Any) -> dict[str, Any]:
    root = _closed(value, ROOT_KEYS, "signing policy")
    if root["schemaVersion"] != SCHEMA or root["product"] != PRODUCT:
        raise SigningPolicyError("invalid signing-policy identity")
    _identifier(root["policyID"], "signing-policy ID")
    revision = root["policyRevision"]
    if not isinstance(revision, int) or isinstance(revision, bool) or not 1 <= revision <= SAFE_INTEGER:
        raise SigningPolicyError("signing-policy revision is invalid")

    release = _closed(root["release"], RELEASE_KEYS, "signing-policy release")
    if not isinstance(release["version"], str) or VERSION.fullmatch(release["version"]) is None:
        raise SigningPolicyError("signing-policy release version is invalid")
    if not isinstance(release["buildNumber"], str) or BUILD.fullmatch(release["buildNumber"]) is None:
        raise SigningPolicyError("signing-policy build number is invalid")
    if release["channel"] not in {"development", "internal", "beta", "stable"}:
        raise SigningPolicyError("signing-policy release channel is invalid")
    targets = release["targets"]
    if not isinstance(targets, list) or not targets or targets != sorted(targets) or len(set(targets)) != len(targets) or any(item not in {"iOS", "macOS"} for item in targets):
        raise SigningPolicyError("signing-policy release targets are invalid")

    source = _closed(root["source"], SOURCE_KEYS, "signing-policy source")
    if not isinstance(source["revision"], str) or REVISION.fullmatch(source["revision"]) is None or source["dirty"] is not False:
        raise SigningPolicyError("signing-policy source must be one clean revision")
    _reference(root["artifactSBOM"], "signing-policy artifact-SBOM reference")
    _reference(root["signedCodeGraph"], "signing-policy graph reference")

    signers = root["officialSigners"]
    if not isinstance(signers, list) or not signers or len(signers) > 2:
        raise SigningPolicyError("signing-policy official signer set is invalid")
    validated_signers: list[dict[str, Any]] = []
    for value in signers:
        signer = _closed(value, SIGNER_KEYS, "signing-policy official signer")
        expected_trust = (
            "developerIDApplication" if signer["platform"] == "macOS"
            else "iosArchiveConstructionOnly" if signer["platform"] == "iOS"
            else None
        )
        if signer["platform"] not in targets or signer["trustProfile"] != expected_trust:
            raise SigningPolicyError("signing-policy official signer profile is invalid")
        if not isinstance(signer["teamIdentifier"], str) or TEAM_IDENTIFIER.fullmatch(signer["teamIdentifier"]) is None:
            raise SigningPolicyError("signing-policy official Team ID is invalid")
        if not isinstance(signer["leafCertificateSHA256"], str) or SHA256.fullmatch(signer["leafCertificateSHA256"]) is None:
            raise SigningPolicyError("signing-policy official certificate digest is invalid")
        validated_signers.append(signer)
    if (
        validated_signers != sorted(validated_signers, key=lambda item: (item["platform"], item["trustProfile"]))
        or len({item["platform"] for item in validated_signers}) != len(validated_signers)
        or len({item["leafCertificateSHA256"] for item in validated_signers}) != len(validated_signers)
        or {item["platform"] for item in validated_signers} != set(targets)
    ):
        raise SigningPolicyError("signing-policy official signers do not exactly cover release targets")
    signers_by_platform = {item["platform"]: item for item in validated_signers}

    executables = root["declaredExecutables"]
    if not isinstance(executables, list) or len(executables) > 32:
        raise SigningPolicyError("signing-policy declared executables are invalid")
    executable_ids: list[str] = []
    for value in executables:
        executable = _closed(value, EXECUTABLE_KEYS, "signing-policy declared executable")
        executable_ids.append(_identifier(executable["id"], "signing-policy executable ID"))
        role = executable["role"]
        platform = executable["platform"]
        if role not in {"macApp", "agent", "cli", "iosApp", "other"} or platform not in targets:
            raise SigningPolicyError("signing-policy executable role or platform is invalid")
        if role in {"macApp", "agent", "cli"} and platform != "macOS":
            raise SigningPolicyError("signing-policy executable role/platform combination is invalid")
        if role == "iosApp" and platform != "iOS":
            raise SigningPolicyError("signing-policy executable role/platform combination is invalid")
        _bundle_identifier(executable["bundleIdentifier"], "signing-policy executable bundle identifier")
        _identifier(executable["artifactID"], "signing-policy executable artifact ID")
        _safe_path(executable["relativePath"], "signing-policy executable path")
    if executables != sorted(executables, key=lambda item: item["id"]) or len(set(executable_ids)) != len(executable_ids):
        raise SigningPolicyError("signing-policy declared executables are not uniquely sorted")

    artifacts = root["artifacts"]
    if not isinstance(artifacts, list) or not artifacts or len(artifacts) > MAX_ARTIFACTS:
        raise SigningPolicyError("signing-policy artifacts are invalid")
    artifact_ids: list[str] = []
    total_objects = 0
    total_architectures = 0
    entitlement_budget = _EntitlementBudget()
    for value in artifacts:
        artifact_policy = _closed(value, ARTIFACT_POLICY_KEYS, "signing-policy artifact policy")
        artifact = _artifact(artifact_policy["artifact"])
        artifact_ids.append(artifact["id"])
        subject_root = _safe_path(artifact_policy["subjectRoot"], "signing-policy subject root")
        profile = artifact_policy["verificationProfile"]
        expected_profile = "macOSDeveloperID" if artifact["kind"] == "macApplication" else "iosArchiveConstructionOnly"
        if profile != expected_profile:
            raise SigningPolicyError("signing-policy verification profile is invalid")
        if artifact["platform"] not in targets:
            raise SigningPolicyError("signing-policy artifact platform is outside the release")
        if artifact["kind"] == "iosArchive" and not subject_root.startswith("Products/Applications/"):
            raise SigningPolicyError("iOS construction policy must identify the xcarchive product")

        allowlist = artifact_policy["thirdPartyAllowlist"]
        if not isinstance(allowlist, list) or len(allowlist) > MAX_OBJECTS:
            raise SigningPolicyError("third-party allowlist is invalid")
        allowlist_keys: list[tuple[str, str]] = []
        for item in allowlist:
            entry = _closed(item, THIRD_PARTY_KEYS, "third-party allowlist entry")
            path = _safe_path(entry["path"], "third-party object path")
            digest = entry["memberSHA256"]
            if not isinstance(digest, str) or SHA256.fullmatch(digest) is None:
                raise SigningPolicyError("third-party member digest is invalid")
            allowlist_keys.append((path, digest))
        if allowlist_keys != sorted(allowlist_keys) or len(set(allowlist_keys)) != len(allowlist_keys):
            raise SigningPolicyError("third-party allowlist is not uniquely sorted")

        objects = artifact_policy["objects"]
        if not isinstance(objects, list) or not objects:
            raise SigningPolicyError("signing-policy object set is empty")
        total_objects += len(objects)
        if total_objects > MAX_OBJECTS:
            raise SigningPolicyError("signing-policy object count exceeds the policy bound")
        object_paths: list[str] = []
        third_party_objects: list[tuple[str, str]] = []
        for item in objects:
            object_value = _closed(item, OBJECT_KEYS, "signing-policy object")
            path = _safe_path(object_value["path"], "signing-policy object path")
            object_paths.append(path)
            member = _closed(object_value["member"], MEMBER_KEYS, "signing-policy member")
            if member["path"] != path or member["type"] != "regularFile" or member["symlinkTarget"] is not None:
                raise SigningPolicyError("signing-policy member identity is invalid")
            if not isinstance(member["mode"], str) or re.fullmatch(r"[0-7]{4}", member["mode"]) is None:
                raise SigningPolicyError("signing-policy member mode is invalid")
            if not isinstance(member["bytes"], int) or isinstance(member["bytes"], bool) or member["bytes"] <= 0:
                raise SigningPolicyError("signing-policy member byte count is invalid")
            if not isinstance(member["sha1"], str) or SHA1.fullmatch(member["sha1"]) is None or not isinstance(member["sha256"], str) or SHA256.fullmatch(member["sha256"]) is None:
                raise SigningPolicyError("signing-policy member digest is invalid")
            for nullable_path in ("ownerBundlePath", "bundleMainFor"):
                if object_value[nullable_path] is not None:
                    _safe_path(object_value[nullable_path], f"signing-policy {nullable_path}")
            declared_ids = object_value["declaredExecutableIDs"]
            if not isinstance(declared_ids, list) or declared_ids != sorted(declared_ids) or len(set(declared_ids)) != len(declared_ids) or any(item not in executable_ids for item in declared_ids):
                raise SigningPolicyError("signing-policy declared executable mapping is invalid")
            if object_value["signerClass"] not in SIGNER_CLASSES:
                raise SigningPolicyError("signing-policy signer class is invalid")
            if object_value["signerClass"] == "thirdParty":
                third_party_objects.append((path, member["sha256"]))

            architectures = object_value["architectures"]
            if not isinstance(architectures, list) or not architectures:
                raise SigningPolicyError("signing-policy architecture set is empty")
            total_architectures += len(architectures)
            if total_architectures > MAX_ARCHITECTURES:
                raise SigningPolicyError("signing-policy architecture count exceeds the policy bound")
            architecture_keys: list[tuple[int, int]] = []
            for architecture_value in architectures:
                architecture = _closed(architecture_value, ARCHITECTURE_KEYS, "signing-policy architecture")
                cpu_type = architecture["cpuType"]
                cpu_subtype = architecture["cpuSubtype"]
                if not isinstance(cpu_type, int) or isinstance(cpu_type, bool) or not isinstance(cpu_subtype, int) or isinstance(cpu_subtype, bool):
                    raise SigningPolicyError("signing-policy CPU tuple is invalid")
                architecture_keys.append((cpu_type, cpu_subtype))
                if not isinstance(architecture["sliceSHA256"], str) or SHA256.fullmatch(architecture["sliceSHA256"]) is None:
                    raise SigningPolicyError("signing-policy slice digest is invalid")
                identity = _closed(architecture["identity"], IDENTITY_KEYS, "signing-policy architecture identity")
                _bundle_identifier(identity["signingIdentifier"], "signing-policy signing identifier")
                if not isinstance(identity["teamIdentifier"], str) or TEAM_IDENTIFIER.fullmatch(identity["teamIdentifier"]) is None:
                    raise SigningPolicyError("signing-policy architecture Team ID is invalid")
                code_directories = identity["codeDirectories"]
                if not isinstance(code_directories, list) or len(code_directories) != 1:
                    raise SigningPolicyError("signing-policy CodeDirectory set is invalid")
                code_directory = _closed(code_directories[0], CODE_DIRECTORY_KEYS, "signing-policy CodeDirectory")
                if (
                    code_directory["hashType"] != "sha256"
                    or not isinstance(code_directory["cdhash"], str)
                    or SHA1.fullmatch(code_directory["cdhash"]) is None
                    or not isinstance(code_directory["codeDirectorySHA256"], str)
                    or SHA256.fullmatch(code_directory["codeDirectorySHA256"]) is None
                    or code_directory["cdhash"] != code_directory["codeDirectorySHA256"][:40]
                ):
                    raise SigningPolicyError("signing-policy CodeDirectory identity is invalid")
                for digest_key in ("leafCertificateSHA256", "designatedRequirementDataSHA256"):
                    if not isinstance(identity[digest_key], str) or SHA256.fullmatch(identity[digest_key]) is None:
                        raise SigningPolicyError(f"signing-policy {digest_key} is invalid")
                target_signer = signers_by_platform[artifact["platform"]]
                if object_value["signerClass"] == "firstParty" and (
                    identity["teamIdentifier"] != target_signer["teamIdentifier"]
                    or identity["leafCertificateSHA256"] != target_signer["leafCertificateSHA256"]
                ):
                    raise SigningPolicyError("first-party signing identity disagrees with official signer")
                signature = _closed(architecture["signature"], SIGNATURE_KEYS, "signing-policy signature rule")
                if signature["trustProfile"] not in TRUST_PROFILES:
                    raise SigningPolicyError("signing-policy trust profile is invalid")
                expected_trust = "developerIDApplication" if profile == "macOSDeveloperID" else "iosArchiveConstructionOnly"
                if signature != {
                    "trustProfile": expected_trust,
                    "requireHardenedRuntime": profile == "macOSDeveloperID",
                    "requireSecureTimestamp": profile == "macOSDeveloperID",
                }:
                    raise SigningPolicyError("signing-policy signature requirements are invalid")
                _entitlements(architecture["entitlements"], entitlement_budget)
            if architecture_keys != sorted(architecture_keys) or len(set(architecture_keys)) != len(architecture_keys):
                raise SigningPolicyError("signing-policy architectures are not uniquely sorted")
        if object_paths != sorted(object_paths) or len(set(object_paths)) != len(object_paths):
            raise SigningPolicyError("signing-policy objects are not uniquely sorted")
        if third_party_objects != allowlist_keys:
            raise SigningPolicyError("third-party allowlist does not exactly match third-party objects")

    if artifact_ids != sorted(artifact_ids) or len(set(artifact_ids)) != len(artifact_ids):
        raise SigningPolicyError("signing-policy artifacts are not uniquely sorted")
    return root


def load_pinned_policy(path: Path, expected_sha256: str) -> tuple[dict[str, Any], bytes]:
    if (
        not isinstance(expected_sha256, str)
        or SHA256.fullmatch(expected_sha256) is None
        or len(set(expected_sha256)) == 1
    ):
        raise SigningPolicyError("independent signing-policy SHA-256 pin is invalid")
    if not hasattr(os, "O_NOFOLLOW"):
        raise SigningPolicyError("platform cannot provide no-follow signing-policy reads")
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise SigningPolicyError("signing policy is unavailable or follows a symlink") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_size <= 0 or before.st_size > MAX_POLICY_BYTES:
            raise SigningPolicyError("signing policy is not a bounded single-link regular file")
        raw = bytearray()
        while len(raw) < before.st_size:
            chunk = os.read(descriptor, min(64 * 1024, before.st_size - len(raw)))
            if not chunk:
                break
            raw.extend(chunk)
        after = os.fstat(descriptor)
        before_facts = (before.st_dev, before.st_ino, before.st_mode, before.st_nlink, before.st_size, before.st_mtime_ns, before.st_ctime_ns)
        after_facts = (after.st_dev, after.st_ino, after.st_mode, after.st_nlink, after.st_size, after.st_mtime_ns, after.st_ctime_ns)
        if len(raw) != before.st_size or before_facts != after_facts:
            raise SigningPolicyError("signing policy changed during read")
    finally:
        os.close(descriptor)
    exact = bytes(raw)
    if hashlib.sha256(exact).hexdigest() != expected_sha256:
        raise SigningPolicyDigestMismatch("signing policy does not match the independent SHA-256 pin")
    try:
        value = parse_canonical_json(exact)
    except (ArtifactSBOMError, UnicodeError, RecursionError, ValueError) as error:
        raise SigningPolicyError("signing policy is not canonical JSON") from error
    return validate_policy(value), exact
