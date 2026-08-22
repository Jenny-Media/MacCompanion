#!/usr/bin/env python3

from __future__ import annotations

import ctypes
import hashlib
import os
import re
import stat
import sys
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from artifact_sbom import (
    ArtifactSBOMError,
    MAX_ENTRIES,
    canonical_bytes,
    safe_relative_path,
)
from platform_signing_fixed_tools import (
    FixedToolIdentity,
    FixedToolInvocation,
)
from signed_code_graph import PRIMARY_KINDS


TEAM_ID_PATTERN = re.compile(r"^[A-Z0-9]{10}$")
MAX_RECONSTRUCTED_ARTIFACTS = 8
MAX_CODESIGN_PLANS = 4096
DARWIN_XATTR_NOFOLLOW = 0x0001
PROVENANCE_XATTR = "com.apple.provenance"
CODESIGN_REQUIREMENT_PREFIX = (
    "=anchor apple generic and certificate "
    "1[field.1.2.840.113635.100.6.2.6] exists and certificate "
    "leaf[field.1.2.840.113635.100.6.1.13] exists and certificate "
    "leaf[subject.OU] = "
)


class PlatformSigningSubjectError(ValueError):
    pass


@dataclass(frozen=True)
class ReconstructedSigningSubject:
    artifact_id: str
    platform: str
    artifact_root: Path
    subject_root: str
    entry_count: int
    composition_sha256: str
    synthetic_directories: tuple[str, ...]
    provenance_path_count: int
    provenance_sha256: str | None

    @property
    def subject_path(self) -> Path:
        return self.artifact_root / self.subject_root


@dataclass(frozen=True)
class PlannedCodeSignVerification:
    artifact_id: str
    object_path: str
    owned_subject_path: Path
    source_depth: int
    invocation: FixedToolInvocation

    def public_record(self) -> dict[str, Any]:
        return {
            "artifactID": self.artifact_id,
            "objectPath": self.object_path,
            "ownedSubjectPath": str(self.owned_subject_path),
            "sourceDepth": self.source_depth,
            "invocationID": self.invocation.invocation_id,
            "tool": self.invocation.tool.public_record(),
            "argv": [
                self.invocation.tool.path,
                *self.invocation.arguments,
            ],
        }


@dataclass(frozen=True)
class PlannedCodeSignOuterVerification:
    artifact_id: str
    owned_subject_path: Path
    invocation: FixedToolInvocation

    def public_record(self) -> dict[str, Any]:
        return {
            "artifactID": self.artifact_id,
            "ownedSubjectPath": str(self.owned_subject_path),
            "invocationID": self.invocation.invocation_id,
            "tool": self.invocation.tool.public_record(),
            "argv": [
                self.invocation.tool.path,
                *self.invocation.arguments,
            ],
        }


@dataclass(frozen=True)
class PlannedMacPlatformAssessment:
    artifact_id: str
    owned_subject_path: Path
    gatekeeper_invocation: FixedToolInvocation
    stapler_invocation: FixedToolInvocation

    def public_record(self) -> dict[str, Any]:
        return {
            "artifactID": self.artifact_id,
            "ownedSubjectPath": str(self.owned_subject_path),
            "gatekeeper": {
                "invocationID": self.gatekeeper_invocation.invocation_id,
                "tool": self.gatekeeper_invocation.tool.public_record(),
                "argv": [
                    self.gatekeeper_invocation.tool.path,
                    *self.gatekeeper_invocation.arguments,
                ],
            },
            "stapler": {
                "invocationID": self.stapler_invocation.invocation_id,
                "tool": self.stapler_invocation.tool.public_record(),
                "argv": [
                    self.stapler_invocation.tool.path,
                    *self.stapler_invocation.arguments,
                ],
            },
        }


@dataclass(frozen=True)
class PlannedCodeSignArchitectureInspection:
    artifact_id: str
    source_path: str
    object_path: str
    owned_source_path: Path
    owned_subject_path: Path
    cpu_type: int
    cpu_subtype: int
    certificate_prefix: Path
    identity_invocation: FixedToolInvocation
    entitlements_invocation: FixedToolInvocation

    def public_record(self) -> dict[str, Any]:
        return {
            "artifactID": self.artifact_id,
            "sourcePath": self.source_path,
            "objectPath": self.object_path,
            "ownedSourcePath": str(self.owned_source_path),
            "ownedSubjectPath": str(self.owned_subject_path),
            "architectureSelector": {
                "cpuType": self.cpu_type,
                "cpuSubtype": self.cpu_subtype,
            },
            "certificatePrefix": str(self.certificate_prefix),
            "identityInvocation": {
                "invocationID": self.identity_invocation.invocation_id,
                "tool": self.identity_invocation.tool.public_record(),
                "argv": [
                    self.identity_invocation.tool.path,
                    *self.identity_invocation.arguments,
                ],
            },
            "entitlementsInvocation": {
                "invocationID": self.entitlements_invocation.invocation_id,
                "tool": self.entitlements_invocation.tool.public_record(),
                "argv": [
                    self.entitlements_invocation.tool.path,
                    *self.entitlements_invocation.arguments,
                ],
            },
        }


def _descriptor_identity(
    metadata: os.stat_result,
) -> tuple[int, int, int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_nlink,
        metadata.st_size,
        metadata.st_mtime_ns,
    )


def _digest_descriptor(
    descriptor: int,
) -> tuple[str, int, tuple[int, int, int, int, int, int]]:
    before = os.fstat(descriptor)
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
        raise PlatformSigningSubjectError(
            "platform-signing archive is not one regular file"
        )
    os.lseek(descriptor, 0, os.SEEK_SET)
    digest = hashlib.sha256()
    size = 0
    while True:
        chunk = os.read(descriptor, 1024 * 1024)
        if not chunk:
            break
        size += len(chunk)
        digest.update(chunk)
    after = os.fstat(descriptor)
    identity = _descriptor_identity(after)
    if size != after.st_size or _descriptor_identity(before) != identity:
        raise PlatformSigningSubjectError(
            "platform-signing archive changed during hashing"
        )
    return digest.hexdigest(), size, identity


