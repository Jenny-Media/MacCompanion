#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import os
import plistlib
import stat
import struct
import unicodedata
from pathlib import Path
from typing import Any

from signed_code_graph import (
    SignedCodeGraphError,
    _macho_facts,
    _reject_duplicate_plist_keys,
)
from signing_policy import (
    MAX_ENTITLEMENT_CHILDREN,
    MAX_ENTITLEMENT_DEPTH,
    MAX_ENTITLEMENT_KEY_BYTES,
    MAX_ENTITLEMENT_KEYS,
    MAX_ENTITLEMENT_NODES,
    MAX_ENTITLEMENT_STRING_BYTES,
    MAX_ENTITLEMENT_TOP_LEVEL_KEYS,
    MAX_ENTITLEMENT_TOTAL_STRING_BYTES,
    SAFE_INTEGER,
    SigningPolicyError,
    _EntitlementBudget,
    _entitlements,
)


CSMAGIC_REQUIREMENT = 0xFADE0C00
CSMAGIC_REQUIREMENTS = 0xFADE0C01
CSMAGIC_CODEDIRECTORY = 0xFADE0C02
CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0
CSMAGIC_EMBEDDED_ENTITLEMENTS = 0xFADE7171
CSMAGIC_EMBEDDED_DER_ENTITLEMENTS = 0xFADE7172
CSMAGIC_BLOBWRAPPER = 0xFADE0B01

CSSLOT_CODEDIRECTORY = 0
CSSLOT_REQUIREMENTS = 2
CSSLOT_ENTITLEMENTS = 5
CSSLOT_DER_ENTITLEMENTS = 7
CSSLOT_SIGNATURE = 0x10000
CSSLOT_ALTERNATE_CODEDIRECTORIES = range(0x1000, 0x1006)
REQUIREMENT_TYPE_DESIGNATED = 3

CS_RUNTIME = 0x00010000
CS_HASHTYPE_SHA256 = 2
MAX_EMBEDDED_SIGNATURE_BYTES = 16 * 1024 * 1024
MAX_SIGNATURE_BLOBS = 32
MAX_CODEDIRECTORY_BYTES = 4 * 1024 * 1024
MAX_REQUIREMENTS_BYTES = 1024 * 1024
MAX_ENTITLEMENTS_BYTES = 1024 * 1024


class PlatformCodeSignatureError(ValueError):
    pass


