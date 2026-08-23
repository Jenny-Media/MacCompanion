#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import re
from pathlib import Path
from typing import Any


MAX_POLICY_BYTES = 16 * 1024
SCHEMA = "maccompanion.update-policy.v0.2"
SPARKLE_REPOSITORY = "https://github.com/sparkle-project/Sparkle"
SPARKLE_VERSION = "2.9.6"
SPARKLE_REVISION = "ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a"
SPARKLE_ARCHIVE_SHA256 = "8d5fb41d960b43f4a68aa14126bf62b098544ec8d191cdcc73eb14e63a8e7606"
SPARKLE_MANIFEST_SHA256 = "076e7810d9a463f3d7f034f9429bd5dcb3ed72203d06e1636f221668ec327962"
SPARKLE_LICENSE_SHA256 = "389a4e4e9a32f059775b13a06e25a591445ba229d2838d26dd3e7c0c45127cfe"
SPARKLE_RUNTIME_EXECUTABLES = [
    "Sparkle.framework/Versions/B/Autoupdate",
    "Sparkle.framework/Versions/B/Sparkle",
    "Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater",
]
SPARKLE_EXCLUDED_XPC_SERVICES = ["Downloader.xpc", "Installer.xpc"]
FEED_REF = re.compile(r"^[a-z][a-z0-9-]{0,62}$")


class UpdatePolicyError(ValueError):
    pass


class DuplicateKeyError(UpdatePolicyError):
    pass


def _closed_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, child in pairs:
        if key in value:
            raise DuplicateKeyError("duplicateKey")
        value[key] = child
    return value


