#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import os
import plistlib
import stat
import struct
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path, PurePosixPath
from typing import Any, Callable

from artifact_sbom import (
    ArtifactSBOMError,
    MAX_ENTRIES,
    MAX_EXPANDED_BYTES,
    MAX_MEMBER_BYTES,
    MAX_SYMLINK_BYTES,
    canonical_bytes,
    exact_keys,
    parse_canonical_json,
    parse_timestamp,
    resolve_inside,
    safe_relative_path,
)

SCHEMA = "maccompanion.signed-code-graph.v0.1"
PRODUCT = "Mac Companion"
EVIDENCE_LEVEL = "constructionDiscovery"
COLLECTOR_PROFILE = "maccompanion.code-object-discovery.v0.1"
MAX_GRAPH_BYTES = 4 * 1024 * 1024
MAX_PLIST_BYTES = 1024 * 1024
MAX_PLIST_DICTIONARY_KEYS = 4096
MAX_PLIST_KEY_BYTES = 1024
MAX_PLIST_KEY_BYTES_TOTAL = 256 * 1024
MAX_ARCHITECTURES = 16
MAX_LOAD_COMMANDS = 4096
MAX_VERSION_RECORDS_PER_SLICE = 8
MAX_BUNDLES = 256
MAX_MACHO_OBJECTS = 1024
MAX_TOTAL_ARCHITECTURES = 2048
MAX_TOTAL_VERSION_RECORDS = 4096
MAX_VERIFICATION_STEPS = 8192
PRIMARY_KINDS = {"macApplication", "iosArchive"}
BUNDLE_SUFFIXES = {
    ".app": "application",
    ".framework": "framework",
    ".appex": "extension",
    ".xpc": "xpcService",
    ".bundle": "resourceBundle",
}
PACKAGE_TYPES = {
    "application": "APPL",
    "framework": "FMWK",
    "extension": "XPC!",
    "xpcService": "XPC!",
    "resourceBundle": "BNDL",
}
CPU_NAMES = {0x01000007: "x86_64", 0x0100000C: "arm64"}
FILE_TYPES = {
    1: "object", 2: "execute", 3: "fixedVMLibrary", 4: "core", 5: "preload",
    6: "dynamicLibrary", 7: "dynamicLinker", 8: "bundle", 9: "dynamicLibraryStub",
    10: "debugSymbols", 11: "kernelExtension",
}
PLATFORM_NAMES = {1: "macOS", 2: "iOS", 6: "macCatalyst", 7: "iOSSimulator"}
THIN_MAGICS = {
    b"\xce\xfa\xed\xfe": ("little", 32),
    b"\xcf\xfa\xed\xfe": ("little", 64),
    b"\xfe\xed\xfa\xce": ("big", 32),
    b"\xfe\xed\xfa\xcf": ("big", 64),
}
FAT_MAGICS = {
    b"\xca\xfe\xba\xbe": ("big", 32),
    b"\xca\xfe\xba\xbf": ("big", 64),
    b"\xbe\xba\xfe\xca": ("little", 32),
    b"\xbf\xba\xfe\xca": ("little", 64),
}
LC_CODE_SIGNATURE = 0x1D
LC_VERSION_MIN_MACOSX = 0x24
LC_VERSION_MIN_IPHONEOS = 0x25
LC_VERSION_MIN_TVOS = 0x2F
LC_VERSION_MIN_WATCHOS = 0x30
LC_BUILD_VERSION = 0x32
LEGACY_MINIMUM_PLATFORMS = {
    LC_VERSION_MIN_MACOSX: "macOS",
    LC_VERSION_MIN_IPHONEOS: "iOS",
    LC_VERSION_MIN_TVOS: "tvOS",
    LC_VERSION_MIN_WATCHOS: "watchOS",
}


class SignedCodeGraphError(ValueError):
    pass


def _descriptor_identity(metadata: os.stat_result) -> tuple[int, int, int, int, int, int, int]:
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
        raise SignedCodeGraphError("code-object discovery archive must be one regular file")
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
    if size != after.st_size or _descriptor_identity(before) != _descriptor_identity(after):
        raise SignedCodeGraphError("code-object discovery archive changed during hashing")
    return hasher.hexdigest(), size, _descriptor_identity(after)