def _descriptor_identity(
    metadata: os.stat_result,
) -> tuple[int, int, int, int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_nlink,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def _read_exact_at(descriptor: int, offset: int, count: int) -> bytes:
    if offset < 0 or count < 0:
        raise PlatformCodeSignatureError("embedded-signature read range is invalid")
    chunks: list[bytes] = []
    cursor = 0
    while cursor < count:
        chunk = os.pread(descriptor, min(1024 * 1024, count - cursor), offset + cursor)
        if not chunk:
            raise PlatformCodeSignatureError("embedded-signature read is truncated")
        chunks.append(chunk)
        cursor += len(chunk)
    return b"".join(chunks)


def _blob_header(raw: bytes, expected_magic: int, maximum: int, label: str) -> int:
    if not 8 <= len(raw) <= maximum:
        raise PlatformCodeSignatureError(f"{label} size is outside the profile")
    magic, length = struct.unpack_from(">II", raw, 0)
    if magic != expected_magic or length != len(raw):
        raise PlatformCodeSignatureError(f"{label} header is invalid")
    return length


def _superblob(
    raw: bytes,
    expected_magic: int,
    maximum: int,
    label: str,
) -> dict[int, bytes]:
    _blob_header(raw, expected_magic, maximum, label)
    if len(raw) < 12:
        raise PlatformCodeSignatureError(f"{label} is truncated")
    count = struct.unpack_from(">I", raw, 8)[0]
    if not 1 <= count <= MAX_SIGNATURE_BLOBS or 12 + count * 8 > len(raw):
        raise PlatformCodeSignatureError(f"{label} index is outside the profile")
    indexed: list[tuple[int, int]] = []
    for index in range(count):
        slot, offset = struct.unpack_from(">II", raw, 12 + index * 8)
        if offset < 12 + count * 8 or offset + 8 > len(raw):
            raise PlatformCodeSignatureError(f"{label} child offset is invalid")
        indexed.append((slot, offset))
    if len({slot for slot, _ in indexed}) != count or len({offset for _, offset in indexed}) != count:
        raise PlatformCodeSignatureError(f"{label} index is ambiguous")
    children: dict[int, bytes] = {}
    ranges: list[tuple[int, int]] = []
    for slot, offset in indexed:
        child_length = struct.unpack_from(">I", raw, offset + 4)[0]
        end = offset + child_length
        if child_length < 8 or end > len(raw):
            raise PlatformCodeSignatureError(f"{label} child range is invalid")
        ranges.append((offset, end))
        children[slot] = raw[offset:end]
    ranges.sort()
    if any(current[0] < previous[1] for previous, current in zip(ranges, ranges[1:])):
        raise PlatformCodeSignatureError(f"{label} children overlap")
    return children


def _cstring(raw: bytes, offset: int, limit: int, label: str) -> str:
    if not 0 < offset < limit <= len(raw):
        raise PlatformCodeSignatureError(f"{label} offset is invalid")
    end = raw.find(b"\0", offset, limit)
    if end <= offset or end >= limit:
        raise PlatformCodeSignatureError(f"{label} is not terminated")
    try:
        value = raw[offset:end].decode("utf-8")
    except UnicodeDecodeError as error:
        raise PlatformCodeSignatureError(f"{label} is not UTF-8") from error
    if len(value.encode("utf-8")) > 255 or any(ord(character) < 32 for character in value):
        raise PlatformCodeSignatureError(f"{label} is outside the profile")
    return value


def _code_directory(raw: bytes) -> dict[str, Any]:
    _blob_header(raw, CSMAGIC_CODEDIRECTORY, MAX_CODEDIRECTORY_BYTES, "CodeDirectory")
    if len(raw) < 44:
        raise PlatformCodeSignatureError("CodeDirectory header is truncated")
    (
        version,
        flags,
        hash_offset,
        identifier_offset,
        special_slots,
        code_slots,
        _code_limit,
    ) = struct.unpack_from(">IIIIIII", raw, 8)
    hash_size, hash_type, _platform, page_size = struct.unpack_from(">BBBB", raw, 36)
    if (
        version < 0x20001
        or hash_type != CS_HASHTYPE_SHA256
        or hash_size != 32
        or page_size > 63
        or special_slots > 4096
        or code_slots > 1_048_576
    ):
        raise PlatformCodeSignatureError("CodeDirectory profile is unsupported")
    total_hashes = special_slots + code_slots
    if hash_offset > len(raw) or total_hashes > len(raw) // hash_size:
        raise PlatformCodeSignatureError("CodeDirectory hash inventory is invalid")
    special_bytes = special_slots * hash_size
    code_bytes = code_slots * hash_size
    data_limit = hash_offset - special_bytes
    minimum_header = 52 if version >= 0x20200 else 44
    if (
        hash_offset < special_bytes
        or hash_offset + code_bytes != len(raw)
        or data_limit < minimum_header
        or identifier_offset < minimum_header
    ):
        raise PlatformCodeSignatureError("CodeDirectory hash range is invalid")
    identifier = _cstring(
        raw,
        identifier_offset,
        data_limit,
        "CodeDirectory identifier",
    )
    team_offset = struct.unpack_from(">I", raw, 48)[0] if version >= 0x20200 and len(raw) >= 52 else 0
    team_identifier = (
        _cstring(raw, team_offset, data_limit, "CodeDirectory Team ID")
        if team_offset
        else None
    )
    digest = hashlib.sha256(raw).hexdigest()
    return {
        "hashType": "sha256",
        "cdhash": digest[:40],
        "codeDirectorySHA256": digest,
        "version": version,
        "flags": flags,
        "hardenedRuntime": bool(flags & CS_RUNTIME),
        "signingIdentifier": identifier,
        "teamIdentifier": team_identifier,
    }


def _designated_requirement(raw: bytes) -> tuple[str, int]:
    requirements = _superblob(
        raw,
        CSMAGIC_REQUIREMENTS,
        MAX_REQUIREMENTS_BYTES,
        "requirements SuperBlob",
    )
    designated = requirements.get(REQUIREMENT_TYPE_DESIGNATED)
    if designated is None:
        raise PlatformCodeSignatureError("explicit designated requirement is absent")
    if set(requirements) != {REQUIREMENT_TYPE_DESIGNATED}:
        raise PlatformCodeSignatureError(
            "additional internal requirements are outside v0.1"
        )
    _blob_header(
        designated,
        CSMAGIC_REQUIREMENT,
        MAX_REQUIREMENTS_BYTES,
        "designated requirement",
    )
    return hashlib.sha256(designated).hexdigest(), len(designated)


def _tag_entitlement_value(value: Any, budget: dict[str, int], depth: int) -> dict[str, Any]:
    if depth > MAX_ENTITLEMENT_DEPTH:
        raise PlatformCodeSignatureError("entitlement value exceeds the depth bound")
    budget["nodes"] += 1
    if budget["nodes"] > MAX_ENTITLEMENT_NODES:
        raise PlatformCodeSignatureError("entitlement node count exceeds the profile")
    if isinstance(value, bool):
        return {"type": "boolean", "value": value}
    if isinstance(value, int):
        if not -SAFE_INTEGER <= value <= SAFE_INTEGER:
            raise PlatformCodeSignatureError("entitlement integer is outside the safe range")
        return {"type": "integer", "value": value}
    if isinstance(value, str):
        try:
            encoded = value.encode("utf-8")
        except UnicodeEncodeError as error:
            raise PlatformCodeSignatureError("entitlement string is not UTF-8") from error
        if (
            not value
            or value != unicodedata.normalize("NFC", value)
            or len(encoded) > MAX_ENTITLEMENT_STRING_BYTES
            or any(ord(character) < 32 or ord(character) == 127 for character in value)
        ):
            raise PlatformCodeSignatureError("entitlement string is outside the profile")
        budget["stringBytes"] += len(encoded)
        if budget["stringBytes"] > MAX_ENTITLEMENT_TOTAL_STRING_BYTES:
            raise PlatformCodeSignatureError("entitlement string bytes exceed the profile")
        return {"type": "string", "value": value}
    if isinstance(value, list):
        if len(value) > MAX_ENTITLEMENT_CHILDREN:
            raise PlatformCodeSignatureError("entitlement array exceeds the child bound")
        return {
            "type": "array",
            "values": [
                _tag_entitlement_value(item, budget, depth + 1)
                for item in value
            ],
        }
    if isinstance(value, dict):
        return {
            "type": "dictionary",
            "entries": _tag_entitlement_entries(value, budget, depth + 1, False),
        }
    raise PlatformCodeSignatureError("entitlement value type is unsupported")


def _tag_entitlement_entries(
    value: dict[Any, Any],
    budget: dict[str, int],
    depth: int,
    top_level: bool,
) -> list[dict[str, Any]]:
    maximum = MAX_ENTITLEMENT_TOP_LEVEL_KEYS if top_level else MAX_ENTITLEMENT_CHILDREN
    if len(value) > maximum:
        raise PlatformCodeSignatureError("entitlement dictionary exceeds the child bound")
    entries: list[dict[str, Any]] = []
    for key in sorted(value, key=lambda item: item if isinstance(item, str) else ""):
        if not isinstance(key, str):
            raise PlatformCodeSignatureError("entitlement dictionary key is not text")
        try:
            encoded = key.encode("ascii")
        except UnicodeEncodeError as error:
            raise PlatformCodeSignatureError("entitlement key is not ASCII") from error
        if (
            not key
            or len(encoded) > MAX_ENTITLEMENT_KEY_BYTES
            or any(byte < 32 or byte == 127 for byte in encoded)
        ):
            raise PlatformCodeSignatureError("entitlement key is outside the profile")
        budget["keys"] += 1
        if budget["keys"] > MAX_ENTITLEMENT_KEYS:
            raise PlatformCodeSignatureError("entitlement key count exceeds the profile")
        entries.append({
            "key": key,
            "value": _tag_entitlement_value(value[key], budget, depth),
        })
    return entries


def entitlement_policy_from_plist(raw: bytes) -> dict[str, Any]:
    if not 1 <= len(raw) <= MAX_ENTITLEMENTS_BYTES:
        raise PlatformCodeSignatureError("embedded entitlements size is outside the profile")
    try:
        _reject_duplicate_plist_keys(raw)
        value = plistlib.loads(raw)
    except (
        SignedCodeGraphError,
        plistlib.InvalidFileException,
        ValueError,
        TypeError,
        OverflowError,
    ) as error:
        raise PlatformCodeSignatureError("embedded entitlements are not a valid plist") from error
    if not isinstance(value, dict):
        raise PlatformCodeSignatureError("embedded entitlements are not a dictionary")
    budget = {"keys": 0, "nodes": 0, "stringBytes": 0}
    result = {
        "mode": "exact",
        "entries": _tag_entitlement_entries(value, budget, 1, True),
    }
    try:
        _entitlements(result, _EntitlementBudget())
    except SigningPolicyError as error:
        raise PlatformCodeSignatureError("embedded entitlements exceed signing policy") from error
    return result


DER_TAG_BOOLEAN = 0x01
DER_TAG_INTEGER = 0x02
DER_TAG_UTF8_STRING = 0x0C
DER_TAG_SEQUENCE = 0x30
DER_TAG_CORE_ENTITLEMENTS = 0x70
DER_TAG_DICTIONARY = 0xB0


class _DEREntitlementBudget:
    def __init__(self) -> None:
        self.keys = 0
        self.nodes = 0
        self.string_bytes = 0

    def charge_key(self, raw: bytes) -> str:
        try:
            value = raw.decode("ascii")
        except UnicodeDecodeError as error:
            raise PlatformCodeSignatureError("DER entitlement key is not ASCII") from error
        if (
            not value
            or len(raw) > MAX_ENTITLEMENT_KEY_BYTES
            or any(byte < 32 or byte == 127 for byte in raw)
        ):
            raise PlatformCodeSignatureError("DER entitlement key is outside the profile")
        self.keys += 1
        if self.keys > MAX_ENTITLEMENT_KEYS:
            raise PlatformCodeSignatureError("DER entitlement key count exceeds the profile")
        return value

    def charge_node(self) -> None:
        self.nodes += 1
        if self.nodes > MAX_ENTITLEMENT_NODES:
            raise PlatformCodeSignatureError("DER entitlement node count exceeds the profile")

    def charge_string(self, raw: bytes) -> str:
        try:
            value = raw.decode("utf-8")
        except UnicodeDecodeError as error:
            raise PlatformCodeSignatureError("DER entitlement string is not UTF-8") from error
        if (
            not value
            or value != unicodedata.normalize("NFC", value)
            or len(raw) > MAX_ENTITLEMENT_STRING_BYTES
            or any(ord(character) < 32 or ord(character) == 127 for character in value)
        ):
            raise PlatformCodeSignatureError("DER entitlement string is outside the profile")
        self.string_bytes += len(raw)
        if self.string_bytes > MAX_ENTITLEMENT_TOTAL_STRING_BYTES:
            raise PlatformCodeSignatureError("DER entitlement string bytes exceed the profile")
        return value


def _der_tlv(
    raw: bytes,
    offset: int,
    limit: int,
    label: str,
) -> tuple[int, int, int, int]:
    if offset < 0 or limit > len(raw) or offset + 2 > limit:
        raise PlatformCodeSignatureError(f"{label} is truncated")
    tag = raw[offset]
    offset += 1
    first_length = raw[offset]
    offset += 1
    if first_length < 0x80:
        length = first_length
    else:
        length_bytes = first_length & 0x7F
        if (
            length_bytes == 0
            or length_bytes > 4
            or offset + length_bytes > limit
            or raw[offset] == 0
        ):
            raise PlatformCodeSignatureError(f"{label} length is not canonical DER")
        length = int.from_bytes(raw[offset:offset + length_bytes], "big")
        offset += length_bytes
        if length < 0x80:
            raise PlatformCodeSignatureError(f"{label} length is not canonical DER")
    end = offset + length
    if end > limit:
        raise PlatformCodeSignatureError(f"{label} value is truncated")
    return tag, offset, end, end


def _der_integer(raw: bytes, start: int, end: int, label: str) -> int:
    value = raw[start:end]
    if not value:
        raise PlatformCodeSignatureError(f"{label} integer is empty")
    if len(value) > 8:
        raise PlatformCodeSignatureError(f"{label} integer is outside the safe range")
    if len(value) > 1 and (
        (value[0] == 0x00 and value[1] & 0x80 == 0)
        or (value[0] == 0xFF and value[1] & 0x80 != 0)
    ):
        raise PlatformCodeSignatureError(f"{label} integer is not canonical DER")
    result = int.from_bytes(value, "big", signed=True)
    if not -SAFE_INTEGER <= result <= SAFE_INTEGER:
        raise PlatformCodeSignatureError(f"{label} integer is outside the safe range")
    return result


def _der_entitlement_value(
    raw: bytes,
    offset: int,
    limit: int,
    budget: _DEREntitlementBudget,
    depth: int,
) -> tuple[dict[str, Any], int]:
    if depth > MAX_ENTITLEMENT_DEPTH:
        raise PlatformCodeSignatureError("DER entitlement value exceeds the depth bound")
    tag, start, end, next_offset = _der_tlv(
        raw,
        offset,
        limit,
        "DER entitlement value",
    )
    budget.charge_node()
    if tag == DER_TAG_BOOLEAN:
        if end - start != 1 or raw[start] not in {0x00, 0xFF}:
            raise PlatformCodeSignatureError("DER entitlement Boolean is not canonical")
        result = {"type": "boolean", "value": raw[start] == 0xFF}
    elif tag == DER_TAG_INTEGER:
        result = {
            "type": "integer",
            "value": _der_integer(raw, start, end, "DER entitlement"),
        }
    elif tag == DER_TAG_UTF8_STRING:
        result = {"type": "string", "value": budget.charge_string(raw[start:end])}
    elif tag == DER_TAG_SEQUENCE:
        values: list[dict[str, Any]] = []
        cursor = start
        while cursor < end:
            if len(values) >= MAX_ENTITLEMENT_CHILDREN:
                raise PlatformCodeSignatureError("DER entitlement array exceeds the child bound")
            child, cursor = _der_entitlement_value(
                raw,
                cursor,
                end,
                budget,
                depth + 1,
            )
            values.append(child)
        result = {"type": "array", "values": values}
    elif tag == DER_TAG_DICTIONARY:
        entries = _der_entitlement_entries(
            raw,
            start,
            end,
            budget,
            depth + 1,
            top_level=False,
        )
        result = {"type": "dictionary", "entries": entries}
    else:
        raise PlatformCodeSignatureError("DER entitlement value type is unsupported")
    return result, next_offset


def _der_entitlement_entries(
    raw: bytes,
    offset: int,
    limit: int,
    budget: _DEREntitlementBudget,
    depth: int,
    *,
    top_level: bool,
) -> list[dict[str, Any]]:
    maximum = MAX_ENTITLEMENT_TOP_LEVEL_KEYS if top_level else MAX_ENTITLEMENT_CHILDREN
    entries: list[dict[str, Any]] = []
    keys: list[str] = []
    cursor = offset
    while cursor < limit:
        if len(entries) >= maximum:
            raise PlatformCodeSignatureError("DER entitlement dictionary exceeds the child bound")
        tag, entry_start, entry_end, cursor = _der_tlv(
            raw,
            cursor,
            limit,
            "DER entitlement dictionary entry",
        )
        if tag != DER_TAG_SEQUENCE:
            raise PlatformCodeSignatureError("DER entitlement dictionary entry tag is invalid")
        key_tag, key_start, key_end, value_offset = _der_tlv(
            raw,
            entry_start,
            entry_end,
            "DER entitlement dictionary key",
        )
        if key_tag != DER_TAG_UTF8_STRING:
            raise PlatformCodeSignatureError("DER entitlement dictionary key tag is invalid")
        key = budget.charge_key(raw[key_start:key_end])
        value, final_offset = _der_entitlement_value(
            raw,
            value_offset,
            entry_end,
            budget,
            depth,
        )
        if final_offset != entry_end:
            raise PlatformCodeSignatureError("DER entitlement dictionary entry has trailing data")
        keys.append(key)
        entries.append({"key": key, "value": value})
    if cursor != limit:
        raise PlatformCodeSignatureError("DER entitlement dictionary is truncated")
    if keys != sorted(keys) or len(set(keys)) != len(keys):
        raise PlatformCodeSignatureError("DER entitlement keys are not uniquely sorted")
    return entries


def entitlement_policy_from_der(raw: bytes) -> dict[str, Any]:
    if not 1 <= len(raw) <= MAX_ENTITLEMENTS_BYTES:
        raise PlatformCodeSignatureError("embedded DER entitlements size is outside the profile")
    tag, root_start, root_end, root_next = _der_tlv(
        raw,
        0,
        len(raw),
        "embedded DER entitlements",
    )
    if tag != DER_TAG_CORE_ENTITLEMENTS or root_next != len(raw):
        raise PlatformCodeSignatureError("embedded DER entitlements envelope is invalid")
    version_tag, version_start, version_end, dictionary_offset = _der_tlv(
        raw,
        root_start,
        root_end,
        "DER entitlement version",
    )
    if (
        version_tag != DER_TAG_INTEGER
        or _der_integer(raw, version_start, version_end, "DER entitlement version") != 1
    ):
        raise PlatformCodeSignatureError("DER entitlement version is unsupported")
    dictionary_tag, dictionary_start, dictionary_end, final_offset = _der_tlv(
        raw,
        dictionary_offset,
        root_end,
        "DER entitlement root dictionary",
    )
    if dictionary_tag != DER_TAG_DICTIONARY or final_offset != root_end:
        raise PlatformCodeSignatureError("DER entitlement root dictionary is invalid")
    budget = _DEREntitlementBudget()
    result = {
        "mode": "exact",
        "entries": _der_entitlement_entries(
            raw,
            dictionary_start,
            dictionary_end,
            budget,
            1,
            top_level=True,
        ),
    }
    try:
        _entitlements(result, _EntitlementBudget())
    except SigningPolicyError as error:
        raise PlatformCodeSignatureError("embedded DER entitlements exceed signing policy") from error
    return result


def _entitlements_from_blobs(blobs: dict[int, bytes]) -> tuple[dict[str, Any], dict[str, Any]]:
    xml_blob = blobs.get(CSSLOT_ENTITLEMENTS)
    der_blob = blobs.get(CSSLOT_DER_ENTITLEMENTS)
    if xml_blob is None:
        if der_blob is not None:
            raise PlatformCodeSignatureError("DER-only entitlements are outside v0.1")
        return {"mode": "absent"}, {
            "xmlSHA256": None,
            "derSHA256": None,
        }
    _blob_header(
        xml_blob,
        CSMAGIC_EMBEDDED_ENTITLEMENTS,
        MAX_ENTITLEMENTS_BYTES,
        "embedded XML entitlements",
    )
    policy = entitlement_policy_from_plist(xml_blob[8:])
    if der_blob is not None:
        _blob_header(
            der_blob,
            CSMAGIC_EMBEDDED_DER_ENTITLEMENTS,
            MAX_ENTITLEMENTS_BYTES,
            "embedded DER entitlements",
        )
        der_policy = entitlement_policy_from_der(der_blob[8:])
        if der_policy != policy:
            raise PlatformCodeSignatureError(
                "embedded XML and DER entitlement semantics differ"
            )
    return policy, {
        "xmlSHA256": hashlib.sha256(xml_blob).hexdigest(),
        "derSHA256": hashlib.sha256(der_blob).hexdigest() if der_blob is not None else None,
    }


def inspect_embedded_signature(
    *,
    object_path: Path,
    graph_architecture: dict[str, Any],
) -> dict[str, Any]:
    try:
        descriptor = os.open(object_path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError as error:
        raise PlatformCodeSignatureError("Mach-O object is unavailable without following links") from error
    try:
        before = os.fstat(descriptor)
        if (
            not stat.S_ISREG(before.st_mode)
            or before.st_nlink != 1
            or before.st_size <= 0
        ):
            raise PlatformCodeSignatureError("Mach-O object has unsafe filesystem facts")
        try:
            cpu_type = graph_architecture["cpuType"]
            cpu_subtype = graph_architecture["cpuSubtype"]
            slice_offset = graph_architecture["sliceOffset"]
            slice_bytes = graph_architecture["sliceBytes"]
            expected_slice_sha256 = graph_architecture["sliceSHA256"]
        except (KeyError, TypeError) as error:
            raise PlatformCodeSignatureError("graph architecture is incomplete") from error
        if (
            not isinstance(cpu_type, int)
            or isinstance(cpu_type, bool)
            or not isinstance(cpu_subtype, int)
            or isinstance(cpu_subtype, bool)
            or not isinstance(slice_offset, int)
            or isinstance(slice_offset, bool)
            or not isinstance(slice_bytes, int)
            or isinstance(slice_bytes, bool)
            or slice_offset < 0
            or slice_bytes <= 0
            or slice_offset + slice_bytes > before.st_size
        ):
            raise PlatformCodeSignatureError("graph slice range is invalid")

        try:
            with os.fdopen(os.dup(descriptor), "rb") as handle:
                macho = _macho_facts(handle, before.st_size)
        except SignedCodeGraphError as error:
            raise PlatformCodeSignatureError("Mach-O inventory could not be rederived") from error
        if not isinstance(macho, dict):
            raise PlatformCodeSignatureError("object is not a supported Mach-O")
        matching = [
            item
            for item in macho.get("architectures", [])
            if item.get("cpuType") == cpu_type
            and item.get("cpuSubtype") == cpu_subtype
        ]
        if (
            len(matching) != 1
            or matching[0] != graph_architecture
            or matching[0]["sliceSHA256"] != expected_slice_sha256
        ):
            raise PlatformCodeSignatureError("Mach-O architecture differs from the signed-code graph")
        observed_architecture = matching[0]
        signature = observed_architecture.get("codeSignature")
        if not isinstance(signature, dict):
            raise PlatformCodeSignatureError("Mach-O architecture lacks an embedded signature")
        signature_offset = signature.get("offset")
        signature_bytes = signature.get("bytes")
        if (
            not isinstance(signature_offset, int)
            or not isinstance(signature_bytes, int)
            or not 0 < signature_bytes <= MAX_EMBEDDED_SIGNATURE_BYTES
            or signature_offset < 0
            or signature_offset + signature_bytes > slice_bytes
        ):
            raise PlatformCodeSignatureError("embedded-signature range is invalid")
        raw_signature = _read_exact_at(
            descriptor,
            slice_offset + signature_offset,
            signature_bytes,
        )
        after = os.fstat(descriptor)
        if _descriptor_identity(before) != _descriptor_identity(after):
            raise PlatformCodeSignatureError("Mach-O object changed during signature inspection")
    finally:
        os.close(descriptor)

    if len(raw_signature) < 8:
        raise PlatformCodeSignatureError("embedded signature SuperBlob is truncated")
    magic, declared_signature_bytes = struct.unpack_from(">II", raw_signature, 0)
    padding = raw_signature[declared_signature_bytes:]
    if (
        magic != CSMAGIC_EMBEDDED_SIGNATURE
        or not 8 <= declared_signature_bytes <= len(raw_signature)
        or len(padding) > 15
    ):
        raise PlatformCodeSignatureError(
            "embedded signature SuperBlob range or trailing alignment is invalid"
        )
    signature_superblob = raw_signature[:declared_signature_bytes]
    blobs = _superblob(
        signature_superblob,
        CSMAGIC_EMBEDDED_SIGNATURE,
        MAX_EMBEDDED_SIGNATURE_BYTES,
        "embedded signature SuperBlob",
    )
    permitted_slots = {
        CSSLOT_CODEDIRECTORY,
        CSSLOT_REQUIREMENTS,
        CSSLOT_ENTITLEMENTS,
        CSSLOT_DER_ENTITLEMENTS,
        CSSLOT_SIGNATURE,
    } | set(CSSLOT_ALTERNATE_CODEDIRECTORIES)
    if not set(blobs) <= permitted_slots:
        raise PlatformCodeSignatureError(
            "embedded signature contains an unsupported slot"
        )
    code_directory_slots = [
        slot
        for slot in blobs
        if slot == CSSLOT_CODEDIRECTORY or slot in CSSLOT_ALTERNATE_CODEDIRECTORIES
    ]
    if code_directory_slots != [CSSLOT_CODEDIRECTORY]:
        raise PlatformCodeSignatureError("embedded signature does not contain exactly one primary CodeDirectory")
    code_directory = _code_directory(blobs[CSSLOT_CODEDIRECTORY])
    requirements = blobs.get(CSSLOT_REQUIREMENTS)
    if requirements is None:
        raise PlatformCodeSignatureError("embedded signature lacks requirements")
    requirement_sha256, requirement_bytes = _designated_requirement(requirements)
    cms = blobs.get(CSSLOT_SIGNATURE)
    if cms is None:
        raise PlatformCodeSignatureError("embedded signature lacks a CMS signature")
    _blob_header(cms, CSMAGIC_BLOBWRAPPER, MAX_EMBEDDED_SIGNATURE_BYTES, "CMS signature wrapper")
    if len(cms) == 8:
        raise PlatformCodeSignatureError("CMS signature wrapper is empty")
    entitlements, entitlement_blobs = _entitlements_from_blobs(blobs)
    return {
        "cpuType": observed_architecture["cpuType"],
        "cpuSubtype": observed_architecture["cpuSubtype"],
        "sliceSHA256": observed_architecture["sliceSHA256"],
        "signingIdentifier": code_directory["signingIdentifier"],
        "teamIdentifier": code_directory["teamIdentifier"],
        "codeDirectories": [{
            key: code_directory[key]
            for key in ("hashType", "cdhash", "codeDirectorySHA256")
        }],
        "codeDirectoryVersion": code_directory["version"],
        "codeDirectoryFlags": code_directory["flags"],
        "hardenedRuntime": code_directory["hardenedRuntime"],
        "designatedRequirementDataSHA256": requirement_sha256,
        "designatedRequirementBytes": requirement_bytes,
        "entitlements": entitlements,
        "entitlementBlobs": entitlement_blobs,
        "cmsSHA256": hashlib.sha256(cms).hexdigest(),
        "embeddedSignatureSHA256": hashlib.sha256(raw_signature).hexdigest(),
        "signatureSuperBlobSHA256": hashlib.sha256(signature_superblob).hexdigest(),
        "signaturePaddingBytes": len(padding),
    }


def compare_architecture_to_policy(
    *,
    facts: dict[str, Any],
    policy_architecture: dict[str, Any],
    leaf_certificate_sha256: str,
    secure_timestamp_present: bool,
    codesign_verified: bool,
    explicit_requirement_verified: bool,
) -> dict[str, Any]:
    try:
        identity = policy_architecture["identity"]
        signature = policy_architecture["signature"]
        expected_facts = {
            "cpuType": policy_architecture["cpuType"],
            "cpuSubtype": policy_architecture["cpuSubtype"],
            "sliceSHA256": policy_architecture["sliceSHA256"],
            "signingIdentifier": identity["signingIdentifier"],
            "teamIdentifier": identity["teamIdentifier"],
            "codeDirectories": identity["codeDirectories"],
            "designatedRequirementDataSHA256": identity["designatedRequirementDataSHA256"],
            "entitlements": policy_architecture["entitlements"],
        }
        observed_facts = {key: facts[key] for key in expected_facts}
    except (KeyError, TypeError) as error:
        raise PlatformCodeSignatureError("signature facts or policy architecture are incomplete") from error
    if observed_facts != expected_facts:
        raise PlatformCodeSignatureError("embedded signature facts differ from signing policy")
    expected_leaf = identity.get("leafCertificateSHA256")
    if leaf_certificate_sha256 != expected_leaf:
        raise PlatformCodeSignatureError("leaf certificate differs from signing policy")
    required_runtime = signature.get("requireHardenedRuntime")
    required_timestamp = signature.get("requireSecureTimestamp")
    if not isinstance(required_runtime, bool) or not isinstance(required_timestamp, bool):
        raise PlatformCodeSignatureError("signature policy requirements are invalid")
    if bool(facts.get("hardenedRuntime")) != required_runtime:
        raise PlatformCodeSignatureError("hardened-runtime fact differs from signing policy")
    if secure_timestamp_present != required_timestamp:
        raise PlatformCodeSignatureError("secure-timestamp fact differs from signing policy")
    if codesign_verified is not True or explicit_requirement_verified is not True:
        raise PlatformCodeSignatureError("Apple verification or explicit requirement did not pass")
    return {
        "status": "passed",
        "policyMatched": True,
        "platformAcceptanceEligible": False,
        "trustProfile": signature.get("trustProfile"),
        "cpuType": facts["cpuType"],
        "cpuSubtype": facts["cpuSubtype"],
        "sliceSHA256": facts["sliceSHA256"],
        "codeDirectorySHA256": facts["codeDirectories"][0]["codeDirectorySHA256"],
        "designatedRequirementDataSHA256": facts["designatedRequirementDataSHA256"],
        "leafCertificateSHA256": leaf_certificate_sha256,
        "secureTimestampPresent": secure_timestamp_present,
        "codesignVerified": True,
        "explicitRequirementVerified": True,
    }
