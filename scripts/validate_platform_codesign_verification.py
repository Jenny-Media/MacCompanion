#!/usr/bin/env python3

from __future__ import annotations

import copy
import tempfile
from dataclasses import replace
from pathlib import Path

from platform_codesign_verification import (
    PlatformCodesignVerificationError,
    _read_raw_reference,
    execute_codesign_verification_plans,
    parse_codesign_verification_output,
)
from platform_signing_fixed_tools import inspect_fixed_tool
from platform_signing_subjects import derive_codesign_verification_plans
from validate_platform_signing_subjects import TEAM_ID, reconstruct


def require_failure(operation, expected: str) -> None:
    try:
        operation()
    except PlatformCodesignVerificationError as error:
        if expected not in str(error):
            raise RuntimeError(
                f"expected codesign failure containing {expected!r}, got {error!r}"
            ) from error
    else:
        raise RuntimeError(
            f"expected codesign failure containing {expected!r}"
        )


def fixture_result(plan, *, passed: bool = True) -> dict:
    return {
        "invocationID": plan.invocation.invocation_id,
        "tool": plan.invocation.tool.public_record(),
        "argv": [plan.invocation.tool.path, *plan.invocation.arguments],
        "environment": {
            "HOME": "/private/fixed",
            "TMPDIR": "/private/fixed",
            "LANG": "C",
            "LC_ALL": "C",
        },
        "timeoutSeconds": plan.invocation.timeout_seconds,
        "outputLimitBytesPerStream": 1024 * 1024,
        "startedAt": "2026-08-22T12:00:00.000Z",
        "completedAt": "2026-08-22T12:00:01.000Z",
        "durationMilliseconds": 1000,
        "termination": "exited",
        "returnCode": 0 if passed else 1,
        "toolUnchanged": True,
        "stdout": {
            "path": f"{plan.invocation.invocation_id}.stdout",
            "bytes": 0,
            "sha256": "e3b0c44298fc1c149afbf4c8996fb924"
            "27ae41e4649b934ca495991b7852b855",
        },
        "stderr": {
            "path": f"{plan.invocation.invocation_id}.stderr",
            "bytes": 1,
            "sha256": "0" * 64,
        },
        "passed": passed,
    }


def success_stderr(plan) -> bytes:
    subject = str(plan.owned_subject_path)
    return (
        f"{subject}: valid on disk\n"
        f"{subject}: satisfies its Designated Requirement\n"
        f"{subject}: explicit requirement satisfied\n"
    ).encode("utf-8")