def _validate_private_directory(path: Path, *, exact_mode: int) -> None:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise PlatformSigningSubjectError(
            "platform-signing private directory is unavailable"
        ) from error
    if (
        not stat.S_ISDIR(metadata.st_mode)
        or stat.S_ISLNK(metadata.st_mode)
        or stat.S_IMODE(metadata.st_mode) != exact_mode
        or metadata.st_uid != os.geteuid()
    ):
        raise PlatformSigningSubjectError(
            "platform-signing private directory has unsafe ownership or mode"
        )


def _entry_mode(entry: dict[str, Any]) -> int:
    try:
        mode = int(entry["mode"], 8)
    except (KeyError, TypeError, ValueError) as error:
        raise PlatformSigningSubjectError(
            "artifact composition mode is invalid"
        ) from error
    if mode & 0o7000:
        raise PlatformSigningSubjectError(
            "artifact composition contains special permission bits"
        )
    if entry.get("type") != "symlink" and mode & 0o022:
        raise PlatformSigningSubjectError(
            "artifact composition contains writable contamination"
        )
    if entry.get("type") == "symlink" and mode != 0o777:
        raise PlatformSigningSubjectError(
            "artifact symlink mode cannot be reconstructed exactly"
        )
    return mode


def _required_directories(entries: list[dict[str, Any]]) -> set[str]:
    directories = {
        entry["path"]
        for entry in entries
        if entry.get("type") == "directory"
    }
    non_directories = {
        entry["path"]
        for entry in entries
        if entry.get("type") != "directory"
    }
    required: set[str] = set(directories)
    for entry in entries:
        parts = entry["path"].split("/")[:-1]
        for index in range(1, len(parts) + 1):
            ancestor = "/".join(parts[:index])
            if ancestor in non_directories:
                raise PlatformSigningSubjectError(
                    "artifact composition has a non-directory ancestor"
                )
            required.add(ancestor)
    return required


def _archive_infos(
    archive: zipfile.ZipFile,
    entries: list[dict[str, Any]],
) -> dict[str, zipfile.ZipInfo]:
    infos = archive.infolist()
    if not infos or len(infos) != len(entries) or len(infos) > MAX_ENTRIES:
        raise PlatformSigningSubjectError(
            "archive entry count differs from artifact composition"
        )
    by_path: dict[str, zipfile.ZipInfo] = {}
    for info in infos:
        path = info.filename[:-1] if info.filename.endswith("/") else info.filename
        try:
            path = safe_relative_path(path, "platform-signing archive member")
        except ArtifactSBOMError as error:
            raise PlatformSigningSubjectError(str(error)) from error
        if path in by_path:
            raise PlatformSigningSubjectError(
                "archive contains a duplicate reconstructed path"
            )
        by_path[path] = info
    if set(by_path) != {entry["path"] for entry in entries}:
        raise PlatformSigningSubjectError(
            "archive paths differ from artifact composition"
        )
    return by_path


def _verify_info(
    info: zipfile.ZipInfo,
    entry: dict[str, Any],
    expected_mode: int,
) -> None:
    unix_mode = (info.external_attr >> 16) & 0xFFFF
    permissions = stat.S_IMODE(unix_mode)
    file_type = stat.S_IFMT(unix_mode)
    expected_type = entry["type"]
    type_matches = (
        (expected_type == "directory" and file_type == stat.S_IFDIR)
        or (expected_type == "regularFile" and file_type == stat.S_IFREG)
        or (expected_type == "symlink" and file_type == stat.S_IFLNK)
    )
    if not type_matches or permissions != expected_mode:
        raise PlatformSigningSubjectError(
            "archive member type or mode differs from artifact composition"
        )
    if info.file_size != entry["bytes"]:
        raise PlatformSigningSubjectError(
            "archive member size differs from artifact composition"
        )


def _stream_regular_file(
    archive: zipfile.ZipFile,
    info: zipfile.ZipInfo,
    destination: Path,
    entry: dict[str, Any],
    mode: int,
) -> None:
    try:
        descriptor = os.open(
            destination,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            0o600,
        )
    except OSError as error:
        raise PlatformSigningSubjectError(
            "reconstructed regular-file path is unavailable"
        ) from error
    sha1 = hashlib.sha1()
    sha256 = hashlib.sha256()
    size = 0
    try:
        with archive.open(info, "r") as source:
            while True:
                chunk = source.read(1024 * 1024)
                if not chunk:
                    break
                size += len(chunk)
                if size > entry["bytes"]:
                    raise PlatformSigningSubjectError(
                        "reconstructed regular file exceeded its bound"
                    )
                sha1.update(chunk)
                sha256.update(chunk)
                cursor = 0
                while cursor < len(chunk):
                    cursor += os.write(descriptor, chunk[cursor:])
        if (
            size != entry["bytes"]
            or sha1.hexdigest() != entry["sha1"]
            or sha256.hexdigest() != entry["sha256"]
        ):
            raise PlatformSigningSubjectError(
                "reconstructed regular-file digest differs from composition"
            )
        os.fchmod(descriptor, mode)
        os.fsync(descriptor)
        metadata = os.fstat(descriptor)
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_nlink != 1
            or stat.S_IMODE(metadata.st_mode) != mode
            or metadata.st_size != size
        ):
            raise PlatformSigningSubjectError(
                "reconstructed regular file has unsafe filesystem facts"
            )
    finally:
        os.close(descriptor)


def _read_symlink_target(
    archive: zipfile.ZipFile,
    info: zipfile.ZipInfo,
    entry: dict[str, Any],
) -> str:
    if entry["bytes"] > 4096:
        raise PlatformSigningSubjectError(
            "reconstructed symlink target exceeds the profile"
        )
    with archive.open(info, "r") as source:
        raw = source.read(4097)
        if source.read(1):
            raise PlatformSigningSubjectError(
                "reconstructed symlink target exceeded its bound"
            )
    if (
        len(raw) != entry["bytes"]
        or hashlib.sha1(raw).hexdigest() != entry["sha1"]
        or hashlib.sha256(raw).hexdigest() != entry["sha256"]
    ):
        raise PlatformSigningSubjectError(
            "reconstructed symlink digest differs from composition"
        )
    try:
        target = raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise PlatformSigningSubjectError(
            "reconstructed symlink target is not UTF-8"
        ) from error
    if target != entry["symlinkTarget"]:
        raise PlatformSigningSubjectError(
            "reconstructed symlink target differs from composition"
        )
    return target


