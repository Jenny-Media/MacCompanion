#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import os
import re
import stat
from pathlib import Path
from typing import Any

from artifact_sbom import canonical_bytes
from platform_signing_fixed_tools import (
    FixedToolError,
    MAX_OUTPUT_BYTES,
    run_fixed_tool_invocation,
)
from platform_signing_subjects import (
    PlatformSigningSubjectError,
    PlannedCodeSignVerification,
    ReconstructedSigningSubject,
    _inventory_reconstruction,
    _private_root_provenance,
    _require_permitted_extended_attributes,
    _validate_private_directory,
    derive_codesign_verification_plans,
)


RAW_REFERENCE_KEYS = {"path", "bytes", "sha256"}
INVOCATION_RESULT_KEYS = {
    "invocationID",
    "tool",
    "argv",
    "environment",
    "timeoutSeconds",
    "outputLimitBytesPerStream",
    "startedAt",
    "completedAt",
    "durationMilliseconds",
    "termination",
    "returnCode",
    "toolUnchanged",
    "stdout",
    "stderr",
    "passed",
}
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")


class PlatformCodesignVerificationError(ValueError):
    pass


def _composition_by_id(
    composition: dict[str, Any],
) -> dict[str, list[dict[str, Any]]]:
    artifacts = composition.get("artifacts")
    if not isinstance(artifacts, list):
        raise PlatformCodesignVerificationError(
            "artifact composition is unavailable for platform verification"
        )
    result: dict[str, list[dict[str, Any]]] = {}
    for artifact in artifacts:
        if (
            not isinstance(artifact, dict)
            or not isinstance(artifact.get("id"), str)
            or not isinstance(artifact.get("entries"), list)
            or artifact["id"] in result
        ):
            raise PlatformCodesignVerificationError(
                "artifact composition is ambiguous for platform verification"
            )
        result[artifact["id"]] = artifact["entries"]
    return result


def _rehash_subject(
    subject: ReconstructedSigningSubject,
    entries: list[dict[str, Any]],
    work_root: Path,
) -> dict[str, Any]:
    expected_subjects_root = work_root / "subjects"
    if subject.artifact_root.parent != expected_subjects_root:
        raise PlatformCodesignVerificationError(
            "reconstructed subject is outside the fixed working root"
        )
    try:
        _validate_private_directory(work_root, exact_mode=0o700)
        _validate_private_directory(expected_subjects_root, exact_mode=0o700)
        _validate_private_directory(subject.artifact_root, exact_mode=0o700)
        provenance = _private_root_provenance(work_root)
        _require_permitted_extended_attributes(
            expected_subjects_root,
            provenance,
        )
        root_has_provenance = _require_permitted_extended_attributes(
            subject.artifact_root,
            provenance,
        )
        inventory, provenance_path_count = _inventory_reconstruction(
            subject.artifact_root,
            entries,
            set(subject.synthetic_directories),
            provenance,
        )
    except (OSError, PlatformSigningSubjectError) as error:
        raise PlatformCodesignVerificationError(
            "reconstructed subject failed exact phase reinspection"
        ) from error
    provenance_path_count += int(root_has_provenance)
    composition_sha256 = hashlib.sha256(
        canonical_bytes({"id": subject.artifact_id, "entries": inventory})
    ).hexdigest()
    provenance_sha256 = (
        hashlib.sha256(provenance).hexdigest()
        if provenance is not None
        else None
    )
    subject_path = subject.subject_path
    if (
        composition_sha256 != subject.composition_sha256
        or len(inventory) != subject.entry_count
        or provenance_path_count != subject.provenance_path_count
        or provenance_sha256 != subject.provenance_sha256
        or not subject_path.is_dir()
        or subject_path.is_symlink()
    ):
        raise PlatformCodesignVerificationError(
            "reconstructed subject changed across the platform phase"
        )
    return {
        "artifactID": subject.artifact_id,
        "compositionSHA256": composition_sha256,
        "entryCount": len(inventory),
        "provenancePathCount": provenance_path_count,
        "provenanceSHA256": provenance_sha256,
    }


def _read_raw_reference(
    work_root: Path,
    reference: Any,
    expected_name: str,
) -> bytes:
    if not isinstance(reference, dict) or set(reference) != RAW_REFERENCE_KEYS:
        raise PlatformCodesignVerificationError(
            "codesign raw-output reference is not closed"
        )
    if (
        reference.get("path") != expected_name
        or not isinstance(reference.get("bytes"), int)
        or isinstance(reference.get("bytes"), bool)
        or reference["bytes"] < 0
        or reference["bytes"] > MAX_OUTPUT_BYTES
        or not isinstance(reference.get("sha256"), str)
        or SHA256_PATTERN.fullmatch(reference["sha256"]) is None
    ):
        raise PlatformCodesignVerificationError(
            "codesign raw-output reference is invalid"
        )
    path = work_root / expected_name
    try:
        metadata = path.lstat()
        if (
            not stat.S_ISREG(metadata.st_mode)
            or stat.S_ISLNK(metadata.st_mode)
            or stat.S_IMODE(metadata.st_mode) != 0o600
            or metadata.st_uid != os.geteuid()
            or metadata.st_nlink != 1
            or metadata.st_size != reference["bytes"]
        ):
            raise PlatformCodesignVerificationError(
                "codesign raw output has unsafe filesystem facts"
            )
        try:
            provenance = _private_root_provenance(work_root)
            _require_permitted_extended_attributes(path, provenance)
        except PlatformSigningSubjectError as error:
            raise PlatformCodesignVerificationError(
                "codesign raw output has unsafe platform metadata"
            ) from error
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError as error:
        raise PlatformCodesignVerificationError(
            "codesign raw output is unavailable"
        ) from error
    try:
        before = os.fstat(descriptor)
        chunks: list[bytes] = []
        size = 0
        digest = hashlib.sha256()
        while True:
            chunk = os.read(descriptor, 64 * 1024)
            if not chunk:
                break
            size += len(chunk)
            if size > reference["bytes"]:
                raise PlatformCodesignVerificationError(
                    "codesign raw output exceeded its retained bound"
                )
            chunks.append(chunk)
            digest.update(chunk)
        after = os.fstat(descriptor)
        if (
            size != reference["bytes"]
            or digest.hexdigest() != reference["sha256"]
            or (
                before.st_dev,
                before.st_ino,
                before.st_mode,
                before.st_nlink,
                before.st_size,
                before.st_mtime_ns,
                before.st_ctime_ns,
            )
            != (
                after.st_dev,
                after.st_ino,
                after.st_mode,
                after.st_nlink,
                after.st_size,
                after.st_mtime_ns,
                after.st_ctime_ns,
            )
        ):
            raise PlatformCodesignVerificationError(
                "codesign raw output changed during inspection"
            )
    finally:
        os.close(descriptor)
    return b"".join(chunks)