def _read_graph(path: Path) -> tuple[dict[str, Any], bytes]:
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError as error:
        raise SignedCodeGraphError("signed-code graph is not a bounded regular file") from error
    try:
        before = os.fstat(descriptor)
        if (
            not stat.S_ISREG(before.st_mode)
            or before.st_nlink != 1
            or not 0 < before.st_size <= MAX_GRAPH_BYTES
        ):
            raise SignedCodeGraphError("signed-code graph is not a bounded regular file")
        chunks: list[bytes] = []
        remaining = MAX_GRAPH_BYTES + 1
        while remaining:
            chunk = os.read(descriptor, min(64 * 1024, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        raw = b"".join(chunks)
        after = os.fstat(descriptor)
        if (
            len(raw) > MAX_GRAPH_BYTES
            or len(raw) != after.st_size
            or _descriptor_identity(before) != _descriptor_identity(after)
        ):
            raise SignedCodeGraphError("signed-code graph changed during read")
    finally:
        os.close(descriptor)
    try:
        value = parse_canonical_json(raw)
    except (ArtifactSBOMError, UnicodeError) as error:
        raise SignedCodeGraphError("signed-code graph is not canonical JSON") from error
    if not isinstance(value, dict):
        raise SignedCodeGraphError("signed-code graph must be an object")
    return value, raw


def load_graph(path: Path) -> tuple[dict[str, Any], bytes]:
    return _read_graph(path)


def _version(value: int) -> str:
    return f"{value >> 16}.{(value >> 8) & 0xff}.{value & 0xff}"


def _thin_architecture(
    read_at: Callable[[int, int], bytes],
    hash_at: Callable[[int, int], str],
    offset: int,
    size: int,
) -> dict[str, Any]:
    raw = read_at(offset, min(size, 32))
    facts = THIN_MAGICS.get(raw[:4])
    if facts is None:
        raise SignedCodeGraphError("fat Mach-O slice lacks a thin Mach-O header")
    byte_order, bits = facts
    header_size = 32 if bits == 64 else 28
    if size < header_size or len(raw) < header_size:
        raise SignedCodeGraphError("Mach-O header is truncated")
    endian = "<" if byte_order == "little" else ">"
    cpu_type, cpu_subtype, file_type, ncmds, sizeofcmds, flags = struct.unpack_from(
        endian + "IIIIII", raw, 4
    )
    name = CPU_NAMES.get(cpu_type)
    kind = FILE_TYPES.get(file_type)
    if name is None or kind is None:
        raise SignedCodeGraphError("Mach-O architecture or file type is outside v0.1")
    if ncmds > MAX_LOAD_COMMANDS or sizeofcmds > size - header_size:
        raise SignedCodeGraphError("Mach-O load-command region is invalid")
    commands = read_at(offset + header_size, sizeofcmds)
    if len(commands) != sizeofcmds:
        raise SignedCodeGraphError("Mach-O load commands are truncated")
    cursor = 0
    build_versions: list[dict[str, Any]] = []
    minimum_versions: list[dict[str, Any]] = []
    code_signature: dict[str, Any] | None = None
    for _ in range(ncmds):
        if cursor + 8 > len(commands):
            raise SignedCodeGraphError("Mach-O load-command header is truncated")
        command, command_size = struct.unpack_from(endian + "II", commands, cursor)
        if command_size < 8 or command_size % 4 != 0 or cursor + command_size > len(commands):
            raise SignedCodeGraphError("Mach-O load-command size is invalid")
        if command == LC_BUILD_VERSION:
            if command_size < 24:
                raise SignedCodeGraphError("LC_BUILD_VERSION is truncated")
            platform, minimum, sdk, tool_count = struct.unpack_from(endian + "IIII", commands, cursor + 8)
            if command_size != 24 + tool_count * 8:
                raise SignedCodeGraphError("LC_BUILD_VERSION tool table is invalid")
            if len(build_versions) + len(minimum_versions) >= MAX_VERSION_RECORDS_PER_SLICE:
                raise SignedCodeGraphError("Mach-O version-record count exceeds the slice profile")
            build_versions.append({
                "platform": PLATFORM_NAMES.get(platform, f"unknown-{platform}"),
                "minimumOS": _version(minimum),
                "sdk": _version(sdk),
            })
        elif command in LEGACY_MINIMUM_PLATFORMS:
            if command_size != 16:
                raise SignedCodeGraphError("legacy minimum-OS command is invalid")
            minimum, sdk = struct.unpack_from(endian + "II", commands, cursor + 8)
            if len(build_versions) + len(minimum_versions) >= MAX_VERSION_RECORDS_PER_SLICE:
                raise SignedCodeGraphError("Mach-O version-record count exceeds the slice profile")
            minimum_versions.append({
                "platform": LEGACY_MINIMUM_PLATFORMS[command],
                "minimumOS": _version(minimum),
                "sdk": _version(sdk),
            })
        elif command == LC_CODE_SIGNATURE:
            if command_size != 16 or code_signature is not None:
                raise SignedCodeGraphError("Mach-O code-signature command is invalid")
            data_offset, data_size = struct.unpack_from(endian + "II", commands, cursor + 8)
            if data_size <= 0 or data_offset < header_size + sizeofcmds or data_offset + data_size > size:
                raise SignedCodeGraphError("Mach-O code-signature range is invalid")
            code_signature = {"offset": data_offset, "bytes": data_size}
        cursor += command_size
    if cursor != sizeofcmds:
        raise SignedCodeGraphError("Mach-O load-command count and size disagree")
    build_versions.sort(key=lambda item: (item["platform"], item["minimumOS"], item["sdk"]))
    minimum_versions.sort(key=lambda item: (item["platform"], item["minimumOS"], item["sdk"]))
    return {
        "name": name,
        "cpuType": cpu_type,
        "cpuSubtype": cpu_subtype,
        "byteOrder": byte_order,
        "bits": bits,
        "fileType": kind,
        "flags": flags,
        "loadCommandCount": ncmds,
        "loadCommandBytes": sizeofcmds,
        "buildVersions": build_versions,
        "minimumVersions": minimum_versions,
        "codeSignature": code_signature,
        "sliceOffset": offset,
        "sliceBytes": size,
        "sliceSHA256": hash_at(offset, size),
    }


def _macho_facts(handle: zipfile.ZipExtFile, size: int) -> dict[str, Any] | None:
    def read_at(offset: int, count: int) -> bytes:
        handle.seek(offset)
        return handle.read(count)

    def hash_at(offset: int, count: int) -> str:
        handle.seek(offset)
        remaining = count
        hasher = hashlib.sha256()
        while remaining:
            chunk = handle.read(min(1024 * 1024, remaining))
            if not chunk:
                raise SignedCodeGraphError("Mach-O slice is truncated during hashing")
            hasher.update(chunk)
            remaining -= len(chunk)
        return hasher.hexdigest()

    magic = read_at(0, 4)
    if magic in THIN_MAGICS:
        return {"format": "thin", "architectures": [_thin_architecture(read_at, hash_at, 0, size)]}
    fat = FAT_MAGICS.get(magic)
    if fat is None:
        return None
    byte_order, width = fat
    endian = "<" if byte_order == "little" else ">"
    header = read_at(0, 8)
    if len(header) != 8:
        raise SignedCodeGraphError("fat Mach-O header is truncated")
    count = struct.unpack_from(endian + "I", header, 4)[0]
    if not 1 <= count <= MAX_ARCHITECTURES:
        raise SignedCodeGraphError("fat Mach-O architecture count is invalid")
    entry_size = 32 if width == 64 else 20
    table = read_at(8, count * entry_size)
    if len(table) != count * entry_size:
        raise SignedCodeGraphError("fat Mach-O architecture table is truncated")
    architectures: list[dict[str, Any]] = []
    ranges: list[tuple[int, int]] = []
    for index in range(count):
        base = index * entry_size
        if width == 64:
            cpu_type, cpu_subtype, slice_offset, slice_size, alignment = struct.unpack_from(endian + "IIQQI", table, base)
        else:
            cpu_type, cpu_subtype, slice_offset, slice_size, alignment = struct.unpack_from(endian + "IIIII", table, base)
        if alignment > 30 or slice_offset % (1 << alignment) != 0:
            raise SignedCodeGraphError("fat Mach-O slice alignment is invalid")
        if slice_size <= 0 or slice_offset < 8 + count * entry_size or slice_offset + slice_size > size:
            raise SignedCodeGraphError("fat Mach-O slice range is invalid")
        if any(slice_offset < end and start < slice_offset + slice_size for start, end in ranges):
            raise SignedCodeGraphError("fat Mach-O slices overlap")
        ranges.append((slice_offset, slice_offset + slice_size))
        architecture = _thin_architecture(read_at, hash_at, slice_offset, slice_size)
        if architecture["cpuType"] != cpu_type or architecture["cpuSubtype"] != cpu_subtype:
            raise SignedCodeGraphError("fat Mach-O slice architecture disagrees with table")
        architecture["tableIndex"] = index
        architecture["alignmentPower"] = alignment
        architectures.append(architecture)
    architectures.sort(key=lambda item: (item["cpuType"], item["cpuSubtype"], item["sliceOffset"]))
    if len({(item["cpuType"], item["cpuSubtype"]) for item in architectures}) != len(architectures):
        raise SignedCodeGraphError("fat Mach-O contains duplicate architectures")
    return {"format": "fat64" if width == 64 else "fat32", "architectures": architectures}


def _bundle_kind(path: str) -> str | None:
    for suffix, kind in BUNDLE_SUFFIXES.items():
        if path.endswith(suffix):
            return kind
    return None


def _nearest_bundle(path: str, bundle_paths: list[str]) -> str | None:
    candidates = [bundle for bundle in bundle_paths if path.startswith(bundle + "/")]
    return max(candidates, key=len) if candidates else None


def _bundle_paths(entries: dict[str, dict[str, Any]]) -> list[str]:
    roots: set[str] = set()
    for path in entries:
        parts = PurePosixPath(path).parts
        prefix: list[str] = []
        for part in parts:
            prefix.append(part)
            if _bundle_kind(part) is not None:
                root = "/".join(prefix)
                if root not in roots:
                    if len(roots) >= MAX_BUNDLES:
                        raise SignedCodeGraphError("code-object discovery bundle count exceeds the profile")
                    roots.add(root)
    return sorted(roots)


def _validate_ancestor_topology(entries: dict[str, dict[str, Any]]) -> None:
    for path in entries:
        parts = PurePosixPath(path).parts
        prefix: list[str] = []
        for part in parts[:-1]:
            prefix.append(part)
            ancestor = entries.get("/".join(prefix))
            if ancestor is not None and ancestor.get("type") != "directory":
                raise SignedCodeGraphError("ZIP member has a non-directory ancestor")


def _member_bytes(archive: zipfile.ZipFile, info: zipfile.ZipInfo, *, maximum: int) -> bytes:
    if info.file_size <= 0 or info.file_size > maximum:
        raise SignedCodeGraphError("bundle metadata is not a bounded regular file")
    with archive.open(info, "r") as handle:
        raw = handle.read(maximum + 1)
    if len(raw) != info.file_size or len(raw) > maximum:
        raise SignedCodeGraphError("bundle metadata changed size during read")
    return raw


def _inspect_archive_entries(archive: zipfile.ZipFile) -> list[dict[str, Any]]:
    infos = archive.infolist()
    if not infos or len(infos) > MAX_ENTRIES:
        raise SignedCodeGraphError("ZIP entry count is outside the discovery profile")
    names: set[str] = set()
    expanded = 0
    entries: list[dict[str, Any]] = []
    for info in infos:
        is_directory_name = info.filename.endswith("/")
        if info.filename.endswith("//"):
            raise SignedCodeGraphError("ZIP member has ambiguous trailing separators")
        try:
            name = safe_relative_path(
                info.filename[:-1] if is_directory_name else info.filename,
                "ZIP member path",
            )
        except ArtifactSBOMError as error:
            raise SignedCodeGraphError(str(error)) from error
        if name in names:
            raise SignedCodeGraphError("ZIP contains a duplicate member")
        names.add(name)
        if info.flag_bits & 0x1 or info.create_system != 3 or info.compress_type not in {
            zipfile.ZIP_STORED,
            zipfile.ZIP_DEFLATED,
        }:
            raise SignedCodeGraphError("ZIP member encoding is outside the discovery profile")
        if info.file_size < 0 or info.file_size > MAX_MEMBER_BYTES:
            raise SignedCodeGraphError("ZIP member size is outside the discovery profile")
        expanded += info.file_size
        if expanded > MAX_EXPANDED_BYTES:
            raise SignedCodeGraphError("expanded ZIP exceeds the discovery profile")
        if info.file_size > 0 and info.compress_size == 0:
            raise SignedCodeGraphError("ZIP member has invalid zero compressed size")
        if info.file_size > 1024 * 1024 and info.file_size / info.compress_size > 1000:
            raise SignedCodeGraphError("ZIP compression ratio exceeds the discovery profile")
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
            raise SignedCodeGraphError("ZIP member mode is outside the discovery profile")
        if entry_type == "directory":
            if info.file_size != 0:
                raise SignedCodeGraphError("ZIP directory has content")
            entries.append({
                "path": name, "type": entry_type, "mode": f"{permissions:04o}",
                "bytes": 0, "sha1": None, "sha256": None, "symlinkTarget": None,
            })
            continue
        sha1 = hashlib.sha1()
        sha256 = hashlib.sha256()
        size = 0
        target_bytes = bytearray()
        with archive.open(info, "r") as handle:
            while True:
                chunk = handle.read(1024 * 1024)
                if not chunk:
                    break
                size += len(chunk)
                if size > info.file_size:
                    raise SignedCodeGraphError("ZIP member size overrun")
                sha1.update(chunk)
                sha256.update(chunk)
                if entry_type == "symlink":
                    if size > MAX_SYMLINK_BYTES:
                        raise SignedCodeGraphError("ZIP symlink target exceeds the discovery profile")
                    target_bytes.extend(chunk)
        if size != info.file_size:
            raise SignedCodeGraphError("ZIP member size mismatch")
        target: str | None = None
        if entry_type == "symlink":
            try:
                target = bytes(target_bytes).decode("utf-8")
            except UnicodeDecodeError as error:
                raise SignedCodeGraphError("ZIP symlink target is not UTF-8") from error
        entries.append({
            "path": name, "type": entry_type, "mode": f"{permissions:04o}",
            "bytes": size, "sha1": sha1.hexdigest(), "sha256": sha256.hexdigest(),
            "symlinkTarget": target,
        })
    return sorted(entries, key=lambda item: item["path"].encode("utf-8"))


def _validate_archive_container(
    handle: Any,
    size: int,
    archive: zipfile.ZipFile,
    infos: list[zipfile.ZipInfo],
) -> None:
    tail_size = min(size, 65_557)
    handle.seek(size - tail_size)
    tail = handle.read(tail_size)
    relative_eocd = tail.rfind(b"PK\x05\x06")
    if relative_eocd < 0:
        raise SignedCodeGraphError("ZIP end record is missing")
    eocd = size - tail_size + relative_eocd
    if eocd + 22 > size:
        raise SignedCodeGraphError("ZIP end record is truncated")
    comment_length = struct.unpack_from("<H", tail, relative_eocd + 20)[0]
    central_size = struct.unpack_from("<I", tail, relative_eocd + 12)[0]
    if eocd + 22 + comment_length != size or archive.start_dir + central_size != eocd:
        raise SignedCodeGraphError("ZIP container has unaccounted bytes")
    ordered = sorted(infos, key=lambda info: info.header_offset)
    if not ordered or ordered[0].header_offset != 0:
        raise SignedCodeGraphError("ZIP container has unaccounted prefix bytes")
    for index, info in enumerate(ordered):
        handle.seek(info.header_offset)
        header = handle.read(30)
        if len(header) != 30 or header[:4] != b"PK\x03\x04":
            raise SignedCodeGraphError("ZIP local header is malformed")
        name_length, extra_length = struct.unpack_from("<HH", header, 26)
        data_end = info.header_offset + 30 + name_length + extra_length + info.compress_size
        next_offset = ordered[index + 1].header_offset if index + 1 < len(ordered) else archive.start_dir
        gap = next_offset - data_end
        if not info.flag_bits & 0x08:
            if gap != 0:
                raise SignedCodeGraphError("ZIP has unaccounted bytes between members")
            continue
        if gap not in {12, 16, 20, 24}:
            raise SignedCodeGraphError("ZIP data descriptor has an invalid size")
        handle.seek(data_end)
        descriptor = handle.read(gap)
        signed = gap in {16, 24}
        cursor = 0
        if signed:
            if descriptor[:4] != b"PK\x07\x08":
                raise SignedCodeGraphError("ZIP data descriptor signature is invalid")
            cursor = 4
        elif descriptor[:4] == b"PK\x07\x08":
            raise SignedCodeGraphError("ZIP data descriptor form is ambiguous")
        descriptor_crc = struct.unpack_from("<I", descriptor, cursor)[0]
        cursor += 4
        if gap in {12, 16}:
            compressed, uncompressed = struct.unpack_from("<II", descriptor, cursor)
        else:
            compressed, uncompressed = struct.unpack_from("<QQ", descriptor, cursor)
        if descriptor_crc != info.CRC or compressed != info.compress_size or uncompressed != info.file_size:
            raise SignedCodeGraphError("ZIP data descriptor disagrees with the central directory")


def _binary_plist_length(raw: bytes, cursor: int, info: int) -> tuple[int, int]:
    if info != 0xF:
        return info, cursor
    if cursor >= len(raw) or raw[cursor] >> 4 != 0x1:
        raise SignedCodeGraphError("binary plist length is invalid")
    byte_count = 1 << (raw[cursor] & 0xF)
    start = cursor + 1
    end = start + byte_count
    if byte_count > 8 or end > len(raw):
        raise SignedCodeGraphError("binary plist length is out of bounds")
    return int.from_bytes(raw[start:end], "big"), end


def _reject_duplicate_plist_keys(raw: bytes) -> None:
    if not raw.startswith(b"bplist00"):
        try:
            root = ET.fromstring(raw)
        except ET.ParseError as error:
            raise SignedCodeGraphError("XML plist is invalid") from error
        for dictionary in root.iter("dict"):
            children = list(dictionary)
            if len(children) % 2:
                raise SignedCodeGraphError("plist dictionary has an incomplete pair")
            seen: set[str] = set()
            for index in range(0, len(children), 2):
                key = children[index]
                if key.tag != "key" or key.text is None or key.text in seen:
                    raise SignedCodeGraphError("plist dictionary has duplicate or invalid keys")
                seen.add(key.text)
        return
    if len(raw) < 40:
        raise SignedCodeGraphError("binary plist trailer is truncated")
    trailer = raw[-32:]
    offset_size = trailer[6]
    reference_size = trailer[7]
    object_count = int.from_bytes(trailer[8:16], "big")
    offset_table = int.from_bytes(trailer[24:32], "big")
    if (
        offset_size not in {1, 2, 4, 8}
        or reference_size not in {1, 2, 4, 8}
        or not 1 <= object_count <= len(raw)
        or offset_table < 8
        or offset_table + object_count * offset_size > len(raw) - 32
    ):
        raise SignedCodeGraphError("binary plist trailer is invalid")
    offsets = [
        int.from_bytes(raw[offset_table + index * offset_size: offset_table + (index + 1) * offset_size], "big")
        for index in range(object_count)
    ]
    if any(offset < 8 or offset >= offset_table for offset in offsets):
        raise SignedCodeGraphError("binary plist object offset is invalid")
    if len(set(offsets)) != len(offsets):
        raise SignedCodeGraphError("binary plist object offsets are not unique")

    def object_extent(offset: int) -> tuple[int, int]:
        marker = raw[offset]
        kind = marker >> 4
        info = marker & 0xF
        if kind == 0x0:
            end = offset + 1
        elif kind in {0x1, 0x2}:
            end = offset + 1 + (1 << info)
        elif kind == 0x3:
            if info != 0x3:
                raise SignedCodeGraphError("binary plist date object is invalid")
            end = offset + 9
        elif kind in {0x4, 0x5, 0x6, 0xA, 0xC, 0xD}:
            count, start = _binary_plist_length(raw, offset + 1, info)
            if kind in {0x4, 0x5}:
                payload_bytes = count
            elif kind == 0x6:
                payload_bytes = count * 2
            elif kind in {0xA, 0xC}:
                payload_bytes = count * reference_size
            else:
                payload_bytes = count * reference_size * 2
            end = start + payload_bytes
        elif kind == 0x8:
            end = offset + 2 + info
        else:
            raise SignedCodeGraphError("binary plist object type is outside the profile")
        if end <= offset or end > offset_table:
            raise SignedCodeGraphError("binary plist object extent is invalid")
        return offset, end

    extents = sorted(object_extent(offset) for offset in offsets)
    if any(extents[index][0] < extents[index - 1][1] for index in range(1, len(extents))):
        raise SignedCodeGraphError("binary plist object extents overlap")

    decoded_key_bytes = 0

    def string_value(reference: int) -> str:
        nonlocal decoded_key_bytes
        if reference >= object_count:
            raise SignedCodeGraphError("binary plist object reference is invalid")
        cursor = offsets[reference]
        marker = raw[cursor]
        kind = marker >> 4
        length, start = _binary_plist_length(raw, cursor + 1, marker & 0xF)
        if kind == 0x5:
            end = start + length
            encoding = "ascii"
        elif kind == 0x6:
            end = start + length * 2
            encoding = "utf-16-be"
        else:
            raise SignedCodeGraphError("binary plist dictionary key is not a string")
        if end > offset_table:
            raise SignedCodeGraphError("binary plist string is out of bounds")
        key_bytes = end - start
        if key_bytes > MAX_PLIST_KEY_BYTES or decoded_key_bytes + key_bytes > MAX_PLIST_KEY_BYTES_TOTAL:
            raise SignedCodeGraphError("binary plist key bytes exceed the profile")
        decoded_key_bytes += key_bytes
        try:
            return raw[start:end].decode(encoding)
        except UnicodeDecodeError as error:
            raise SignedCodeGraphError("binary plist key is invalid") from error

    dictionary_key_work = 0
    for cursor in offsets:
        marker = raw[cursor]
        if marker >> 4 != 0xD:
            continue
        count, start = _binary_plist_length(raw, cursor + 1, marker & 0xF)
        dictionary_key_work += count
        if dictionary_key_work > MAX_PLIST_DICTIONARY_KEYS:
            raise SignedCodeGraphError("binary plist dictionary work exceeds the profile")
        end = start + count * reference_size * 2
        if count > object_count or end > offset_table:
            raise SignedCodeGraphError("binary plist dictionary is out of bounds")
        seen: set[str] = set()
        for index in range(count):
            begin = start + index * reference_size
            reference = int.from_bytes(raw[begin:begin + reference_size], "big")
            key = string_value(reference)
            if key in seen:
                raise SignedCodeGraphError("plist dictionary has duplicate keys")
            seen.add(key)


def _bundle_info_path(root: str, kind: str, entries: dict[str, dict[str, Any]]) -> str:
    if kind == "framework":
        candidates = [
            f"{root}/Versions/A/Resources/Info.plist",
            f"{root}/Resources/Info.plist",
            f"{root}/Info.plist",
        ]
    elif f"{root}/Contents/Info.plist" in entries:
        candidates = [f"{root}/Contents/Info.plist"]
    else:
        candidates = [f"{root}/Info.plist"]
    matches = [path for path in candidates if path in entries]
    if len(matches) != 1 or entries[matches[0]]["type"] != "regularFile":
        raise SignedCodeGraphError("modeled bundle lacks one authoritative Info.plist")
    return matches[0]


def _main_executable_path(root: str, info_path: str, executable: str | None) -> str | None:
    if executable is None:
        return None
    if "/Versions/A/Resources/Info.plist" in info_path:
        return f"{root}/Versions/A/{executable}"
    if info_path.endswith("/Contents/Info.plist"):
        return f"{root}/Contents/MacOS/{executable}"
    return f"{root}/{executable}"


def _discover_bundles(
    *,
    archive: zipfile.ZipFile,
    info_by_path: dict[str, zipfile.ZipInfo],
    entries: dict[str, dict[str, Any]],
    artifact_kind: str,
) -> tuple[str, list[dict[str, Any]]]:
    bundle_paths = _bundle_paths(entries)
    if artifact_kind == "macApplication":
        outer = [path for path in bundle_paths if path.endswith(".app") and ".app/" not in path]
    else:
        outer = [
            path for path in bundle_paths
            if path.startswith("Products/Applications/") and path.endswith(".app") and ".app/" not in path
        ]
    if len(outer) != 1:
        raise SignedCodeGraphError("artifact does not contain one distribution subject")
    subject_root = outer[0]
    if any(path != subject_root and not path.startswith(subject_root + "/") for path in bundle_paths):
        raise SignedCodeGraphError("modeled bundle exists outside the distribution subject")
    bundles: list[dict[str, Any]] = []
    for path in bundle_paths:
        kind = _bundle_kind(path)
        assert kind is not None
        info_path = _bundle_info_path(path, kind, entries)
        archive_info = info_by_path.get(info_path)
        if archive_info is None:
            raise SignedCodeGraphError("bundle Info.plist is absent from exact archive")
        raw = _member_bytes(archive, archive_info, maximum=MAX_PLIST_BYTES)
        _reject_duplicate_plist_keys(raw)
        try:
            metadata = plistlib.loads(raw)
        except (plistlib.InvalidFileException, ValueError, TypeError) as error:
            raise SignedCodeGraphError("bundle Info.plist is invalid") from error
        if not isinstance(metadata, dict):
            raise SignedCodeGraphError("bundle Info.plist root is invalid")
        identifier = metadata.get("CFBundleIdentifier")
        executable = metadata.get("CFBundleExecutable")
        package_type = metadata.get("CFBundlePackageType")
        if not isinstance(identifier, str) or not identifier or not isinstance(package_type, str) or not package_type:
            raise SignedCodeGraphError("bundle Info.plist lacks required string facts")
        if package_type != PACKAGE_TYPES[kind]:
            raise SignedCodeGraphError("bundle package type disagrees with its fixed layout")
        if executable is not None and (not isinstance(executable, str) or not executable or "/" in executable):
            raise SignedCodeGraphError("CFBundleExecutable is invalid")
        if kind != "resourceBundle" and executable is None:
            raise SignedCodeGraphError("code bundle lacks CFBundleExecutable")
        main_path = _main_executable_path(path, info_path, executable)
        if main_path is not None and (main_path not in entries or entries[main_path]["type"] != "regularFile"):
            raise SignedCodeGraphError("CFBundleExecutable does not resolve to a regular member")
        if "/Versions/A/Resources/Info.plist" in info_path and executable is not None:
            current = entries.get(f"{path}/Versions/Current")
            public_executable = entries.get(f"{path}/{executable}")
            if (
                current is None
                or current.get("type") != "symlink"
                or current.get("symlinkTarget") != "A"
                or public_executable is None
                or public_executable.get("type") != "symlink"
                or public_executable.get("symlinkTarget") != f"Versions/Current/{executable}"
            ):
                raise SignedCodeGraphError("versioned framework aliases are ambiguous")
        bundles.append({
            "path": path,
            "kind": kind,
            "enclosingBundlePath": _nearest_bundle(path, [other for other in bundle_paths if other != path]),
            "infoPlist": {
                "path": info_path,
                "bytes": len(raw),
                "sha256": hashlib.sha256(raw).hexdigest(),
                "format": "binary" if raw.startswith(b"bplist00") else "xml",
            },
            "bundleIdentifier": identifier,
            "packageType": package_type,
            "executableName": executable,
            "mainExecutablePath": main_path,
        })
    return subject_root, bundles


def _discover_launch_services(
    *,
    archive: zipfile.ZipFile,
    info_by_path: dict[str, zipfile.ZipInfo],
    entries: dict[str, dict[str, Any]],
    subject_root: str,
    object_paths: set[str],
) -> list[dict[str, Any]]:
    prefix = f"{subject_root}/Contents/Library/LaunchAgents/"
    services: list[dict[str, Any]] = []
    for path, entry in sorted(entries.items()):
        if entry["type"] != "regularFile" or not path.startswith(prefix) or not path.endswith(".plist"):
            continue
        archive_info = info_by_path.get(path)
        if archive_info is None:
            raise SignedCodeGraphError("LaunchAgent plist is absent from exact archive")
        raw = _member_bytes(archive, archive_info, maximum=MAX_PLIST_BYTES)
        _reject_duplicate_plist_keys(raw)
        try:
            metadata = plistlib.loads(raw)
        except (plistlib.InvalidFileException, ValueError, TypeError) as error:
            raise SignedCodeGraphError("LaunchAgent plist is invalid") from error
        label = metadata.get("Label") if isinstance(metadata, dict) else None
        program = metadata.get("BundleProgram") if isinstance(metadata, dict) else None
        if (
            not isinstance(label, str) or not label
            or not isinstance(program, str) or not program
            or program.startswith("/") or ".." in PurePosixPath(program).parts
        ):
            raise SignedCodeGraphError("LaunchAgent plist lacks a safe Label and BundleProgram")
        resolved = f"{subject_root}/{program}"
        if resolved not in object_paths:
            raise SignedCodeGraphError("LaunchAgent BundleProgram is not a discovered Mach-O")
        services.append({
            "plistPath": path,
            "plistSHA256": hashlib.sha256(raw).hexdigest(),
            "label": label,
            "bundleProgram": program,
            "resolvedObjectPath": resolved,
        })
    return services


def _verification_plan(
    *, artifact_id: str, platform: str, subject_root: str, objects: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    plan: list[dict[str, Any]] = []
    subject_objects = [item for item in objects if item["inDistributionSubject"]]
    for item in sorted(subject_objects, key=lambda value: (-value["path"].count("/"), value["path"])):
        verification_subject = item["bundleMainFor"] or item["path"]
        plan.append({
            "toolID": "apple.codesign",
            "action": "verifyObjectAllArchitectures",
            "artifactID": artifact_id,
            "objectPath": verification_subject,
            "architectureSelector": None,
            "status": "notRun",
        })
        for architecture in item["machO"]["architectures"]:
            selector = {"cpuType": architecture["cpuType"], "cpuSubtype": architecture["cpuSubtype"]}
            for action in ("reportIdentityAndRequirements", "reportEntitlements"):
                plan.append({
                    "toolID": "apple.codesign",
                    "action": action,
                    "artifactID": artifact_id,
                    "objectPath": verification_subject,
                    "architectureSelector": selector,
                    "status": "notRun",
                })
    if platform == "macOS":
        plan.extend([
            {
                "toolID": "apple.codesign",
                "action": "verifyOuterBundleDeepCrossCheck",
                "artifactID": artifact_id,
                "objectPath": subject_root,
                "architectureSelector": None,
                "status": "notRun",
            },
            {
                "toolID": "apple.spctl",
                "action": "assessOuterExecutable",
                "artifactID": artifact_id,
                "objectPath": subject_root,
                "architectureSelector": None,
                "status": "notRun",
            },
        ])
    return plan


def _inventory_artifact(
    *,
    binding: dict[str, Any],
    entries: list[dict[str, Any]],
    release_executables: list[dict[str, Any]],
    evidence_root: Path,
) -> dict[str, Any]:
    resolved_root = evidence_root.resolve(strict=True)
    candidate_path = resolved_root / binding["path"]
    archive_path = resolve_inside(resolved_root, binding["path"], must_exist=True)
    if candidate_path.absolute() != archive_path:
        raise SignedCodeGraphError("code-object discovery archive path contains a symlink")
    try:
        descriptor = os.open(candidate_path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError as error:
        raise SignedCodeGraphError("cannot open code-object discovery archive") from error
    try:
        before_digest, before_size, before_identity = _digest_descriptor(descriptor)
        if (before_digest, before_size) != (binding["sha256"], binding["bytes"]):
            raise SignedCodeGraphError("code-object discovery archive binding mismatch")
        entry_by_path = {entry["path"]: entry for entry in entries}
        declared_by_path: dict[str, list[str]] = {}
        declared_subjects: set[tuple[str, str]] = set()
        for executable in release_executables:
            if executable.get("artifactID") != binding["id"]:
                continue
            subject = (binding["id"], executable["relativePath"])
            if subject in declared_subjects:
                raise SignedCodeGraphError("duplicate release executable subject")
            declared_subjects.add(subject)
            declared_by_path.setdefault(executable["relativePath"], []).append(executable["id"])
        with os.fdopen(os.dup(descriptor), "rb") as archive_handle, zipfile.ZipFile(archive_handle, "r") as archive:
            _validate_archive_container(archive_handle, before_size, archive, archive.infolist())
            actual_entries = _inspect_archive_entries(archive)
            if actual_entries != entries:
                raise SignedCodeGraphError("exact archive members differ from the artifact composition")
            info_by_path = {info.filename.rstrip("/"): info for info in archive.infolist()}
            _validate_ancestor_topology(entry_by_path)
            subject_root, bundles = _discover_bundles(
                archive=archive,
                info_by_path=info_by_path,
                entries=entry_by_path,
                artifact_kind=binding["kind"],
            )
            bundle_paths = [item["path"] for item in bundles]
            main_paths = {item["mainExecutablePath"]: item["path"] for item in bundles if item["mainExecutablePath"]}
            objects: list[dict[str, Any]] = []
            total_architectures = 0
            total_version_records = 0
            for entry in entries:
                if entry["type"] != "regularFile":
                    continue
                info = info_by_path.get(entry["path"])
                if info is None:
                    raise SignedCodeGraphError("composition member is missing from archive")
                with archive.open(info, "r") as handle:
                    facts = _macho_facts(handle, entry["bytes"])
                if facts is None:
                    continue
                if len(objects) >= MAX_MACHO_OBJECTS:
                    raise SignedCodeGraphError("Mach-O object count exceeds the discovery profile")
                architecture_count = len(facts["architectures"])
                version_record_count = sum(
                    len(item["buildVersions"]) + len(item["minimumVersions"])
                    for item in facts["architectures"]
                )
                if total_architectures + architecture_count > MAX_TOTAL_ARCHITECTURES:
                    raise SignedCodeGraphError("Mach-O architecture count exceeds the discovery profile")
                if total_version_records + version_record_count > MAX_TOTAL_VERSION_RECORDS:
                    raise SignedCodeGraphError("Mach-O version facts exceed the discovery profile")
                total_architectures += architecture_count
                total_version_records += version_record_count
                owner = _nearest_bundle(entry["path"], bundle_paths)
                objects.append({
                    "path": entry["path"],
                    "ownerBundlePath": owner,
                    "bundleMainFor": main_paths.get(entry["path"]),
                    "inDistributionSubject": entry["path"].startswith(subject_root + "/"),
                    "member": {
                        key: entry[key]
                        for key in ("path", "type", "mode", "bytes", "sha1", "sha256", "symlinkTarget")
                    },
                    "machO": facts,
                    "declaredExecutableIDs": sorted(declared_by_path.get(entry["path"], [])),
                })
            objects.sort(key=lambda item: item["path"].encode("utf-8"))
            discovered_paths = {item["path"] for item in objects}
            if not objects or any(path not in discovered_paths for path in declared_by_path):
                raise SignedCodeGraphError("declared executable is absent from Mach-O inventory")
            if any(bundle["mainExecutablePath"] not in discovered_paths for bundle in bundles if bundle["mainExecutablePath"]):
                raise SignedCodeGraphError("bundle main executable is not a discovered Mach-O")
            launch_services = _discover_launch_services(
                archive=archive,
                info_by_path=info_by_path,
                entries=entry_by_path,
                subject_root=subject_root,
                object_paths=discovered_paths,
            ) if binding["platform"] == "macOS" else []
            verification_step_count = sum(
                1 + 2 * len(item["machO"]["architectures"])
                for item in objects
                if item["inDistributionSubject"]
            ) + (2 if binding["platform"] == "macOS" else 0)
            if verification_step_count > MAX_VERIFICATION_STEPS:
                raise SignedCodeGraphError("verification plan exceeds the discovery profile")
        after_digest, after_size, after_identity = _digest_descriptor(descriptor)
        try:
            path_identity = _descriptor_identity(candidate_path.lstat())
        except OSError as error:
            raise SignedCodeGraphError("code-object discovery archive path disappeared") from error
        if (
            (before_digest, before_size, before_identity) != (after_digest, after_size, after_identity)
            or path_identity != before_identity
        ):
            raise SignedCodeGraphError("code-object discovery archive changed during inventory")
    except (OSError, RuntimeError, zipfile.BadZipFile) as error:
        raise SignedCodeGraphError("cannot inspect code-object discovery archive") from error
    finally:
        os.close(descriptor)
    result = {
        "artifact": dict(binding),
        "subjectRoot": subject_root,
        "platformAcceptanceEligible": False,
        "bundles": bundles,
        "launchServices": launch_services,
        "machOObjects": objects,
        "machOObjectCount": len(objects),
        "declaredExecutableCount": sum(len(item["declaredExecutableIDs"]) for item in objects),
        "verificationPlan": _verification_plan(
            artifact_id=binding["id"], platform=binding["platform"], subject_root=subject_root, objects=objects
        ),
    }
    return result


def generate_graph(
    *,
    index: dict[str, Any],
    composition: dict[str, Any],
    release_manifest: dict[str, Any],
    artifact_sbom_reference: dict[str, Any],
    evidence_root: Path,
    created: str,
) -> dict[str, Any]:
    parse_timestamp(created)
    composition_by_id = {artifact["id"]: artifact["entries"] for artifact in composition["artifacts"]}
    artifacts = [
        _inventory_artifact(
            binding=binding,
            entries=composition_by_id[binding["id"]],
            release_executables=release_manifest["executables"],
            evidence_root=evidence_root,
        )
        for binding in index["artifacts"]
        if binding["kind"] in PRIMARY_KINDS
    ]
    if {artifact["artifact"]["platform"] for artifact in artifacts} != set(index["release"]["targets"]):
        raise SignedCodeGraphError("signed-code graph target coverage is incomplete")
    result = {
        "schemaVersion": SCHEMA,
        "evidenceLevel": EVIDENCE_LEVEL,
        "product": PRODUCT,
        "release": dict(index["release"]),
        "source": dict(index["source"]),
        "created": created,
        "artifactSBOM": dict(artifact_sbom_reference),
        "collectorProfile": COLLECTOR_PROFILE,
        "artifacts": artifacts,
    }
    if len(canonical_bytes(result)) > MAX_GRAPH_BYTES:
        raise SignedCodeGraphError("generated signed-code graph exceeds the profile")
    return result


def validate_graph(
    value: dict[str, Any],
    *,
    index: dict[str, Any],
    composition: dict[str, Any],
    release_manifest: dict[str, Any],
    artifact_sbom_reference: dict[str, Any],
    evidence_root: Path,
) -> None:
    try:
        root = exact_keys(
            value,
            {
                "schemaVersion", "evidenceLevel", "product", "release", "source", "created",
                "artifactSBOM", "collectorProfile", "artifacts",
            },
            "signed-code graph",
        )
    except ArtifactSBOMError as error:
        raise SignedCodeGraphError(str(error)) from error
    if (
        root["schemaVersion"] != SCHEMA
        or root["evidenceLevel"] != EVIDENCE_LEVEL
        or root["product"] != PRODUCT
        or root["collectorProfile"] != COLLECTOR_PROFILE
    ):
        raise SignedCodeGraphError("invalid signed-code graph identity")
    expected = generate_graph(
        index=index,
        composition=composition,
        release_manifest=release_manifest,
        artifact_sbom_reference=artifact_sbom_reference,
        evidence_root=evidence_root,
        created=root["created"],
    )
    if canonical_bytes(root) != canonical_bytes(expected):
        raise SignedCodeGraphError("signed-code graph differs from exact archive inventory")
