#!/usr/bin/env python3

from __future__ import annotations

import copy
import tempfile
from pathlib import Path
from typing import Any, Callable

import platform_codesign_inspection as inspection_module
from artifact_sbom import canonical_bytes
from platform_signing_evidence import (
    MAX_RECORD_BYTES,
    PlatformSigningEvidenceError,
    _target_results,
    exact_reference,
    generate_construction_record,
    parse_construction_record,
    validate_construction_record,
)
from platform_signing_subjects import derive_codesign_outer_verification_plans
from validate_platform_codesign_inspection_execution import (
    execute_with_fakes,
    fake_embedded_inspector,
    prepare,
)
from validate_platform_codesign_outer import execute_correlated_with_fakes
from validate_platform_signing_subjects import TEAM_ID


def require_failure(operation: Callable[[], Any], expected: str) -> None:
    try:
        operation()
    except PlatformSigningEvidenceError as error:
        if expected not in str(error):
            raise RuntimeError(
                f"expected platform evidence failure containing {expected!r}, got {error!r}"
            ) from error
    else:
        raise RuntimeError(
            f"expected platform evidence failure containing {expected!r}"
        )


def inputs(context: dict[str, Any]) -> dict[str, Any]:
    return {
        "releaseManifest": exact_reference(
            "verification/release-manifest.json",
            context["releaseManifest"],
        ),
        "artifactSBOM": copy.deepcopy(context["graph"]["artifactSBOM"]),
        "signedCodeGraph": copy.deepcopy(context["policy"]["signedCodeGraph"]),
        "signingPolicy": exact_reference(
            "verification/signing-policy.json",
            context["policy"],
        ),
    }


def record_inputs(
    context: dict[str, Any],
    architecture_records: list[dict[str, Any]],
    outer_records: list[dict[str, Any]],
) -> dict[str, Any]:
    return {
        "release_manifest": context["releaseManifest"],
        "artifact_index": context["index"],
        "composition": context["composition"],
        "graph": context["graph"],
        "policy": context["policy"],
        "input_references": inputs(context),
        "environment": {
            "hostOSBuild": "macOS 27.0 build 26A123",
            "xcodeBuild": "Xcode 27.0 beta build 18A123",
            "sdkBuild": "macOS 27.0 SDK 26A123",
            "stableReleaseToolchain": False,
        },
        "outer_plans": derive_codesign_outer_verification_plans(
            graph=context["graph"],
            reconstructed=context["subjects"],
            codesign_tool=context["plans"][0].identity_invocation.tool,
        ),
        "outer_records": outer_records,
        "architecture_plans": context["plans"],
        "architecture_records": architecture_records,
        "verification_records": context["verificationRecords"],
        "reconstructed": context["subjects"],
        "team_id": TEAM_ID,
        "evidence_root": context["evidenceRoot"],
        "work_root": context["workRoot"],
    }


def with_fake_inspector(context: dict[str, Any], operation: Callable[[], Any]) -> Any:
    original = inspection_module.inspect_embedded_signature
    inspection_module.inspect_embedded_signature = fake_embedded_inspector(context)
    try:
        return operation()
    finally:
        inspection_module.inspect_embedded_signature = original


