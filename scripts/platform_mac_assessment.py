#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
from typing import Any

from platform_codesign_outer import (
    PlatformCodesignOuterError,
    validate_correlated_outer_codesign_records,
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
    PlannedCodeSignArchitectureInspection,
    PlannedCodeSignOuterVerification,
    PlannedMacPlatformAssessment,
    PlatformSigningSubjectError,
    ReconstructedSigningSubject,
    derive_mac_platform_assessment_plans,
)


class PlatformMacAssessmentError(ValueError):
    pass


def _assessment_rehash(
    subject: ReconstructedSigningSubject,
    entries: list[dict[str, Any]],
    work_root: Path,
    phase: str,
) -> dict[str, Any]:
    try:
        return _rehash_subject(subject, entries, work_root)
    except PlatformCodesignVerificationError as error:
        raise PlatformMacAssessmentError(
            f"Mac subject failed {phase} reinspection"
        ) from error


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


def _validate_invocation(
    invocation: Any,
    expected: Any,
    label: str,
) -> dict[str, Any] | None:
    if not isinstance(invocation, dict) or set(invocation) != INVOCATION_RESULT_KEYS:
        raise PlatformMacAssessmentError(f"{label} invocation result is not closed")
    if (
        invocation.get("invocationID") != expected.invocation_id
        or invocation.get("tool") != expected.tool.public_record()
        or invocation.get("argv") != [expected.tool.path, *expected.arguments]
    ):
        raise PlatformMacAssessmentError(
            f"{label} invocation differs from its fixed plan"
        )
    if invocation.get("passed") is not True:
        return _failed_result(invocation)
    if (
        invocation.get("termination") != "exited"
        or invocation.get("returnCode") != 0
        or invocation.get("toolUnchanged") is not True
    ):
        raise PlatformMacAssessmentError(
            f"{label} success contains contradictory facts"
        )
    return None


def parse_gatekeeper_output(
    plan: PlannedMacPlatformAssessment,
    invocation: dict[str, Any],
    stdout: bytes,
    stderr: bytes,
) -> dict[str, Any]:
    failed = _validate_invocation(
        invocation,
        plan.gatekeeper_invocation,
        "Gatekeeper assessment",
    )
    if failed is not None:
        return {**failed, "source": None}
    if stdout:
        raise PlatformMacAssessmentError(
            "Gatekeeper success contains unexpected stdout"
        )
    expected = (
        f"{plan.owned_subject_path}: accepted\n"
        "source=Notarized Developer ID\n"
    ).encode("utf-8")
    if stderr != expected:
        raise PlatformMacAssessmentError(
            "Gatekeeper success output is outside the closed grammar"
        )
    return {
        "status": "passed",
        "reason": None,
        "source": "Notarized Developer ID",
    }


def parse_stapler_output(
    plan: PlannedMacPlatformAssessment,
    invocation: dict[str, Any],
    stdout: bytes,
    stderr: bytes,
) -> dict[str, Any]:
    failed = _validate_invocation(
        invocation,
        plan.stapler_invocation,
        "stapler validation",
    )
    if failed is not None:
        return {**failed, "ticketValidated": False}
    if stderr:
        raise PlatformMacAssessmentError(
            "stapler success contains unexpected stderr"
        )
    expected = (
        f"Processing: {plan.owned_subject_path}\n"
        "The validate action worked!\n"
    ).encode("utf-8")
    if stdout != expected:
        raise PlatformMacAssessmentError(
            "stapler success output is outside the closed grammar"
        )
    return {
        "status": "passed",
        "reason": None,
        "ticketValidated": True,
    }


