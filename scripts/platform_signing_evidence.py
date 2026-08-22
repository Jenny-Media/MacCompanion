#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import re
from pathlib import Path
from typing import Any

from artifact_sbom import (
    ArtifactSBOMError,
    canonical_bytes,
    parse_canonical_json,
    parse_timestamp,
    safe_relative_path,
    validate_composition,
    validate_index,
    validate_release_binding,
)
from platform_codesign_outer import (
    PlatformCodesignOuterError,
    validate_correlated_outer_codesign_records,
)
from platform_codesign_inspection import PlatformCodesignInspectionError
from platform_codesign_verification import (
    PlatformCodesignVerificationError,
    _composition_by_id,
    _rehash_subject,
)
from platform_signing_subjects import (
    PlannedCodeSignArchitectureInspection,
    PlannedCodeSignOuterVerification,
    ReconstructedSigningSubject,
)
from signed_code_graph import SignedCodeGraphError, validate_graph
from signing_policy import SigningPolicyError, validate_policy


SCHEMA = "maccompanion.platform-signing-evidence.v0.1"
PRODUCT = "Mac Companion"
EVIDENCE_LEVEL = "constructionOnly"
MAX_RECORD_BYTES = 8 * 1024 * 1024
MAX_REFERENCE_BYTES = 8 * 1024 * 1024
SHA256 = re.compile(r"^[0-9a-f]{64}$")
BOUNDED_TEXT = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 ._+()/-]{0,191}$")

ROOT_KEYS = {
    "schemaVersion",
    "product",
    "evidenceLevel",
    "release",
    "source",
    "created",
    "inputs",
    "environment",
    "tools",
    "artifacts",
    "wholeObjectVerification",
    "architectures",
    "macOuterVerification",
    "targetResults",
    "unresolvedGates",
    "platformAcceptanceEligible",
}
INPUT_KEYS = {
    "releaseManifest",
    "artifactSBOM",
    "signedCodeGraph",
    "signingPolicy",
}
REFERENCE_KEYS = {"path", "bytes", "sha256"}
ENVIRONMENT_KEYS = {
    "hostOSBuild",
    "xcodeBuild",
    "sdkBuild",
    "stableReleaseToolchain",
}
TOOL_KEYS = {"toolID", "path", "bytes", "sha256"}
ARTIFACT_KEYS = {
    "artifactID",
    "platform",
    "subjectRoot",
    "subject",
    "architectureCount",
    "outerConsistencyVerified",
    "platformAcceptanceEligible",
}
TARGET_RESULT_KEYS = {
    "platform",
    "status",
    "unresolvedGates",
    "platformAcceptanceEligible",
}

GLOBAL_GATES = {
    "finalCandidateExecutionRequired",
    "productionCredentialCustodyRequired",
    "physicalMatrixRequired",
    "humanPromotionApprovalRequired",
}
MAC_GATES = {
    "gatekeeperAssessmentRequired",
    "notarizationCorrelationRequired",
    "staplingValidationRequired",
    "packagingEquivalenceRequired",
}
IOS_GATES = {
    "exportedIPARequired",
    "provisioningAcceptanceRequired",
    "physicalInstallLaunchRequired",
}


class PlatformSigningEvidenceError(ValueError):
    pass


