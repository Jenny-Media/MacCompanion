#!/usr/bin/env python3

from __future__ import annotations

import copy
import hashlib
import io
import os
import plistlib
import struct
import tempfile
from pathlib import Path
from typing import Any

from platform_code_signature import (
    CSMAGIC_BLOBWRAPPER,
    CSMAGIC_CODEDIRECTORY,
    CSMAGIC_EMBEDDED_DER_ENTITLEMENTS,
    CSMAGIC_EMBEDDED_ENTITLEMENTS,
    CSMAGIC_EMBEDDED_SIGNATURE,
    CSMAGIC_REQUIREMENT,
    CSMAGIC_REQUIREMENTS,
    CSSLOT_CODEDIRECTORY,
    CSSLOT_DER_ENTITLEMENTS,
    CSSLOT_ENTITLEMENTS,
    CSSLOT_REQUIREMENTS,
    CSSLOT_SIGNATURE,
    CS_RUNTIME,
    PlatformCodeSignatureError,
    compare_architecture_to_policy,
    entitlement_policy_from_der,
    entitlement_policy_from_plist,
    inspect_embedded_signature,
)
from signed_code_graph import _macho_facts, _thin_architecture


CPU_TYPE = 0x0100000C
CPU_SUBTYPE = 2
TEAM_ID = "ABCDE12345"
SIGNING_IDENTIFIER = "media.jenny.maccompanion.fixture"
LEAF_CERTIFICATE_SHA256 = hashlib.sha256(b"fixture leaf certificate").hexdigest()


def blob(magic: int, payload: bytes) -> bytes:
    return struct.pack(">II", magic, 8 + len(payload)) + payload


def superblob(magic: int, children: list[tuple[int, bytes]]) -> bytes:
    table_bytes = 12 + len(children) * 8
    cursor = table_bytes
    indexes = []
    payload = bytearray()
    for slot, child in children:
        indexes.append(struct.pack(">II", slot, cursor))
        payload.extend(child)
        cursor += len(child)
    return (
        struct.pack(">III", magic, cursor, len(children))
        + b"".join(indexes)
        + bytes(payload)
    )


def code_directory(*, runtime: bool = True) -> bytes:
    identifier = SIGNING_IDENTIFIER.encode("utf-8") + b"\0"
    team = TEAM_ID.encode("ascii") + b"\0"
    identifier_offset = 52
    team_offset = identifier_offset + len(identifier)
    length = team_offset + len(team)
    header = struct.pack(
        ">IIIIIIIIIBBBBIII",
        CSMAGIC_CODEDIRECTORY,
        length,
        0x20200,
        CS_RUNTIME if runtime else 0,
        length,
        identifier_offset,
        0,
        0,
        0,
        32,
        2,
        1,
        14,
        0,
        0,
        team_offset,
    )
    return header + identifier + team


def requirements(*, designated: bool = True) -> bytes:
    child = blob(CSMAGIC_REQUIREMENT, struct.pack(">I", 1))
    return superblob(
        CSMAGIC_REQUIREMENTS,
        [(3 if designated else 1, child)],
    )


def entitlements_blob(value: dict[str, Any]) -> bytes:
    raw = plistlib.dumps(value, fmt=plistlib.FMT_XML, sort_keys=True)
    return blob(CSMAGIC_EMBEDDED_ENTITLEMENTS, raw)


