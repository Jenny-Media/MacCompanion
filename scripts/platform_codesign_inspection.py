#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import os
import re
import stat
from pathlib import Path
from typing import Any

from platform_code_signature import (
    PlatformCodeSignatureError,
    compare_architecture_to_policy,
    entitlement_policy_from_plist,
    inspect_embedded_signature,
)
from platform_codesign_verification import (
    INVOCATION_RESULT_KEYS,
    PlatformCodesignVerificationError,
    _composition_by_id,
    _read_raw_reference,
    _rehash_subject,
    parse_codesign_verification_output,
)
from platform_signing_fixed_tools import (
    FixedToolError,
    run_fixed_tool_invocation,
)
from platform_signing_subjects import (
    PlatformSigningSubjectError,
    PlannedCodeSignArchitectureInspection,
    ReconstructedSigningSubject,
    _private_root_provenance,
    _require_permitted_extended_attributes,
    derive_codesign_architecture_inspection_plans,
    derive_codesign_verification_plans,
)
from signing_policy import SigningPolicyError, validate_policy


SHA1_PATTERN = re.compile(r"^[0-9a-f]{40}$")
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
TEAM_PATTERN = re.compile(r"^[A-Z0-9]{10}$")
REQUIREMENT_LINE = re.compile(r"^[a-z][a-z0-9-]{0,31} => .{1,4096}$")
MAX_DISPLAY_LINES = 256
MAX_REQUIREMENT_LINES = 8
MAX_LINE_BYTES = 4096
MAX_CERTIFICATE_FILES = 8
MAX_CERTIFICATE_BYTES = 1024 * 1024
CERTIFICATE_REFERENCE_KEYS = {"path", "bytes", "sha256"}
VERIFICATION_RECORD_KEYS = {
    "artifactID",
    "objectPath",
    "subjectBefore",
    "invocation",
    "verification",
    "subjectAfter",
}
ARCHITECTURE_RECORD_KEYS = {
    "artifactID",
    "sourcePath",
    "objectPath",
    "architectureSelector",
    "status",
    "reason",
    "platformAcceptanceEligible",
    "verificationPrerequisite",
    "subjectBefore",
    "embeddedSignature",
    "identityInvocation",
    "certificateFiles",
    "identityInspection",
    "subjectAfterIdentity",
    "entitlementsInvocation",
    "entitlementsInspection",
    "correlation",
    "policyComparison",
    "subjectAfter",
}


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
        "Signature size": [],
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
    signature = _single(keys, "Signature size")
    team_identifier = _single(keys, "TeamIdentifier")
    if (
        not identifier
        or SHA256_PATTERN.fullmatch(code_directory_sha256) is None
        or SHA1_PATTERN.fullmatch(cdhash) is None
        or cdhash != code_directory_sha256[:40]
        or not signature.isdigit()
        or int(signature) <= 0
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
            "signatureBytes": int(signature),
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


def _architecture_key(
    plan: PlannedCodeSignArchitectureInspection,
) -> tuple[str, str, int, int]:
    return (
        plan.artifact_id,
        plan.source_path,
        plan.cpu_type,
        plan.cpu_subtype,
    )


def _graph_architectures(
    graph: dict[str, Any],
) -> dict[tuple[str, str, int, int], dict[str, Any]]:
    artifacts = graph.get("artifacts")
    if not isinstance(artifacts, list):
        raise PlatformCodesignInspectionError(
            "signed-code graph is unavailable for architecture inspection"
        )
    result: dict[tuple[str, str, int, int], dict[str, Any]] = {}
    for artifact in artifacts:
        binding = artifact.get("artifact") if isinstance(artifact, dict) else None
        artifact_id = binding.get("id") if isinstance(binding, dict) else None
        objects = artifact.get("machOObjects") if isinstance(artifact, dict) else None
        if not isinstance(artifact_id, str) or not isinstance(objects, list):
            raise PlatformCodesignInspectionError(
                "signed-code graph architecture binding is invalid"
            )
        for item in objects:
            if not isinstance(item, dict):
                raise PlatformCodesignInspectionError(
                    "signed-code graph Mach-O object is invalid"
                )
            if item.get("inDistributionSubject") is not True:
                continue
            path = item.get("path")
            macho = item.get("machO")
            architectures = (
                macho.get("architectures")
                if isinstance(macho, dict)
                else None
            )
            if not isinstance(path, str) or not isinstance(architectures, list):
                raise PlatformCodesignInspectionError(
                    "signed-code graph architecture inventory is invalid"
                )
            for architecture in architectures:
                if not isinstance(architecture, dict):
                    raise PlatformCodesignInspectionError(
                        "signed-code graph architecture is invalid"
                    )
                key = (
                    artifact_id,
                    path,
                    architecture.get("cpuType"),
                    architecture.get("cpuSubtype"),
                )
                if (
                    not isinstance(key[2], int)
                    or isinstance(key[2], bool)
                    or not isinstance(key[3], int)
                    or isinstance(key[3], bool)
                    or key in result
                ):
                    raise PlatformCodesignInspectionError(
                        "signed-code graph architecture key is ambiguous"
                    )
                result[key] = architecture
    if not result:
        raise PlatformCodesignInspectionError(
            "signed-code graph architecture inventory is empty"
        )
    return result


def _policy_architectures(
    policy: dict[str, Any],
) -> dict[tuple[str, str, int, int], dict[str, Any]]:
    try:
        validated = validate_policy(policy)
    except SigningPolicyError as error:
        raise PlatformCodesignInspectionError(
            "signing policy is invalid for architecture inspection"
        ) from error
    result: dict[tuple[str, str, int, int], dict[str, Any]] = {}
    for artifact in validated["artifacts"]:
        artifact_id = artifact["artifact"]["id"]
        for item in artifact["objects"]:
            for architecture in item["architectures"]:
                key = (
                    artifact_id,
                    item["path"],
                    architecture["cpuType"],
                    architecture["cpuSubtype"],
                )
                if key in result:
                    raise PlatformCodesignInspectionError(
                        "signing-policy architecture key is ambiguous"
                    )
                result[key] = architecture
    if not result:
        raise PlatformCodesignInspectionError(
            "signing-policy architecture inventory is empty"
        )
    return result


def _certificate_entry_names(prefix: Path, work_root: Path) -> list[str]:
    if (
        not prefix.is_absolute()
        or prefix.parent != work_root
        or not prefix.name
        or len(prefix.name.encode("utf-8")) > 128
    ):
        raise PlatformCodesignInspectionError(
            "certificate prefix is outside the fixed working root"
        )
    try:
        names = [
            entry.name
            for entry in os.scandir(work_root)
            if entry.name.startswith(prefix.name)
        ]
    except OSError as error:
        raise PlatformCodesignInspectionError(
            "certificate output inventory is unavailable"
        ) from error
    return sorted(names)


def _require_certificate_prefix_clear(prefix: Path, work_root: Path) -> None:
    if _certificate_entry_names(prefix, work_root):
        raise PlatformCodesignInspectionError(
            "certificate output prefix already exists"
        )


def _retain_certificate_file(path: Path, work_root: Path) -> dict[str, Any]:
    flags = os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise PlatformCodesignInspectionError(
            "extracted certificate is unavailable without following links"
        ) from error
    try:
        initial = os.fstat(descriptor)
        if (
            not stat.S_ISREG(initial.st_mode)
            or initial.st_uid != os.geteuid()
            or initial.st_nlink != 1
            or not 0 < initial.st_size <= MAX_CERTIFICATE_BYTES
            or stat.S_IMODE(initial.st_mode) & 0o022
        ):
            raise PlatformCodesignInspectionError(
                "extracted certificate has unsafe filesystem facts"
            )
        os.fchmod(descriptor, 0o600)
        os.fsync(descriptor)
        retained = os.fstat(descriptor)
        if stat.S_IMODE(retained.st_mode) != 0o600:
            raise PlatformCodesignInspectionError(
                "extracted certificate could not be retained privately"
            )
        try:
            provenance = _private_root_provenance(work_root)
            _require_permitted_extended_attributes(path, provenance)
        except PlatformSigningSubjectError as error:
            raise PlatformCodesignInspectionError(
                "extracted certificate has unsafe platform metadata"
            ) from error
        digest = hashlib.sha256()
        size = 0
        while True:
            chunk = os.read(descriptor, 64 * 1024)
            if not chunk:
                break
            size += len(chunk)
            if size > MAX_CERTIFICATE_BYTES:
                raise PlatformCodesignInspectionError(
                    "extracted certificate exceeded its retained bound"
                )
            digest.update(chunk)
        after = os.fstat(descriptor)
        pathname = path.lstat()
        stable_fields = (
            "st_dev",
            "st_ino",
            "st_mode",
            "st_uid",
            "st_nlink",
            "st_size",
            "st_mtime_ns",
            "st_ctime_ns",
        )
        if (
            size != retained.st_size
            or any(getattr(retained, key) != getattr(after, key) for key in stable_fields)
            or any(getattr(after, key) != getattr(pathname, key) for key in stable_fields)
        ):
            raise PlatformCodesignInspectionError(
                "extracted certificate changed during retention"
            )
    except OSError as error:
        raise PlatformCodesignInspectionError(
            "extracted certificate could not be retained"
        ) from error
    finally:
        os.close(descriptor)
    return {
        "path": path.name,
        "bytes": size,
        "sha256": digest.hexdigest(),
    }


def _retain_extracted_certificates(
    prefix: Path,
    work_root: Path,
) -> list[dict[str, Any]]:
    names = _certificate_entry_names(prefix, work_root)
    expected = [
        f"{prefix.name}{index}"
        for index in range(len(names))
    ]
    if (
        not 1 <= len(names) <= MAX_CERTIFICATE_FILES
        or names != expected
    ):
        raise PlatformCodesignInspectionError(
            "extracted certificate inventory is not contiguous and bounded"
        )
    references = [
        _retain_certificate_file(work_root / name, work_root)
        for name in names
    ]
    if any(set(reference) != CERTIFICATE_REFERENCE_KEYS for reference in references):
        raise PlatformCodesignInspectionError(
            "extracted certificate reference is not closed"
        )
    return references


def _read_certificate_reference(
    reference: Any,
    expected_name: str,
    work_root: Path,
) -> str:
    if (
        not isinstance(reference, dict)
        or set(reference) != CERTIFICATE_REFERENCE_KEYS
        or reference.get("path") != expected_name
        or not isinstance(reference.get("bytes"), int)
        or isinstance(reference.get("bytes"), bool)
        or not 0 < reference["bytes"] <= MAX_CERTIFICATE_BYTES
        or not isinstance(reference.get("sha256"), str)
        or SHA256_PATTERN.fullmatch(reference["sha256"]) is None
        or Path(expected_name).name != expected_name
    ):
        raise PlatformCodesignInspectionError(
            "retained certificate reference is not closed"
        )
    path = work_root / expected_name
    flags = os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
    try:
        metadata = path.lstat()
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_uid != os.geteuid()
            or metadata.st_nlink != 1
            or stat.S_IMODE(metadata.st_mode) != 0o600
            or metadata.st_size != reference["bytes"]
        ):
            raise PlatformCodesignInspectionError(
                "retained certificate has unsafe filesystem facts"
            )
        provenance = _private_root_provenance(work_root)
        _require_permitted_extended_attributes(path, provenance)
        descriptor = os.open(path, flags)
    except (OSError, PlatformSigningSubjectError) as error:
        raise PlatformCodesignInspectionError(
            "retained certificate is unavailable"
        ) from error
    try:
        before = os.fstat(descriptor)
        digest = hashlib.sha256()
        size = 0
        while True:
            chunk = os.read(descriptor, 64 * 1024)
            if not chunk:
                break
            size += len(chunk)
            if size > reference["bytes"]:
                raise PlatformCodesignInspectionError(
                    "retained certificate exceeded its reference"
                )
            digest.update(chunk)
        after = os.fstat(descriptor)
        stable_fields = (
            "st_dev",
            "st_ino",
            "st_mode",
            "st_uid",
            "st_nlink",
            "st_size",
            "st_mtime_ns",
            "st_ctime_ns",
        )
        if (
            size != reference["bytes"]
            or digest.hexdigest() != reference["sha256"]
            or any(getattr(before, key) != getattr(after, key) for key in stable_fields)
        ):
            raise PlatformCodesignInspectionError(
                "retained certificate changed during reinspection"
            )
    finally:
        os.close(descriptor)
    return reference["sha256"]


