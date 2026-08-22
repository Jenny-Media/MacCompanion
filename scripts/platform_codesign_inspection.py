#!/usr/bin/env python3

from __future__ import annotations

import re
from typing import Any

from platform_code_signature import (
    PlatformCodeSignatureError,
    entitlement_policy_from_plist,
)
from platform_codesign_verification import INVOCATION_RESULT_KEYS
from platform_signing_subjects import PlannedCodeSignArchitectureInspection


SHA1_PATTERN = re.compile(r"^[0-9a-f]{40}$")
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
TEAM_PATTERN = re.compile(r"^[A-Z0-9]{10}$")
REQUIREMENT_LINE = re.compile(r"^[a-z][a-z0-9-]{0,31} => .{1,4096}$")
MAX_DISPLAY_LINES = 256
MAX_REQUIREMENT_LINES = 8
MAX_LINE_BYTES = 4096


class PlatformCodesignInspectionError(ValueError):
    pass


def _failed_result(invocation_result: dict[str, Any]) -> dict[str, Any]:
    termination = invocation_result.get("termination")
    return_code = invocation_result.get("returnCode")
    if termination != "exited":
        reason = termination if isinstance(termination, str) else "invalidResult"
    elif return_code != 0:
        reason = "nonzeroExit"
    elif invocation_result.get("toolUnchanged") is not True:
        reason = "toolChanged"
    else:
        reason = "fixedRunnerRejected"
    return {"status": "failed", "reason": reason}


def _validate_result(
    plan: PlannedCodeSignArchitectureInspection,
    invocation_result: dict[str, Any],
    *,
    identity: bool,
) -> dict[str, Any] | None:
    invocation = plan.identity_invocation if identity else plan.entitlements_invocation
    if not isinstance(invocation_result, dict) or set(invocation_result) != INVOCATION_RESULT_KEYS:
        raise PlatformCodesignInspectionError(
            "codesign inspection invocation result is not closed"
        )
    if (
        invocation_result.get("invocationID") != invocation.invocation_id
        or invocation_result.get("tool") != invocation.tool.public_record()
        or invocation_result.get("argv")
        != [invocation.tool.path, *invocation.arguments]
    ):
        raise PlatformCodesignInspectionError(
            "codesign inspection result differs from its fixed plan"
        )
    if invocation_result.get("passed") is not True:
        return _failed_result(invocation_result)
    if (
        invocation_result.get("termination") != "exited"
        or invocation_result.get("returnCode") != 0
        or invocation_result.get("toolUnchanged") is not True
    ):
        raise PlatformCodesignInspectionError(
            "codesign inspection success contains contradictory facts"
        )
    return None


def _lines(raw: bytes, label: str, maximum: int) -> list[str]:
    if not raw or not raw.endswith(b"\n") or b"\r" in raw or b"\0" in raw:
        raise PlatformCodesignInspectionError(
            f"{label} is outside the closed line profile"
        )
    try:
        value = raw[:-1].decode("utf-8")
    except UnicodeDecodeError as error:
        raise PlatformCodesignInspectionError(f"{label} is not UTF-8") from error
    lines = value.split("\n")
    if (
        not 1 <= len(lines) <= maximum
        or any(not line or len(line.encode("utf-8")) > MAX_LINE_BYTES for line in lines)
        or any(any(ord(character) < 32 or ord(character) == 127 for character in line) for line in lines)
    ):
        raise PlatformCodesignInspectionError(
            f"{label} exceeds the closed line profile"
        )
    return lines


def _single(values: dict[str, list[str]], key: str) -> str:
    matches = values.get(key, [])
    if len(matches) != 1:
        raise PlatformCodesignInspectionError(
            f"codesign display must contain one {key} fact"
        )
    return matches[0]