def main() -> int:
    codesign = inspect_fixed_tool("apple.codesign", "/usr/bin/codesign")
    with tempfile.TemporaryDirectory(
        prefix="maccompanion-codesign-execution-"
    ) as value:
        root = Path(value)
        _, composition, graph, work_root, subjects = reconstruct(root, "mac")
        plans = derive_codesign_verification_plans(
            graph=graph,
            reconstructed=subjects,
            team_id=TEAM_ID,
            codesign_tool=codesign,
        )
        records = execute_codesign_verification_plans(
            plans=plans,
            reconstructed=subjects,
            composition=composition,
            graph=graph,
            team_id=TEAM_ID,
            work_root=work_root,
        )
        if len(records) != len(plans):
            raise RuntimeError("codesign execution omitted a fixed plan")
        if any(
            record["verification"]
            != {"status": "failed", "reason": "nonzeroExit", "messages": []}
            for record in records
        ):
            raise RuntimeError("unsigned fixtures did not fail closed")
        if any(
            record["subjectBefore"] != record["subjectAfter"]
            or record["invocation"]["stdout"]["bytes"] != 0
            or record["invocation"]["stderr"]["bytes"] <= 0
            for record in records
        ):
            raise RuntimeError("codesign execution evidence is incomplete")

        stdout_reference = records[0]["invocation"]["stdout"]
        stdout_path = work_root / stdout_reference["path"]
        stdout_path.write_bytes(b"mutation")
        require_failure(
            lambda: _read_raw_reference(
                work_root,
                stdout_reference,
                stdout_reference["path"],
            ),
            "unsafe filesystem facts",
        )

        plan = plans[0]
        passed = fixture_result(plan)
        parsed = parse_codesign_verification_output(
            plan,
            passed,
            b"",
            success_stderr(plan),
        )
        if parsed != {
            "status": "passed",
            "reason": None,
            "messages": [
                "validOnDisk",
                "satisfiesDesignatedRequirement",
                "explicitRequirementSatisfied",
            ],
        }:
            raise RuntimeError("closed codesign success grammar changed")

        require_failure(
            lambda: parse_codesign_verification_output(
                plan,
                passed,
                b"unexpected stdout\n",
                success_stderr(plan),
            ),
            "contradictory facts",
        )
        require_failure(
            lambda: parse_codesign_verification_output(
                plan,
                passed,
                b"",
                success_stderr(plan) + b"warning\n",
            ),
            "closed grammar",
        )
        require_failure(
            lambda: parse_codesign_verification_output(
                plan,
                passed,
                b"",
                success_stderr(plan).replace(b"valid on disk\n", b""),
            ),
            "closed grammar",
        )
        require_failure(
            lambda: parse_codesign_verification_output(
                plan,
                passed,
                b"",
                success_stderr(plan).replace(b"\n", b"\r\n"),
            ),
            "closed grammar",
        )
        changed_result = fixture_result(plan)
        changed_result["argv"] = ["/usr/bin/codesign", "substituted"]
        require_failure(
            lambda: parse_codesign_verification_output(
                plan,
                changed_result,
                b"",
                success_stderr(plan),
            ),
            "differs from its fixed plan",
        )
        open_result = fixture_result(plan)
        open_result["unexpected"] = True
        require_failure(
            lambda: parse_codesign_verification_output(
                plan,
                open_result,
                b"",
                success_stderr(plan),
            ),
            "not closed",
        )
        failed = fixture_result(plan, passed=False)
        if parse_codesign_verification_output(
            plan,
            failed,
            b"",
            b"candidate-controlled failure detail",
        ) != {"status": "failed", "reason": "nonzeroExit", "messages": []}:
            raise RuntimeError("failed codesign output was interpreted as success")

    with tempfile.TemporaryDirectory(
        prefix="maccompanion-codesign-plan-mutation-"
    ) as value:
        root = Path(value)
        _, composition, graph, work_root, subjects = reconstruct(root, "mac")
        plans = derive_codesign_verification_plans(
            graph=graph,
            reconstructed=subjects,
            team_id=TEAM_ID,
            codesign_tool=codesign,
        )
        changed_plans = list(plans)
        changed_plans[0] = replace(
            plans[0],
            object_path="Mac Companion.app/substituted",
        )
        require_failure(
            lambda: execute_codesign_verification_plans(
                plans=changed_plans,
                reconstructed=subjects,
                composition=composition,
                graph=graph,
                team_id=TEAM_ID,
                work_root=work_root,
            ),
            "differ from exact rederivation",
        )

    with tempfile.TemporaryDirectory(
        prefix="maccompanion-codesign-subject-mutation-"
    ) as value:
        root = Path(value)
        _, composition, graph, work_root, subjects = reconstruct(root, "mac")
        plans = derive_codesign_verification_plans(
            graph=graph,
            reconstructed=subjects,
            team_id=TEAM_ID,
            codesign_tool=codesign,
        )
        entries = composition["artifacts"][0]["entries"]
        entry = next(item for item in entries if item["type"] == "regularFile")
        path = subjects[0].artifact_root / entry["path"]
        path.write_bytes(path.read_bytes() + b"mutation")
        require_failure(
            lambda: execute_codesign_verification_plans(
                plans=plans,
                reconstructed=subjects,
                composition=composition,
                graph=graph,
                team_id=TEAM_ID,
                work_root=work_root,
            ),
            "phase reinspection",
        )
        if list(work_root.glob("codesign-verify-*.stdout")):
            raise RuntimeError("mutated subject reached a codesign invocation")

    with tempfile.TemporaryDirectory(
        prefix="maccompanion-codesign-composition-mutation-"
    ) as value:
        root = Path(value)
        _, composition, graph, work_root, subjects = reconstruct(root, "mac")
        plans = derive_codesign_verification_plans(
            graph=graph,
            reconstructed=subjects,
            team_id=TEAM_ID,
            codesign_tool=codesign,
        )
        changed_composition = copy.deepcopy(composition)
        entry = next(
            item
            for item in changed_composition["artifacts"][0]["entries"]
            if item["type"] == "regularFile"
        )
        entry["sha256"] = "0" * 64
        require_failure(
            lambda: execute_codesign_verification_plans(
                plans=plans,
                reconstructed=subjects,
                composition=changed_composition,
                graph=graph,
                team_id=TEAM_ID,
                work_root=work_root,
            ),
            "phase reinspection",
        )

    print(
        "Validated exact fixed codesign execution, immutable subject rehashing, "
        "bounded raw evidence, and closed verification-output parsing."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