def _validated_verification_prerequisites(
    *,
    records: list[dict[str, Any]],
    reconstructed: list[ReconstructedSigningSubject],
    composition: dict[str, Any],
    graph: dict[str, Any],
    team_id: str,
    work_root: Path,
    codesign_tool: Any,
) -> dict[tuple[str, str], dict[str, Any]]:
    try:
        expected_plans = derive_codesign_verification_plans(
            graph=graph,
            reconstructed=reconstructed,
            team_id=team_id,
            codesign_tool=codesign_tool,
        )
        entries_by_id = _composition_by_id(composition)
    except (PlatformSigningSubjectError, PlatformCodesignVerificationError) as error:
        raise PlatformCodesignInspectionError(
            "whole-subject verification prerequisites could not be rederived"
        ) from error
    if len(records) != len(expected_plans):
        raise PlatformCodesignInspectionError(
            "whole-subject verification record set is incomplete"
        )
    subjects_by_id = {item.artifact_id: item for item in reconstructed}
    result: dict[tuple[str, str], dict[str, Any]] = {}
    for expected, record in zip(expected_plans, records, strict=True):
        key = (expected.artifact_id, expected.object_path)
        subject = subjects_by_id.get(expected.artifact_id)
        entries = entries_by_id.get(expected.artifact_id)
        if (
            not isinstance(record, dict)
            or set(record) != VERIFICATION_RECORD_KEYS
            or record.get("artifactID") != expected.artifact_id
            or record.get("objectPath") != expected.object_path
            or not isinstance(record.get("invocation"), dict)
            or key in result
            or subject is None
            or entries is None
        ):
            raise PlatformCodesignInspectionError(
                "whole-subject verification record differs from its exact plan"
            )
        try:
            current = _rehash_subject(subject, entries, work_root)
            stdout = _read_raw_reference(
                work_root,
                record["invocation"].get("stdout"),
                f"{expected.invocation.invocation_id}.stdout",
            )
            stderr = _read_raw_reference(
                work_root,
                record["invocation"].get("stderr"),
                f"{expected.invocation.invocation_id}.stderr",
            )
            parsed = parse_codesign_verification_output(
                expected,
                record["invocation"],
                stdout,
                stderr,
            )
        except PlatformCodesignVerificationError as error:
            raise PlatformCodesignInspectionError(
                "whole-subject verification evidence failed reinspection"
            ) from error
        if (
            record["subjectBefore"] != current
            or record["subjectAfter"] != current
            or record["verification"] != parsed
            or parsed.get("status") != "passed"
            or parsed.get("messages") != [
                "validOnDisk",
                "satisfiesDesignatedRequirement",
                "explicitRequirementSatisfied",
            ]
        ):
            raise PlatformCodesignInspectionError(
                "whole-subject verification did not pass unchanged"
            )
        result[key] = {
            "artifactID": expected.artifact_id,
            "objectPath": expected.object_path,
            "invocationID": expected.invocation.invocation_id,
            "status": "passed",
            "codesignVerified": True,
            "explicitRequirementVerified": True,
        }
    return result


