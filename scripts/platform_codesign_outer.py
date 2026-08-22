#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
from typing import Any

from platform_codesign_inspection import (
    PlatformCodesignInspectionError,
    validate_codesign_architecture_records,
)
from platform_codesign_verification import (
    INVOCATION_RESULT_KEYS,
    PlatformCodesignVerificationError,
    _composition_by_id,
    _read_raw_reference,
    _rehash_subject,
)
from platform_signing_fixed_tools import FixedToolError, run_fixed_tool_invocation
from platform_signing_subjects import (
    PlatformSigningSubjectError,
    PlannedCodeSignArchitectureInspection,
    PlannedCodeSignOuterVerification,
    ReconstructedSigningSubject,
    derive_codesign_outer_verification_plans,
)


class PlatformCodesignOuterError(ValueError):
    pass


OUTER_EXECUTION_RECORD_KEYS = {
    "artifactID",
    "status",
    "reason",
    "platformAcceptanceEligible",
    "subjectBefore",
    "invocation",
    "verification",
    "subjectAfter",
}


def parse_outer_codesign_verification_output(
    plan: PlannedCodeSignOuterVerification,
    invocation_result: dict[str, Any],
    stdout: bytes,
    stderr: bytes,
) -> dict[str, Any]:
    if (
        not isinstance(invocation_result, dict)
        or set(invocation_result) != INVOCATION_RESULT_KEYS
    ):
        raise PlatformCodesignOuterError(
            "outer codesign invocation result is not closed"
        )
    if (
        invocation_result.get("invocationID") != plan.invocation.invocation_id
        or invocation_result.get("tool") != plan.invocation.tool.public_record()
        or invocation_result.get("argv")
        != [plan.invocation.tool.path, *plan.invocation.arguments]
    ):
        raise PlatformCodesignOuterError(
            "outer codesign invocation result differs from its fixed plan"
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
        return {"status": "failed", "reason": reason, "messages": []}
    if (
        invocation_result.get("termination") != "exited"
        or invocation_result.get("returnCode") != 0
        or invocation_result.get("toolUnchanged") is not True
        or stdout
    ):
        raise PlatformCodesignOuterError(
            "outer codesign success contains contradictory facts"
        )
    subject = str(plan.owned_subject_path)
    expected_messages = [
        f"{subject}: valid on disk",
        f"{subject}: satisfies its Designated Requirement",
    ]
    try:
        expected_stderr = ("\n".join(expected_messages) + "\n").encode("utf-8")
    except UnicodeError as error:
        raise PlatformCodesignOuterError(
            "outer codesign subject is not valid UTF-8"
        ) from error
    if stderr != expected_stderr:
        raise PlatformCodesignOuterError(
            "outer codesign success output is outside the closed grammar"
        )
    return {
        "status": "passed",
        "reason": None,
        "messages": ["validOnDisk", "satisfiesDesignatedRequirement"],
    }


def execute_outer_codesign_verification_plans(
    *,
    plans: list[PlannedCodeSignOuterVerification],
    reconstructed: list[ReconstructedSigningSubject],
    composition: dict[str, Any],
    graph: dict[str, Any],
    work_root: Path,
) -> list[dict[str, Any]]:
    mac_subjects = [subject for subject in reconstructed if subject.platform == "macOS"]
    if not mac_subjects:
        if plans:
            raise PlatformCodesignOuterError(
                "outer codesign plans exist without a Mac subject"
            )
        return []
    if not plans:
        raise PlatformCodesignOuterError(
            "outer codesign plan set is empty for a Mac subject"
        )
    try:
        expected_plans = derive_codesign_outer_verification_plans(
            graph=graph,
            reconstructed=reconstructed,
            codesign_tool=plans[0].invocation.tool,
        )
    except PlatformSigningSubjectError as error:
        raise PlatformCodesignOuterError(
            "outer codesign plans failed exact rederivation"
        ) from error
    if plans != expected_plans:
        raise PlatformCodesignOuterError(
            "outer codesign plans differ from exact rederivation"
        )
    subjects_by_id = {subject.artifact_id: subject for subject in reconstructed}
    try:
        entries_by_id = _composition_by_id(composition)
    except PlatformCodesignVerificationError as error:
        raise PlatformCodesignOuterError(
            "outer codesign composition is unavailable"
        ) from error
    records: list[dict[str, Any]] = []
    for plan in plans:
        subject = subjects_by_id.get(plan.artifact_id)
        entries = entries_by_id.get(plan.artifact_id)
        if subject is None or entries is None:
            raise PlatformCodesignOuterError(
                "outer codesign plan lacks exact reconstructed composition"
            )
        try:
            before = _rehash_subject(subject, entries, work_root)
        except PlatformCodesignVerificationError as error:
            raise PlatformCodesignOuterError(
                "outer codesign subject failed preflight reinspection"
            ) from error
        try:
            invocation = run_fixed_tool_invocation(plan.invocation, work_root)
        except FixedToolError as error:
            raise PlatformCodesignOuterError(
                "fixed outer codesign invocation could not produce evidence"
            ) from error
        try:
            after = _rehash_subject(subject, entries, work_root)
            stdout = _read_raw_reference(
                work_root,
                invocation.get("stdout"),
                f"{plan.invocation.invocation_id}.stdout",
            )
            stderr = _read_raw_reference(
                work_root,
                invocation.get("stderr"),
                f"{plan.invocation.invocation_id}.stderr",
            )
        except PlatformCodesignVerificationError as error:
            raise PlatformCodesignOuterError(
                "outer codesign evidence failed exact reinspection"
            ) from error
        if before != after:
            raise PlatformCodesignOuterError(
                "reconstructed subject changed during outer codesign verification"
            )
        parsed = parse_outer_codesign_verification_output(
            plan,
            invocation,
            stdout,
            stderr,
        )
        records.append({
            "artifactID": plan.artifact_id,
            "status": parsed["status"],
            "reason": parsed["reason"],
            "platformAcceptanceEligible": False,
            "subjectBefore": before,
            "invocation": invocation,
            "verification": parsed,
            "subjectAfter": after,
        })
    return records


def execute_correlated_outer_codesign_verification_plans(
    *,
    plans: list[PlannedCodeSignOuterVerification],
    architecture_plans: list[PlannedCodeSignArchitectureInspection],
    architecture_records: list[dict[str, Any]],
    verification_records: list[dict[str, Any]],
    reconstructed: list[ReconstructedSigningSubject],
    composition: dict[str, Any],
    graph: dict[str, Any],
    policy: dict[str, Any],
    team_id: str,
    work_root: Path,
) -> list[dict[str, Any]]:
    mac_subjects = [subject for subject in reconstructed if subject.platform == "macOS"]
    if not mac_subjects:
        if plans:
            raise PlatformCodesignOuterError(
                "correlated outer codesign plans exist without a Mac subject"
            )
        return []
    try:
        before = validate_codesign_architecture_records(
            plans=architecture_plans,
            records=architecture_records,
            reconstructed=reconstructed,
            composition=composition,
            graph=graph,
            policy=policy,
            verification_records=verification_records,
            team_id=team_id,
            work_root=work_root,
        )
    except PlatformCodesignInspectionError as error:
        raise PlatformCodesignOuterError(
            "outer codesign architecture prerequisites failed reinspection"
        ) from error
    raw_records = execute_outer_codesign_verification_plans(
        plans=plans,
        reconstructed=reconstructed,
        composition=composition,
        graph=graph,
        work_root=work_root,
    )
    try:
        after = validate_codesign_architecture_records(
            plans=architecture_plans,
            records=architecture_records,
            reconstructed=reconstructed,
            composition=composition,
            graph=graph,
            policy=policy,
            verification_records=verification_records,
            team_id=team_id,
            work_root=work_root,
        )
    except PlatformCodesignInspectionError as error:
        raise PlatformCodesignOuterError(
            "outer codesign architecture prerequisites failed postflight reinspection"
        ) from error
    if before != after:
        raise PlatformCodesignOuterError(
            "outer codesign architecture prerequisites changed during execution"
        )
    if len(raw_records) != len(plans):
        raise PlatformCodesignOuterError(
            "outer codesign execution record set is incomplete"
        )
    correlated: list[dict[str, Any]] = []
    for plan, record in zip(plans, raw_records, strict=True):
        prerequisites = [
            item for item in before if item["artifactID"] == plan.artifact_id
        ]
        if (
            not isinstance(record, dict)
            or set(record) != OUTER_EXECUTION_RECORD_KEYS
            or record.get("artifactID") != plan.artifact_id
            or not prerequisites
        ):
            raise PlatformCodesignOuterError(
                "outer codesign result lacks exact architecture prerequisites"
            )
        correlated.append({
            **record,
            "architecturePrerequisites": prerequisites,
            "architecturePrerequisitesRevalidatedAfterOuter": True,
        })
    return correlated