def der_length(value: int) -> bytes:
    if value < 0x80:
        return bytes([value])
    raw = value.to_bytes((value.bit_length() + 7) // 8, "big")
    return bytes([0x80 | len(raw)]) + raw


def der_tlv(tag: int, value: bytes) -> bytes:
    return bytes([tag]) + der_length(len(value)) + value


def der_integer(value: int) -> bytes:
    if value == 0:
        raw = b"\0"
    else:
        size = max(1, (value.bit_length() + 8) // 8)
        raw = value.to_bytes(size, "big", signed=True)
        while len(raw) > 1 and (
            (raw[0] == 0 and raw[1] & 0x80 == 0)
            or (raw[0] == 0xFF and raw[1] & 0x80 != 0)
        ):
            raw = raw[1:]
    return der_tlv(0x02, raw)


def der_value(value: Any) -> bytes:
    if isinstance(value, bool):
        return der_tlv(0x01, b"\xff" if value else b"\0")
    if isinstance(value, int):
        return der_integer(value)
    if isinstance(value, str):
        return der_tlv(0x0C, value.encode("utf-8"))
    if isinstance(value, list):
        return der_tlv(0x30, b"".join(der_value(item) for item in value))
    if isinstance(value, dict):
        return der_dictionary(value)
    raise TypeError("unsupported DER fixture value")


def der_dictionary(value: dict[str, Any]) -> bytes:
    entries = []
    for key in sorted(value):
        entries.append(
            der_tlv(0x30, der_tlv(0x0C, key.encode("ascii")) + der_value(value[key]))
        )
    return der_tlv(0xB0, b"".join(entries))


def der_entitlements(value: dict[str, Any]) -> bytes:
    return der_tlv(0x70, der_integer(1) + der_dictionary(value))


def embedded_signature(
    *,
    runtime: bool = True,
    designated: bool = True,
    entitlements: dict[str, Any] | None = None,
    include_requirements: bool = True,
    include_cms: bool = True,
    include_alternate: bool = False,
    der_only: bool = False,
    include_der: bool = False,
    der_value_override: dict[str, Any] | None = None,
    unknown_slot: bool = False,
    additional_requirement: bool = False,
) -> bytes:
    children: list[tuple[int, bytes]] = [
        (CSSLOT_CODEDIRECTORY, code_directory(runtime=runtime)),
    ]
    if include_requirements:
        requirement_blob = requirements(designated=designated)
        if additional_requirement:
            child = blob(CSMAGIC_REQUIREMENT, struct.pack(">I", 1))
            requirement_blob = superblob(
                CSMAGIC_REQUIREMENTS,
                [(3, child), (1, child)],
            )
        children.append((CSSLOT_REQUIREMENTS, requirement_blob))
    if entitlements is not None and not der_only:
        children.append((CSSLOT_ENTITLEMENTS, entitlements_blob(entitlements)))
    if der_only or include_der:
        der_source = (
            der_value_override
            if der_value_override is not None
            else entitlements if entitlements is not None
            else {}
        )
        children.append((
            CSSLOT_DER_ENTITLEMENTS,
            blob(CSMAGIC_EMBEDDED_DER_ENTITLEMENTS, der_entitlements(der_source)),
        ))
    if include_alternate:
        children.append((0x1000, code_directory(runtime=runtime)))
    if include_cms:
        children.append((CSSLOT_SIGNATURE, blob(CSMAGIC_BLOBWRAPPER, b"fixture-cms")))
    if unknown_slot:
        children.append((42, blob(CSMAGIC_BLOBWRAPPER, b"unknown")))
    return superblob(CSMAGIC_EMBEDDED_SIGNATURE, children)


def macho(
    signature: bytes,
    *,
    cpu_type: int = CPU_TYPE,
    cpu_subtype: int = CPU_SUBTYPE,
) -> bytes:
    build = struct.pack("<IIIIII", 0x32, 24, 1, 0x001A0000, 0x001B0000, 0)
    signature_offset = 32 + len(build) + 16
    signature_command = struct.pack("<IIII", 0x1D, 16, signature_offset, len(signature))
    header = struct.pack(
        "<IIIIIIII",
        0xFEEDFACF,
        cpu_type,
        cpu_subtype,
        2,
        2,
        len(build) + len(signature_command),
        0,
        0,
    )
    return header + build + signature_command + signature


def fat_macho(signature: bytes) -> bytes:
    arm = macho(signature)
    x86 = macho(signature, cpu_type=0x01000007, cpu_subtype=3)
    first = 64
    second = ((first + len(arm) + 15) // 16) * 16
    header = struct.pack(">II", 0xCAFEBABE, 2)
    table = struct.pack(">IIIII", CPU_TYPE, CPU_SUBTYPE, first, len(arm), 4)
    table += struct.pack(">IIIII", 0x01000007, 3, second, len(x86), 4)
    result = bytearray(header + table)
    result.extend(b"\0" * (first - len(result)))
    result.extend(arm)
    result.extend(b"\0" * (second - len(result)))
    result.extend(x86)
    return bytes(result)


def architecture(raw: bytes) -> dict[str, Any]:
    return _thin_architecture(
        lambda offset, count: raw[offset:offset + count],
        lambda offset, count: hashlib.sha256(raw[offset:offset + count]).hexdigest(),
        0,
        len(raw),
    )


def inspect(root: Path, signature: bytes) -> tuple[Path, dict[str, Any], dict[str, Any]]:
    raw = macho(signature)
    path = root / "fixture"
    path.write_bytes(raw)
    graph_architecture = architecture(raw)
    facts = inspect_embedded_signature(
        object_path=path,
        graph_architecture=graph_architecture,
    )
    return path, graph_architecture, facts


def policy_for(facts: dict[str, Any], *, runtime: bool = True, timestamp: bool = True) -> dict[str, Any]:
    return {
        "cpuType": facts["cpuType"],
        "cpuSubtype": facts["cpuSubtype"],
        "sliceSHA256": facts["sliceSHA256"],
        "identity": {
            "signingIdentifier": facts["signingIdentifier"],
            "teamIdentifier": facts["teamIdentifier"],
            "codeDirectories": facts["codeDirectories"],
            "leafCertificateSHA256": LEAF_CERTIFICATE_SHA256,
            "designatedRequirementDataSHA256": facts["designatedRequirementDataSHA256"],
        },
        "signature": {
            "trustProfile": "developerIDApplication",
            "requireHardenedRuntime": runtime,
            "requireSecureTimestamp": timestamp,
        },
        "entitlements": facts["entitlements"],
    }


def require_failure(operation, expected: str) -> None:
    try:
        operation()
    except PlatformCodeSignatureError as error:
        if expected not in str(error):
            raise RuntimeError(
                f"expected signature failure containing {expected!r}, got {error!r}"
            ) from error
    else:
        raise RuntimeError(f"expected signature failure containing {expected!r}")


def main() -> int:
    exact_entitlements = {
        "com.apple.security.network.client": True,
        "com.example.mode": "fixture",
        "com.example.nested": {"count": 3, "values": ["one", "two"]},
    }
    duplicate_xml = b"""<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>duplicate</key><true/>
<key>duplicate</key><false/>
</dict></plist>
"""
    require_failure(
        lambda: entitlement_policy_from_plist(duplicate_xml),
        "not a valid plist",
    )
    apple_codesign_vector = bytes.fromhex(
        "7053020101b04e30180c07612d6172726179300d0c0566697273740201fe010100"
        "300b0c06622d626f6f6c0101ff30180c06632d64696374b00e300c0c066e657374"
        "656402020101300b0c06642d7a65726f020100"
    )
    apple_codesign_value = {
        "a-array": ["first", -2, False],
        "b-bool": True,
        "c-dict": {"nested": 257},
        "d-zero": 0,
    }
    if (
        der_entitlements(apple_codesign_value) != apple_codesign_vector
        or entitlement_policy_from_der(apple_codesign_vector)
        != entitlement_policy_from_plist(
            plistlib.dumps(apple_codesign_value, fmt=plistlib.FMT_XML, sort_keys=True)
        )
    ):
        raise RuntimeError("Apple codesign DER entitlement vector changed")
    with tempfile.TemporaryDirectory(prefix="maccompanion-embedded-signature-") as value:
        root = Path(value)
        path, graph_architecture, facts = inspect(
            root,
            embedded_signature(entitlements=exact_entitlements, include_der=True),
        )
        if (
            facts["signingIdentifier"] != SIGNING_IDENTIFIER
            or facts["teamIdentifier"] != TEAM_ID
            or facts["hardenedRuntime"] is not True
            or facts["entitlements"]["mode"] != "exact"
            or facts["codeDirectories"][0]["cdhash"]
            != facts["codeDirectories"][0]["codeDirectorySHA256"][:40]
            or facts["designatedRequirementBytes"] != 12
            or facts["entitlementBlobs"]["derSHA256"] is None
        ):
            raise RuntimeError("embedded signature facts are incomplete")
        result = compare_architecture_to_policy(
            facts=facts,
            policy_architecture=policy_for(facts),
            leaf_certificate_sha256=LEAF_CERTIFICATE_SHA256,
            secure_timestamp_present=True,
            codesign_verified=True,
            explicit_requirement_verified=True,
        )
        if result["status"] != "passed" or result["platformAcceptanceEligible"] is not False:
            raise RuntimeError("policy comparison changed its non-acceptance boundary")

        fat_raw = fat_macho(embedded_signature(entitlements=exact_entitlements))
        fat_path = root / "fat-fixture"
        fat_path.write_bytes(fat_raw)
        fat_facts = _macho_facts(io.BytesIO(fat_raw), len(fat_raw))
        if fat_facts is None or fat_facts["format"] != "fat32":
            raise RuntimeError("fat signature fixture is invalid")
        for fat_architecture in fat_facts["architectures"]:
            inspected = inspect_embedded_signature(
                object_path=fat_path,
                graph_architecture=fat_architecture,
            )
            if (
                inspected["cpuType"] != fat_architecture["cpuType"]
                or inspected["cpuSubtype"] != fat_architecture["cpuSubtype"]
            ):
                raise RuntimeError("fat architecture signature was miscorrelated")

        changed_graph = copy.deepcopy(graph_architecture)
        changed_graph["sliceSHA256"] = "0" * 64
        require_failure(
            lambda: inspect_embedded_signature(
                object_path=path,
                graph_architecture=changed_graph,
            ),
            "differs from the signed-code graph",
        )

        link = root / "fixture-link"
        link.symlink_to(path.name)
        require_failure(
            lambda: inspect_embedded_signature(
                object_path=link,
                graph_architecture=graph_architecture,
            ),
            "without following links",
        )

    invalid_cases = [
        (embedded_signature(include_requirements=False), "lacks requirements"),
        (embedded_signature(designated=False), "designated requirement is absent"),
        (embedded_signature(include_cms=False), "lacks a CMS signature"),
        (embedded_signature(include_alternate=True), "exactly one primary CodeDirectory"),
        (embedded_signature(der_only=True), "DER-only entitlements"),
        (
            embedded_signature(
                entitlements={"fixture": True},
                include_der=True,
                der_value_override={"fixture": False},
            ),
            "semantics differ",
        ),
        (embedded_signature(unknown_slot=True), "unsupported slot"),
        (embedded_signature(additional_requirement=True), "additional internal requirements"),
        (embedded_signature(entitlements={"unsupported": b"data"}), "value type is unsupported"),
    ]
    for index, (signature, expected) in enumerate(invalid_cases):
        with tempfile.TemporaryDirectory(prefix=f"maccompanion-signature-invalid-{index}-") as value:
            root = Path(value)
            raw = macho(signature)
            path = root / "fixture"
            path.write_bytes(raw)
            graph_architecture = architecture(raw)
            require_failure(
                lambda path=path, graph_architecture=graph_architecture: inspect_embedded_signature(
                    object_path=path,
                    graph_architecture=graph_architecture,
                ),
                expected,
            )

    duplicate_entry = der_tlv(
        0x30,
        der_tlv(0x0C, b"same") + der_tlv(0x01, b"\xff"),
    )
    invalid_der_cases = [
        (b"", "size is outside"),
        (der_tlv(0x71, der_integer(1) + der_dictionary({})), "envelope"),
        (der_entitlements({}) + b"\0", "envelope"),
        (der_tlv(0x70, der_integer(2) + der_dictionary({})), "version is unsupported"),
        (b"\x70\x81\x05\x02\x01\x01\xb0\x00", "length is not canonical"),
        (der_tlv(0x70, der_integer(1)), "root dictionary"),
        (
            der_tlv(0x70, der_integer(1) + der_tlv(0xB0, duplicate_entry + duplicate_entry)),
            "not uniquely sorted",
        ),
        (
            der_tlv(
                0x70,
                der_integer(1)
                + der_tlv(
                    0xB0,
                    der_tlv(0x30, der_tlv(0x0C, b"z") + der_tlv(0x01, b"\xff"))
                    + der_tlv(0x30, der_tlv(0x0C, b"a") + der_tlv(0x01, b"\xff")),
                ),
            ),
            "not uniquely sorted",
        ),
        (
            der_tlv(
                0x70,
                der_integer(1)
                + der_tlv(
                    0xB0,
                    der_tlv(0x30, der_tlv(0x0C, b"bool") + der_tlv(0x01, b"\x01")),
                ),
            ),
            "Boolean is not canonical",
        ),
        (
            der_tlv(
                0x70,
                der_integer(1)
                + der_tlv(
                    0xB0,
                    der_tlv(0x30, der_tlv(0x0C, b"integer") + der_tlv(0x02, b"\0\x01")),
                ),
            ),
            "integer is not canonical",
        ),
        (
            der_tlv(
                0x70,
                der_integer(1)
                + der_tlv(
                    0xB0,
                    der_tlv(0x30, der_tlv(0x0C, b"string") + der_tlv(0x0C, b"\xff")),
                ),
            ),
            "string is not UTF-8",
        ),
        (
            der_tlv(
                0x70,
                der_integer(1)
                + der_tlv(
                    0xB0,
                    der_tlv(0x30, der_tlv(0x0C, b"unsupported") + der_tlv(0x04, b"data")),
                ),
            ),
            "value type is unsupported",
        ),
    ]
    invalid_der_cases.extend([
        (der_entitlements({"unsafe": 9_007_199_254_740_992}), "outside the safe range"),
        (der_entitlements({"array": [True] * 65}), "array exceeds the child bound"),
        (
            der_entitlements({f"key-{index:03d}": True for index in range(129)}),
            "dictionary exceeds the child bound",
        ),
        (
            der_entitlements({"a": {"b": {"c": {"d": {"e": True}}}}}),
            "exceeds the depth bound",
        ),
        (der_entitlements({"string": "e\u0301"}), "string is outside the profile"),
        (der_entitlements({"string": "line\nfeed"}), "string is outside the profile"),
        (der_entitlements({"k" * 129: True}), "key is outside the profile"),
    ])
    for raw, expected in invalid_der_cases:
        require_failure(lambda raw=raw: entitlement_policy_from_der(raw), expected)

    with tempfile.TemporaryDirectory(prefix="maccompanion-signature-policy-") as value:
        _, _, facts = inspect(Path(value), embedded_signature())
        policy = policy_for(facts)
        changed = copy.deepcopy(policy)
        changed["identity"]["signingIdentifier"] += ".substituted"
        require_failure(
            lambda: compare_architecture_to_policy(
                facts=facts,
                policy_architecture=changed,
                leaf_certificate_sha256=LEAF_CERTIFICATE_SHA256,
                secure_timestamp_present=True,
                codesign_verified=True,
                explicit_requirement_verified=True,
            ),
            "facts differ",
        )
        require_failure(
            lambda: compare_architecture_to_policy(
                facts=facts,
                policy_architecture=policy,
                leaf_certificate_sha256="0" * 64,
                secure_timestamp_present=True,
                codesign_verified=True,
                explicit_requirement_verified=True,
            ),
            "leaf certificate differs",
        )
        require_failure(
            lambda: compare_architecture_to_policy(
                facts=facts,
                policy_architecture=policy,
                leaf_certificate_sha256=LEAF_CERTIFICATE_SHA256,
                secure_timestamp_present=False,
                codesign_verified=True,
                explicit_requirement_verified=True,
            ),
            "timestamp",
        )
        require_failure(
            lambda: compare_architecture_to_policy(
                facts=facts,
                policy_architecture=policy,
                leaf_certificate_sha256=LEAF_CERTIFICATE_SHA256,
                secure_timestamp_present=True,
                codesign_verified=False,
                explicit_requirement_verified=True,
            ),
            "did not pass",
        )
        runtime_policy = policy_for(facts, runtime=False)
        require_failure(
            lambda: compare_architecture_to_policy(
                facts=facts,
                policy_architecture=runtime_policy,
                leaf_certificate_sha256=LEAF_CERTIFICATE_SHA256,
                secure_timestamp_present=True,
                codesign_verified=True,
                explicit_requirement_verified=True,
            ),
            "hardened-runtime",
        )

    print(
        "Validated descriptor-bound per-architecture embedded CodeDirectory, "
        "requirement, CMS, runtime, entitlement, and policy correlation facts."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
