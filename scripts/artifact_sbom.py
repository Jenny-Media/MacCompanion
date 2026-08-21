#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import stat
import struct
import tempfile
import unicodedata
import uuid
import zipfile
from datetime import datetime
from pathlib import Path, PurePosixPath
from typing import Any


SCHEMA = "maccompanion.artifact-sbom.v0.1"
COMPOSITION_SCHEMA = "maccompanion.artifact-composition.v0.1"
PRODUCT = "Mac Companion"
COVERED_KINDS = {"macApplication", "sparkleArchive", "iosArchive"}
KIND_PLATFORM = {
    "macApplication": "macOS",
    "sparkleArchive": "macOS",
    "iosArchive": "iOS",
}
TARGETS = {"macOS", "iOS"}
IDENTIFIER = re.compile(r"^[a-z0-9](?:[a-z0-9.-]{0,62}[a-z0-9])?$")
VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$")
BUILD = re.compile(r"^(?:0|[1-9][0-9]{0,17})$")
REVISION = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
SHA1 = re.compile(r"^[0-9a-f]{40}$")
UTC_TIME = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
MAX_ENTRIES = 20_000
MAX_EXPANDED_BYTES = 4 * 1024 * 1024 * 1024
MAX_MEMBER_BYTES = 2 * 1024 * 1024 * 1024
MAX_SYMLINK_BYTES = 4_096

INDEX_KEYS = {
    "schemaVersion", "product", "release", "source", "created", "artifacts",
    "composition", "spdx",
}
RELEASE_KEYS = {"version", "buildNumber", "targets"}
SOURCE_KEYS = {"revision", "dirty"}
ARTIFACT_KEYS = {"id", "kind", "platform", "path", "sha256", "bytes"}
REFERENCE_KEYS = {"path", "sha256", "bytes"}
COMPOSITION_KEYS = {"schemaVersion", "artifacts"}
COMPOSITION_ARTIFACT_KEYS = {"id", "entries"}
ENTRY_KEYS = {"path", "type", "mode", "bytes", "sha1", "sha256", "symlinkTarget"}
SPDX_ROOT_KEYS = {
    "SPDXID", "spdxVersion", "dataLicense", "name", "documentNamespace",
    "creationInfo", "documentDescribes", "packages", "files", "relationships",
}
SPDX_PACKAGE_KEYS = {
    "SPDXID", "name", "versionInfo", "supplier", "downloadLocation",
    "filesAnalyzed", "licenseConcluded", "licenseDeclared", "copyrightText",
    "checksums", "packageVerificationCode",
}
SPDX_FILE_KEYS = {"SPDXID", "fileName", "checksums", "licenseConcluded", "copyrightText"}
SPDX_CHECKSUM_KEYS = {"algorithm", "checksumValue"}
SPDX_VERIFICATION_CODE_KEYS = {"packageVerificationCodeValue"}
SPDX_RELATIONSHIP_KEYS = {"spdxElementId", "relationshipType", "relatedSpdxElement"}


class ArtifactSBOMError(ValueError):
    pass


class DuplicateKeyError(ArtifactSBOMError):
    pass


def closed_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKeyError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle, object_pairs_hook=closed_pairs)


def load_canonical_json(path: Path) -> Any:
    raw = path.read_bytes()
    return parse_canonical_json(raw)


def parse_canonical_json(raw: bytes) -> Any:
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=closed_pairs)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ArtifactSBOMError("artifact SBOM JSON is not valid UTF-8 JSON") from error
    if raw != canonical_bytes(value):
        raise ArtifactSBOMError("artifact SBOM JSON is not canonical")
    return value


def canonical_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def digest_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def digest_file(path: Path) -> tuple[str, int]:
    hasher = hashlib.sha256()
    size = 0
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            size += len(chunk)
            hasher.update(chunk)
    return hasher.hexdigest(), size