def execute_mac_platform_assessment_plans(
    *,
    plans: list[PlannedMacPlatformAssessment],
    outer_plans: list[PlannedCodeSignOuterVerification],
    outer_records: list[dict[str, Any]],
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
            raise PlatformMacAssessmentError(
                "Mac platform assessment plans exist without a Mac subject"
            )
        return []
    if not plans or not outer_plans:
        raise PlatformMacAssessmentError(
            "Mac platform assessment lacks its exact signing prerequisites"
        )
    try:
        expected_plans = derive_mac_platform_assessment_plans(
            graph=graph,
            reconstructed=reconstructed,
            codesign_tool=outer_plans[0].invocation.tool,
            gatekeeper_tool=plans[0].gatekeeper_invocation.tool,
            stapler_tool=plans[0].stapler_invocation.tool,
        )
        before_prerequisites = validate_correlated_outer_codesign_records(
            plans=outer_plans,
            records=outer_records,
            architecture_plans=architecture_plans,
            architecture_records=architecture_records,
            verification_records=verification_records,
            reconstructed=reconstructed,
            composition=composition,
            graph=graph,
            policy=policy,
            team_id=team_id,
            work_root=work_root,
        )
        entries_by_id = _composition_by_id(composition)
    except (
        PlatformSigningSubjectError,
        PlatformCodesignOuterError,
        PlatformCodesignVerificationError,
    ) as error:
        raise PlatformMacAssessmentError(
            "Mac platform assessment signing prerequisites failed reinspection"
        ) from error
    if plans != expected_plans:
        raise PlatformMacAssessmentError(
            "Mac platform assessment plans differ from exact rederivation"
        )
    subjects_by_id = {subject.artifact_id: subject for subject in reconstructed}
    records: list[dict[str, Any]] = []
    for plan in plans:
        subject = subjects_by_id.get(plan.artifact_id)
        entries = entries_by_id.get(plan.artifact_id)
        prerequisite = next(
            (
                item
                for item in before_prerequisites
                if item["artifactID"] == plan.artifact_id
            ),
            None,
        )
        if subject is None or entries is None or prerequisite is None:
            raise PlatformMacAssessmentError(
                "Mac platform assessment lacks its exact outer prerequisite"
            )
        before = _assessment_rehash(subject, entries, work_root, "preflight")
        try:
            gatekeeper_invocation = run_fixed_tool_invocation(
                plan.gatekeeper_invocation,
                work_root,
            )
        except FixedToolError as error:
            raise PlatformMacAssessmentError(
                "fixed Gatekeeper assessment could not produce evidence"
            ) from error
        after_gatekeeper = _assessment_rehash(
            subject,
            entries,
            work_root,
            "post-Gatekeeper",
        )
        if before != after_gatekeeper:
            raise PlatformMacAssessmentError(
                "Mac subject changed during Gatekeeper assessment"
            )
        try:
            gatekeeper_stdout = _read_raw_reference(
                work_root,
                gatekeeper_invocation.get("stdout"),
                f"{plan.gatekeeper_invocation.invocation_id}.stdout",
            )
            gatekeeper_stderr = _read_raw_reference(
                work_root,
                gatekeeper_invocation.get("stderr"),
                f"{plan.gatekeeper_invocation.invocation_id}.stderr",
            )
        except PlatformCodesignVerificationError as error:
            raise PlatformMacAssessmentError(
                "Gatekeeper raw evidence failed reinspection"
            ) from error
        gatekeeper = parse_gatekeeper_output(
            plan,
            gatekeeper_invocation,
            gatekeeper_stdout,
            gatekeeper_stderr,
        )
        stapler_invocation: dict[str, Any] | None = None
        stapler: dict[str, Any] | None = None
        after_stapler = after_gatekeeper
        if gatekeeper["status"] == "passed":
            try:
                stapler_invocation = run_fixed_tool_invocation(
                    plan.stapler_invocation,
                    work_root,
                )
            except FixedToolError as error:
                raise PlatformMacAssessmentError(
                    "fixed stapler validation could not produce evidence"
                ) from error
            after_stapler = _assessment_rehash(
                subject,
                entries,
                work_root,
                "post-stapler",
            )
            if after_gatekeeper != after_stapler:
                raise PlatformMacAssessmentError(
                    "Mac subject changed during stapler validation"
                )
            try:
                stapler_stdout = _read_raw_reference(
                    work_root,
                    stapler_invocation.get("stdout"),
                    f"{plan.stapler_invocation.invocation_id}.stdout",
                )
                stapler_stderr = _read_raw_reference(
                    work_root,
                    stapler_invocation.get("stderr"),
                    f"{plan.stapler_invocation.invocation_id}.stderr",
                )
            except PlatformCodesignVerificationError as error:
                raise PlatformMacAssessmentError(
                    "stapler raw evidence failed reinspection"
                ) from error
            stapler = parse_stapler_output(
                plan,
                stapler_invocation,
                stapler_stdout,
                stapler_stderr,
            )
        passed = (
            gatekeeper["status"] == "passed"
            and stapler is not None
            and stapler["status"] == "passed"
        )
        records.append({
            "artifactID": plan.artifact_id,
            "status": "passed" if passed else "failed",
            "reason": (
                None
                if passed
                else gatekeeper["reason"]
                if gatekeeper["status"] != "passed"
                else stapler["reason"] if stapler is not None else "staplerNotRun"
            ),
            "platformAcceptanceEligible": False,
            "outerPrerequisite": prerequisite,
            "subjectBefore": before,
            "gatekeeperInvocation": gatekeeper_invocation,
            "gatekeeperAssessment": gatekeeper,
            "subjectAfterGatekeeper": after_gatekeeper,
            "staplerInvocation": stapler_invocation,
            "staplerValidation": stapler,
            "notarizationCorrelation": None,
            "subjectAfterStapler": after_stapler,
        })
    try:
        after_prerequisites = validate_correlated_outer_codesign_records(
            plans=outer_plans,
            records=outer_records,
            architecture_plans=architecture_plans,
            architecture_records=architecture_records,
            verification_records=verification_records,
            reconstructed=reconstructed,
            composition=composition,
            graph=graph,
            policy=policy,
            team_id=team_id,
            work_root=work_root,
        )
    except PlatformCodesignOuterError as error:
        raise PlatformMacAssessmentError(
            "Mac platform assessment signing prerequisites failed postflight reinspection"
        ) from error
    if before_prerequisites != after_prerequisites:
        raise PlatformMacAssessmentError(
            "Mac platform assessment signing prerequisites changed during execution"
        )
    return records
