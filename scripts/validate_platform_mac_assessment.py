#!/usr/bin/env python3

from __future__ import annotations

import copy
import tempfile
from dataclasses import replace
from pathlib import Path
from typing import Any, Callable

import platform_codesign_inspection as inspection_module
import platform_mac_assessment as assessment_module
from platform_mac_assessment import (
    PlatformMacAssessmentError,
    execute_mac_platform_assessment_plans,
    parse_gatekeeper_output,
    parse_stapler_output,
)
from platform_signing_fixed_tools import inspect_fixed_tool
from platform_signing_subjects import (
    derive_codesign_outer_verification_plans,
    derive_mac_platform_assessment_plans,
)
from validate_platform_codesign_inspection_execution import (
    execute_with_fakes,
    fake_embedded_inspector,
    invocation_result,
    prepare,
)
from validate_platform_codesign_outer import execute_correlated_with_fakes
from validate_platform_signing_subjects import TEAM_ID


# Both paths are already admitted by the production assessment policy.
# Prefer stable Xcode; inspect_fixed_tool still enforces regular-file identity.
STAPLER_PATH = "/Applications/Xcode.app/Contents/Developer/usr/bin/stapler"
if not Path(STAPLER_PATH).exists():
    STAPLER_PATH = "/Applications/Xcode-beta.app/Contents/Developer/usr/bin/stapler"


def require_failure(operation: Callable[[], Any], expected: str) -> None:
    try:
        operation()
    except PlatformMacAssessmentError as error:
        if expected not in str(error):
            raise RuntimeError(
                f"expected Mac assessment failure containing {expected!r}, got {error!r}"
            ) from error
    else:
        raise RuntimeError(
            f"expected Mac assessment failure containing {expected!r}"
        )


def plans(context: dict[str, Any]):
    return derive_mac_platform_assessment_plans(
        graph=context["graph"],
        reconstructed=context["subjects"],
        codesign_tool=context["plans"][0].identity_invocation.tool,
        gatekeeper_tool=inspect_fixed_tool("apple.spctl", "/usr/sbin/spctl"),
        stapler_tool=inspect_fixed_tool("apple.stapler", STAPLER_PATH),
    )


def execute_with_assessment_fakes(
    context: dict[str, Any],
    architecture_records: list[dict[str, Any]],
    outer_records: list[dict[str, Any]],
    *,
    gatekeeper_passed: bool = True,
    gatekeeper_warning: bool = False,
    mutate_after_gatekeeper: bool = False,
    assessment_plans: list[Any] | None = None,
) -> list[dict[str, Any]]:
    fixed_plans = assessment_plans or plans(context)
    original_runner = assessment_module.run_fixed_tool_invocation
    original_inspector = inspection_module.inspect_embedded_signature

    def runner(invocation, work_root):
        plan = fixed_plans[0]
        if invocation == plan.gatekeeper_invocation:
            result = invocation_result(
                invocation,
                work_root,
                b"",
                (
                    f"{plan.owned_subject_path}: accepted\n"
                    "source=Notarized Developer ID\n"
                    + ("warning\n" if gatekeeper_warning else "")
                ).encode("utf-8"),
                passed=gatekeeper_passed,
            )
            if mutate_after_gatekeeper:
                subject = context["subjects"][0]
                entry = next(
                    item
                    for item in context["composition"]["artifacts"][0]["entries"]
                    if item["type"] == "regularFile"
                )
                path = subject.artifact_root / entry["path"]
                path.write_bytes(path.read_bytes() + b"assessment mutation")
            return result
        if invocation == plan.stapler_invocation:
            return invocation_result(
                invocation,
                work_root,
                (
                    f"Processing: {plan.owned_subject_path}\n"
                    "The validate action worked!\n"
                ).encode("utf-8"),
                b"",
            )
        raise RuntimeError("Mac assessment fixture received an unknown invocation")

    assessment_module.run_fixed_tool_invocation = runner
    inspection_module.inspect_embedded_signature = fake_embedded_inspector(context)
    try:
        return execute_mac_platform_assessment_plans(
            plans=fixed_plans,
            outer_plans=derive_codesign_outer_verification_plans(
                graph=context["graph"],
                reconstructed=context["subjects"],
                codesign_tool=context["plans"][0].identity_invocation.tool,
            ),
            outer_records=outer_records,
            architecture_plans=context["plans"],
            architecture_records=architecture_records,
            verification_records=context["verificationRecords"],
            reconstructed=context["subjects"],
            composition=context["composition"],
            graph=context["graph"],
            policy=context["policy"],
            team_id=TEAM_ID,
            work_root=context["workRoot"],
        )
    finally:
        assessment_module.run_fixed_tool_invocation = original_runner
        inspection_module.inspect_embedded_signature = original_inspector