def parse_codesign_verification_output(
    plan: PlannedCodeSignVerification,
    invocation_result: dict[str, Any],
    stdout: bytes,
    stderr: bytes,
) -> dict[str, Any]:
    if (
        not isinstance(invocation_result, dict)
        or set(invocation_result) != INVOCATION_RESULT_KEYS
    ):
        raise PlatformCodesignVerificationError(
            "codesign invocation result is not closed"
        )
    if (
        invocation_result.get("invocationID")
        != plan.invocation.invocation_id
        or invocation_result.get("tool")
        != plan.invocation.tool.public_record()
        or invocation_result.get("argv")
        != [plan.invocation.tool.path, *plan.invocation.arguments]
    ):
        raise PlatformCodesignVerificationError(
            "codesign invocation result differs from its fixed plan"
        )
    if invocation_result.get("passed") is not True:
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
        return {
            "status": "failed",
            "reason": reason,
            "messages": [],
        }
    if (
        invocation_result.get("termination") != "exited"
        or invocation_result.get("returnCode") != 0
        or invocation_result.get("toolUnchanged") is not True
        or stdout
    ):
        raise PlatformCodesignVerificationError(
            "codesign success result contains contradictory facts"
        )
    try:
        subject = str(plan.owned_subject_path)
        expected_messages = [
            f"{subject}: valid on disk",
            f"{subject}: satisfies its Designated Requirement",
            f"{subject}: explicit requirement satisfied",
        ]
        expected_stderr = ("\n".join(expected_messages) + "\n").encode("utf-8")
    except UnicodeError as error:
        raise PlatformCodesignVerificationError(
            "codesign verification subject is not valid UTF-8"
        ) from error
    if stderr != expected_stderr:
        raise PlatformCodesignVerificationError(
            "codesign success output is outside the closed grammar"
        )
    return {
        "status": "passed",
        "reason": None,
        "messages": [
            "validOnDisk",
            "satisfiesDesignatedRequirement",
            "explicitRequirementSatisfied",
        ],
    }


def execute_codesign_verification_plans(
    *,
    plans: list[PlannedCodeSignVerification],
    reconstructed: list[ReconstructedSigningSubject],
    composition: dict[str, Any],
    graph: dict[str, Any],
    team_id: str,
    work_root: Path,
) -> list[dict[str, Any]]:
    if not plans:
        raise PlatformCodesignVerificationError(
            "codesign verification plan set is empty"
        )
    tool = plans[0].invocation.tool
    try:
        expected_plans = derive_codesign_verification_plans(
            graph=graph,
            reconstructed=reconstructed,
            team_id=team_id,
            codesign_tool=tool,
        )
    except PlatformSigningSubjectError as error:
        raise PlatformCodesignVerificationError(
            "codesign verification plans failed exact rederivation"
        ) from error
    if plans != expected_plans:
        raise PlatformCodesignVerificationError(
            "codesign verification plans differ from exact rederivation"
        )
    subjects_by_id = {item.artifact_id: item for item in reconstructed}
    if len(subjects_by_id) != len(reconstructed):
        raise PlatformCodesignVerificationError(
            "reconstructed subject set is ambiguous"
        )
    entries_by_id = _composition_by_id(composition)
    records: list[dict[str, Any]] = []
    for plan in plans:
        subject = subjects_by_id.get(plan.artifact_id)
        entries = entries_by_id.get(plan.artifact_id)
        if subject is None or entries is None:
            raise PlatformCodesignVerificationError(
                "codesign plan lacks exact reconstructed composition"
            )
        before = _rehash_subject(subject, entries, work_root)
        try:
            result = run_fixed_tool_invocation(plan.invocation, work_root)
        except FixedToolError as error:
            raise PlatformCodesignVerificationError(
                "fixed codesign invocation could not produce evidence"
            ) from error
        after = _rehash_subject(subject, entries, work_root)
        if before != after:
            raise PlatformCodesignVerificationError(
                "reconstructed subject changed during codesign verification"
            )
        stdout = _read_raw_reference(
            work_root,
            result.get("stdout"),
            f"{plan.invocation.invocation_id}.stdout",
        )
        stderr = _read_raw_reference(
            work_root,
            result.get("stderr"),
            f"{plan.invocation.invocation_id}.stderr",
        )
        parsed = parse_codesign_verification_output(
            plan,
            result,
            stdout,
            stderr,
        )
        records.append(
            {
                "artifactID": plan.artifact_id,
                "objectPath": plan.object_path,
                "subjectBefore": before,
                "invocation": result,
                "verification": parsed,
                "subjectAfter": after,
            }
        )
    return records