def _list_extended_attributes(path: Path) -> list[str]:
    attributes: list[str]
    if hasattr(os, "listxattr"):
        try:
            attributes = os.listxattr(path, follow_symlinks=False)
        except OSError as error:
            raise PlatformSigningSubjectError(
                "reconstructed path extended attributes are unavailable"
            ) from error
    elif sys.platform == "darwin":
        library = ctypes.CDLL(None, use_errno=True)
        function = library.listxattr
        function.argtypes = [
            ctypes.c_char_p,
            ctypes.c_void_p,
            ctypes.c_size_t,
            ctypes.c_int,
        ]
        function.restype = ctypes.c_ssize_t
        encoded_path = os.fsencode(path)
        required = function(encoded_path, None, 0, DARWIN_XATTR_NOFOLLOW)
        if required < 0:
            error_number = ctypes.get_errno()
            raise PlatformSigningSubjectError(
                "reconstructed path extended attributes are unavailable"
            ) from OSError(error_number, os.strerror(error_number))
        if required == 0:
            attributes = []
        else:
            buffer = ctypes.create_string_buffer(required)
            received = function(
                encoded_path,
                buffer,
                required,
                DARWIN_XATTR_NOFOLLOW,
            )
            if received != required:
                raise PlatformSigningSubjectError(
                    "reconstructed path extended attributes changed during inspection"
                )
            attributes = [
                os.fsdecode(value)
                for value in buffer.raw[:received].split(b"\0")
                if value
            ]
    else:
        raise PlatformSigningSubjectError(
            "reconstructed path extended attributes are unavailable"
        )
    return attributes


def _read_extended_attribute(path: Path, attribute: str) -> bytes:
    if hasattr(os, "getxattr"):
        try:
            return os.getxattr(path, attribute, follow_symlinks=False)
        except OSError as error:
            raise PlatformSigningSubjectError(
                "reconstructed provenance attribute could not be read"
            ) from error
    if sys.platform != "darwin":
        raise PlatformSigningSubjectError(
            "reconstructed provenance attribute could not be read"
        )
    library = ctypes.CDLL(None, use_errno=True)
    function = library.getxattr
    function.argtypes = [
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.c_void_p,
        ctypes.c_size_t,
        ctypes.c_uint32,
        ctypes.c_int,
    ]
    function.restype = ctypes.c_ssize_t
    encoded_path = os.fsencode(path)
    encoded_attribute = os.fsencode(attribute)
    ctypes.set_errno(0)
    required = function(
        encoded_path,
        encoded_attribute,
        None,
        0,
        0,
        DARWIN_XATTR_NOFOLLOW,
    )
    if required < 0 or required > 4096:
        error_number = ctypes.get_errno()
        raise PlatformSigningSubjectError(
            "reconstructed provenance attribute could not be read"
        ) from OSError(error_number, os.strerror(error_number))
    buffer = ctypes.create_string_buffer(required)
    received = function(
        encoded_path,
        encoded_attribute,
        buffer,
        required,
        0,
        DARWIN_XATTR_NOFOLLOW,
    )
    if received != required:
        raise PlatformSigningSubjectError(
            "reconstructed provenance attribute changed during inspection"
        )
    return buffer.raw[:received]


def _private_root_provenance(path: Path) -> bytes | None:
    attributes = _list_extended_attributes(path)
    if not attributes:
        return None
    if set(attributes) != {PROVENANCE_XATTR} or len(attributes) != 1:
        raise PlatformSigningSubjectError(
            "platform-signing private root contains extended-attribute contamination"
        )
    value = _read_extended_attribute(path, PROVENANCE_XATTR)
    if not value:
        raise PlatformSigningSubjectError(
            "platform-signing private root provenance attribute is empty"
        )
    if _list_extended_attributes(path) != [PROVENANCE_XATTR]:
        raise PlatformSigningSubjectError(
            "platform-signing private root attributes changed during inspection"
        )
    return value


def _require_permitted_extended_attributes(
    path: Path,
    expected_provenance: bytes | None,
) -> bool:
    attributes = _list_extended_attributes(path)
    if not attributes:
        return False
    if set(attributes) != {PROVENANCE_XATTR} or len(attributes) != 1:
        raise PlatformSigningSubjectError(
            "reconstructed path contains extended-attribute contamination"
        )
    if (
        expected_provenance is None
        or _read_extended_attribute(path, PROVENANCE_XATTR)
        != expected_provenance
    ):
        raise PlatformSigningSubjectError(
            "reconstructed provenance attribute differs from the private root"
        )
    if _list_extended_attributes(path) != [PROVENANCE_XATTR]:
        raise PlatformSigningSubjectError(
            "reconstructed path extended attributes changed during inspection"
        )
    return True