def _closed(value: Any, keys: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise PlatformSigningEvidenceError(f"{label} is not closed")
    return value


def _reference(
    value: Any,
    expected_value: dict[str, Any],
    label: str,
) -> dict[str, Any]:
    reference = _closed(value, REFERENCE_KEYS, label)
    try:
        safe_relative_path(reference["path"], f"{label} path")
    except ArtifactSBOMError as error:
        raise PlatformSigningEvidenceError(f"{label} path is unsafe") from error
    raw = canonical_bytes(expected_value)
    if (
        not isinstance(reference["bytes"], int)
        or isinstance(reference["bytes"], bool)
        or not 0 < reference["bytes"] <= MAX_REFERENCE_BYTES
        or not isinstance(reference["sha256"], str)
        or SHA256.fullmatch(reference["sha256"]) is None
        or reference["bytes"] != len(raw)
        or reference["sha256"] != hashlib.sha256(raw).hexdigest()
    ):
        raise PlatformSigningEvidenceError(
            f"{label} does not bind its exact canonical input"
        )
    return dict(reference)


def exact_reference(path: str, value: dict[str, Any]) -> dict[str, Any]:
    try:
        safe_relative_path(path, "platform signing input path")
    except ArtifactSBOMError as error:
        raise PlatformSigningEvidenceError(
            "platform signing input path is unsafe"
        ) from error
    raw = canonical_bytes(value)
    if not 0 < len(raw) <= MAX_REFERENCE_BYTES:
        raise PlatformSigningEvidenceError(
            "platform signing input exceeds the reference profile"
        )
    return {
        "path": path,
        "bytes": len(raw),
        "sha256": hashlib.sha256(raw).hexdigest(),
    }


def _environment(value: Any) -> dict[str, Any]:
    environment = _closed(value, ENVIRONMENT_KEYS, "platform signing environment")
    for key in ("hostOSBuild", "xcodeBuild", "sdkBuild"):
        item = environment[key]
        if not isinstance(item, str) or BOUNDED_TEXT.fullmatch(item) is None:
            raise PlatformSigningEvidenceError(
                f"platform signing environment {key} is invalid"
            )
    if not isinstance(environment["stableReleaseToolchain"], bool):
        raise PlatformSigningEvidenceError(
            "stable release toolchain fact is not Boolean"
        )
    return dict(environment)


def _tool_inventory(
    architecture_plans: list[PlannedCodeSignArchitectureInspection],
    outer_plans: list[PlannedCodeSignOuterVerification],
) -> list[dict[str, Any]]:
    tools = {
        plan.identity_invocation.tool
        for plan in architecture_plans
    } | {
        plan.entitlements_invocation.tool
        for plan in architecture_plans
    } | {
        plan.invocation.tool
        for plan in outer_plans
    }
    records = sorted(
        (tool.public_record() for tool in tools),
        key=lambda item: item["toolID"],
    )
    if len(records) != 1:
        raise PlatformSigningEvidenceError(
            "construction record requires one fixed platform signing tool"
        )
    tool = _closed(records[0], TOOL_KEYS, "platform signing tool")
    if (
        tool["toolID"] != "apple.codesign"
        or tool["path"] != "/usr/bin/codesign"
        or not isinstance(tool["bytes"], int)
        or isinstance(tool["bytes"], bool)
        or tool["bytes"] <= 0
        or not isinstance(tool["sha256"], str)
        or SHA256.fullmatch(tool["sha256"]) is None
    ):
        raise PlatformSigningEvidenceError(
            "platform signing tool inventory is invalid"
        )
    return [dict(tool)]


def _target_results(
    targets: list[str],
    stable_release_toolchain: bool,
) -> tuple[list[dict[str, Any]], list[str]]:
    global_gates = set(GLOBAL_GATES)
    if not stable_release_toolchain:
        global_gates.add("stableReleaseToolchainRequired")
    results: list[dict[str, Any]] = []
    all_gates = set(global_gates)
    for platform in targets:
        if platform == "macOS":
            gates = sorted(global_gates | MAC_GATES)
            status = "signedConstructionOnly"
        elif platform == "iOS":
            gates = sorted(global_gates | IOS_GATES)
            status = "archiveConstructionOnly"
        else:
            raise PlatformSigningEvidenceError(
                "platform signing target is unsupported"
            )
        all_gates.update(gates)
        results.append({
            "platform": platform,
            "status": status,
            "unresolvedGates": gates,
            "platformAcceptanceEligible": False,
        })
    return results, sorted(all_gates)


def generate_construction_record(
    *,
    release_manifest: dict[str, Any],
    artifact_index: dict[str, Any],
    composition: dict[str, Any],
    graph: dict[str, Any],
    policy: dict[str, Any],
    input_references: dict[str, Any],
    environment: dict[str, Any],
    created: str,
    outer_plans: list[PlannedCodeSignOuterVerification],
    outer_records: list[dict[str, Any]],
    architecture_plans: list[PlannedCodeSignArchitectureInspection],
    architecture_records: list[dict[str, Any]],
    verification_records: list[dict[str, Any]],
    reconstructed: list[ReconstructedSigningSubject],
    team_id: str,
    evidence_root: Path,
    work_root: Path,
) -> dict[str, Any]:
    try:
        parse_timestamp(created)
        index = validate_index(artifact_index)
        validated_composition = validate_composition(composition, index)
        validate_release_binding(release_manifest, index, validated_composition)
        validated_policy = validate_policy(policy)
    except (ArtifactSBOMError, SigningPolicyError) as error:
        raise PlatformSigningEvidenceError(
            "platform signing record input is invalid"
        ) from error
    references = _closed(input_references, INPUT_KEYS, "platform signing inputs")
    bound_references = {
        "releaseManifest": _reference(
            references["releaseManifest"],
            release_manifest,
            "release manifest reference",
        ),
        "artifactSBOM": _reference(
            references["artifactSBOM"],
            index,
            "artifact SBOM reference",
        ),
        "signedCodeGraph": _reference(
            references["signedCodeGraph"],
            graph,
            "signed-code graph reference",
        ),
        "signingPolicy": _reference(
            references["signingPolicy"],
            validated_policy,
            "signing policy reference",
        ),
    }
    if (
        validated_policy["artifactSBOM"] != bound_references["artifactSBOM"]
        or validated_policy["signedCodeGraph"]
        != bound_references["signedCodeGraph"]
        or graph.get("artifactSBOM") != bound_references["artifactSBOM"]
    ):
        raise PlatformSigningEvidenceError(
            "platform signing input references do not agree"
        )
    release_projection = {
        "version": validated_policy["release"]["version"],
        "buildNumber": validated_policy["release"]["buildNumber"],
        "targets": validated_policy["release"]["targets"],
    }
    if (
        graph.get("release") != release_projection
        or index["release"] != release_projection
        or graph.get("source") != validated_policy["source"]
        or index["source"] != validated_policy["source"]
    ):
        raise PlatformSigningEvidenceError(
            "platform signing release or source bindings disagree"
        )
    try:
        validate_graph(
            graph,
            index=index,
            composition=validated_composition,
            release_manifest=release_manifest,
            artifact_sbom_reference=bound_references["artifactSBOM"],
            evidence_root=evidence_root,
        )
        outer_summaries = validate_correlated_outer_codesign_records(
            plans=outer_plans,
            records=outer_records,
            architecture_plans=architecture_plans,
            architecture_records=architecture_records,
            verification_records=verification_records,
            reconstructed=reconstructed,
            composition=validated_composition,
            graph=graph,
            policy=validated_policy,
            team_id=team_id,
            work_root=work_root,
        )
        entries_by_id = _composition_by_id(validated_composition)
    except (
        SignedCodeGraphError,
        PlatformCodesignOuterError,
        PlatformCodesignInspectionError,
        PlatformCodesignVerificationError,
    ) as error:
        raise PlatformSigningEvidenceError(
            "platform signing execution evidence failed reinspection"
        ) from error
    architecture_counts: dict[str, int] = {}
    for record in architecture_records:
        artifact_id = record.get("artifactID") if isinstance(record, dict) else None
        if not isinstance(artifact_id, str):
            raise PlatformSigningEvidenceError(
                "platform signing architecture record lacks an artifact"
            )
        architecture_counts[artifact_id] = architecture_counts.get(artifact_id, 0) + 1
    outer_ids = {summary["artifactID"] for summary in outer_summaries}
    artifacts: list[dict[str, Any]] = []
    for subject in reconstructed:
        entries = entries_by_id.get(subject.artifact_id)
        if entries is None or subject.artifact_id not in architecture_counts:
            raise PlatformSigningEvidenceError(
                "platform signing artifact coverage is incomplete"
            )
        current = _rehash_subject(subject, entries, work_root)
        artifacts.append({
            "artifactID": subject.artifact_id,
            "platform": subject.platform,
            "subjectRoot": subject.subject_root,
            "subject": current,
            "architectureCount": architecture_counts[subject.artifact_id],
            "outerConsistencyVerified": (
                True if subject.platform == "macOS" and subject.artifact_id in outer_ids
                else None
            ),
            "platformAcceptanceEligible": False,
        })
    artifacts.sort(key=lambda item: item["artifactID"])
    validated_environment = _environment(environment)
    target_results, unresolved_gates = _target_results(
        validated_policy["release"]["targets"],
        validated_environment["stableReleaseToolchain"],
    )
    record = {
        "schemaVersion": SCHEMA,
        "product": PRODUCT,
        "evidenceLevel": EVIDENCE_LEVEL,
        "release": dict(validated_policy["release"]),
        "source": dict(validated_policy["source"]),
        "created": created,
        "inputs": bound_references,
        "environment": validated_environment,
        "tools": _tool_inventory(architecture_plans, outer_plans),
        "artifacts": artifacts,
        "wholeObjectVerification": verification_records,
        "architectures": architecture_records,
        "macOuterVerification": outer_records,
        "targetResults": target_results,
        "unresolvedGates": unresolved_gates,
        "platformAcceptanceEligible": False,
    }
    if len(canonical_bytes(record)) > MAX_RECORD_BYTES:
        raise PlatformSigningEvidenceError(
            "platform signing record exceeds the canonical size bound"
        )
    return record


def validate_construction_record(
    value: Any,
    **inputs: Any,
) -> dict[str, Any]:
    root = _closed(value, ROOT_KEYS, "platform signing record")
    if (
        root.get("schemaVersion") != SCHEMA
        or root.get("product") != PRODUCT
        or root.get("evidenceLevel") != EVIDENCE_LEVEL
        or root.get("platformAcceptanceEligible") is not False
    ):
        raise PlatformSigningEvidenceError(
            "platform signing record identity or acceptance state is invalid"
        )
    expected = generate_construction_record(
        created=root["created"],
        **inputs,
    )
    if canonical_bytes(root) != canonical_bytes(expected):
        raise PlatformSigningEvidenceError(
            "platform signing record differs from exact recomposition"
        )
    return root


def parse_construction_record(raw: bytes, **inputs: Any) -> dict[str, Any]:
    if not 0 < len(raw) <= MAX_RECORD_BYTES:
        raise PlatformSigningEvidenceError(
            "platform signing record size is outside the profile"
        )
    try:
        value = parse_canonical_json(raw)
    except ArtifactSBOMError as error:
        raise PlatformSigningEvidenceError(
            "platform signing record is not canonical JSON"
        ) from error
    return validate_construction_record(value, **inputs)