def validate_codesign_architecture_records(
    *,
    plans: list[PlannedCodeSignArchitectureInspection],
    records: list[dict[str, Any]],
    reconstructed: list[ReconstructedSigningSubject],
    composition: dict[str, Any],
    graph: dict[str, Any],
    policy: dict[str, Any],
    verification_records: list[dict[str, Any]],
    team_id: str,
    work_root: Path,
) -> list[dict[str, Any]]:
    if not plans:
        raise PlatformCodesignInspectionError(
            "codesign architecture reinspection plan set is empty"
        )
    tool = plans[0].identity_invocation.tool
    try:
        expected_plans = derive_codesign_architecture_inspection_plans(
            graph=graph,
            reconstructed=reconstructed,
            codesign_tool=tool,
        )
        entries_by_id = _composition_by_id(composition)
    except (PlatformSigningSubjectError, PlatformCodesignVerificationError) as error:
        raise PlatformCodesignInspectionError(
            "codesign architecture reinspection plans failed exact rederivation"
        ) from error
    if plans != expected_plans:
        raise PlatformCodesignInspectionError(
            "codesign architecture reinspection plans differ from exact rederivation"
        )
    graph_by_key = _graph_architectures(graph)
    policy_by_key = _policy_architectures(policy)
    plan_keys = [_architecture_key(plan) for plan in plans]
    if (
        len(set(plan_keys)) != len(plan_keys)
        or set(plan_keys) != set(graph_by_key)
        or set(plan_keys) != set(policy_by_key)
        or len(records) != len(plans)
    ):
        raise PlatformCodesignInspectionError(
            "codesign architecture record coverage is incomplete"
        )
    prerequisites = _validated_verification_prerequisites(
        records=verification_records,
        reconstructed=reconstructed,
        composition=composition,
        graph=graph,
        team_id=team_id,
        work_root=work_root,
        codesign_tool=tool,
    )
    subjects_by_id = {item.artifact_id: item for item in reconstructed}
    if len(subjects_by_id) != len(reconstructed):
        raise PlatformCodesignInspectionError(
            "reconstructed signing subject set is ambiguous"
        )

    summaries: list[dict[str, Any]] = []
    for plan, key, record in zip(plans, plan_keys, records, strict=True):
        subject = subjects_by_id.get(plan.artifact_id)
        entries = entries_by_id.get(plan.artifact_id)
        prerequisite = prerequisites.get((plan.artifact_id, plan.object_path))
        selector = {"cpuType": plan.cpu_type, "cpuSubtype": plan.cpu_subtype}
        if (
            not isinstance(record, dict)
            or set(record) != ARCHITECTURE_RECORD_KEYS
            or record.get("artifactID") != plan.artifact_id
            or record.get("sourcePath") != plan.source_path
            or record.get("objectPath") != plan.object_path
            or record.get("architectureSelector") != selector
            or record.get("status") != "passed"
            or record.get("reason") is not None
            or record.get("platformAcceptanceEligible") is not False
            or record.get("verificationPrerequisite") != prerequisite
            or subject is None
            or entries is None
            or prerequisite is None
        ):
            raise PlatformCodesignInspectionError(
                "codesign architecture record differs from its exact plan"
            )
        try:
            current = _rehash_subject(subject, entries, work_root)
            embedded = inspect_embedded_signature(
                object_path=plan.owned_source_path,
                graph_architecture=graph_by_key[key],
            )
        except (PlatformCodesignVerificationError, PlatformCodeSignatureError) as error:
            raise PlatformCodesignInspectionError(
                "codesign architecture record subject failed reinspection"
            ) from error

        certificate_files = record.get("certificateFiles")
        if (
            not isinstance(certificate_files, list)
            or not 1 <= len(certificate_files) <= MAX_CERTIFICATE_FILES
        ):
            raise PlatformCodesignInspectionError(
                "codesign architecture record lacks its certificate chain"
            )
        certificate_sha256 = [
            _read_certificate_reference(
                reference,
                f"{plan.certificate_prefix.name}{index}",
                work_root,
            )
            for index, reference in enumerate(certificate_files)
        ]
        try:
            identity_invocation = record.get("identityInvocation")
            entitlements_invocation = record.get("entitlementsInvocation")
            if not isinstance(identity_invocation, dict) or not isinstance(
                entitlements_invocation, dict
            ):
                raise PlatformCodesignInspectionError(
                    "codesign architecture record invocation is unavailable"
                )
            identity_stdout = _read_raw_reference(
                work_root,
                identity_invocation.get("stdout"),
                f"{plan.identity_invocation.invocation_id}.stdout",
            )
            identity_stderr = _read_raw_reference(
                work_root,
                identity_invocation.get("stderr"),
                f"{plan.identity_invocation.invocation_id}.stderr",
            )
            entitlements_stdout = _read_raw_reference(
                work_root,
                entitlements_invocation.get("stdout"),
                f"{plan.entitlements_invocation.invocation_id}.stdout",
            )
            entitlements_stderr = _read_raw_reference(
                work_root,
                entitlements_invocation.get("stderr"),
                f"{plan.entitlements_invocation.invocation_id}.stderr",
            )
        except PlatformCodesignVerificationError as error:
            raise PlatformCodesignInspectionError(
                "codesign architecture raw evidence failed reinspection"
            ) from error
        identity = parse_identity_inspection_output(
            plan,
            identity_invocation,
            identity_stdout,
            identity_stderr,
            certificate_sha256,
        )
        entitlements = parse_entitlements_inspection_output(
            plan,
            entitlements_invocation,
            entitlements_stdout,
            entitlements_stderr,
        )
        correlated = correlate_codesign_inspection(
            embedded_facts=embedded,
            identity_inspection=identity,
            entitlements_inspection=entitlements,
        )
        try:
            policy_result = compare_architecture_to_policy(
                facts=embedded,
                policy_architecture=policy_by_key[key],
                leaf_certificate_sha256=correlated["leafCertificateSHA256"],
                secure_timestamp_present=correlated["secureTimestampPresent"],
                codesign_verified=prerequisite["codesignVerified"],
                explicit_requirement_verified=prerequisite[
                    "explicitRequirementVerified"
                ],
            )
        except PlatformCodeSignatureError as error:
            raise PlatformCodesignInspectionError(
                "codesign architecture record differs from signing policy"
            ) from error
        expected_fields = {
            "subjectBefore": current,
            "embeddedSignature": embedded,
            "identityInspection": identity,
            "subjectAfterIdentity": current,
            "entitlementsInspection": entitlements,
            "correlation": correlated,
            "policyComparison": policy_result,
            "subjectAfter": current,
        }
        if any(record.get(name) != value for name, value in expected_fields.items()):
            raise PlatformCodesignInspectionError(
                "codesign architecture record did not pass unchanged"
            )
        summaries.append({
            "artifactID": plan.artifact_id,
            "sourcePath": plan.source_path,
            "objectPath": plan.object_path,
            "architectureSelector": selector,
            "wholeVerification": prerequisite,
            "codeDirectorySHA256": policy_result["codeDirectorySHA256"],
            "designatedRequirementDataSHA256": policy_result[
                "designatedRequirementDataSHA256"
            ],
            "leafCertificateSHA256": policy_result["leafCertificateSHA256"],
            "policyMatched": True,
            "status": "passed",
            "platformAcceptanceEligible": False,
            "subject": current,
        })
    return summaries


