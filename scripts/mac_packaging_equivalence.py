#!/usr/bin/env python3

from __future__ import annotations

import copy
import ctypes
import hashlib
import os
import plistlib
import re
import stat
import subprocess
import tempfile
import unicodedata
from pathlib import Path
from typing import Any

from artifact_sbom import (
    ArtifactSBOMError,
    _validate_symlink_graph,
    canonical_bytes,
    exact_keys,
    parse_canonical_json,
    parse_timestamp,
    safe_relative_path,
    validate_release_binding,
)


SCHEMA = "maccompanion.mac-packaging-equivalence.v0.1"
PRODUCT = "Mac Companion"
APP_NAME = "Mac Companion.app"
SHA256 = re.compile(r"^[0-9a-f]{64}$")
REVISION = re.compile(r"^[0-9a-f]{40}$")
IDENTIFIER = re.compile(r"^[a-z0-9](?:[a-z0-9.-]{0,62}[a-z0-9])?$")
VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$")
BUILD = re.compile(r"^(?:0|[1-9][0-9]{0,17})$")
MODE = re.compile(r"^[0-7]{4}$")
SHA1 = re.compile(r"^[0-9a-f]{40}$")
DEVICE = re.compile(r"^/dev/disk[0-9]+$")
ANY_DEVICE = re.compile(r"^/dev/disk[0-9]+(?:s[0-9]+)?$")
ROOT_KEYS = {"schemaVersion", "product", "release", "source", "created", "artifactSBOM", "canonicalApp", "containers", "dmgLayout"}
RELEASE_KEYS = {"version", "buildNumber", "targets"}
SOURCE_KEYS = {"revision", "dirty"}
REFERENCE_KEYS = {"path", "sha256", "bytes"}
SUMMARY_KEYS = {"name", "treeSHA256", "entryCount", "expandedBytes"}
CONTAINER_KEYS = {"artifactID", "kind", "path", "sha256", "bytes", "appPath", "treeSHA256", "entryCount", "expandedBytes"}
LAYOUT_KEYS = {"filesystem", "readOnly", "applicationPath", "applicationsLinkPath", "applicationsLinkTarget", "rootEntryCount"}
KIND_ORDER = ["macApplication", "sparkleArchive", "macDiskImage"]
EXPECTED_LAYOUT = {
    "filesystem": "APFS", "readOnly": True,
    "applicationPath": APP_NAME, "applicationsLinkPath": "Applications",
    "applicationsLinkTarget": "/Applications", "rootEntryCount": 2,
}
MAX_ENTRIES = 20_000
MAX_EXPANDED_BYTES = 4 * 1024 * 1024 * 1024
MAX_MEMBER_BYTES = 2 * 1024 * 1024 * 1024
MAX_RECEIPT_BYTES = 1024 * 1024
MAX_RECOVERY_BYTES = 16 * 1024
PROVENANCE_XATTR = "com.apple.provenance"


class MacPackagingEquivalenceError(ValueError):
    pass