def parse_identity_inspection_output(
    plan: PlannedCodeSignArchitectureInspection,
    invocation_result: dict[str, Any],
    stdout: bytes,
    stderr: bytes,
    certificate_sha256: list[str],
) -> dict[str, Any]:
    failed = _validate_result(plan, invocation_result, identity=True)
    if failed is not None:
        return {**failed, "displayFacts": None, "certificateSHA256": []}
    requirement_lines = _lines(stdout, "codesign requirements output", MAX_REQUIREMENT_LINES)
    if (
        any(REQUIREMENT_LINE.fullmatch(line) is None for line in requirement_lines)
        or sum(line.startswith("designated => ") for line in requirement_lines) != 1
    ):
        raise PlatformCodesignInspectionError(
            "codesign requirements output lacks one explicit designated requirement"
        )
    display_lines = _lines(stderr, "codesign display output", MAX_DISPLAY_LINES)
    expected_executable = f"Executable={plan.owned_source_path}"
    if display_lines[0] != expected_executable:
        raise PlatformCodesignInspectionError(
            "codesign display executable differs from the graph Mach-O source"
        )
    keys = {
        "Identifier": [],
        "CandidateCDHashFull sha256": [],
        "CDHash": [],
        "Signature": [],
        "TeamIdentifier": [],
        "Timestamp": [],
        "Authority": [],
    }
    for line in display_lines[1:]:
        for key in keys:
            prefix = key + "="
            if line.startswith(prefix):
                keys[key].append(line[len(prefix):])
                break
    identifier = _single(keys, "Identifier")
    code_directory_sha256 = _single(keys, "CandidateCDHashFull sha256")
    cdhash = _single(keys, "CDHash")
    signature = _single(keys, "Signature")
    team_identifier = _single(keys, "TeamIdentifier")
    if (
        not identifier
        or SHA256_PATTERN.fullmatch(code_directory_sha256) is None
        or SHA1_PATTERN.fullmatch(cdhash) is None
        or cdhash != code_directory_sha256[:40]
        or not signature.startswith("size=")
        or not signature[5:].isdigit()
        or int(signature[5:]) <= 0
        or TEAM_PATTERN.fullmatch(team_identifier) is None
        or not keys["Authority"]
        or len(keys["Authority"]) > 8
        or any(not authority for authority in keys["Authority"])
        or len(keys["Timestamp"]) > 1
        or any(not value for value in keys["Timestamp"])
    ):
        raise PlatformCodesignInspectionError(
            "codesign display identity facts are invalid"
        )
    if (
        not 1 <= len(certificate_sha256) <= 8
        or any(SHA256_PATTERN.fullmatch(value) is None for value in certificate_sha256)
    ):
        raise PlatformCodesignInspectionError(
            "codesign extracted certificate inventory is invalid"
        )
    return {
        "status": "passed",
        "reason": None,
        "displayFacts": {
            "signingIdentifier": identifier,
            "teamIdentifier": team_identifier,
            "codeDirectorySHA256": code_directory_sha256,
            "cdhash": cdhash,
            "signatureBytes": int(signature[5:]),
            "secureTimestampPresent": bool(keys["Timestamp"]),
            "authorityCount": len(keys["Authority"]),
            "explicitDesignatedRequirementReported": True,
        },
        "certificateSHA256": list(certificate_sha256),
    }


def parse_entitlements_inspection_output(
    plan: PlannedCodeSignArchitectureInspection,
    invocation_result: dict[str, Any],
    stdout: bytes,
    stderr: bytes,
) -> dict[str, Any]:
    failed = _validate_result(plan, invocation_result, identity=False)
    if failed is not None:
        return {**failed, "entitlements": None}
    expected = f"Executable={plan.owned_source_path}\n".encode("utf-8")
    if stderr != expected:
        raise PlatformCodesignInspectionError(
            "codesign entitlement display output is outside the closed grammar"
        )
    if not stdout:
        entitlements = {"mode": "absent"}
    else:
        try:
            entitlements = entitlement_policy_from_plist(stdout)
        except PlatformCodeSignatureError as error:
            raise PlatformCodesignInspectionError(
                "codesign entitlement output is invalid"
            ) from error
    return {
        "status": "passed",
        "reason": None,
        "entitlements": entitlements,
    }


def correlate_codesign_inspection(
    *,
    embedded_facts: dict[str, Any],
    identity_inspection: dict[str, Any],
    entitlements_inspection: dict[str, Any],
) -> dict[str, Any]:
    if (
        identity_inspection.get("status") != "passed"
        or entitlements_inspection.get("status") != "passed"
    ):
        raise PlatformCodesignInspectionError(
            "codesign architecture inspection did not pass"
        )
    display = identity_inspection.get("displayFacts")
    try:
        expected_display = {
            "signingIdentifier": embedded_facts["signingIdentifier"],
            "teamIdentifier": embedded_facts["teamIdentifier"],
            "codeDirectorySHA256": embedded_facts["codeDirectories"][0]["codeDirectorySHA256"],
            "cdhash": embedded_facts["codeDirectories"][0]["cdhash"],
        }
    except (KeyError, TypeError) as error:
        raise PlatformCodesignInspectionError(
            "embedded signature facts are incomplete for codesign correlation"
        ) from error
    if (
        not isinstance(display, dict)
        or {key: display.get(key) for key in expected_display} != expected_display
        or display.get("explicitDesignatedRequirementReported") is not True
        or entitlements_inspection.get("entitlements") != embedded_facts.get("entitlements")
    ):
        raise PlatformCodesignInspectionError(
            "codesign display disagrees with embedded signature facts"
        )
    certificates = identity_inspection.get("certificateSHA256")
    if not isinstance(certificates, list) or not certificates:
        raise PlatformCodesignInspectionError(
            "codesign inspection lacks an extracted leaf certificate"
        )
    return {
        "status": "passed",
        "leafCertificateSHA256": certificates[0],
        "certificateCount": len(certificates),
        "secureTimestampPresent": display.get("secureTimestampPresent") is True,
        "explicitDesignatedRequirementReported": True,
        "entitlementsMatched": True,
    }