def exact_keys(value: Any, keys: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise ArtifactSBOMError(f"{label} must contain exactly {sorted(keys)}")
    return value


def safe_relative_path(value: Any, label: str) -> str:
    try:
        encoded = value.encode("utf-8") if isinstance(value, str) else b""
    except UnicodeEncodeError as error:
        raise ArtifactSBOMError(f"{label} must be valid Unicode") from error
    if not isinstance(value, str) or not value or len(encoded) > 1024:
        raise ArtifactSBOMError(f"{label} must be a bounded nonempty path")
    if value != unicodedata.normalize("NFC", value):
        raise ArtifactSBOMError(f"{label} must be NFC")
    parts = value.split("/")
    if (
        PurePosixPath(value).is_absolute()
        or "\\" in value
        or any(part in {"", ".", ".."} for part in parts)
        or any(ord(character) < 32 or ord(character) == 127 for character in value)
    ):
        raise ArtifactSBOMError(f"{label} is unsafe")
    return value


def parse_timestamp(value: Any) -> str:
    if not isinstance(value, str) or UTC_TIME.fullmatch(value) is None:
        raise ArtifactSBOMError("created must be whole-second UTC")
    try:
        datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError as error:
        raise ArtifactSBOMError("created must be a real UTC timestamp") from error
    return value


def resolve_inside(root: Path, relative: str, *, must_exist: bool) -> Path:
    candidate = root / relative
    try:
        resolved = candidate.resolve(strict=must_exist)
    except OSError as error:
        raise ArtifactSBOMError(f"missing path: {relative}") from error
    resolved_root = root.resolve(strict=True)
    if resolved != resolved_root and resolved_root not in resolved.parents:
        raise ArtifactSBOMError(f"path escapes evidence root: {relative}")
    if must_exist and (not resolved.is_file() or candidate.is_symlink()):
        raise ArtifactSBOMError(f"path must be a non-symlink file: {relative}")
    return resolved


def _lexical_symlink_destination(path: str, target: str) -> str:
    try:
        target_bytes = target.encode("utf-8")
    except (AttributeError, UnicodeEncodeError) as error:
        raise ArtifactSBOMError(f"invalid symlink target for {path}") from error
    if not target or len(target_bytes) > MAX_SYMLINK_BYTES:
        raise ArtifactSBOMError(f"invalid symlink target for {path}")
    if target != unicodedata.normalize("NFC", target) or "\\" in target or PurePosixPath(target).is_absolute():
        raise ArtifactSBOMError(f"unsafe symlink target for {path}")
    if any(ord(character) < 32 or ord(character) == 127 for character in target):
        raise ArtifactSBOMError(f"unsafe symlink target for {path}")
    stack = path.split("/")[:-1]
    for part in target.split("/"):
        if part in {"", "."}:
            continue
        if part == "..":
            if not stack:
                raise ArtifactSBOMError(f"escaping symlink target for {path}")
            stack.pop()
        else:
            stack.append(part)
    return "/".join(stack)


def _validate_symlink_graph(entries: list[dict[str, Any]]) -> None:
    known_paths = {entry["path"] for entry in entries}
    links = {
        entry["path"]: entry["symlinkTarget"]
        for entry in entries
        if entry["type"] == "symlink"
    }
    for origin in links:
        visited: set[str] = set()
        components = _lexical_symlink_destination(origin, links[origin]).split("/")
        for _ in range(MAX_ENTRIES):
            replaced = False
            for index in range(1, len(components) + 1):
                prefix = "/".join(components[:index])
                if prefix not in links:
                    continue
                if prefix in visited:
                    raise ArtifactSBOMError(f"cyclic symlink target for {origin}")
                visited.add(prefix)
                replacement = _lexical_symlink_destination(prefix, links[prefix]).split("/")
                components = replacement + components[index:]
                replaced = True
                break
            if replaced:
                continue
            destination = "/".join(components)
            if destination not in known_paths and not any(item.startswith(destination + "/") for item in known_paths):
                raise ArtifactSBOMError(f"missing symlink destination for {origin}")
            break
        else:
            raise ArtifactSBOMError(f"symlink resolution bound exceeded for {origin}")


def _validate_zip_container(path: Path, archive: zipfile.ZipFile, infos: list[zipfile.ZipInfo]) -> None:
    size = path.stat().st_size
    tail_size = min(size, 65_557)
    with path.open("rb") as handle:
        handle.seek(size - tail_size)
        tail = handle.read(tail_size)
        signature = b"PK\x05\x06"
        relative_eocd = tail.rfind(signature)
        if relative_eocd < 0:
            raise ArtifactSBOMError("ZIP end record is missing")
        eocd = size - tail_size + relative_eocd
        if eocd + 22 > size:
            raise ArtifactSBOMError("ZIP end record is truncated")
        comment_length = struct.unpack_from("<H", tail, relative_eocd + 20)[0]
        central_size = struct.unpack_from("<I", tail, relative_eocd + 12)[0]
        if eocd + 22 + comment_length != size:
            raise ArtifactSBOMError("ZIP has unaccounted trailing bytes")
        if archive.start_dir + central_size != eocd:
            raise ArtifactSBOMError("ZIP central directory has unaccounted bytes")
        ordered = sorted(infos, key=lambda info: info.header_offset)
        if ordered[0].header_offset != 0:
            raise ArtifactSBOMError("ZIP has unaccounted prefix bytes")
        for index, info in enumerate(ordered):
            handle.seek(info.header_offset)
            header = handle.read(30)
            if len(header) != 30 or header[:4] != b"PK\x03\x04":
                raise ArtifactSBOMError("ZIP local header is malformed")
            name_length, extra_length = struct.unpack_from("<HH", header, 26)
            data_end = info.header_offset + 30 + name_length + extra_length + info.compress_size
            next_offset = ordered[index + 1].header_offset if index + 1 < len(ordered) else archive.start_dir
            gap = next_offset - data_end
            if not info.flag_bits & 0x08:
                if gap != 0:
                    raise ArtifactSBOMError("ZIP has unaccounted bytes between members")
                continue
            if gap not in {12, 16, 20, 24}:
                raise ArtifactSBOMError("ZIP has unaccounted bytes between members")
            handle.seek(data_end)
            descriptor = handle.read(gap)
            signed = gap in {16, 24}
            cursor = 0
            if signed:
                if descriptor[:4] != b"PK\x07\x08":
                    raise ArtifactSBOMError("ZIP data descriptor signature is invalid")
                cursor = 4
            elif descriptor[:4] == b"PK\x07\x08":
                raise ArtifactSBOMError("ZIP data descriptor form is ambiguous")
            descriptor_crc = struct.unpack_from("<I", descriptor, cursor)[0]
            cursor += 4
            if gap in {12, 16}:
                compressed, uncompressed = struct.unpack_from("<II", descriptor, cursor)
            else:
                compressed, uncompressed = struct.unpack_from("<QQ", descriptor, cursor)
            if descriptor_crc != info.CRC or compressed != info.compress_size or uncompressed != info.file_size:
                raise ArtifactSBOMError("ZIP data descriptor facts do not match the central directory")


def inspect_zip(path: Path) -> list[dict[str, Any]]:
    try:
        archive = zipfile.ZipFile(path, "r")
    except (OSError, zipfile.BadZipFile) as error:
        raise ArtifactSBOMError("artifact is not a supported ZIP") from error
    with archive:
        infos = archive.infolist()
        if not infos or len(infos) > MAX_ENTRIES:
            raise ArtifactSBOMError("ZIP entry count is outside the profile")
        _validate_zip_container(path, archive, infos)
        names: set[str] = set()
        folded: set[str] = set()
        expanded = 0
        prepared: list[tuple[zipfile.ZipInfo, str, int, str]] = []
        for info in infos:
            is_directory_name = info.filename.endswith("/")
            if info.filename.endswith("//"):
                raise ArtifactSBOMError("ZIP member has ambiguous trailing separators")
            name = safe_relative_path(info.filename[:-1] if is_directory_name else info.filename, "ZIP member path")
            if name in names:
                raise ArtifactSBOMError(f"duplicate ZIP member: {name}")
            collision = unicodedata.normalize("NFC", name).casefold()
            if collision in folded:
                raise ArtifactSBOMError(f"case-fold collision: {name}")
            names.add(name)
            folded.add(collision)
            if info.flag_bits & 0x1:
                raise ArtifactSBOMError(f"encrypted ZIP member: {name}")
            if info.create_system != 3 or info.compress_type not in {zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED}:
                raise ArtifactSBOMError(f"unsupported ZIP member encoding: {name}")
            if info.file_size < 0 or info.file_size > MAX_MEMBER_BYTES:
                raise ArtifactSBOMError(f"ZIP member too large: {name}")
            expanded += info.file_size
            if expanded > MAX_EXPANDED_BYTES:
                raise ArtifactSBOMError("expanded ZIP exceeds profile bound")
            if info.file_size > 0 and info.compress_size == 0:
                raise ArtifactSBOMError(f"invalid zero-size compressed member: {name}")
            if info.file_size > 1024 * 1024 and info.file_size / info.compress_size > 1000:
                raise ArtifactSBOMError(f"ZIP compression ratio exceeds profile: {name}")
            unix_mode = (info.external_attr >> 16) & 0xFFFF
            file_type = stat.S_IFMT(unix_mode)
            permissions = unix_mode & 0o7777
            if file_type == stat.S_IFDIR and is_directory_name:
                entry_type = "directory"
            elif file_type == stat.S_IFREG and not is_directory_name:
                entry_type = "regularFile"
            elif file_type == stat.S_IFLNK and not is_directory_name:
                entry_type = "symlink"
            else:
                raise ArtifactSBOMError(f"unsupported or malformed ZIP member mode: {name}")
            prepared.append((info, name, permissions, entry_type))

        entries: list[dict[str, Any]] = []
        for info, name, permissions, entry_type in prepared:
            if entry_type == "directory":
                if info.file_size != 0:
                    raise ArtifactSBOMError(f"directory has content: {name}")
                entries.append({"path": name, "type": entry_type, "mode": f"{permissions:04o}", "bytes": 0, "sha1": None, "sha256": None, "symlinkTarget": None})
                continue
            sha1 = hashlib.sha1()
            sha256 = hashlib.sha256()
            size = 0
            target_bytes = bytearray()
            try:
                with archive.open(info, "r") as handle:
                    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                        size += len(chunk)
                        if size > info.file_size:
                            raise ArtifactSBOMError(f"ZIP size overrun: {name}")
                        sha1.update(chunk)
                        sha256.update(chunk)
                        if entry_type == "symlink":
                            if size > MAX_SYMLINK_BYTES:
                                raise ArtifactSBOMError(f"symlink target too large: {name}")
                            target_bytes.extend(chunk)
            except (OSError, RuntimeError, zipfile.BadZipFile) as error:
                raise ArtifactSBOMError(f"cannot read ZIP member: {name}") from error
            if size != info.file_size:
                raise ArtifactSBOMError(f"ZIP size mismatch: {name}")
            target: str | None = None
            if entry_type == "symlink":
                try:
                    target = bytes(target_bytes).decode("utf-8")
                except UnicodeDecodeError as error:
                    raise ArtifactSBOMError(f"symlink target is not UTF-8: {name}") from error
            entries.append({"path": name, "type": entry_type, "mode": f"{permissions:04o}", "bytes": size, "sha1": sha1.hexdigest(), "sha256": sha256.hexdigest(), "symlinkTarget": target})
        entries = sorted(entries, key=lambda entry: entry["path"].encode("utf-8"))
        _validate_symlink_graph(entries)
        return entries


def validate_candidate(value: Any) -> dict[str, Any]:
    root = exact_keys(value, {"schemaVersion", "product", "release", "source", "created", "artifacts"}, "candidate")
    if root["schemaVersion"] != SCHEMA or root["product"] != PRODUCT:
        raise ArtifactSBOMError("invalid candidate identity")
    release = exact_keys(root["release"], RELEASE_KEYS, "release")
    if not isinstance(release["version"], str) or VERSION.fullmatch(release["version"]) is None:
        raise ArtifactSBOMError("invalid release version")
    if not isinstance(release["buildNumber"], str) or BUILD.fullmatch(release["buildNumber"]) is None:
        raise ArtifactSBOMError("invalid build number")
    targets = release["targets"]
    if not isinstance(targets, list) or targets != sorted(set(targets)) or not 1 <= len(targets) <= 2 or not set(targets) <= TARGETS:
        raise ArtifactSBOMError("targets must be unique and sorted")
    source = exact_keys(root["source"], SOURCE_KEYS, "source")
    if not isinstance(source["revision"], str) or REVISION.fullmatch(source["revision"]) is None or source["dirty"] is not False:
        raise ArtifactSBOMError("artifact SBOM requires a clean full Git revision")
    parse_timestamp(root["created"])
    artifacts = root["artifacts"]
    if not isinstance(artifacts, list) or not 1 <= len(artifacts) <= 8:
        raise ArtifactSBOMError("invalid artifact set")
    seen: set[str] = set()
    kinds: set[str] = set()
    previous = ""
    for artifact in artifacts:
        obj = exact_keys(artifact, {"id", "kind", "path"}, "candidate artifact")
        identifier = obj["id"]
        if not isinstance(identifier, str) or IDENTIFIER.fullmatch(identifier) is None or identifier in seen or identifier <= previous:
            raise ArtifactSBOMError("artifact IDs must be unique and sorted")
        previous = identifier
        seen.add(identifier)
        if obj["kind"] not in COVERED_KINDS:
            raise ArtifactSBOMError("unsupported artifact kind")
        kinds.add(obj["kind"])
        safe_relative_path(obj["path"], "artifact path")
    if "macOS" in targets and not {"macApplication", "sparkleArchive"} <= kinds:
        raise ArtifactSBOMError("macOS target lacks exact ZIP coverage")
    if "iOS" in targets and "iosArchive" not in kinds:
        raise ArtifactSBOMError("iOS target lacks exact ZIP coverage")
    if kinds and {KIND_PLATFORM[kind] for kind in kinds} != set(targets):
        raise ArtifactSBOMError("artifact platforms do not exactly match targets")
    return root


def _reference(path: str, content: bytes) -> dict[str, Any]:
    return {"path": path, "sha256": digest_bytes(content), "bytes": len(content)}


def generate(candidate: dict[str, Any], evidence_root: Path) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    root = validate_candidate(candidate)
    bindings: list[dict[str, Any]] = []
    compositions: list[dict[str, Any]] = []
    for artifact in root["artifacts"]:
        archive_path = resolve_inside(evidence_root, artifact["path"], must_exist=True)
        archive_digest, archive_size = digest_file(archive_path)
        entries = inspect_zip(archive_path)
        confirmed_digest, confirmed_size = digest_file(archive_path)
        if (archive_digest, archive_size) != (confirmed_digest, confirmed_size):
            raise ArtifactSBOMError("artifact changed during SBOM generation")
        binding = {
            "id": artifact["id"], "kind": artifact["kind"],
            "platform": KIND_PLATFORM[artifact["kind"]], "path": artifact["path"],
            "sha256": archive_digest, "bytes": archive_size,
        }
        bindings.append(binding)
        compositions.append({"id": artifact["id"], "entries": entries})
    composition = {"schemaVersion": COMPOSITION_SCHEMA, "artifacts": compositions}
    composition_content = canonical_bytes(composition)
    spdx = build_spdx(root, bindings, compositions, digest_bytes(composition_content))
    spdx_content = canonical_bytes(spdx)
    index = {
        "schemaVersion": SCHEMA,
        "product": PRODUCT,
        "release": root["release"],
        "source": root["source"],
        "created": root["created"],
        "artifacts": bindings,
        "composition": _reference("artifact-composition.json", composition_content),
        "spdx": _reference("artifact-sbom.spdx.json", spdx_content),
    }
    return index, composition, spdx


def build_spdx(candidate: dict[str, Any], bindings: list[dict[str, Any]], compositions: list[dict[str, Any]], composition_digest: str) -> dict[str, Any]:
    packages: list[dict[str, Any]] = []
    files: list[dict[str, Any]] = []
    relationships: list[dict[str, Any]] = []
    described: list[str] = []
    composition_by_id = {item["id"]: item["entries"] for item in compositions}
    for binding in bindings:
        package_id = f"SPDXRef-Package-{binding['id']}"
        described.append(package_id)
        analyzed_entries = [entry for entry in composition_by_id[binding["id"]] if entry["type"] != "directory"]
        verification_input = "".join(sorted(entry["sha1"] for entry in analyzed_entries)).encode("ascii")
        verification_code = hashlib.sha1(verification_input).hexdigest()
        packages.append({
            "SPDXID": package_id, "name": binding["path"],
            "versionInfo": f"{candidate['release']['version']}+{candidate['release']['buildNumber']}",
            "supplier": "Organization: Jenny Media LLC", "downloadLocation": "NOASSERTION",
            "filesAnalyzed": True, "licenseConcluded": "NOASSERTION",
            "licenseDeclared": "NOASSERTION", "copyrightText": "NOASSERTION",
            "checksums": [{"algorithm": "SHA256", "checksumValue": binding["sha256"]}],
            "packageVerificationCode": {"packageVerificationCodeValue": verification_code},
        })
        relationships.append({"spdxElementId": "SPDXRef-DOCUMENT", "relationshipType": "DESCRIBES", "relatedSpdxElement": package_id})
        file_index = 0
        for entry in composition_by_id[binding["id"]]:
            if entry["type"] == "directory":
                continue
            file_index += 1
            file_id = f"SPDXRef-File-{binding['id']}-{file_index:05d}"
            files.append({
                "SPDXID": file_id,
                "fileName": f"./{binding['id']}/{entry['path']}",
                "checksums": [
                    {"algorithm": "SHA1", "checksumValue": entry["sha1"]},
                    {"algorithm": "SHA256", "checksumValue": entry["sha256"]},
                ],
                "licenseConcluded": "NOASSERTION", "copyrightText": "NOASSERTION",
            })
            relationships.append({"spdxElementId": package_id, "relationshipType": "CONTAINS", "relatedSpdxElement": file_id})
    seed = canonical_bytes({
        "schema": SCHEMA, "release": candidate["release"], "source": candidate["source"],
        "created": candidate["created"], "artifacts": bindings, "compositionSHA256": composition_digest,
    }).decode("utf-8")
    return {
        "SPDXID": "SPDXRef-DOCUMENT", "spdxVersion": "SPDX-2.3", "dataLicense": "CC0-1.0",
        "name": f"Mac-Companion-{candidate['release']['version']}-{candidate['release']['buildNumber']}-artifact-composition",
        "documentNamespace": f"https://spdx.org/spdxdocs/mac-companion-artifact-{uuid.uuid5(uuid.NAMESPACE_URL, seed)}",
        "creationInfo": {"created": candidate["created"], "creators": ["Organization: Jenny Media LLC", "Tool: Mac Companion artifact SBOM generator-0.1"]},
        "documentDescribes": described, "packages": packages, "files": files, "relationships": relationships,
    }


def _validate_reference(value: Any, expected_path: str, label: str) -> dict[str, Any]:
    obj = exact_keys(value, REFERENCE_KEYS, label)
    if obj["path"] != expected_path or not isinstance(obj["sha256"], str) or SHA256.fullmatch(obj["sha256"]) is None or not isinstance(obj["bytes"], int) or isinstance(obj["bytes"], bool) or obj["bytes"] <= 0:
        raise ArtifactSBOMError(f"invalid {label}")
    return obj


def validate_index(value: Any) -> dict[str, Any]:
    root = exact_keys(value, INDEX_KEYS, "artifact SBOM index")
    if not isinstance(root.get("artifacts"), list) or any(not isinstance(item, dict) for item in root["artifacts"]):
        raise ArtifactSBOMError("artifact bindings must be an array of objects")
    candidate = {
        "schemaVersion": root["schemaVersion"], "product": root["product"],
        "release": root["release"], "source": root["source"], "created": root["created"],
        "artifacts": [{"id": item.get("id"), "kind": item.get("kind"), "path": item.get("path")} for item in root.get("artifacts", [])] if isinstance(root.get("artifacts"), list) else root.get("artifacts"),
    }
    validate_candidate(candidate)
    for artifact in root["artifacts"]:
        exact_keys(artifact, ARTIFACT_KEYS, "artifact binding")
        if artifact["platform"] != KIND_PLATFORM[artifact["kind"]] or not isinstance(artifact["sha256"], str) or SHA256.fullmatch(artifact["sha256"]) is None or not isinstance(artifact["bytes"], int) or isinstance(artifact["bytes"], bool) or artifact["bytes"] <= 0:
            raise ArtifactSBOMError("invalid artifact binding")
    _validate_reference(root["composition"], "artifact-composition.json", "composition reference")
    _validate_reference(root["spdx"], "artifact-sbom.spdx.json", "SPDX reference")
    return root


def validate_composition(value: Any, index: dict[str, Any]) -> dict[str, Any]:
    root = exact_keys(value, COMPOSITION_KEYS, "composition")
    if root["schemaVersion"] != COMPOSITION_SCHEMA or not isinstance(root["artifacts"], list):
        raise ArtifactSBOMError("invalid composition identity")
    if [item.get("id") for item in root["artifacts"] if isinstance(item, dict)] != [item["id"] for item in index["artifacts"]]:
        raise ArtifactSBOMError("composition artifact set mismatch")
    for artifact in root["artifacts"]:
        exact_keys(artifact, COMPOSITION_ARTIFACT_KEYS, "composition artifact")
        entries = artifact["entries"]
        if not isinstance(entries, list) or not entries or len(entries) > MAX_ENTRIES:
            raise ArtifactSBOMError("invalid composition entry set")
        previous = b""
        folded: set[str] = set()
        expanded = 0
        for entry in entries:
            exact_keys(entry, ENTRY_KEYS, "composition entry")
            path = safe_relative_path(entry["path"], "composition entry path")
            encoded = path.encode("utf-8")
            if encoded <= previous:
                raise ArtifactSBOMError("composition entries are not uniquely sorted")
            previous = encoded
            collision = path.casefold()
            if collision in folded:
                raise ArtifactSBOMError("composition path collision")
            folded.add(collision)
            if not isinstance(entry["mode"], str) or re.fullmatch(r"[0-7]{4}", entry["mode"]) is None:
                raise ArtifactSBOMError("invalid entry mode")
            if not isinstance(entry["bytes"], int) or isinstance(entry["bytes"], bool) or not 0 <= entry["bytes"] <= MAX_MEMBER_BYTES:
                raise ArtifactSBOMError("invalid entry byte count")
            expanded += entry["bytes"]
            if expanded > MAX_EXPANDED_BYTES:
                raise ArtifactSBOMError("composition expanded bound exceeded")
            if entry["type"] == "directory":
                if entry["bytes"] != 0 or entry["sha1"] is not None or entry["sha256"] is not None or entry["symlinkTarget"] is not None:
                    raise ArtifactSBOMError("invalid directory entry")
            elif entry["type"] == "regularFile":
                if not isinstance(entry["sha1"], str) or SHA1.fullmatch(entry["sha1"]) is None or not isinstance(entry["sha256"], str) or SHA256.fullmatch(entry["sha256"]) is None or entry["symlinkTarget"] is not None:
                    raise ArtifactSBOMError("invalid regular-file entry")
            elif entry["type"] == "symlink":
                target = entry["symlinkTarget"]
                target_bytes = target.encode("utf-8") if isinstance(target, str) else b""
                if not isinstance(target, str) or hashlib.sha1(target_bytes).hexdigest() != entry["sha1"] or digest_bytes(target_bytes) != entry["sha256"] or len(target_bytes) != entry["bytes"]:
                    raise ArtifactSBOMError("invalid symlink entry")
            else:
                raise ArtifactSBOMError("unsupported entry type")
        _validate_symlink_graph(entries)
    return root


def validate_spdx(value: Any, index: dict[str, Any], composition: dict[str, Any]) -> dict[str, Any]:
    root = exact_keys(value, SPDX_ROOT_KEYS, "SPDX document")
    expected = build_spdx(
        {"release": index["release"], "source": index["source"], "created": index["created"]},
        index["artifacts"], composition["artifacts"], index["composition"]["sha256"],
    )
    if root != expected:
        raise ArtifactSBOMError("SPDX is not exactly reciprocal with composition")
    for package in root["packages"]:
        exact_keys(package, SPDX_PACKAGE_KEYS, "SPDX package")
        exact_keys(package["packageVerificationCode"], SPDX_VERIFICATION_CODE_KEYS, "SPDX package verification code")
        for checksum in package["checksums"]:
            exact_keys(checksum, SPDX_CHECKSUM_KEYS, "SPDX checksum")
    for file in root["files"]:
        exact_keys(file, SPDX_FILE_KEYS, "SPDX file")
        for checksum in file["checksums"]:
            exact_keys(checksum, SPDX_CHECKSUM_KEYS, "SPDX checksum")
    for relationship in root["relationships"]:
        exact_keys(relationship, SPDX_RELATIONSHIP_KEYS, "SPDX relationship")
    return root


def validate_bundle(index_path: Path, *, evidence_root: Path | None = None, verify_archives: bool = False) -> tuple[dict[str, Any], dict[str, Any]]:
    if index_path.is_symlink() or not index_path.is_file():
        raise ArtifactSBOMError("artifact SBOM index must be a non-symlink file")
    index = validate_index(load_canonical_json(index_path))
    bundle_root = index_path.resolve(strict=True).parent
    composition_path = resolve_inside(bundle_root, index["composition"]["path"], must_exist=True)
    spdx_path = resolve_inside(bundle_root, index["spdx"]["path"], must_exist=True)
    composition_raw = composition_path.read_bytes()
    spdx_raw = spdx_path.read_bytes()
    for reference, raw in ((index["composition"], composition_raw), (index["spdx"], spdx_raw)):
        if digest_bytes(raw) != reference["sha256"] or len(raw) != reference["bytes"]:
            raise ArtifactSBOMError("transitive SBOM reference mismatch")
    composition = validate_composition(parse_canonical_json(composition_raw), index)
    validate_spdx(parse_canonical_json(spdx_raw), index, composition)
    if verify_archives:
        if evidence_root is None:
            raise ArtifactSBOMError("archive verification requires an evidence root")
        composition_by_id = {item["id"]: item["entries"] for item in composition["artifacts"]}
        for binding in index["artifacts"]:
            archive = resolve_inside(evidence_root, binding["path"], must_exist=True)
            digest, size = digest_file(archive)
            if digest != binding["sha256"] or size != binding["bytes"]:
                raise ArtifactSBOMError("archive binding mismatch")
            inspected = inspect_zip(archive)
            confirmed_digest, confirmed_size = digest_file(archive)
            if (digest, size) != (confirmed_digest, confirmed_size):
                raise ArtifactSBOMError("archive changed during verification")
            if inspected != composition_by_id[binding["id"]]:
                raise ArtifactSBOMError("archive composition mismatch")
    return index, composition


def validate_release_binding(release_manifest: dict[str, Any], index: dict[str, Any], composition: dict[str, Any]) -> None:
    release = release_manifest.get("release")
    source = release_manifest.get("source")
    artifacts = release_manifest.get("artifacts")
    executables = release_manifest.get("executables")
    if not isinstance(release, dict) or not isinstance(source, dict) or not isinstance(artifacts, list) or not isinstance(executables, list):
        raise ArtifactSBOMError("release manifest cannot be bound to artifact SBOM")
    expected_release = {
        "version": release.get("version"),
        "buildNumber": release.get("buildNumber"),
        "targets": sorted(release.get("targets", [])) if isinstance(release.get("targets"), list) else None,
    }
    if index["release"] != expected_release:
        raise ArtifactSBOMError("artifact SBOM release metadata mismatch")
    if index["source"] != {"revision": source.get("revision"), "dirty": source.get("dirty")}:
        raise ArtifactSBOMError("artifact SBOM source metadata mismatch")
    expected_artifacts: list[dict[str, Any]] = []
    for artifact in artifacts:
        if isinstance(artifact, dict) and artifact.get("kind") in COVERED_KINDS:
            expected_artifacts.append({
                "id": artifact.get("id"), "kind": artifact.get("kind"),
                "platform": KIND_PLATFORM[artifact["kind"]], "path": artifact.get("path"),
                "sha256": artifact.get("sha256"), "bytes": artifact.get("bytes"),
            })
    expected_artifacts.sort(key=lambda item: item["id"] if isinstance(item["id"], str) else "")
    if index["artifacts"] != expected_artifacts:
        raise ArtifactSBOMError("artifact SBOM candidate binding mismatch")
    composition_by_id = {
        artifact["id"]: {entry["path"]: entry for entry in artifact["entries"]}
        for artifact in composition["artifacts"]
    }
    if "macOS" in expected_release["targets"]:
        artifact_id_by_kind = {artifact["kind"]: artifact["id"] for artifact in index["artifacts"]}
        canonical_entries = composition_by_id[artifact_id_by_kind["macApplication"]]
        sparkle_entries = composition_by_id[artifact_id_by_kind["sparkleArchive"]]
        if canonical_entries != sparkle_entries:
            raise ArtifactSBOMError("Sparkle archive app payload differs from the canonical application ZIP")
    for executable in executables:
        if not isinstance(executable, dict):
            raise ArtifactSBOMError("invalid release executable binding")
        artifact_id = executable.get("artifactID")
        if artifact_id not in composition_by_id:
            continue
        relative_path = executable.get("relativePath")
        entry = composition_by_id[artifact_id].get(relative_path)
        if not isinstance(entry, dict) or entry.get("type") != "regularFile" or int(entry.get("mode", "0"), 8) & 0o111 == 0:
            raise ArtifactSBOMError("signed executable is absent from exact composition")


def atomic_write_set(output_directory: Path, files: dict[str, bytes]) -> None:
    if output_directory.exists() or output_directory.is_symlink():
        raise ArtifactSBOMError("artifact SBOM output already exists")
    output_directory.parent.mkdir(parents=True, exist_ok=True)
    parent = output_directory.parent.resolve(strict=True)
    temporary_directory = Path(tempfile.mkdtemp(prefix=f".{output_directory.name}.", dir=parent))
    try:
        for name, content in files.items():
            if PurePosixPath(name).name != name or not name:
                raise ArtifactSBOMError("invalid output member name")
            destination = temporary_directory / name
            descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
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
        directory_descriptor = os.open(temporary_directory, os.O_RDONLY)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
        os.rename(temporary_directory, output_directory)
        parent_descriptor = os.open(parent, os.O_RDONLY)
        try:
            os.fsync(parent_descriptor)
        finally:
            os.close(parent_descriptor)
    finally:
        if temporary_directory.exists():
            shutil.rmtree(temporary_directory)