def main() -> int:
    with tempfile.TemporaryDirectory(
        prefix="maccompanion-platform-signing-evidence-"
    ) as value:
        context = prepare(Path(value))
        architecture_records = execute_with_fakes(context)
        outer_records = execute_correlated_with_fakes(context, architecture_records)
        kwargs = record_inputs(context, architecture_records, outer_records)
        record = with_fake_inspector(
            context,
            lambda: generate_construction_record(
                created="2026-08-22T17:30:00Z",
                **kwargs,
            ),
        )
        raw = canonical_bytes(record)
        if (
            not 0 < len(raw) <= MAX_RECORD_BYTES
            or record["platformAcceptanceEligible"] is not False
            or record["evidenceLevel"] != "constructionOnly"
            or record["targetResults"] != [{
                "platform": "macOS",
                "status": "signedConstructionOnly",
                "unresolvedGates": sorted({
                    "finalCandidateExecutionRequired",
                    "productionCredentialCustodyRequired",
                    "physicalMatrixRequired",
                    "humanPromotionApprovalRequired",
                    "stableReleaseToolchainRequired",
                    "gatekeeperAssessmentRequired",
                    "notarizationCorrelationRequired",
                    "staplingValidationRequired",
                    "packagingEquivalenceRequired",
                }),
                "platformAcceptanceEligible": False,
            }]
            or record["artifacts"][0]["outerConsistencyVerified"] is not True
            or record["artifacts"][0]["architectureCount"]
            != len(architecture_records)
        ):
            raise RuntimeError("canonical platform signing construction record is incomplete")

        parsed = with_fake_inspector(
            context,
            lambda: parse_construction_record(raw, **kwargs),
        )
        if parsed != record:
            raise RuntimeError("canonical platform signing record did not round trip")
        repeated = with_fake_inspector(
            context,
            lambda: generate_construction_record(
                created=record["created"],
                **kwargs,
            ),
        )
        if canonical_bytes(repeated) != raw:
            raise RuntimeError("platform signing record generation is not deterministic")

        changed = copy.deepcopy(record)
        changed["platformAcceptanceEligible"] = True
        require_failure(
            lambda: validate_construction_record(changed, **kwargs),
            "identity or acceptance state",
        )
        changed = copy.deepcopy(record)
        changed["unexpected"] = True
        require_failure(
            lambda: validate_construction_record(changed, **kwargs),
            "not closed",
        )
        changed = copy.deepcopy(record)
        changed["architectures"][0]["policyComparison"]["policyMatched"] = False
        require_failure(
            lambda: with_fake_inspector(
                context,
                lambda: validate_construction_record(changed, **kwargs),
            ),
            "exact recomposition",
        )
        changed = copy.deepcopy(record)
        changed["unresolvedGates"] = changed["unresolvedGates"][:-1]
        require_failure(
            lambda: with_fake_inspector(
                context,
                lambda: validate_construction_record(changed, **kwargs),
            ),
            "exact recomposition",
        )

        bad_kwargs = copy.deepcopy(kwargs)
        bad_kwargs["input_references"] = copy.deepcopy(kwargs["input_references"])
        bad_kwargs["input_references"]["signingPolicy"]["sha256"] = "0" * 64
        require_failure(
            lambda: with_fake_inspector(
                context,
                lambda: generate_construction_record(
                    created=record["created"],
                    **bad_kwargs,
                ),
            ),
            "exact canonical input",
        )
        bad_kwargs = copy.deepcopy(kwargs)
        bad_kwargs["architecture_records"] = kwargs["architecture_records"][:-1]
        require_failure(
            lambda: with_fake_inspector(
                context,
                lambda: generate_construction_record(
                    created=record["created"],
                    **bad_kwargs,
                ),
            ),
            "failed reinspection",
        )
        require_failure(
            lambda: with_fake_inspector(
                context,
                lambda: parse_construction_record(raw[:-1] + b" \n", **kwargs),
            ),
            "not canonical JSON",
        )
        require_failure(
            lambda: parse_construction_record(b"x" * (MAX_RECORD_BYTES + 1), **kwargs),
            "size is outside",
        )

        target_results, gates = _target_results(["iOS", "macOS"], True)
        if (
            [item["platform"] for item in target_results] != ["iOS", "macOS"]
            or "exportedIPARequired" not in gates
            or "gatekeeperAssessmentRequired" not in gates
            or "stableReleaseToolchainRequired" in gates
            or any(item["platformAcceptanceEligible"] is not False for item in target_results)
        ):
            raise RuntimeError("target-specific unresolved gates are not closed")

    print(
        "Validated deterministic bounded platform-signing record composition, "
        "exact input and execution reinspection, target-specific unresolved gates, "
        "and immutable construction-only acceptance state."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
