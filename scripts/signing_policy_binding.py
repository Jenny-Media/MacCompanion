#!/usr/bin/env python3

from __future__ import annotations

from typing import Any

from signing_policy import SigningPolicyError, validate_policy


EXECUTABLE_FIELDS = (
    "id", "role", "platform", "bundleIdentifier", "artifactID", "relativePath",
)
MEMBER_FIELDS = ("path", "type", "mode", "bytes", "sha1", "sha256", "symlinkTarget")


def _exact_executable(value: dict[str, Any]) -> dict[str, Any]:
    return {key: value[key] for key in EXECUTABLE_FIELDS}


def _construction_object(value: dict[str, Any]) -> dict[str, Any]:
    return {
        "path": value["path"],
        "member": {key: value["member"][key] for key in MEMBER_FIELDS},
        "ownerBundlePath": value["ownerBundlePath"],
        "bundleMainFor": value["bundleMainFor"],
        "declaredExecutableIDs": value["declaredExecutableIDs"],
        "architectures": [
            {
                "cpuType": architecture["cpuType"],
                "cpuSubtype": architecture["cpuSubtype"],
                "sliceSHA256": architecture["sliceSHA256"],
            }
            for architecture in value["architectures"]
        ],
    }


def _graph_construction_object(value: dict[str, Any]) -> dict[str, Any]:
    return {
        "path": value["path"],
        "member": {key: value["member"][key] for key in MEMBER_FIELDS},
        "ownerBundlePath": value["ownerBundlePath"],
        "bundleMainFor": value["bundleMainFor"],
        "declaredExecutableIDs": value["declaredExecutableIDs"],
        "architectures": [
            {
                "cpuType": architecture["cpuType"],
                "cpuSubtype": architecture["cpuSubtype"],
                "sliceSHA256": architecture["sliceSHA256"],
            }
            for architecture in value["machO"]["architectures"]
        ],
    }


def validate_policy_binding(
    policy_value: dict[str, Any],
    *,
    release_manifest: dict[str, Any],
    signed_code_graph: dict[str, Any],
    artifact_sbom_reference: dict[str, Any],
    signed_code_graph_reference: dict[str, Any],
) -> None:
    policy = validate_policy(policy_value)
    release = release_manifest["release"]
    expected_release = {
        "version": release["version"],
        "buildNumber": release["buildNumber"],
        "channel": release["channel"],
        "targets": sorted(release["targets"]),
    }
    if policy["release"] != expected_release:
        raise SigningPolicyError("signing policy release binding mismatch")
    if policy["source"] != {"revision": release_manifest["source"]["revision"], "dirty": False}:
        raise SigningPolicyError("signing policy source binding mismatch")
    if signed_code_graph.get("release") != {
        "version": release["version"],
        "buildNumber": release["buildNumber"],
        "targets": sorted(release["targets"]),
    } or signed_code_graph.get("source") != policy["source"]:
        raise SigningPolicyError("signed-code graph release or source binding mismatch")
    if policy["artifactSBOM"] != artifact_sbom_reference or signed_code_graph.get("artifactSBOM") != artifact_sbom_reference:
        raise SigningPolicyError("signing policy artifact-SBOM binding mismatch")
    if policy["signedCodeGraph"] != signed_code_graph_reference:
        raise SigningPolicyError("signing policy graph-reference binding mismatch")

    expected_executables = sorted(
        (_exact_executable(value) for value in release_manifest["executables"]),
        key=lambda item: item["id"],
    )
    if policy["declaredExecutables"] != expected_executables:
        raise SigningPolicyError("signing policy declared-executable binding mismatch")

    graph_artifacts = signed_code_graph.get("artifacts")
    if not isinstance(graph_artifacts, list):
        raise SigningPolicyError("signed-code graph artifact set is invalid")
    policy_by_id = {value["artifact"]["id"]: value for value in policy["artifacts"]}
    graph_by_id = {value["artifact"]["id"]: value for value in graph_artifacts}
    if len(policy_by_id) != len(policy["artifacts"]) or len(graph_by_id) != len(graph_artifacts) or set(policy_by_id) != set(graph_by_id):
        raise SigningPolicyError("signing policy artifact coverage mismatch")

    declared_coverage: list[str] = []
    for artifact_id in sorted(graph_by_id):
        graph_artifact = graph_by_id[artifact_id]
        policy_artifact = policy_by_id[artifact_id]
        if graph_artifact.get("platformAcceptanceEligible") is not False:
            raise SigningPolicyError("construction graph made an ineligible platform-acceptance claim")
        if policy_artifact["artifact"] != graph_artifact.get("artifact"):
            raise SigningPolicyError("signing policy artifact identity mismatch")
        if policy_artifact["subjectRoot"] != graph_artifact.get("subjectRoot"):
            raise SigningPolicyError("signing policy subject-root mismatch")
        bundle_identifiers = {
            value["path"]: value["bundleIdentifier"]
            for value in graph_artifact.get("bundles", [])
        }

        graph_objects = [
            value for value in graph_artifact.get("machOObjects", [])
            if value.get("inDistributionSubject") is True
        ]
        policy_objects = policy_artifact["objects"]
        if [value["path"] for value in policy_objects] != [value["path"] for value in graph_objects]:
            raise SigningPolicyError("signing policy distribution-object coverage mismatch")
        for policy_object, graph_object in zip(policy_objects, graph_objects):
            if _construction_object(policy_object) != _graph_construction_object(graph_object):
                raise SigningPolicyError("signing policy object or architecture binding mismatch")
            expected_identifiers: set[str] = set()
            declared_ids = policy_object["declaredExecutableIDs"]
            if len(declared_ids) > 1:
                raise SigningPolicyError("one signing-policy object maps multiple declared executables")
            if declared_ids:
                expected_identifiers.add(
                    next(
                        value["bundleIdentifier"]
                        for value in expected_executables
                        if value["id"] == declared_ids[0]
                    )
                )
            bundle_main = policy_object["bundleMainFor"]
            if bundle_main is not None:
                if bundle_main not in bundle_identifiers:
                    raise SigningPolicyError("signing-policy bundle-main identity is absent from graph topology")
                expected_identifiers.add(bundle_identifiers[bundle_main])
            if len(expected_identifiers) > 1:
                raise SigningPolicyError("declared and bundle signing identifiers disagree")
            if expected_identifiers:
                expected_identifier = next(iter(expected_identifiers))
                if any(
                    architecture["identity"]["signingIdentifier"] != expected_identifier
                    for architecture in policy_object["architectures"]
                ):
                    raise SigningPolicyError("signing-policy architecture signing identifier mismatch")
            declared_coverage.extend(policy_object["declaredExecutableIDs"])

    expected_ids = [value["id"] for value in expected_executables]
    if sorted(declared_coverage) != sorted(expected_ids) or len(declared_coverage) != len(set(declared_coverage)):
        raise SigningPolicyError("signing policy declared-executable coverage mismatch")