def _inventory_reconstruction(
    artifact_root: Path,
    entries: list[dict[str, Any]],
    synthetic_directories: set[str],
    expected_provenance: bytes | None,
) -> tuple[list[dict[str, Any]], int]:
    inventory: list[dict[str, Any]] = []
    provenance_path_count = 0
    for entry in entries:
        path = artifact_root / entry["path"]
        metadata = path.lstat()
        mode = _entry_mode(entry)
        provenance_path_count += int(
            _require_permitted_extended_attributes(path, expected_provenance)
        )
        if entry["type"] == "directory":
            if not stat.S_ISDIR(metadata.st_mode) or stat.S_IMODE(metadata.st_mode) != mode:
                raise PlatformSigningSubjectError(
                    "reconstructed directory differs from composition"
                )
            observed = dict(entry)
        elif entry["type"] == "regularFile":
            if (
                not stat.S_ISREG(metadata.st_mode)
                or metadata.st_nlink != 1
                or stat.S_IMODE(metadata.st_mode) != mode
            ):
                raise PlatformSigningSubjectError(
                    "reconstructed regular file differs from composition"
                )
            sha1 = hashlib.sha1()
            sha256 = hashlib.sha256()
            size = 0
            with path.open("rb") as handle:
                for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                    size += len(chunk)
                    sha1.update(chunk)
                    sha256.update(chunk)
            observed = {
                "path": entry["path"],
                "type": "regularFile",
                "mode": f"{mode:04o}",
                "bytes": size,
                "sha1": sha1.hexdigest(),
                "sha256": sha256.hexdigest(),
                "symlinkTarget": None,
            }
        else:
            filesystem_mode = stat.S_IMODE(metadata.st_mode)
            expected_filesystem_mode = 0o755 if sys.platform == "darwin" else mode
            if (
                not stat.S_ISLNK(metadata.st_mode)
                or filesystem_mode != expected_filesystem_mode
            ):
                raise PlatformSigningSubjectError(
                    "reconstructed symlink differs from composition"
                )
            target = os.readlink(path)
            raw = target.encode("utf-8")
            observed = {
                "path": entry["path"],
                "type": "symlink",
                "mode": f"{mode:04o}",
                "bytes": len(raw),
                "sha1": hashlib.sha1(raw).hexdigest(),
                "sha256": hashlib.sha256(raw).hexdigest(),
                "symlinkTarget": target,
            }
        if observed != entry:
            raise PlatformSigningSubjectError(
                "reconstructed entry differs from exact composition"
            )
        inventory.append(observed)

    resolved_root = artifact_root.resolve(strict=True)
    for entry in entries:
        if entry["type"] != "symlink":
            continue
        resolved = (artifact_root / entry["path"]).resolve(strict=True)
        if resolved != resolved_root and resolved_root not in resolved.parents:
            raise PlatformSigningSubjectError(
                "reconstructed symlink topology escapes its artifact root"
            )
    for relative in synthetic_directories:
        path = artifact_root / relative
        metadata = path.lstat()
        provenance_path_count += int(
            _require_permitted_extended_attributes(path, expected_provenance)
        )
        if (
            not stat.S_ISDIR(metadata.st_mode)
            or stat.S_IMODE(metadata.st_mode) != 0o755
        ):
            raise PlatformSigningSubjectError(
                "synthetic parent directory differs from the fixed profile"
            )
    return inventory, provenance_path_count