def execute_codesign_architecture_inspection_plans(
    *,
    plans: list[PlannedCodeSignArchitectureInspection],
    reconstructed: list[ReconstructedSigningSubject],
    composition: dict[str, Any],
    graph: dict[str, Any],
    policy: dict[str, Any],
    verification_records: list[dict[str, Any]],
    team_id: str,
    work_root: Path,
) -> list[dict[str, Any]]:
    if not plans:
        raise PlatformCodesignInspectionError(
            "codesign architecture inspection plan set is empty"
        )
    tool = plans[0].identity_invocation.tool
    try:
        expected_plans = derive_codesign_architecture_inspection_plans(
            graph=graph,
            reconstructed=reconstructed,
            codesign_tool=tool,
        )
        entries_by_id = _composition_by_id(composition)
    except (PlatformSigningSubjectError, PlatformCodesignVerificationError) as error:
        raise PlatformCodesignInspectionError(
            "codesign architecture inspection plans failed exact rederivation"
        ) from error
    if plans != expected_plans:
        raise PlatformCodesignInspectionError(
            "codesign architecture inspection plans differ from exact rederivation"
        )
    graph_by_key = _graph_architectures(graph)
    policy_by_key = _policy_architectures(policy)
    plan_keys = [_architecture_key(plan) for plan in plans]
    if (
        len(set(plan_keys)) != len(plan_keys)
        or set(plan_keys) != set(graph_by_key)
        or set(plan_keys) != set(policy_by_key)
    ):
        raise PlatformCodesignInspectionError(
            "graph, policy, and inspection architecture coverage differ"
        )
    prerequisites = _validated_verification_prerequisites(
        records=verification_records,
        reconstructed=reconstructed,
        composition=composition,
        graph=graph,
        team_id=team_id,
        work_root=work_root,
        codesign_tool=tool,
    )
    subjects_by_id = {item.artifact_id: item for item in reconstructed}
    if len(subjects_by_id) != len(reconstructed):
        raise PlatformCodesignInspectionError(
            "reconstructed signing subject set is ambiguous"
        )

    records: list[dict[str, Any]] = []
    for plan, key in zip(plans, plan_keys, strict=True):
        subject = subjects_by_id.get(plan.artifact_id)
        entries = entries_by_id.get(plan.artifact_id)
        prerequisite = prerequisites.get((plan.artifact_id, plan.object_path))
        if subject is None or entries is None or prerequisite is None:
            raise PlatformCodesignInspectionError(
                "architecture inspection lacks a passed exact-subject prerequisite"
            )
        before = _rehash_subject(subject, entries, work_root)
        try:
            embedded = inspect_embedded_signature(
                object_path=plan.owned_source_path,
                graph_architecture=graph_by_key[key],
            )
        except PlatformCodeSignatureError as error:
            raise PlatformCodesignInspectionError(
                "embedded architecture signature failed independent inspection"
            ) from error

        _require_certificate_prefix_clear(plan.certificate_prefix, work_root)
        try:
            identity_result = run_fixed_tool_invocation(
                plan.identity_invocation,
                work_root,
            )
        except FixedToolError as error:
            raise PlatformCodesignInspectionError(
                "fixed identity inspection could not produce evidence"
            ) from error
        after_identity = _rehash_subject(subject, entries, work_root)
        if before != after_identity:
            raise PlatformCodesignInspectionError(
                "reconstructed subject changed during identity inspection"
            )
        if identity_result.get("passed") is True:
            certificate_files = _retain_extracted_certificates(
                plan.certificate_prefix,
                work_root,
            )
        else:
            if _certificate_entry_names(plan.certificate_prefix, work_root):
                raise PlatformCodesignInspectionError(
                    "failed identity inspection produced certificate files"
                )
            certificate_files = []
        try:
            identity_stdout = _read_raw_reference(
                work_root,
                identity_result.get("stdout"),
                f"{plan.identity_invocation.invocation_id}.stdout",
            )
            identity_stderr = _read_raw_reference(
                work_root,
                identity_result.get("stderr"),
                f"{plan.identity_invocation.invocation_id}.stderr",
            )
        except PlatformCodesignVerificationError as error:
            raise PlatformCodesignInspectionError(
                "identity inspection raw evidence failed reinspection"
            ) from error
        identity = parse_identity_inspection_output(
            plan,
            identity_result,
            identity_stdout,
            identity_stderr,
            [item["sha256"] for item in certificate_files],
        )

        try:
            entitlements_result = run_fixed_tool_invocation(
                plan.entitlements_invocation,
                work_root,
            )
        except FixedToolError as error:
            raise PlatformCodesignInspectionError(
                "fixed entitlement inspection could not produce evidence"
            ) from error
        after = _rehash_subject(subject, entries, work_root)
        if after_identity != after:
            raise PlatformCodesignInspectionError(
                "reconstructed subject changed during entitlement inspection"
            )
        try:
            entitlements_stdout = _read_raw_reference(
                work_root,
                entitlements_result.get("stdout"),
                f"{plan.entitlements_invocation.invocation_id}.stdout",
            )
            entitlements_stderr = _read_raw_reference(
                work_root,
                entitlements_result.get("stderr"),
                f"{plan.entitlements_invocation.invocation_id}.stderr",
            )
        except PlatformCodesignVerificationError as error:
            raise PlatformCodesignInspectionError(
                "entitlement inspection raw evidence failed reinspection"
            ) from error
        entitlements = parse_entitlements_inspection_output(
            plan,
            entitlements_result,
            entitlements_stdout,
            entitlements_stderr,
        )

        if identity["status"] == "passed" and entitlements["status"] == "passed":
            correlated = correlate_codesign_inspection(
                embedded_facts=embedded,
                identity_inspection=identity,
                entitlements_inspection=entitlements,
            )
            try:
                policy_result = compare_architecture_to_policy(
                    facts=embedded,
                    policy_architecture=policy_by_key[key],
                    leaf_certificate_sha256=correlated["leafCertificateSHA256"],
                    secure_timestamp_present=correlated["secureTimestampPresent"],
                    codesign_verified=prerequisite["codesignVerified"],
                    explicit_requirement_verified=prerequisite[
                        "explicitRequirementVerified"
                    ],
                )
            except PlatformCodeSignatureError as error:
                raise PlatformCodesignInspectionError(
                    "architecture signature differs from signing policy"
                ) from error
            status = "passed"
            reason = None
        else:
            correlated = None
            policy_result = None
            status = "failed"
            reason = (
                identity["reason"]
                if identity["status"] != "passed"
                else entitlements["reason"]
            )
        records.append({
            "artifactID": plan.artifact_id,
            "sourcePath": plan.source_path,
            "objectPath": plan.object_path,
            "architectureSelector": {
                "cpuType": plan.cpu_type,
                "cpuSubtype": plan.cpu_subtype,
            },
            "status": status,
            "reason": reason,
            "platformAcceptanceEligible": False,
            "verificationPrerequisite": prerequisite,
            "subjectBefore": before,
            "embeddedSignature": embedded,
            "identityInvocation": identity_result,
            "certificateFiles": certificate_files,
            "identityInspection": identity,
            "subjectAfterIdentity": after_identity,
            "entitlementsInvocation": entitlements_result,
            "entitlementsInspection": entitlements,
            "correlation": correlated,
            "policyComparison": policy_result,
            "subjectAfter": after,
        })
    return records