def canonical_bytes(value: Any) -> bytes:
    return (
        json.dumps(
            value,
            ensure_ascii=False,
            allow_nan=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
        + b"\n"
    )


def _require_exact_object(
    value: Any,
    expected: set[str],
    error: str,
) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != expected:
        raise UpdatePolicyError(error)
    return value


def _require_true(value: Any, error: str) -> None:
    if value is not True:
        raise UpdatePolicyError(error)


def _require_false(value: Any, error: str) -> None:
    if value is not False:
        raise UpdatePolicyError(error)


def validate_policy(value: Any) -> None:
    root = _require_exact_object(
        value,
        {
            "channels",
            "dependency",
            "privacy",
            "product",
            "rotation",
            "runtime",
            "schemaVersion",
            "security",
            "topology",
        },
        "invalidRoot",
    )
    if root["schemaVersion"] != SCHEMA or root["product"] != "Mac Companion":
        raise UpdatePolicyError("invalidIdentity")

    dependency = _require_exact_object(
        root["dependency"],
        {
            "archiveSHA256",
            "binaryTarget",
            "licenseSHA256",
            "manifestSHA256",
            "packageRequirement",
            "repository",
            "revision",
            "version",
        },
        "invalidDependency",
    )
    if dependency != {
        "archiveSHA256": SPARKLE_ARCHIVE_SHA256,
        "binaryTarget": "Sparkle",
        "licenseSHA256": SPARKLE_LICENSE_SHA256,
        "manifestSHA256": SPARKLE_MANIFEST_SHA256,
        "packageRequirement": "exactVersion",
        "repository": SPARKLE_REPOSITORY,
        "revision": SPARKLE_REVISION,
        "version": SPARKLE_VERSION,
    }:
        raise UpdatePolicyError("invalidDependency")

    channels = root["channels"]
    if not isinstance(channels, list) or len(channels) != 2:
        raise UpdatePolicyError("invalidChannels")
    names: list[str] = []
    references: set[str] = set()
    for channel in channels:
        item = _require_exact_object(
            channel,
            {
                "automaticChecks",
                "automaticDownloads",
                "automaticInstalls",
                "feedAuthorityRef",
                "name",
            },
            "invalidChannel",
        )
        name = item["name"]
        if name not in {"beta", "stable"}:
            raise UpdatePolicyError("invalidChannel")
        reference = item["feedAuthorityRef"]
        if not isinstance(reference, str) or not FEED_REF.fullmatch(reference):
            raise UpdatePolicyError("invalidFeedAuthority")
        if reference in references:
            raise UpdatePolicyError("sharedFeedAuthority")
        _require_true(item["automaticChecks"], "automaticChecksRequired")
        _require_false(item["automaticDownloads"], "automaticDownloadDenied")
        _require_false(item["automaticInstalls"], "automaticInstallDenied")
        names.append(name)
        references.add(reference)
    if names != ["beta", "stable"]:
        raise UpdatePolicyError("invalidChannelOrder")

    privacy = _require_exact_object(
        root["privacy"],
        {
            "customFeedParameters",
            "sendsSystemProfile",
            "systemProfilingInfoPlist",
            "upstreamPrivacyManifestPresent",
        },
        "invalidPrivacy",
    )
    for key in privacy:
        _require_false(privacy[key], f"{key}Denied")

    topology = _require_exact_object(
        root["topology"],
        {
            "applicationSandboxed",
            "embeddedRuntimeExecutables",
            "excludedXPCServices",
            "releaseToolsEmbedded",
            "resignNestedCodeDuringArchiveExport",
        },
        "invalidTopology",
    )
    _require_false(topology["applicationSandboxed"], "sandboxedTopologyDenied")
    _require_false(topology["releaseToolsEmbedded"], "releaseToolsDenied")
    _require_true(
        topology["resignNestedCodeDuringArchiveExport"],
        "nestedCodeResigningRequired",
    )
    if topology["embeddedRuntimeExecutables"] != SPARKLE_RUNTIME_EXECUTABLES:
        raise UpdatePolicyError("invalidRuntimeTopology")
    if topology["excludedXPCServices"] != SPARKLE_EXCLUDED_XPC_SERVICES:
        raise UpdatePolicyError("invalidXPCExclusions")

    security = _require_exact_object(
        root["security"],
        {
            "archiveSignature",
            "deltaUpdates",
            "developerIDValidation",
            "httpsOnly",
            "installerPackages",
            "notarizedReplacement",
            "signedFeed",
            "verifyBeforeExtraction",
            "wholeBundleReplacement",
        },
        "invalidSecurity",
    )
    if security["archiveSignature"] != "ed25519":
        raise UpdatePolicyError("invalidArchiveSignature")
    for key in (
        "developerIDValidation",
        "httpsOnly",
        "notarizedReplacement",
        "signedFeed",
        "verifyBeforeExtraction",
        "wholeBundleReplacement",
    ):
        _require_true(security[key], f"{key}Required")
    _require_false(security["deltaUpdates"], "deltaUpdatesDenied")
    _require_false(security["installerPackages"], "installerPackagesDenied")

    runtime = _require_exact_object(
        root["runtime"],
        {
            "cancelOnForegroundLoss",
            "closeNetworkAdmissionBeforeInstall",
            "confirmationLifetimeMilliseconds",
            "drainBoundedWorkBeforeInstall",
            "exactAgentVersionMatch",
            "refuseUnlessControlInactive",
            "requireForegroundConfirmation",
            "stopAgentBeforeInstall",
        },
        "invalidRuntime",
    )
    if runtime["confirmationLifetimeMilliseconds"] != 300_000:
        raise UpdatePolicyError("invalidConfirmationLifetime")
    for key in runtime:
        if key != "confirmationLifetimeMilliseconds":
            _require_true(runtime[key], f"{key}Required")

    rotation = _require_exact_object(
        root["rotation"],
        {
            "allowDeveloperIDAndEd25519Together",
            "externalKeyCustody",
            "feedFallback",
            "updaterDowngrade",
        },
        "invalidRotation",
    )
    _require_false(
        rotation["allowDeveloperIDAndEd25519Together"],
        "simultaneousRotationDenied",
    )
    _require_true(rotation["externalKeyCustody"], "externalKeyCustodyRequired")
    _require_false(rotation["feedFallback"], "feedFallbackDenied")
    _require_false(rotation["updaterDowngrade"], "updaterDowngradeDenied")

    _scan_secret_material(root)


def _scan_secret_material(value: Any) -> None:
    forbidden_keys = {
        "apikey",
        "credential",
        "credentials",
        "password",
        "privatekey",
        "publickey",
        "secret",
        "url",
    }
    if isinstance(value, dict):
        for key, child in value.items():
            normalized = re.sub(r"[^a-z]", "", key.lower())
            if normalized in forbidden_keys:
                raise UpdatePolicyError("forbiddenReleaseAuthority")
            _scan_secret_material(child)
    elif isinstance(value, list):
        for child in value:
            _scan_secret_material(child)
    elif isinstance(value, str):
        lowered = value.lower()
        if "-----begin" in lowered or lowered.endswith((".p8", ".p12")):
            raise UpdatePolicyError("forbiddenReleaseAuthority")


def load_policy(path: Path) -> dict[str, Any]:
    try:
        info = path.lstat()
    except OSError as error:
        raise UpdatePolicyError("unreadablePolicy") from error
    if not path.is_file() or path.is_symlink() or info.st_nlink != 1:
        raise UpdatePolicyError("unsafePolicyFile")
    if info.st_size <= 0 or info.st_size > MAX_POLICY_BYTES:
        raise UpdatePolicyError("invalidPolicySize")
    try:
        raw = path.read_bytes()
        value = json.loads(raw, object_pairs_hook=_closed_pairs)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, DuplicateKeyError) as error:
        raise UpdatePolicyError("invalidPolicyJSON") from error
    if raw != canonical_bytes(value):
        raise UpdatePolicyError("noncanonicalPolicy")
    validate_policy(value)
    return value


def write_new_policy(path: Path, value: dict[str, Any]) -> None:
    validate_policy(value)
    data = canonical_bytes(value)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    descriptor = os.open(path, flags, 0o600)
    complete = False
    try:
        remaining = memoryview(data)
        while remaining:
            written = os.write(descriptor, remaining)
            if written <= 0:
                raise OSError("short update-policy write")
            remaining = remaining[written:]
        os.fsync(descriptor)
        complete = True
    finally:
        os.close(descriptor)
        if not complete:
            try:
                path.unlink()
            except FileNotFoundError:
                pass
    directory = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)