def main() -> int:
    with tempfile.TemporaryDirectory(
        prefix="maccompanion-platform-mac-assessment-"
    ) as value:
        context = prepare(Path(value))
        architecture_records = execute_with_fakes(context)
        outer_records = execute_correlated_with_fakes(context, architecture_records)
        fixed_plans = plans(context)
        if (
            len(fixed_plans) != 1
            or fixed_plans[0].gatekeeper_invocation.arguments != (
                "--assess",
                "--type",
                "execute",
                "--verbose=4",
                str(fixed_plans[0].owned_subject_path),
            )
            or fixed_plans[0].stapler_invocation.arguments != (
                "validate",
                str(fixed_plans[0].owned_subject_path),
            )
        ):
            raise RuntimeError("Mac assessment fixed plans changed")
        records = execute_with_assessment_fakes(
            context,
            architecture_records,
            outer_records,
        )
        if (
            len(records) != 1
            or records[0]["status"] != "passed"
            or records[0]["platformAcceptanceEligible"] is not False
            or records[0]["gatekeeperAssessment"] != {
                "status": "passed",
                "reason": None,
                "source": "Notarized Developer ID",
            }
            or records[0]["staplerValidation"] != {
                "status": "passed",
                "reason": None,
                "ticketValidated": True,
            }
            or records[0]["notarizationCorrelation"] is not None
            or records[0]["subjectBefore"] != records[0]["subjectAfterStapler"]
        ):
            raise RuntimeError("Mac platform assessment record is incomplete")

        plan = fixed_plans[0]
        gatekeeper_result = copy.deepcopy(records[0]["gatekeeperInvocation"])
        require_failure(
            lambda: parse_gatekeeper_output(
                plan,
                gatekeeper_result,
                b"unexpected\n",
                b"",
            ),
            "unexpected stdout",
        )

    with tempfile.TemporaryDirectory(
        prefix="maccompanion-platform-mac-assessment-failure-"
    ) as value:
        context = prepare(Path(value))
        architecture_records = execute_with_fakes(context)
        outer_records = execute_correlated_with_fakes(context, architecture_records)
        records = execute_with_assessment_fakes(
            context,
            architecture_records,
            outer_records,
            gatekeeper_passed=False,
        )
        if (
            records[0]["status"] != "failed"
            or records[0]["reason"] != "nonzeroExit"
            or records[0]["staplerInvocation"] is not None
            or records[0]["staplerValidation"] is not None
        ):
            raise RuntimeError("failed Gatekeeper assessment did not stop stapler")

    with tempfile.TemporaryDirectory(
        prefix="maccompanion-platform-mac-assessment-warning-"
    ) as value:
        context = prepare(Path(value))
        architecture_records = execute_with_fakes(context)
        outer_records = execute_correlated_with_fakes(context, architecture_records)
        require_failure(
            lambda: execute_with_assessment_fakes(
                context,
                architecture_records,
                outer_records,
                gatekeeper_warning=True,
            ),
            "closed grammar",
        )

    with tempfile.TemporaryDirectory(
        prefix="maccompanion-platform-mac-assessment-prerequisite-"
    ) as value:
        context = prepare(Path(value))
        architecture_records = execute_with_fakes(context)
        outer_records = execute_correlated_with_fakes(context, architecture_records)
        changed = copy.deepcopy(outer_records)
        changed[0]["status"] = "failed"
        require_failure(
            lambda: execute_with_assessment_fakes(
                context,
                architecture_records,
                changed,
            ),
            "prerequisites failed reinspection",
        )
        if list(context["workRoot"].glob("spctl-assess-*.stdout")):
            raise RuntimeError("invalid outer prerequisite reached Gatekeeper")

    with tempfile.TemporaryDirectory(
        prefix="maccompanion-platform-mac-assessment-plan-"
    ) as value:
        context = prepare(Path(value))
        architecture_records = execute_with_fakes(context)
        outer_records = execute_correlated_with_fakes(context, architecture_records)
        fixed = plans(context)
        changed = [replace(fixed[0], artifact_id="substituted")]
        require_failure(
            lambda: execute_with_assessment_fakes(
                context,
                architecture_records,
                outer_records,
                assessment_plans=changed,
            ),
            "differ from exact rederivation",
        )

    with tempfile.TemporaryDirectory(
        prefix="maccompanion-platform-mac-assessment-subject-"
    ) as value:
        context = prepare(Path(value))
        architecture_records = execute_with_fakes(context)
        outer_records = execute_correlated_with_fakes(context, architecture_records)
        require_failure(
            lambda: execute_with_assessment_fakes(
                context,
                architecture_records,
                outer_records,
                mutate_after_gatekeeper=True,
            ),
            "post-Gatekeeper reinspection",
        )

    print(
        "Validated exact graph-bound Gatekeeper and stapler plans, closed measured "
        "success grammars, complete signing prerequisites, immutable subjects, and "
        "non-acceptance platform evidence."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