def _reconstruct_artifact(
    *,
    binding: dict[str, Any],
    entries: list[dict[str, Any]],
    graph_artifact: dict[str, Any],
    evidence_root: Path,
    subjects_root: Path,
    expected_provenance: bytes | None,
) -> ReconstructedSigningSubject:
    artifact_id = binding.get("id")
    if not isinstance(artifact_id, str) or not artifact_id:
        raise PlatformSigningSubjectError("artifact binding lacks an ID")
    if graph_artifact.get("artifact") != binding:
        raise PlatformSigningSubjectError(
            "signed-code graph artifact binding differs from the SBOM"
        )
    try:
        archive_relative = safe_relative_path(
            binding["path"], "platform-signing archive path"
        )
        subject_root = safe_relative_path(
            graph_artifact["subjectRoot"], "platform-signing subject root"
        )
    except (ArtifactSBOMError, KeyError) as error:
        raise PlatformSigningSubjectError(str(error)) from error
    if graph_artifact.get("platformAcceptanceEligible") is not False:
        raise PlatformSigningSubjectError(
            "construction graph may not claim platform acceptance"
        )
    try:
        archive_path = evidence_root.resolve(strict=True) / archive_relative
        resolved_archive = archive_path.resolve(strict=True)
    except OSError as error:
        raise PlatformSigningSubjectError(
            "platform-signing archive path is unavailable"
        ) from error
    if archive_path.absolute() != resolved_archive or archive_path.is_symlink():
        raise PlatformSigningSubjectError(
            "platform-signing archive path contains a link"
        )
    try:
        descriptor = os.open(archive_path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError as error:
        raise PlatformSigningSubjectError(
            "platform-signing archive could not be opened"
        ) from error
    artifact_root = subjects_root / artifact_id
    try:
        artifact_root.mkdir(mode=0o700)
    except OSError as error:
        raise PlatformSigningSubjectError(
            "reconstructed artifact root already exists or is unavailable"
        ) from error
    _validate_private_directory(artifact_root, exact_mode=0o700)

    try:
        before_digest, before_size, before_identity = _digest_descriptor(descriptor)
        if (
            before_digest != binding.get("sha256")
            or before_size != binding.get("bytes")
        ):
            raise PlatformSigningSubjectError(
                "platform-signing archive differs from its SBOM binding"
            )
        if not isinstance(entries, list) or not entries or len(entries) > MAX_ENTRIES:
            raise PlatformSigningSubjectError(
                "artifact composition entry set is outside the profile"
            )
        required_directories = _required_directories(entries)
        explicit_directories = {
            entry["path"]: _entry_mode(entry)
            for entry in entries
            if entry.get("type") == "directory"
        }
        synthetic_directories = required_directories - set(explicit_directories)
        for relative in sorted(required_directories, key=lambda value: (value.count("/"), value)):
            path = artifact_root / relative
            path.mkdir(mode=0o700)

        with os.fdopen(os.dup(descriptor), "rb") as archive_handle:
            with zipfile.ZipFile(archive_handle, "r") as archive:
                infos = _archive_infos(archive, entries)
                modes = {entry["path"]: _entry_mode(entry) for entry in entries}
                for entry in entries:
                    _verify_info(infos[entry["path"]], entry, modes[entry["path"]])
                for entry in entries:
                    if entry["type"] != "regularFile":
                        continue
                    _stream_regular_file(
                        archive,
                        infos[entry["path"]],
                        artifact_root / entry["path"],
                        entry,
                        modes[entry["path"]],
                    )
                for entry in entries:
                    if entry["type"] != "symlink":
                        continue
                    target = _read_symlink_target(
                        archive,
                        infos[entry["path"]],
                        entry,
                    )
                    try:
                        os.symlink(target, artifact_root / entry["path"])
                    except OSError as error:
                        raise PlatformSigningSubjectError(
                            "reconstructed symlink path is unavailable"
                        ) from error

        for relative in sorted(required_directories, key=lambda value: (-value.count("/"), value)):
            os.chmod(
                artifact_root / relative,
                explicit_directories.get(relative, 0o755),
                follow_symlinks=False,
            )
        root_has_provenance = _require_permitted_extended_attributes(
            artifact_root,
            expected_provenance,
        )
        inventory, provenance_path_count = _inventory_reconstruction(
            artifact_root,
            entries,
            synthetic_directories,
            expected_provenance,
        )
        provenance_path_count += int(root_has_provenance)
        subject_path = artifact_root / subject_root
        if not subject_path.is_dir() or subject_path.is_symlink():
            raise PlatformSigningSubjectError(
                "graph distribution subject is absent after reconstruction"
            )
        before_composition = hashlib.sha256(
            canonical_bytes({"id": artifact_id, "entries": entries})
        ).hexdigest()
        after_composition = hashlib.sha256(
            canonical_bytes({"id": artifact_id, "entries": inventory})
        ).hexdigest()
        if before_composition != after_composition:
            raise PlatformSigningSubjectError(
                "reconstructed composition digest does not match the SBOM"
            )
        after_digest, after_size, after_identity = _digest_descriptor(descriptor)
        path_identity = _descriptor_identity(archive_path.lstat())
        if (
            (before_digest, before_size, before_identity)
            != (after_digest, after_size, after_identity)
            or path_identity != before_identity
        ):
            raise PlatformSigningSubjectError(
                "platform-signing archive changed during reconstruction"
            )
    except PlatformSigningSubjectError:
        raise
    except (
        AttributeError,
        KeyError,
        OSError,
        RuntimeError,
        TypeError,
        ValueError,
        zipfile.BadZipFile,
    ) as error:
        raise PlatformSigningSubjectError(
            "platform-signing artifact reconstruction failed"
        ) from error
    finally:
        os.close(descriptor)

    return ReconstructedSigningSubject(
        artifact_id=artifact_id,
        platform=binding["platform"],
        artifact_root=artifact_root,
        subject_root=subject_root,
        entry_count=len(entries),
        composition_sha256=before_composition,
        synthetic_directories=tuple(sorted(synthetic_directories)),
        provenance_path_count=provenance_path_count,
        provenance_sha256=(
            hashlib.sha256(expected_provenance).hexdigest()
            if expected_provenance is not None
            else None
        ),
    )


def reconstruct_signing_subjects(
    *,
    index: dict[str, Any],
    composition: dict[str, Any],
    graph: dict[str, Any],
    evidence_root: Path,
    work_root: Path,
) -> list[ReconstructedSigningSubject]:
    _validate_private_directory(work_root, exact_mode=0o700)
    expected_provenance = _private_root_provenance(work_root)
    subjects_root = work_root / "subjects"
    try:
        subjects_root.mkdir(mode=0o700)
    except OSError as error:
        raise PlatformSigningSubjectError(
            "platform-signing subjects root already exists or is unavailable"
        ) from error
    _validate_private_directory(subjects_root, exact_mode=0o700)
    _require_permitted_extended_attributes(
        subjects_root,
        expected_provenance,
    )

    bindings = index.get("artifacts")
    compositions = composition.get("artifacts")
    graph_artifacts = graph.get("artifacts")
    if (
        not isinstance(bindings, list)
        or not isinstance(compositions, list)
        or not isinstance(graph_artifacts, list)
        or not 1 <= len(graph_artifacts) <= MAX_RECONSTRUCTED_ARTIFACTS
    ):
        raise PlatformSigningSubjectError(
            "platform-signing artifact inputs are outside the profile"
        )
    if (
        graph.get("release") != index.get("release")
        or graph.get("source") != index.get("source")
    ):
        raise PlatformSigningSubjectError(
            "signed-code graph release or source differs from the SBOM"
        )
    if any(
        not isinstance(item, dict)
        or not isinstance(item.get("id"), str)
        or not item["id"]
        for item in bindings
    ):
        raise PlatformSigningSubjectError(
            "platform-signing artifact bindings are invalid"
        )
    if any(
        not isinstance(item, dict)
        or not isinstance(item.get("id"), str)
        or not item["id"]
        for item in compositions
    ):
        raise PlatformSigningSubjectError(
            "platform-signing artifact compositions are invalid"
        )
    binding_by_id = {item["id"]: item for item in bindings}
    composition_by_id = {
        item["id"]: item.get("entries") for item in compositions
    }
    if len(binding_by_id) != len(bindings) or len(composition_by_id) != len(compositions):
        raise PlatformSigningSubjectError(
            "platform-signing artifact IDs are ambiguous"
        )
    reconstructed: list[ReconstructedSigningSubject] = []
    expected_primary_ids = {
        item["id"] for item in bindings if item.get("kind") in PRIMARY_KINDS
    }
    if not expected_primary_ids:
        raise PlatformSigningSubjectError(
            "platform-signing SBOM contains no primary artifacts"
        )
    seen: set[str] = set()
    for graph_artifact in graph_artifacts:
        if not isinstance(graph_artifact, dict):
            raise PlatformSigningSubjectError(
                "signed-code graph artifact is not an object"
            )
        graph_binding = graph_artifact.get("artifact")
        artifact_id = graph_binding.get("id") if isinstance(graph_binding, dict) else None
        if (
            not isinstance(artifact_id, str)
            or artifact_id in seen
            or artifact_id not in binding_by_id
            or artifact_id not in composition_by_id
        ):
            raise PlatformSigningSubjectError(
                "signed-code graph artifact set differs from the SBOM"
            )
        seen.add(artifact_id)
        reconstructed.append(
            _reconstruct_artifact(
                binding=binding_by_id[artifact_id],
                entries=composition_by_id[artifact_id],
                graph_artifact=graph_artifact,
                evidence_root=evidence_root,
                subjects_root=subjects_root,
                expected_provenance=expected_provenance,
            )
        )
    if seen != expected_primary_ids:
        raise PlatformSigningSubjectError(
            "signed-code graph artifact set differs from the SBOM"
        )
    return reconstructed


def derive_codesign_verification_plans(
    *,
    graph: dict[str, Any],
    reconstructed: list[ReconstructedSigningSubject],
    team_id: str,
    codesign_tool: FixedToolIdentity,
) -> list[PlannedCodeSignVerification]:
    if TEAM_ID_PATTERN.fullmatch(team_id) is None:
        raise PlatformSigningSubjectError(
            "signing-policy Team ID is outside the fixed profile"
        )
    if codesign_tool.tool_id != "apple.codesign" or codesign_tool.path != "/usr/bin/codesign":
        raise PlatformSigningSubjectError(
            "codesign plan requires the pinned absolute Apple tool"
        )
    reconstructed_by_id = {item.artifact_id: item for item in reconstructed}
    if len(reconstructed_by_id) != len(reconstructed):
        raise PlatformSigningSubjectError(
            "reconstructed signing subjects contain duplicate artifacts"
        )
    requirement = CODESIGN_REQUIREMENT_PREFIX + f'"{team_id}"'
    plans: list[PlannedCodeSignVerification] = []
    graph_artifacts = graph.get("artifacts")
    if not isinstance(graph_artifacts, list):
        raise PlatformSigningSubjectError(
            "signed-code graph artifact set is unavailable"
        )
    for artifact_index, graph_artifact in enumerate(graph_artifacts):
        if not isinstance(graph_artifact, dict):
            raise PlatformSigningSubjectError(
                "signed-code graph artifact is not an object"
            )
        binding = graph_artifact.get("artifact")
        artifact_id = binding.get("id") if isinstance(binding, dict) else None
        subject = reconstructed_by_id.get(artifact_id)
        objects = graph_artifact.get("machOObjects")
        graph_plan = graph_artifact.get("verificationPlan")
        if subject is None or not isinstance(objects, list) or not isinstance(graph_plan, list):
            raise PlatformSigningSubjectError(
                "signed-code graph cannot be bound to reconstructed subjects"
            )
        if any(not isinstance(item, dict) for item in objects):
            raise PlatformSigningSubjectError(
                "signed-code graph Mach-O object is not an object"
            )
        selected = [
            item for item in objects
            if item.get("inDistributionSubject") is True
        ]
        if any(not isinstance(item.get("path"), str) for item in selected):
            raise PlatformSigningSubjectError(
                "signed-code graph Mach-O object path is invalid"
            )
        selected.sort(
            key=lambda item: (-item["path"].count("/"), item["path"])
        )
        expected_steps = [
            step
            for step in graph_plan
            if isinstance(step, dict) and step.get("action") == "verifyObjectAllArchitectures"
        ]
        expected_paths: list[str] = []
        for step in expected_steps:
            if (
                step.get("toolID") != "apple.codesign"
                or step.get("artifactID") != artifact_id
                or step.get("architectureSelector") is not None
                or step.get("status") != "notRun"
            ):
                raise PlatformSigningSubjectError(
                    "graph codesign verification step is not fixed and inert"
                )
            object_path = step.get("objectPath")
            if not isinstance(object_path, str):
                raise PlatformSigningSubjectError(
                    "graph codesign verification object path is invalid"
                )
            expected_paths.append(object_path)
        derived_paths: list[str] = []
        for object_index, item in enumerate(selected):
            try:
                source_path = safe_relative_path(
                    item["path"], "graph Mach-O object path"
                )
                object_path = safe_relative_path(
                    item.get("bundleMainFor") or source_path,
                    "graph codesign verification subject",
                )
            except (ArtifactSBOMError, KeyError) as error:
                raise PlatformSigningSubjectError(str(error)) from error
            if not source_path.startswith(subject.subject_root + "/"):
                raise PlatformSigningSubjectError(
                    "graph Mach-O object is outside its distribution subject"
                )
            if (
                object_path != subject.subject_root
                and not object_path.startswith(subject.subject_root + "/")
            ):
                raise PlatformSigningSubjectError(
                    "graph codesign subject is outside its distribution subject"
                )
            owned_path = subject.artifact_root / object_path
            try:
                resolved = owned_path.resolve(strict=True)
                resolved_root = subject.artifact_root.resolve(strict=True)
            except OSError as error:
                raise PlatformSigningSubjectError(
                    "graph codesign verification subject is unavailable"
                ) from error
            if (
                (resolved != resolved_root and resolved_root not in resolved.parents)
                or owned_path.is_symlink()
                or not (owned_path.is_file() or owned_path.is_dir())
            ):
                raise PlatformSigningSubjectError(
                    "graph codesign verification subject is unsafe"
                )
            derived_paths.append(object_path)
            invocation_id = (
                f"codesign-verify-{artifact_index + 1:02d}-{object_index + 1:04d}"
            )
            invocation = FixedToolInvocation(
                invocation_id=invocation_id,
                tool=codesign_tool,
                arguments=(
                    "--verify",
                    "--strict",
                    "--all-architectures",
                    "--verbose=4",
                    "--test-requirement",
                    requirement,
                    str(owned_path),
                ),
                timeout_seconds=120,
            )
            plans.append(
                PlannedCodeSignVerification(
                    artifact_id=artifact_id,
                    object_path=object_path,
                    owned_subject_path=owned_path,
                    source_depth=source_path.count("/"),
                    invocation=invocation,
                )
            )
            if len(plans) > MAX_CODESIGN_PLANS:
                raise PlatformSigningSubjectError(
                    "codesign verification plan exceeds the profile"
                )
        if derived_paths != expected_paths:
            raise PlatformSigningSubjectError(
                "derived codesign order differs from the signed-code graph"
            )
    if set(reconstructed_by_id) != {
        item.artifact_id for item in plans
    }:
        raise PlatformSigningSubjectError(
            "codesign verification plan does not cover every reconstructed artifact"
        )
    return plans


def derive_codesign_outer_verification_plans(
    *,
    graph: dict[str, Any],
    reconstructed: list[ReconstructedSigningSubject],
    codesign_tool: FixedToolIdentity,
) -> list[PlannedCodeSignOuterVerification]:
    if codesign_tool.tool_id != "apple.codesign" or codesign_tool.path != "/usr/bin/codesign":
        raise PlatformSigningSubjectError(
            "outer codesign verification requires the pinned absolute Apple tool"
        )
    reconstructed_by_id = {item.artifact_id: item for item in reconstructed}
    if len(reconstructed_by_id) != len(reconstructed):
        raise PlatformSigningSubjectError(
            "reconstructed signing subjects contain duplicate artifacts"
        )
    graph_artifacts = graph.get("artifacts")
    if not isinstance(graph_artifacts, list):
        raise PlatformSigningSubjectError(
            "signed-code graph artifact set is unavailable"
        )
    plans: list[PlannedCodeSignOuterVerification] = []
    mac_artifact_ids: set[str] = set()
    for artifact_index, graph_artifact in enumerate(graph_artifacts):
        if not isinstance(graph_artifact, dict):
            raise PlatformSigningSubjectError(
                "signed-code graph artifact is not an object"
            )
        binding = graph_artifact.get("artifact")
        if not isinstance(binding, dict):
            raise PlatformSigningSubjectError(
                "signed-code graph artifact binding is invalid"
            )
        artifact_id = binding.get("id")
        platform = binding.get("platform")
        kind = binding.get("kind")
        if platform != "macOS":
            continue
        if kind != "macApplication" or not isinstance(artifact_id, str):
            raise PlatformSigningSubjectError(
                "outer codesign verification requires one Mac application binding"
            )
        if artifact_id in mac_artifact_ids:
            raise PlatformSigningSubjectError(
                "outer codesign verification artifact is ambiguous"
            )
        mac_artifact_ids.add(artifact_id)
        subject = reconstructed_by_id.get(artifact_id)
        subject_root = graph_artifact.get("subjectRoot")
        if (
            subject is None
            or subject.platform != "macOS"
            or subject.subject_root != subject_root
            or not isinstance(subject_root, str)
            or not subject_root.endswith(".app")
        ):
            raise PlatformSigningSubjectError(
                "outer codesign verification lacks its reconstructed Mac application"
            )
        owned_path = subject.subject_path
        try:
            resolved_root = subject.artifact_root.resolve(strict=True)
            resolved = owned_path.resolve(strict=True)
        except OSError as error:
            raise PlatformSigningSubjectError(
                "outer codesign verification subject is unavailable"
            ) from error
        if (
            resolved_root not in resolved.parents
            or owned_path.is_symlink()
            or not owned_path.is_dir()
        ):
            raise PlatformSigningSubjectError(
                "outer codesign verification subject is unsafe"
            )
        invocation = FixedToolInvocation(
            invocation_id=f"codesign-outer-{artifact_index + 1:02d}",
            tool=codesign_tool,
            arguments=(
                "--verify",
                "--deep",
                "--strict",
                "--all-architectures",
                "--verbose=4",
                str(owned_path),
            ),
            timeout_seconds=300,
        )
        plans.append(
            PlannedCodeSignOuterVerification(
                artifact_id=artifact_id,
                owned_subject_path=owned_path,
                invocation=invocation,
            )
        )
    expected_mac_ids = {
        subject.artifact_id
        for subject in reconstructed
        if subject.platform == "macOS"
    }
    if mac_artifact_ids != expected_mac_ids or len(plans) > 1:
        raise PlatformSigningSubjectError(
            "outer codesign verification does not exactly cover the Mac application"
        )
    return plans


def derive_mac_platform_assessment_plans(
    *,
    graph: dict[str, Any],
    reconstructed: list[ReconstructedSigningSubject],
    codesign_tool: FixedToolIdentity,
    gatekeeper_tool: FixedToolIdentity,
    stapler_tool: FixedToolIdentity,
) -> list[PlannedMacPlatformAssessment]:
    if (
        gatekeeper_tool.tool_id != "apple.spctl"
        or gatekeeper_tool.path != "/usr/sbin/spctl"
    ):
        raise PlatformSigningSubjectError(
            "Mac platform assessment requires the pinned Gatekeeper tool"
        )
    if (
        stapler_tool.tool_id != "apple.stapler"
        or stapler_tool.path
        not in {
            "/Applications/Xcode.app/Contents/Developer/usr/bin/stapler",
            "/Applications/Xcode-beta.app/Contents/Developer/usr/bin/stapler",
        }
    ):
        raise PlatformSigningSubjectError(
            "Mac platform assessment requires the pinned Xcode stapler tool"
        )
    try:
        outer_subjects = derive_codesign_outer_verification_plans(
            graph=graph,
            reconstructed=reconstructed,
            codesign_tool=codesign_tool,
        )
    except PlatformSigningSubjectError as error:
        raise PlatformSigningSubjectError(
            "Mac platform assessment subject could not be rederived"
        ) from error
    plans: list[PlannedMacPlatformAssessment] = []
    for index, outer in enumerate(outer_subjects):
        subject = str(outer.owned_subject_path)
        plans.append(
            PlannedMacPlatformAssessment(
                artifact_id=outer.artifact_id,
                owned_subject_path=outer.owned_subject_path,
                gatekeeper_invocation=FixedToolInvocation(
                    invocation_id=f"spctl-assess-{index + 1:02d}",
                    tool=gatekeeper_tool,
                    arguments=(
                        "--assess",
                        "--type",
                        "execute",
                        "--verbose=4",
                        subject,
                    ),
                    timeout_seconds=120,
                ),
                stapler_invocation=FixedToolInvocation(
                    invocation_id=f"stapler-validate-{index + 1:02d}",
                    tool=stapler_tool,
                    arguments=("validate", subject),
                    timeout_seconds=120,
                ),
            )
        )
    return plans


def derive_codesign_architecture_inspection_plans(
    *,
    graph: dict[str, Any],
    reconstructed: list[ReconstructedSigningSubject],
    codesign_tool: FixedToolIdentity,
) -> list[PlannedCodeSignArchitectureInspection]:
    if codesign_tool.tool_id != "apple.codesign" or codesign_tool.path != "/usr/bin/codesign":
        raise PlatformSigningSubjectError(
            "codesign inspection requires the pinned absolute Apple tool"
        )
    reconstructed_by_id = {item.artifact_id: item for item in reconstructed}
    if len(reconstructed_by_id) != len(reconstructed):
        raise PlatformSigningSubjectError(
            "reconstructed signing subjects contain duplicate artifacts"
        )
    graph_artifacts = graph.get("artifacts")
    if not isinstance(graph_artifacts, list):
        raise PlatformSigningSubjectError(
            "signed-code graph artifact set is unavailable"
        )
    plans: list[PlannedCodeSignArchitectureInspection] = []
    for artifact_index, graph_artifact in enumerate(graph_artifacts):
        if not isinstance(graph_artifact, dict):
            raise PlatformSigningSubjectError(
                "signed-code graph artifact is not an object"
            )
        binding = graph_artifact.get("artifact")
        artifact_id = binding.get("id") if isinstance(binding, dict) else None
        subject = reconstructed_by_id.get(artifact_id)
        objects = graph_artifact.get("machOObjects")
        graph_plan = graph_artifact.get("verificationPlan")
        if subject is None or not isinstance(objects, list) or not isinstance(graph_plan, list):
            raise PlatformSigningSubjectError(
                "signed-code graph cannot be bound to inspection subjects"
            )
        selected = [
            item for item in objects
            if isinstance(item, dict) and item.get("inDistributionSubject") is True
        ]
        if len(selected) != sum(
            1
            for item in objects
            if isinstance(item, dict) and item.get("inDistributionSubject") is True
        ) or any(not isinstance(item, dict) for item in objects):
            raise PlatformSigningSubjectError(
                "signed-code graph Mach-O object is not an object"
            )
        selected.sort(key=lambda item: (-item.get("path", "").count("/"), item.get("path", "")))
        expected_steps = [
            step
            for step in graph_plan
            if isinstance(step, dict)
            and step.get("action") in {"reportIdentityAndRequirements", "reportEntitlements"}
        ]
        if len(expected_steps) != sum(
            1
            for step in graph_plan
            if isinstance(step, dict)
            and step.get("action") in {"reportIdentityAndRequirements", "reportEntitlements"}
        ):
            raise PlatformSigningSubjectError(
                "graph codesign inspection step is not an object"
            )
        derived_steps: list[dict[str, Any]] = []
        for object_index, item in enumerate(selected):
            architectures = item.get("machO", {}).get("architectures")
            if not isinstance(architectures, list) or not architectures:
                raise PlatformSigningSubjectError(
                    "graph codesign inspection architectures are unavailable"
                )
            try:
                source_path = safe_relative_path(
                    item["path"], "graph Mach-O object path"
                )
                object_path = safe_relative_path(
                    item.get("bundleMainFor") or source_path,
                    "graph codesign inspection subject",
                )
            except (ArtifactSBOMError, KeyError) as error:
                raise PlatformSigningSubjectError(str(error)) from error
            if not source_path.startswith(subject.subject_root + "/"):
                raise PlatformSigningSubjectError(
                    "graph Mach-O object is outside its distribution subject"
                )
            if (
                object_path != subject.subject_root
                and not object_path.startswith(subject.subject_root + "/")
            ):
                raise PlatformSigningSubjectError(
                    "graph codesign inspection subject is outside its distribution subject"
                )
            owned_source_path = subject.artifact_root / source_path
            owned_subject_path = subject.artifact_root / object_path
            try:
                resolved_root = subject.artifact_root.resolve(strict=True)
                resolved_source = owned_source_path.resolve(strict=True)
                resolved_subject = owned_subject_path.resolve(strict=True)
            except OSError as error:
                raise PlatformSigningSubjectError(
                    "graph codesign inspection path is unavailable"
                ) from error
            if (
                resolved_root not in resolved_source.parents
                or (resolved_subject != resolved_root and resolved_root not in resolved_subject.parents)
                or owned_source_path.is_symlink()
                or owned_subject_path.is_symlink()
                or not owned_source_path.is_file()
                or not (owned_subject_path.is_file() or owned_subject_path.is_dir())
            ):
                raise PlatformSigningSubjectError(
                    "graph codesign inspection path is unsafe"
                )
            for architecture_index, architecture in enumerate(architectures):
                if not isinstance(architecture, dict):
                    raise PlatformSigningSubjectError(
                        "graph codesign inspection architecture is not an object"
                    )
                cpu_type = architecture.get("cpuType")
                cpu_subtype = architecture.get("cpuSubtype")
                if (
                    not isinstance(cpu_type, int)
                    or isinstance(cpu_type, bool)
                    or not isinstance(cpu_subtype, int)
                    or isinstance(cpu_subtype, bool)
                ):
                    raise PlatformSigningSubjectError(
                        "graph codesign inspection CPU tuple is invalid"
                    )
                selector_record = {
                    "cpuType": cpu_type,
                    "cpuSubtype": cpu_subtype,
                }
                for action in ("reportIdentityAndRequirements", "reportEntitlements"):
                    derived_steps.append({
                        "toolID": "apple.codesign",
                        "action": action,
                        "artifactID": artifact_id,
                        "objectPath": object_path,
                        "architectureSelector": selector_record,
                        "status": "notRun",
                    })
                stem = (
                    f"codesign-inspect-{artifact_index + 1:02d}-"
                    f"{object_index + 1:04d}-{architecture_index + 1:02d}"
                )
                certificate_prefix = subject.artifact_root.parent.parent / f"{stem}.certificate-"
                selector = f"{cpu_type},{cpu_subtype}"
                identity_invocation = FixedToolInvocation(
                    invocation_id=f"{stem}-identity",
                    tool=codesign_tool,
                    arguments=(
                        "--display",
                        "--verbose=4",
                        "--requirements",
                        "-",
                        f"--extract-certificates={certificate_prefix}",
                        "--architecture",
                        selector,
                        str(owned_subject_path),
                    ),
                    timeout_seconds=120,
                    stdout_required=True,
                    stderr_required=True,
                )
                entitlements_invocation = FixedToolInvocation(
                    invocation_id=f"{stem}-entitlements",
                    tool=codesign_tool,
                    arguments=(
                        "--display",
                        "--entitlements",
                        "-",
                        "--xml",
                        "--architecture",
                        selector,
                        str(owned_subject_path),
                    ),
                    timeout_seconds=120,
                    stderr_required=True,
                )
                plans.append(
                    PlannedCodeSignArchitectureInspection(
                        artifact_id=artifact_id,
                        source_path=source_path,
                        object_path=object_path,
                        owned_source_path=owned_source_path,
                        owned_subject_path=owned_subject_path,
                        cpu_type=cpu_type,
                        cpu_subtype=cpu_subtype,
                        certificate_prefix=certificate_prefix,
                        identity_invocation=identity_invocation,
                        entitlements_invocation=entitlements_invocation,
                    )
                )
                if len(plans) > MAX_CODESIGN_PLANS:
                    raise PlatformSigningSubjectError(
                        "codesign inspection plan exceeds the profile"
                    )
        if derived_steps != expected_steps:
            raise PlatformSigningSubjectError(
                "derived codesign inspection order differs from the signed-code graph"
            )
    if set(reconstructed_by_id) != {item.artifact_id for item in plans}:
        raise PlatformSigningSubjectError(
            "codesign inspection plan does not cover every reconstructed artifact"
        )
    return plans
