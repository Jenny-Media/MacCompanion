#!/usr/bin/env python3

from __future__ import annotations

import copy
import tempfile
from dataclasses import replace
from pathlib import Path

from platform_codesign_outer import (
    PlatformCodesignOuterError,
    execute_outer_codesign_verification_plans,
    parse_outer_codesign_verification_output,
)
from platform_signing_fixed_tools import inspect_fixed_tool
from platform_signing_subjects import derive_codesign_outer_verification_plans
from validate_platform_signing_subjects import reconstruct


def require_failure(operation, expected: str) -> None:
    try:
        operation()
    except PlatformCodesignOuterError as error:
        if expected not in str(error):
            raise RuntimeError(
                f"expected outer codesign failure containing {expected!r}, got {error!r}"
            ) from error
    else:
        raise RuntimeError(
            f"expected outer codesign failure containing {expected!r}"
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
            "sha256": "1" * 64,
        },
        "passed": passed,
    }


def success_stderr(plan) -> bytes:
    subject = str(plan.owned_subject_path)
    return (
        f"{subject}: valid on disk\n"
        f"{subject}: satisfies its Designated Requirement\n"
    ).encode("utf-8")


def main() -> int:
    codesign = inspect_fixed_tool("apple.codesign", "/usr/bin/codesign")
    with tempfile.TemporaryDirectory(
        prefix="maccompanion-outer-codesign-execution-"
    ) as value:
        root = Path(value)
        _, composition, graph, work_root, subjects = reconstruct(root, "mac")
        plans = derive_codesign_outer_verification_plans(
            graph=graph,
            reconstructed=subjects,
            codesign_tool=codesign,
        )
        if len(plans) != 1:
            raise RuntimeError("outer codesign plan did not select one Mac application")
        plan = plans[0]
        if plan.invocation.arguments != (
            "--verify",
            "--deep",
            "--strict",
            "--all-architectures",
            "--verbose=4",
            str(plan.owned_subject_path),
        ):
            raise RuntimeError("outer codesign plan changed its fixed argv")
        records = execute_outer_codesign_verification_plans(
            plans=plans,
            reconstructed=subjects,
            composition=composition,
            graph=graph,
            work_root=work_root,
        )
        if (
            len(records) != 1
            or records[0]["status"] != "failed"
            or records[0]["reason"] != "nonzeroExit"
            or records[0]["platformAcceptanceEligible"] is not False
            or records[0]["subjectBefore"] != records[0]["subjectAfter"]
        ):
            raise RuntimeError("unsigned outer codesign execution did not fail closed")

        passed = fixture_result(plan)
        parsed = parse_outer_codesign_verification_output(
            plan,
            passed,
            b"",
            success_stderr(plan),
        )
        if parsed != {
            "status": "passed",
            "reason": None,
            "messages": ["validOnDisk", "satisfiesDesignatedRequirement"],
        }:
            raise RuntimeError("outer codesign success grammar changed")
        require_failure(
            lambda: parse_outer_codesign_verification_output(
                plan,
                passed,
                b"unexpected\n",
                success_stderr(plan),
            ),
            "contradictory facts",
        )
        require_failure(
            lambda: parse_outer_codesign_verification_output(
                plan,
                passed,
                b"",
                success_stderr(plan) + b"warning\n",
            ),
            "closed grammar",
        )
        require_failure(
            lambda: parse_outer_codesign_verification_output(
                plan,
                passed,
                b"",
                success_stderr(plan).replace(b"valid on disk\n", b""),
            ),
            "closed grammar",
        )
        changed = fixture_result(plan)
        changed["argv"] = ["/usr/bin/codesign", "substituted"]
        require_failure(
            lambda: parse_outer_codesign_verification_output(
                plan,
                changed,
                b"",
                success_stderr(plan),
            ),
            "differs from its fixed plan",
        )
        open_result = fixture_result(plan)
        open_result["unexpected"] = True
        require_failure(
            lambda: parse_outer_codesign_verification_output(
                plan,
                open_result,
                b"",
                success_stderr(plan),
            ),
            "not closed",
        )
        failed = fixture_result(plan, passed=False)
        if parse_outer_codesign_verification_output(
            plan,
            failed,
            b"",
            b"candidate-controlled failure detail",
        ) != {"status": "failed", "reason": "nonzeroExit", "messages": []}:
            raise RuntimeError("outer codesign failure output was interpreted as success")

    with tempfile.TemporaryDirectory(
        prefix="maccompanion-outer-codesign-combined-"
    ) as value:
        root = Path(value)
        _, composition, graph, work_root, subjects = reconstruct(root, "combined")
        plans = derive_codesign_outer_verification_plans(
            graph=graph,
            reconstructed=subjects,
            codesign_tool=codesign,
        )
        if len(plans) != 1 or plans[0].artifact_id != "mac-application":
            raise RuntimeError("outer codesign plan did not exclude the iOS construction subject")

    with tempfile.TemporaryDirectory(
        prefix="maccompanion-outer-codesign-ios-"
    ) as value:
        root = Path(value)
        _, composition, graph, work_root, subjects = reconstruct(root, "ios")
        plans = derive_codesign_outer_verification_plans(
            graph=graph,
            reconstructed=subjects,
            codesign_tool=codesign,
        )
        if plans or execute_outer_codesign_verification_plans(
            plans=plans,
            reconstructed=subjects,
            composition=composition,
            graph=graph,
            work_root=work_root,
        ):
            raise RuntimeError("outer Mac verification broadened the iOS construction lane")

    with tempfile.TemporaryDirectory(
        prefix="maccompanion-outer-codesign-plan-mutation-"
    ) as value:
        root = Path(value)
        _, composition, graph, work_root, subjects = reconstruct(root, "mac")
        plans = derive_codesign_outer_verification_plans(
            graph=graph,
            reconstructed=subjects,
            codesign_tool=codesign,
        )
        changed = [replace(plans[0], artifact_id="substituted")]
        require_failure(
            lambda: execute_outer_codesign_verification_plans(
                plans=changed,
                reconstructed=subjects,
                composition=composition,
                graph=graph,
                work_root=work_root,
            ),
            "differ from exact rederivation",
        )

    with tempfile.TemporaryDirectory(
        prefix="maccompanion-outer-codesign-subject-mutation-"
    ) as value:
        root = Path(value)
        _, composition, graph, work_root, subjects = reconstruct(root, "mac")
        plans = derive_codesign_outer_verification_plans(
            graph=graph,
            reconstructed=subjects,
            codesign_tool=codesign,
        )
        entry = next(
            item
            for item in composition["artifacts"][0]["entries"]
            if item["type"] == "regularFile"
        )
        path = subjects[0].artifact_root / entry["path"]
        path.write_bytes(path.read_bytes() + b"mutation")
        require_failure(
            lambda: execute_outer_codesign_verification_plans(
                plans=plans,
                reconstructed=subjects,
                composition=composition,
                graph=graph,
                work_root=work_root,
            ),
            "preflight reinspection",
        )
        if list(work_root.glob("codesign-outer-*.stdout")):
            raise RuntimeError("mutated outer subject reached codesign execution")

    with tempfile.TemporaryDirectory(
        prefix="maccompanion-outer-codesign-composition-mutation-"
    ) as value:
        root = Path(value)
        _, composition, graph, work_root, subjects = reconstruct(root, "mac")
        plans = derive_codesign_outer_verification_plans(
            graph=graph,
            reconstructed=subjects,
            codesign_tool=codesign,
        )
        changed = copy.deepcopy(composition)
        entry = next(
            item
            for item in changed["artifacts"][0]["entries"]
            if item["type"] == "regularFile"
        )
        entry["sha256"] = "0" * 64
        require_failure(
            lambda: execute_outer_codesign_verification_plans(
                plans=plans,
                reconstructed=subjects,
                composition=changed,
                graph=graph,
                work_root=work_root,
            ),
            "preflight reinspection",
        )

    print(
        "Validated exact Mac outer deep-codesign planning, immutable execution, "
        "closed success grammar, and non-acceptance evidence."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