def _read_bounded_file(path: Path, *, maximum_bytes: int, label: str) -> bytes:
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError as error:
        raise MacPackagingEquivalenceError(f"{label} must be a bounded non-symlink file") from error
    try:
        before = os.fstat(descriptor)
        if (
            not stat.S_ISREG(before.st_mode)
            or before.st_size <= 0
            or before.st_size > maximum_bytes
        ):
            raise MacPackagingEquivalenceError(f"{label} must be a bounded non-symlink file")
        chunks: list[bytes] = []
        remaining = maximum_bytes + 1
        while remaining > 0:
            chunk = os.read(descriptor, min(64 * 1024, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        raw = b"".join(chunks)
        after = os.fstat(descriptor)
        if (
            len(raw) > maximum_bytes
            or len(raw) != after.st_size
            or _file_identity(before) != _file_identity(after)
        ):
            raise MacPackagingEquivalenceError(f"{label} changed during bounded read")
        return raw
    finally:
        os.close(descriptor)


def load_canonical_receipt_with_bytes(path: Path) -> tuple[dict[str, Any], bytes]:
    raw = _read_bounded_file(
        path,
        maximum_bytes=MAX_RECEIPT_BYTES,
        label="packaging receipt",
    )
    try:
        value = parse_canonical_json(raw)
    except (ArtifactSBOMError, UnicodeError) as error:
        raise MacPackagingEquivalenceError(str(error)) from error
    if not isinstance(value, dict):
        raise MacPackagingEquivalenceError("packaging receipt must be an object")
    return value, raw


def load_canonical_receipt(path: Path) -> dict[str, Any]:
    return load_canonical_receipt_with_bytes(path)[0]


def _app_entries(entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if not isinstance(entries, list) or not entries:
        raise MacPackagingEquivalenceError("application composition is empty")
    top_levels = {entry.get("path", "").split("/", 1)[0] for entry in entries if isinstance(entry, dict)}
    if top_levels != {APP_NAME}:
        raise MacPackagingEquivalenceError("container must contain only the canonical application")
    root = next((entry for entry in entries if entry.get("path") == APP_NAME), None)
    if not isinstance(root, dict) or root.get("type") != "directory":
        raise MacPackagingEquivalenceError("canonical application root directory is missing")
    return entries


def _validate_reference(value: Any, label: str) -> dict[str, Any]:
    try:
        reference = exact_keys(value, REFERENCE_KEYS, label)
        path = safe_relative_path(reference["path"], f"{label} path")
    except ArtifactSBOMError as error:
        raise MacPackagingEquivalenceError(str(error)) from error
    if (
        path != reference["path"]
        or not isinstance(reference["sha256"], str)
        or SHA256.fullmatch(reference["sha256"]) is None
        or not isinstance(reference["bytes"], int)
        or isinstance(reference["bytes"], bool)
        or reference["bytes"] <= 0
    ):
        raise MacPackagingEquivalenceError(f"invalid {label}")
    return reference


def _validate_release(value: Any) -> dict[str, Any]:
    try:
        release = exact_keys(value, RELEASE_KEYS, "packaging release")
    except ArtifactSBOMError as error:
        raise MacPackagingEquivalenceError(str(error)) from error
    targets = release["targets"]
    if (
        not isinstance(release["version"], str)
        or VERSION.fullmatch(release["version"]) is None
        or not isinstance(release["buildNumber"], str)
        or BUILD.fullmatch(release["buildNumber"]) is None
        or not isinstance(targets, list)
        or targets != sorted(set(targets))
        or not 1 <= len(targets) <= 2
        or any(target not in {"macOS", "iOS"} for target in targets)
        or "macOS" not in targets
    ):
        raise MacPackagingEquivalenceError("invalid packaging release")
    return release


def _validate_source(value: Any) -> dict[str, Any]:
    try:
        source = exact_keys(value, SOURCE_KEYS, "packaging source")
    except ArtifactSBOMError as error:
        raise MacPackagingEquivalenceError(str(error)) from error
    if (
        not isinstance(source["revision"], str)
        or REVISION.fullmatch(source["revision"]) is None
        or len(set(source["revision"])) == 1
        or source["dirty"] is not False
    ):
        raise MacPackagingEquivalenceError("invalid packaging source")
    return source


def _validate_summary(value: Any, label: str) -> dict[str, Any]:
    try:
        summary = exact_keys(value, SUMMARY_KEYS, label)
    except ArtifactSBOMError as error:
        raise MacPackagingEquivalenceError(str(error)) from error
    if (
        summary["name"] != APP_NAME
        or not isinstance(summary["treeSHA256"], str)
        or SHA256.fullmatch(summary["treeSHA256"]) is None
        or not isinstance(summary["entryCount"], int)
        or isinstance(summary["entryCount"], bool)
        or not 1 <= summary["entryCount"] <= MAX_ENTRIES
        or not isinstance(summary["expandedBytes"], int)
        or isinstance(summary["expandedBytes"], bool)
        or not 0 <= summary["expandedBytes"] <= MAX_EXPANDED_BYTES
    ):
        raise MacPackagingEquivalenceError(f"invalid {label}")
    return summary


def _validate_container(value: Any) -> dict[str, Any]:
    try:
        container = exact_keys(value, CONTAINER_KEYS, "packaging container")
        safe_relative_path(container["path"], "packaging container path")
        safe_relative_path(container["appPath"], "packaging app path")
    except ArtifactSBOMError as error:
        raise MacPackagingEquivalenceError(str(error)) from error
    if (
        not isinstance(container["artifactID"], str)
        or IDENTIFIER.fullmatch(container["artifactID"]) is None
        or container["kind"] not in KIND_ORDER
        or not isinstance(container["sha256"], str)
        or SHA256.fullmatch(container["sha256"]) is None
        or not isinstance(container["bytes"], int)
        or isinstance(container["bytes"], bool)
        or container["bytes"] <= 0
        or container["appPath"] != APP_NAME
    ):
        raise MacPackagingEquivalenceError("invalid packaging container")
    _validate_summary(
        {
            "name": container["appPath"],
            "treeSHA256": container["treeSHA256"],
            "entryCount": container["entryCount"],
            "expandedBytes": container["expandedBytes"],
        },
        "packaging container summary",
    )
    return container


def _validate_layout(value: Any) -> dict[str, Any]:
    try:
        layout = exact_keys(value, LAYOUT_KEYS, "DMG layout")
    except ArtifactSBOMError as error:
        raise MacPackagingEquivalenceError(str(error)) from error
    if layout != EXPECTED_LAYOUT:
        raise MacPackagingEquivalenceError("DMG root layout is outside v0.1")
    return layout


def _validate_entries(entries: Any) -> list[dict[str, Any]]:
    if not isinstance(entries, list) or not entries or len(entries) > MAX_ENTRIES:
        raise MacPackagingEquivalenceError("invalid application composition")
    previous = b""
    folded: set[str] = set()
    expanded = 0
    for entry in entries:
        try:
            exact_keys(entry, {"path", "type", "mode", "bytes", "sha1", "sha256", "symlinkTarget"}, "application entry")
            path = safe_relative_path(entry["path"], "application entry path")
        except ArtifactSBOMError as error:
            raise MacPackagingEquivalenceError(str(error)) from error
        encoded = path.encode("utf-8")
        if encoded <= previous or path.casefold() in folded:
            raise MacPackagingEquivalenceError("application entries are not uniquely sorted")
        previous = encoded
        folded.add(path.casefold())
        if not isinstance(entry["mode"], str) or MODE.fullmatch(entry["mode"]) is None:
            raise MacPackagingEquivalenceError("invalid application entry mode")
        size = entry["bytes"]
        if not isinstance(size, int) or isinstance(size, bool) or not 0 <= size <= MAX_MEMBER_BYTES:
            raise MacPackagingEquivalenceError("invalid application entry byte count")
        expanded += size
        if expanded > MAX_EXPANDED_BYTES:
            raise MacPackagingEquivalenceError("application composition exceeds expanded bound")
        if entry["type"] == "directory":
            if size != 0 or entry["sha1"] is not None or entry["sha256"] is not None or entry["symlinkTarget"] is not None:
                raise MacPackagingEquivalenceError("invalid application directory entry")
        elif entry["type"] == "regularFile":
            if (
                not isinstance(entry["sha1"], str) or SHA1.fullmatch(entry["sha1"]) is None
                or not isinstance(entry["sha256"], str) or SHA256.fullmatch(entry["sha256"]) is None
                or entry["symlinkTarget"] is not None
            ):
                raise MacPackagingEquivalenceError("invalid application regular-file entry")
        elif entry["type"] == "symlink":
            target = entry["symlinkTarget"]
            target_bytes = target.encode("utf-8") if isinstance(target, str) else b""
            if (
                not isinstance(target, str)
                or len(target_bytes) != size
                or hashlib.sha1(target_bytes).hexdigest() != entry["sha1"]
                or hashlib.sha256(target_bytes).hexdigest() != entry["sha256"]
            ):
                raise MacPackagingEquivalenceError("invalid application symlink entry")
        else:
            raise MacPackagingEquivalenceError("unsupported application entry type")
    try:
        _validate_symlink_graph(entries)
    except ArtifactSBOMError as error:
        raise MacPackagingEquivalenceError(str(error)) from error
    app_entries = _app_entries(entries)
    by_path = {entry["path"]: entry for entry in app_entries}
    for entry in app_entries:
        if entry["path"] == APP_NAME:
            continue
        parent = entry["path"].rsplit("/", 1)[0]
        parent_entry = by_path.get(parent)
        if not isinstance(parent_entry, dict) or parent_entry.get("type") != "directory":
            raise MacPackagingEquivalenceError("application entry parent directory is missing")
    return app_entries


def tree_summary(entries: list[dict[str, Any]]) -> dict[str, Any]:
    app_entries = _validate_entries(entries)
    return {
        "name": APP_NAME,
        "treeSHA256": hashlib.sha256(canonical_bytes(app_entries)).hexdigest(),
        "entryCount": len(app_entries),
        "expandedBytes": sum(entry["bytes"] for entry in app_entries),
    }


def _one_per_kind(
    artifacts: Any,
    required_kinds: set[str],
    label: str,
) -> dict[str, dict[str, Any]]:
    if not isinstance(artifacts, list) or any(not isinstance(item, dict) for item in artifacts):
        raise MacPackagingEquivalenceError(f"invalid {label}")
    result: dict[str, dict[str, Any]] = {}
    for kind in required_kinds:
        matches = [item for item in artifacts if item.get("kind") == kind]
        if len(matches) != 1:
            raise MacPackagingEquivalenceError(f"{label} must contain exactly one {kind}")
        result[kind] = matches[0]
    return result


def build_receipt(
    *,
    index: dict[str, Any],
    composition: dict[str, Any],
    artifact_sbom_reference: dict[str, Any],
    dmg_artifact: dict[str, Any],
    dmg_entries: list[dict[str, Any]],
    dmg_layout: dict[str, Any],
    created: str,
) -> dict[str, Any]:
    try:
        parse_timestamp(created)
    except ArtifactSBOMError as error:
        raise MacPackagingEquivalenceError(str(error)) from error
    _validate_release(index.get("release"))
    _validate_source(index.get("source"))
    _validate_reference(artifact_sbom_reference, "artifact SBOM reference")
    composition_by_id = {artifact["id"]: artifact["entries"] for artifact in composition["artifacts"]}
    binding_by_kind = _one_per_kind(
        index.get("artifacts"),
        {"macApplication", "sparkleArchive"},
        "artifact SBOM",
    )
    canonical_binding = binding_by_kind["macApplication"]
    sparkle_binding = binding_by_kind["sparkleArchive"]
    if dmg_artifact.get("kind") != "macDiskImage":
        raise MacPackagingEquivalenceError("invalid DMG artifact binding")
    try:
        safe_relative_path(dmg_artifact.get("path"), "DMG artifact path")
    except ArtifactSBOMError as error:
        raise MacPackagingEquivalenceError(str(error)) from error
    if (
        not isinstance(dmg_artifact.get("id"), str)
        or IDENTIFIER.fullmatch(dmg_artifact["id"]) is None
        or not isinstance(dmg_artifact.get("sha256"), str)
        or SHA256.fullmatch(dmg_artifact["sha256"]) is None
        or not isinstance(dmg_artifact.get("bytes"), int)
        or isinstance(dmg_artifact["bytes"], bool)
        or dmg_artifact["bytes"] <= 0
    ):
        raise MacPackagingEquivalenceError("invalid DMG artifact binding")
    canonical_entries = _validate_entries(composition_by_id[canonical_binding["id"]])
    sparkle_entries = _validate_entries(composition_by_id[sparkle_binding["id"]])
    if canonical_entries != sparkle_entries:
        raise MacPackagingEquivalenceError("Sparkle payload differs from canonical application")
    if canonical_entries != _validate_entries(dmg_entries):
        raise MacPackagingEquivalenceError("DMG payload differs from canonical application")
    summary = tree_summary(canonical_entries)
    _validate_layout(dmg_layout)
    containers: list[dict[str, Any]] = []
    for binding in (canonical_binding, sparkle_binding, dmg_artifact):
        containers.append({
            "artifactID": binding["id"], "kind": binding["kind"],
            "path": binding["path"], "sha256": binding["sha256"], "bytes": binding["bytes"],
            "appPath": APP_NAME, "treeSHA256": summary["treeSHA256"],
            "entryCount": summary["entryCount"], "expandedBytes": summary["expandedBytes"],
        })
    return {
        "schemaVersion": SCHEMA, "product": PRODUCT,
        "release": copy.deepcopy(index["release"]),
        "source": copy.deepcopy(index["source"]),
        "created": created,
        "artifactSBOM": copy.deepcopy(artifact_sbom_reference),
        "canonicalApp": summary,
        "containers": containers,
        "dmgLayout": copy.deepcopy(dmg_layout),
    }


def validate_receipt(
    value: Any,
    *,
    index: dict[str, Any],
    composition: dict[str, Any],
    artifact_sbom_reference: dict[str, Any],
    release_manifest: dict[str, Any],
    observed_dmg_entries: list[dict[str, Any]] | None = None,
    observed_dmg_layout: dict[str, Any] | None = None,
) -> dict[str, Any]:
    try:
        root = exact_keys(value, ROOT_KEYS, "packaging receipt")
        if root["schemaVersion"] != SCHEMA or root["product"] != PRODUCT:
            raise MacPackagingEquivalenceError("invalid packaging receipt identity")
        _validate_release(root["release"])
        _validate_source(root["source"])
        parse_timestamp(root["created"])
        _validate_reference(root["artifactSBOM"], "artifact SBOM reference")
        _validate_summary(root["canonicalApp"], "canonical app summary")
        _validate_layout(root["dmgLayout"])
        if not isinstance(root["containers"], list) or len(root["containers"]) != 3:
            raise MacPackagingEquivalenceError("packaging receipt requires three containers")
        for container in root["containers"]:
            _validate_container(container)
        if [container["kind"] for container in root["containers"]] != KIND_ORDER:
            raise MacPackagingEquivalenceError("packaging containers are not in canonical order")
    except ArtifactSBOMError as error:
        raise MacPackagingEquivalenceError(str(error)) from error

    release = release_manifest["release"]
    release_targets = release.get("targets")
    expected_release = {
        "version": release.get("version"),
        "buildNumber": release.get("buildNumber"),
        "targets": sorted(release_targets) if isinstance(release_targets, list) else None,
    }
    if root["release"] != expected_release or index["release"] != expected_release:
        raise MacPackagingEquivalenceError("packaging release binding mismatch")
    if root["source"] != release_manifest["source"] or root["source"] != index["source"] or root["source"].get("dirty") is not False:
        raise MacPackagingEquivalenceError("packaging source binding mismatch")
    if root["artifactSBOM"] != artifact_sbom_reference:
        raise MacPackagingEquivalenceError("artifact SBOM reference mismatch")
    artifact_by_kind = _one_per_kind(
        release_manifest.get("artifacts"),
        set(KIND_ORDER),
        "release artifacts",
    )
    try:
        validate_release_binding(release_manifest, index, composition)
    except ArtifactSBOMError as error:
        raise MacPackagingEquivalenceError(str(error)) from error
    composition_by_id = {artifact["id"]: artifact["entries"] for artifact in composition["artifacts"]}
    binding_by_kind = _one_per_kind(
        index.get("artifacts"),
        {"macApplication", "sparkleArchive"},
        "artifact SBOM",
    )
    canonical_entries = _validate_entries(composition_by_id[binding_by_kind["macApplication"]["id"]])
    sparkle_entries = _validate_entries(composition_by_id[binding_by_kind["sparkleArchive"]["id"]])
    if canonical_entries != sparkle_entries:
        raise MacPackagingEquivalenceError("Sparkle payload differs from canonical application")
    summary = tree_summary(canonical_entries)
    if root["canonicalApp"] != summary:
        raise MacPackagingEquivalenceError("canonical app summary mismatch")
    for container in root["containers"]:
        artifact = artifact_by_kind[container["kind"]]
        expected = {
            "artifactID": artifact["id"], "kind": artifact["kind"], "path": artifact["path"],
            "sha256": artifact["sha256"], "bytes": artifact["bytes"], "appPath": APP_NAME,
            "treeSHA256": summary["treeSHA256"], "entryCount": summary["entryCount"],
            "expandedBytes": summary["expandedBytes"],
        }
        if container != expected:
            raise MacPackagingEquivalenceError("packaging container binding mismatch")
    expected_layout = EXPECTED_LAYOUT
    if root["dmgLayout"] != expected_layout:
        raise MacPackagingEquivalenceError("DMG layout receipt mismatch")
    if observed_dmg_entries is not None:
        if _validate_entries(observed_dmg_entries) != canonical_entries:
            raise MacPackagingEquivalenceError("reinspected DMG app differs from canonical application")
        if observed_dmg_layout != expected_layout:
            raise MacPackagingEquivalenceError("reinspected DMG layout mismatch")
    return root


def _scan_app_tree(app_root: Path, filesystem_device: int) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    expanded_bytes = 0
    stack = [app_root]
    while stack:
        path = stack.pop()
        metadata = path.lstat()
        if metadata.st_dev != filesystem_device:
            raise MacPackagingEquivalenceError("cross-device DMG entry")
        relative = path.relative_to(app_root.parent).as_posix()
        try:
            safe_relative_path(relative, "mounted app path")
        except ArtifactSBOMError as error:
            raise MacPackagingEquivalenceError(str(error)) from error
        if relative != unicodedata.normalize("NFC", relative):
            raise MacPackagingEquivalenceError("mounted app path is not NFC")
        mode = stat.S_IMODE(metadata.st_mode)
        if getattr(metadata, "st_flags", 0) != 0:
            raise MacPackagingEquivalenceError("mounted app entry has file flags")
        if not _platform_xattrs_allowed(_xattr_values(path)):
            raise MacPackagingEquivalenceError("mounted app entry has extended attributes")
        if stat.S_ISDIR(metadata.st_mode):
            entries.append({"path": relative, "type": "directory", "mode": f"{mode:04o}", "bytes": 0, "sha1": None, "sha256": None, "symlinkTarget": None})
            children = list(os.scandir(path))
            names = [child.name for child in children]
            if len({unicodedata.normalize("NFC", name).casefold() for name in names}) != len(names):
                raise MacPackagingEquivalenceError("mounted app path collision")
            try:
                ordered_children = sorted(children, key=lambda child: child.name.encode("utf-8"))
            except UnicodeEncodeError as error:
                raise MacPackagingEquivalenceError("mounted app path is not valid UTF-8") from error
            stack.extend(Path(child.path) for child in reversed(ordered_children))
        elif stat.S_ISLNK(metadata.st_mode):
            target = os.readlink(path)
            try:
                target_bytes = target.encode("utf-8")
            except UnicodeEncodeError as error:
                raise MacPackagingEquivalenceError("mounted app symlink target is not UTF-8") from error
            entries.append({"path": relative, "type": "symlink", "mode": f"{mode:04o}", "bytes": len(target_bytes), "sha1": hashlib.sha1(target_bytes).hexdigest(), "sha256": hashlib.sha256(target_bytes).hexdigest(), "symlinkTarget": target})
        elif stat.S_ISREG(metadata.st_mode):
            if metadata.st_nlink != 1:
                raise MacPackagingEquivalenceError("mounted app regular file is hard-linked")
            if metadata.st_size > MAX_MEMBER_BYTES or expanded_bytes + metadata.st_size > MAX_EXPANDED_BYTES:
                raise MacPackagingEquivalenceError("mounted app exceeds profile bounds")
            descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
            try:
                before = os.fstat(descriptor)
                sha1 = hashlib.sha1()
                sha256 = hashlib.sha256()
                size = 0
                while True:
                    chunk = os.read(descriptor, 1024 * 1024)
                    if not chunk:
                        break
                    size += len(chunk)
                    sha1.update(chunk)
                    sha256.update(chunk)
                after = os.fstat(descriptor)
            finally:
                os.close(descriptor)
            if (
                _file_identity(before) != _file_identity(after)
                or _file_identity(before) != _file_identity(metadata)
                or size != metadata.st_size
            ):
                raise MacPackagingEquivalenceError("mounted app file changed during scan")
            entries.append({"path": relative, "type": "regularFile", "mode": f"{mode:04o}", "bytes": size, "sha1": sha1.hexdigest(), "sha256": sha256.hexdigest(), "symlinkTarget": None})
        else:
            raise MacPackagingEquivalenceError("mounted app contains a special file")
        expanded_bytes += entries[-1]["bytes"]
        if len(entries) > MAX_ENTRIES or expanded_bytes > MAX_EXPANDED_BYTES:
            raise MacPackagingEquivalenceError("mounted app exceeds profile bounds")
    entries.sort(key=lambda entry: entry["path"].encode("utf-8"))
    try:
        _validate_symlink_graph(entries)
    except ArtifactSBOMError as error:
        raise MacPackagingEquivalenceError(str(error)) from error
    return entries


def _platform_xattrs_allowed(values: dict[str, bytes]) -> bool:
    if not values:
        return True
    provenance = values.get(PROVENANCE_XATTR)
    return (
        set(values) == {PROVENANCE_XATTR}
        and isinstance(provenance, bytes)
        and len(provenance) == 11
        and provenance.startswith(b"\x01\x02\x00")
    )


def _xattr_values(path: Path) -> dict[str, bytes]:
    if hasattr(os, "listxattr"):
        try:
            names = {
                os.fsdecode(name): name
                for name in os.listxattr(path, follow_symlinks=False)
            }
            return {
                decoded: os.getxattr(path, raw, follow_symlinks=False)
                for decoded, raw in names.items()
            }
        except OSError as error:
            raise MacPackagingEquivalenceError("cannot inspect mounted app attributes") from error
    # The workspace Python on macOS omits os.listxattr. Use the native
    # no-follow API directly so symlink inspection remains exact.
    libc = ctypes.CDLL(None, use_errno=True)
    function = libc.listxattr
    function.argtypes = [ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int]
    function.restype = ctypes.c_ssize_t
    encoded = os.fsencode(path)
    size = function(encoded, None, 0, 0x0001)  # XATTR_NOFOLLOW
    if size < 0:
        error_number = ctypes.get_errno()
        raise MacPackagingEquivalenceError("cannot inspect mounted app attributes") from OSError(
            error_number,
            os.strerror(error_number),
            path,
        )
    if size == 0:
        return {}
    buffer = ctypes.create_string_buffer(size)
    confirmed = function(encoded, buffer, size, 0x0001)
    if confirmed != size:
        error_number = ctypes.get_errno()
        raise MacPackagingEquivalenceError("cannot inspect mounted app attributes") from OSError(
            error_number,
            os.strerror(error_number) if error_number else "xattr list changed",
            path,
        )
    try:
        names = {
            name.decode("utf-8")
            for name in buffer.raw[:size].split(b"\0")
            if name
        }
    except UnicodeDecodeError as error:
        raise MacPackagingEquivalenceError("mounted app attribute name is not UTF-8") from error
    get_function = libc.getxattr
    get_function.argtypes = [
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.c_void_p,
        ctypes.c_size_t,
        ctypes.c_uint32,
        ctypes.c_int,
    ]
    get_function.restype = ctypes.c_ssize_t
    values: dict[str, bytes] = {}
    for name in names:
        name_bytes = name.encode("utf-8")
        value_size = get_function(encoded, name_bytes, None, 0, 0, 0x0001)
        if value_size < 0:
            error_number = ctypes.get_errno()
            raise MacPackagingEquivalenceError("cannot inspect mounted app attributes") from OSError(
                error_number,
                os.strerror(error_number),
                path,
            )
        value_buffer = ctypes.create_string_buffer(value_size)
        value_confirmed = get_function(
            encoded,
            name_bytes,
            value_buffer,
            value_size,
            0,
            0x0001,
        )
        if value_confirmed != value_size:
            raise MacPackagingEquivalenceError("mounted app attributes changed during inspection")
        values[name] = value_buffer.raw[:value_size]
    return values


def scan_mounted_dmg(mount_point: Path) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    root_metadata = mount_point.lstat()
    if not stat.S_ISDIR(root_metadata.st_mode):
        raise MacPackagingEquivalenceError("DMG mount point is not a directory")
    root_entries = list(os.scandir(mount_point))
    if {entry.name for entry in root_entries} != {APP_NAME, "Applications"}:
        raise MacPackagingEquivalenceError("DMG root layout is outside v0.1")
    app = mount_point / APP_NAME
    applications = mount_point / "Applications"
    if not app.is_dir() or app.is_symlink() or not applications.is_symlink() or os.readlink(applications) != "/Applications":
        raise MacPackagingEquivalenceError("DMG root application or Applications link is invalid")
    entries = _scan_app_tree(app, root_metadata.st_dev)
    return entries, {
        "filesystem": "APFS", "readOnly": True, "applicationPath": APP_NAME,
        "applicationsLinkPath": "Applications", "applicationsLinkTarget": "/Applications",
        "rootEntryCount": 2,
    }


def _run(arguments: list[str], *, timeout: int = 120) -> bytes:
    try:
        result = subprocess.run(arguments, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise MacPackagingEquivalenceError("disk-image tool failed") from error
    if result.returncode != 0:
        raise MacPackagingEquivalenceError("disk-image tool rejected candidate")
    return result.stdout


def _run_result(arguments: list[str], *, timeout: int = 120) -> subprocess.CompletedProcess[bytes]:
    try:
        return subprocess.run(
            arguments,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise MacPackagingEquivalenceError("disk-image tool failed") from error


def _image_records() -> list[dict[str, Any]]:
    value = _parse_plist(_run(["/usr/bin/hdiutil", "info", "-plist"]), "disk-image inventory")
    images = value.get("images") if isinstance(value, dict) else None
    if not isinstance(images, list) or any(not isinstance(image, dict) for image in images):
        raise MacPackagingEquivalenceError("disk-image inventory is invalid")
    return images


def _record_devices(images: list[dict[str, Any]]) -> set[str]:
    return {
        entity["dev-entry"]
        for image in images
        for entity in image.get("system-entities", [])
        if isinstance(entity, dict) and isinstance(entity.get("dev-entry"), str)
    }


def _matching_images(images: list[dict[str, Any]], image_path: Path) -> list[dict[str, Any]]:
    expected = str(image_path)
    return [image for image in images if image.get("image-path") == expected]


def _owned_attachment(
    images: list[dict[str, Any]],
    *,
    image_path: Path,
    mount_point: Path,
    prior_devices: set[str],
) -> tuple[str, dict[str, Any]] | None:
    expected_mount = str(mount_point)
    matches: list[dict[str, Any]] = []
    for image in _matching_images(images, image_path):
        entities = image.get("system-entities")
        if not isinstance(entities, list):
            continue
        if any(
            isinstance(entity, dict) and entity.get("mount-point") == expected_mount
            for entity in entities
        ):
            matches.append(image)
    if not matches:
        return None
    if len(matches) != 1:
        raise MacPackagingEquivalenceError("private mount point has ambiguous disk-image ownership")
    image = matches[0]
    entities = image["system-entities"]
    roots = [
        entity.get("dev-entry")
        for entity in entities
        if isinstance(entity, dict) and entity.get("content-hint") == "GUID_partition_scheme"
    ]
    mounted_points = [
        entity.get("mount-point")
        for entity in entities
        if isinstance(entity, dict) and entity.get("mount-point") is not None
    ]
    if (
        len(roots) != 1
        or not isinstance(roots[0], str)
        or DEVICE.fullmatch(roots[0]) is None
        or roots[0] in prior_devices
        or mounted_points != [expected_mount]
        or image.get("writeable") is not False
    ):
        raise MacPackagingEquivalenceError("disk-image ownership facts are invalid")
    return roots[0], image


def _write_recovery_state(
    path: Path,
    *,
    original_image_path: Path,
    pinned_image_path: Path,
    image_digest: str,
    image_bytes: int,
    mount_point: Path,
    device: str | None,
    prior_devices: set[str],
) -> None:
    content = canonical_bytes({
        "schemaVersion": "maccompanion.mac-packaging-recovery.v0.1",
        "runID": path.parent.name,
        "originalImagePath": str(original_image_path),
        "pinnedImagePath": str(pinned_image_path),
        "imageSHA256": image_digest,
        "imageBytes": image_bytes,
        "mountPoint": str(mount_point),
        "device": device,
        "priorDevices": sorted(prior_devices),
    })
    temporary = path.with_name(path.name + ".tmp")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
    except BaseException:
        try:
            os.close(descriptor)
        except OSError:
            pass
        raise
    os.replace(temporary, path)
    directory = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def _file_identity(metadata: os.stat_result) -> tuple[int, int, int, int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_nlink,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def _digest_descriptor(descriptor: int) -> tuple[str, int, tuple[int, int, int, int, int, int, int]]:
    before = os.fstat(descriptor)
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
        raise MacPackagingEquivalenceError("DMG must be one regular file with one link")
    os.lseek(descriptor, 0, os.SEEK_SET)
    hasher = hashlib.sha256()
    size = 0
    while True:
        chunk = os.read(descriptor, 1024 * 1024)
        if not chunk:
            break
        size += len(chunk)
        hasher.update(chunk)
    after = os.fstat(descriptor)
    if _file_identity(before) != _file_identity(after) or size != after.st_size:
        raise MacPackagingEquivalenceError("DMG changed during hashing")
    return hasher.hexdigest(), size, _file_identity(after)


def _parse_plist(raw: bytes, label: str) -> Any:
    try:
        return plistlib.loads(raw)
    except (plistlib.InvalidFileException, ValueError, TypeError) as error:
        raise MacPackagingEquivalenceError(f"invalid {label} result") from error


def _copy_descriptor(source: int, destination: Path) -> int:
    descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o400)
    try:
        os.fchmod(descriptor, 0o400)
        os.lseek(source, 0, os.SEEK_SET)
        while True:
            chunk = os.read(source, 1024 * 1024)
            if not chunk:
                break
            view = memoryview(chunk)
            while view:
                written = os.write(descriptor, view)
                if written <= 0:
                    raise MacPackagingEquivalenceError("cannot pin DMG bytes")
                view = view[written:]
        os.fsync(descriptor)
    except BaseException:
        os.close(descriptor)
        raise
    os.close(descriptor)
    return os.open(destination, os.O_RDONLY | os.O_NOFOLLOW)


def _attachment_output_facts(
    raw: bytes,
    *,
    mount_point: Path,
    prior_devices: set[str],
) -> tuple[str, str] | None:
    try:
        attachment = _parse_plist(raw, "DMG attachment")
    except MacPackagingEquivalenceError:
        return None
    entities = attachment.get("system-entities") if isinstance(attachment, dict) else None
    if not isinstance(entities, list):
        return None
    roots = [
        entity.get("dev-entry")
        for entity in entities
        if isinstance(entity, dict) and entity.get("content-hint") == "GUID_partition_scheme"
    ]
    mounted = [
        entity for entity in entities
        if isinstance(entity, dict) and entity.get("mount-point") == str(mount_point)
    ]
    all_mounted = [
        entity for entity in entities
        if isinstance(entity, dict) and entity.get("mount-point") is not None
    ]
    mounted_device = mounted[0].get("dev-entry") if len(mounted) == 1 else None
    if (
        len(roots) != 1
        or not isinstance(roots[0], str)
        or DEVICE.fullmatch(roots[0]) is None
        or roots[0] in prior_devices
        or len(mounted) != 1
        or len(all_mounted) != 1
        or mounted[0].get("volume-kind") != "apfs"
        or not isinstance(mounted_device, str)
    ):
        return None
    return roots[0], mounted_device


def inspect_dmg(
    dmg_path: Path,
    *,
    expected_sha256: str,
    expected_bytes: int,
    allow_readonly_mount: bool = False,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    if allow_readonly_mount is not True:
        raise MacPackagingEquivalenceError("read-only DMG mount was not explicitly authorized")
    if (
        not isinstance(expected_sha256, str)
        or SHA256.fullmatch(expected_sha256) is None
        or not isinstance(expected_bytes, int)
        or isinstance(expected_bytes, bool)
        or expected_bytes <= 0
    ):
        raise MacPackagingEquivalenceError("invalid expected DMG binding")
    try:
        descriptor = os.open(dmg_path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError as error:
        raise MacPackagingEquivalenceError("DMG must be a non-symlink regular file") from error
    mount_parent: Path | None = None
    pinned_descriptor: int | None = None
    attachment_started = False
    try:
        before_digest, before_size, before_identity = _digest_descriptor(descriptor)
        if (before_digest, before_size) != (expected_sha256, expected_bytes):
            raise MacPackagingEquivalenceError("DMG does not match expected artifact binding")
        resolved = dmg_path.resolve(strict=True)
        if _file_identity(resolved.lstat()) != before_identity:
            raise MacPackagingEquivalenceError("DMG path identity changed before inspection")

        mount_parent = Path(tempfile.mkdtemp(
            prefix="maccompanion-dmg-equivalence-",
            dir="/private/tmp",
        ))
        os.chmod(mount_parent, 0o700)
        pinned_path = mount_parent / "pinned.dmg"
        pinned_descriptor = _copy_descriptor(descriptor, pinned_path)
        pinned_before = _digest_descriptor(pinned_descriptor)
        if pinned_before[:2] != (expected_sha256, expected_bytes):
            raise MacPackagingEquivalenceError("pinned DMG copy differs from release binding")
        if _file_identity(resolved.lstat()) != before_identity:
            raise MacPackagingEquivalenceError("DMG path changed while creating pinned copy")

        _run(["/usr/bin/hdiutil", "verify", "-nocache", str(pinned_path)])
        encrypted = _parse_plist(
            _run(["/usr/bin/hdiutil", "isencrypted", "-plist", str(pinned_path)]),
            "DMG encryption",
        )
        if encrypted != {"encrypted": False}:
            raise MacPackagingEquivalenceError("DMG is encrypted or encryption status is invalid")
        image_info = _parse_plist(
            _run(["/usr/bin/hdiutil", "imageinfo", "-plist", str(pinned_path)]),
            "DMG image-info",
        )
        if not isinstance(image_info, dict) or image_info.get("Format") != "UDZO":
            raise MacPackagingEquivalenceError("DMG format is outside v0.1")

        prior_images = _image_records()
        if _matching_images(prior_images, pinned_path):
            raise MacPackagingEquivalenceError("pinned DMG copy is already attached")
        prior_devices = _record_devices(prior_images)
        mount_point = mount_parent / "mount"
        mount_point.mkdir(mode=0o700)
        recovery_path = mount_parent / "recovery.json"
        _write_recovery_state(
            recovery_path,
            original_image_path=resolved,
            pinned_image_path=pinned_path,
            image_digest=before_digest,
            image_bytes=before_size,
            mount_point=mount_point,
            device=None,
            prior_devices=prior_devices,
        )
        detach_device: str | None = None
        mounted_device: str | None = None
        attachment_started = True
        try:
            attach_result = _run_result([
                "/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen",
                "-noautoopenro", "-noautoopenrw", "-noverify", "-noautofsck",
                "-mount", "required", "-mountpoint", str(mount_point), "-plist",
                str(pinned_path),
            ])
            output_facts = _attachment_output_facts(
                attach_result.stdout,
                mount_point=mount_point,
                prior_devices=prior_devices,
            )
            if output_facts is not None:
                detach_device, mounted_device = output_facts
                _write_recovery_state(
                    recovery_path,
                    original_image_path=resolved,
                    pinned_image_path=pinned_path,
                    image_digest=before_digest,
                    image_bytes=before_size,
                    mount_point=mount_point,
                    device=detach_device,
                    prior_devices=prior_devices,
                )
            owned = _owned_attachment(
                _image_records(),
                image_path=pinned_path,
                mount_point=mount_point,
                prior_devices=prior_devices,
            )
            if owned is not None:
                if detach_device is not None and detach_device != owned[0]:
                    detach_device = owned[0]
                    raise MacPackagingEquivalenceError("DMG attachment ownership mismatch")
                detach_device = owned[0]
                _write_recovery_state(
                    recovery_path,
                    original_image_path=resolved,
                    pinned_image_path=pinned_path,
                    image_digest=before_digest,
                    image_bytes=before_size,
                    mount_point=mount_point,
                    device=detach_device,
                    prior_devices=prior_devices,
                )
            if attach_result.returncode != 0:
                raise MacPackagingEquivalenceError("disk-image tool rejected candidate")
            if detach_device is None or mounted_device is None:
                raise MacPackagingEquivalenceError("DMG attachment result is invalid")
            disk_info = _parse_plist(
                _run(["/usr/sbin/diskutil", "info", "-plist", str(mount_point)]),
                "mounted-volume facts",
            )
            if (
                not isinstance(disk_info, dict)
                or disk_info.get("FilesystemName") != "APFS"
                or disk_info.get("MountPoint") != str(mount_point)
                or disk_info.get("DeviceNode") != mounted_device
                or disk_info.get("Writable") is not False
                or disk_info.get("WritableMedia") is not False
                or disk_info.get("WritableVolume") is not False
            ):
                raise MacPackagingEquivalenceError("DMG mounted-volume facts are invalid")
            entries, layout = scan_mounted_dmg(mount_point)
        finally:
            if detach_device is None:
                try:
                    owned = _owned_attachment(
                        _image_records(),
                        image_path=pinned_path,
                        mount_point=mount_point,
                        prior_devices=prior_devices,
                    )
                except MacPackagingEquivalenceError as error:
                    raise MacPackagingEquivalenceError(
                        f"DMG ownership recovery failed; recovery retained at {recovery_path}"
                    ) from error
                if owned is not None:
                    detach_device = owned[0]
                    _write_recovery_state(
                        recovery_path,
                        original_image_path=resolved,
                        pinned_image_path=pinned_path,
                        image_digest=before_digest,
                        image_bytes=before_size,
                        mount_point=mount_point,
                        device=detach_device,
                        prior_devices=prior_devices,
                    )
            if detach_device is not None:
                try:
                    _run(["/usr/bin/hdiutil", "detach", detach_device])
                except MacPackagingEquivalenceError as error:
                    raise MacPackagingEquivalenceError(
                        f"DMG detach failed; recovery retained at {recovery_path}"
                    ) from error
            if os.path.ismount(mount_point):
                raise MacPackagingEquivalenceError(
                    f"DMG detach could not be confirmed; recovery retained at {recovery_path}"
                )
            try:
                remaining = _matching_images(_image_records(), pinned_path)
            except MacPackagingEquivalenceError as error:
                raise MacPackagingEquivalenceError(
                    f"DMG detach inventory failed; recovery retained at {recovery_path}"
                ) from error
            if remaining:
                raise MacPackagingEquivalenceError(
                    f"DMG device detach could not be confirmed; recovery retained at {recovery_path}"
                )
            if _digest_descriptor(pinned_descriptor) != pinned_before:
                raise MacPackagingEquivalenceError("pinned DMG changed during inspection")
            try:
                mount_point.rmdir()
                recovery_path.unlink()
                pinned_path.unlink()
                mount_parent.rmdir()
            except OSError as error:
                raise MacPackagingEquivalenceError("DMG private mount root did not cleanly close") from error

        after_digest, after_size, after_identity = _digest_descriptor(descriptor)
        try:
            path_identity = _file_identity(resolved.lstat())
        except OSError as error:
            raise MacPackagingEquivalenceError("DMG path disappeared during inspection") from error
        if (
            (before_digest, before_size, before_identity)
            != (after_digest, after_size, after_identity)
            or path_identity != before_identity
            or (after_digest, after_size) != (expected_sha256, expected_bytes)
        ):
            raise MacPackagingEquivalenceError("DMG changed during inspection")
        return entries, layout
    finally:
        if pinned_descriptor is not None:
            os.close(pinned_descriptor)
        os.close(descriptor)
        if not attachment_started and mount_parent is not None and mount_parent.exists():
            # No attach command ran, so this private preflight state is safe to
            # remove without any device reconciliation.
            for child in sorted(mount_parent.iterdir(), reverse=True):
                if child.is_dir() and not child.is_symlink():
                    child.rmdir()
                else:
                    child.unlink()
            mount_parent.rmdir()


RECOVERY_KEYS = {
    "schemaVersion",
    "runID",
    "originalImagePath",
    "pinnedImagePath",
    "imageSHA256",
    "imageBytes",
    "mountPoint",
    "device",
    "priorDevices",
}


def load_recovery_state(root: Path) -> tuple[Path, dict[str, Any]]:
    resolved_root = root.resolve(strict=True)
    if (
        resolved_root.parent != Path("/private/tmp")
        or not resolved_root.name.startswith("maccompanion-dmg-equivalence-")
        or root.is_symlink()
        or not resolved_root.is_dir()
        or stat.S_IMODE(resolved_root.stat().st_mode) != 0o700
    ):
        raise MacPackagingEquivalenceError("invalid packaging recovery root")
    candidates = [
        path for path in (
            resolved_root / "recovery.json",
            resolved_root / "recovery.json.tmp",
        )
        if path.exists()
    ]
    if not candidates:
        raise MacPackagingEquivalenceError("packaging recovery record is missing")
    states: list[tuple[Path, dict[str, Any]]] = []
    for path in candidates:
        try:
            metadata = path.lstat()
            if (
                path.is_symlink()
                or not stat.S_ISREG(metadata.st_mode)
                or stat.S_IMODE(metadata.st_mode) != 0o600
                or not 0 < metadata.st_size <= MAX_RECOVERY_BYTES
            ):
                continue
            value = parse_canonical_json(path.read_bytes())
            state = exact_keys(value, RECOVERY_KEYS, "packaging recovery record")
        except (ArtifactSBOMError, OSError, UnicodeError):
            continue
        original_path = state["originalImagePath"]
        if (
            state["schemaVersion"] != "maccompanion.mac-packaging-recovery.v0.1"
            or state["runID"] != resolved_root.name
            or not isinstance(original_path, str)
            or not original_path.startswith("/")
            or original_path != str(Path(original_path).resolve(strict=False))
            or state["pinnedImagePath"] != str(resolved_root / "pinned.dmg")
            or state["mountPoint"] != str(resolved_root / "mount")
            or not isinstance(state["imageSHA256"], str)
            or SHA256.fullmatch(state["imageSHA256"]) is None
            or not isinstance(state["imageBytes"], int)
            or isinstance(state["imageBytes"], bool)
            or state["imageBytes"] <= 0
            or (state["device"] is not None and (
                not isinstance(state["device"], str)
                or DEVICE.fullmatch(state["device"]) is None
            ))
            or not isinstance(state["priorDevices"], list)
            or state["priorDevices"] != sorted(set(state["priorDevices"]))
            or any(not isinstance(device, str) or ANY_DEVICE.fullmatch(device) is None for device in state["priorDevices"])
        ):
            continue
        states.append((path, state))
    if not states:
        raise MacPackagingEquivalenceError("no valid packaging recovery record remains")
    immutable_keys = RECOVERY_KEYS - {"device"}
    if len(states) == 2 and any(
        states[0][1][key] != states[1][1][key]
        for key in immutable_keys
    ):
        raise MacPackagingEquivalenceError("packaging recovery records disagree")
    states.sort(key=lambda item: item[1]["device"] is not None, reverse=True)
    return states[0]


def _validate_recovery_root_entries(root: Path) -> None:
    allowed = {"pinned.dmg", "mount", "recovery.json", "recovery.json.tmp"}
    with os.scandir(root) as scanner:
        entries = {entry.name: entry for entry in scanner}
    if (
        not {"pinned.dmg", "mount"}.issubset(entries)
        or not {"recovery.json", "recovery.json.tmp"} & entries.keys()
        or set(entries) - allowed
    ):
        raise MacPackagingEquivalenceError("packaging recovery root has invalid contents")
    if any(entry.is_symlink() for entry in entries.values()):
        raise MacPackagingEquivalenceError("packaging recovery root contains a symlink")
    if not entries["pinned.dmg"].is_file(follow_symlinks=False):
        raise MacPackagingEquivalenceError("packaging recovery pinned image has invalid type")
    if not entries["mount"].is_dir(follow_symlinks=False):
        raise MacPackagingEquivalenceError("packaging recovery mount has invalid type")
    if any(
        not entries[name].is_file(follow_symlinks=False)
        for name in ("recovery.json", "recovery.json.tmp")
        if name in entries
    ):
        raise MacPackagingEquivalenceError("packaging recovery record has invalid type")


def reconcile_recovery_root(
    root: Path,
    *,
    allow_nonforce_detach: bool = False,
) -> None:
    if allow_nonforce_detach is not True:
        raise MacPackagingEquivalenceError("packaging recovery detach was not explicitly authorized")
    resolved_root = root.resolve(strict=True)
    _validate_recovery_root_entries(resolved_root)
    _, state = load_recovery_state(root)
    pinned_path = resolved_root / "pinned.dmg"
    mount_point = resolved_root / "mount"
    if pinned_path.is_symlink() or not pinned_path.is_file() or not mount_point.is_dir() or mount_point.is_symlink():
        raise MacPackagingEquivalenceError("packaging recovery files are incomplete")
    pinned_metadata = pinned_path.lstat()
    if stat.S_IMODE(pinned_metadata.st_mode) != 0o400 or pinned_metadata.st_nlink != 1:
        raise MacPackagingEquivalenceError("packaging recovery pinned image metadata is invalid")
    pinned_descriptor = os.open(pinned_path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        pinned = _digest_descriptor(pinned_descriptor)
    finally:
        os.close(pinned_descriptor)
    if pinned[:2] != (state["imageSHA256"], state["imageBytes"]):
        raise MacPackagingEquivalenceError("packaging recovery pinned image mismatch")
    images = _image_records()
    owned = _owned_attachment(
        images,
        image_path=pinned_path,
        mount_point=mount_point,
        prior_devices=set(state["priorDevices"]),
    )
    if owned is not None:
        device, image = owned
        if state["device"] is not None and state["device"] != device:
            raise MacPackagingEquivalenceError("packaging recovery device mismatch")
        mounted = [
            entity for entity in image["system-entities"]
            if isinstance(entity, dict) and entity.get("mount-point") == str(mount_point)
        ]
        mounted_device = mounted[0].get("dev-entry") if len(mounted) == 1 else None
        disk_info = _parse_plist(
            _run(["/usr/sbin/diskutil", "info", "-plist", str(mount_point)]),
            "recovery mounted-volume facts",
        )
        if (
            not isinstance(mounted_device, str)
            or not isinstance(disk_info, dict)
            or disk_info.get("FilesystemName") != "APFS"
            or disk_info.get("MountPoint") != str(mount_point)
            or disk_info.get("DeviceNode") != mounted_device
            or disk_info.get("Writable") is not False
            or disk_info.get("WritableMedia") is not False
            or disk_info.get("WritableVolume") is not False
        ):
            raise MacPackagingEquivalenceError("packaging recovery volume is not safely read-only")
        _run(["/usr/bin/hdiutil", "detach", device])
    if os.path.ismount(mount_point):
        raise MacPackagingEquivalenceError("packaging recovery mount remains active")
    if _matching_images(_image_records(), pinned_path):
        raise MacPackagingEquivalenceError("packaging recovery device remains attached")
    mount_point.rmdir()
    for name in ("recovery.json", "recovery.json.tmp", "pinned.dmg"):
        path = resolved_root / name
        if os.path.lexists(path):
            path.unlink()
    resolved_root.rmdir()
