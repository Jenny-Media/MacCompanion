#!/usr/bin/env python3

from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Any

from artifact_sbom import canonical_bytes


SYNTHETIC_TEAM_ID = "ABCDE12345"
SYNTHETIC_MAC_CERTIFICATE_SHA256 = hashlib.sha256(
    b"Mac Companion synthetic Developer ID Application fixture certificate"
).hexdigest()
SYNTHETIC_IOS_CERTIFICATE_SHA256 = hashlib.sha256(
    b"Mac Companion synthetic Apple Distribution fixture certificate"
).hexdigest()


def _digest(label: str) -> str:
    return hashlib.sha256(label.encode("utf-8")).hexdigest()


def _signing_identifier(
    graph_artifact: dict[str, Any],
    object_value: dict[str, Any],
    declared_bundle_identifiers: dict[str, str],
) -> str:
    declared = object_value["declaredExecutableIDs"]
    if declared:
        return declared_bundle_identifiers[declared[0]]
    bundle_path = object_value["bundleMainFor"] or object_value["ownerBundlePath"]
    bundle = next(
        (item for item in graph_artifact.get("bundles", []) if item.get("path") == bundle_path),
        None,
    )
    if bundle is not None:
        return bundle["bundleIdentifier"]
    return f"com.example.maccompanion.object-{_digest(object_value['path'])[:16]}"


def generate_fixture_policy(
    *,
    release: dict[str, Any],
    graph: dict[str, Any],
    graph_reference: dict[str, Any],
    artifact_sbom_reference: dict[str, Any],
) -> dict[str, Any]:
    declared_bundle_identifiers = {
        executable["id"]: executable["bundleIdentifier"]
        for executable in release["executables"]
    }
    artifacts: list[dict[str, Any]] = []
    for graph_artifact in graph["artifacts"]:
        profile = (
            "macOSDeveloperID"
            if graph_artifact["artifact"]["platform"] == "macOS"
            else "iosArchiveConstructionOnly"
        )
        objects: list[dict[str, Any]] = []
        for graph_object in graph_artifact["machOObjects"]:
            if graph_object["inDistributionSubject"] is not True:
                continue
            identifier = _signing_identifier(
                graph_artifact,
                graph_object,
                declared_bundle_identifiers,
            )
            architectures = []
            for architecture in graph_object["machO"]["architectures"]:
                code_directory_sha256 = _digest(
                    f"{graph_artifact['artifact']['id']}:{graph_object['path']}:"
                    f"{architecture['cpuType']}:{architecture['cpuSubtype']}:CodeDirectory"
                )
                architectures.append({
                    "cpuType": architecture["cpuType"],
                    "cpuSubtype": architecture["cpuSubtype"],
                    "sliceSHA256": architecture["sliceSHA256"],
                    "identity": {
                        "signingIdentifier": identifier,
                        "teamIdentifier": SYNTHETIC_TEAM_ID,
                        "codeDirectories": [{
                            "hashType": "sha256",
                            "cdhash": code_directory_sha256[:40],
                            "codeDirectorySHA256": code_directory_sha256,
                        }],
                        "leafCertificateSHA256": (
                            SYNTHETIC_MAC_CERTIFICATE_SHA256
                            if profile == "macOSDeveloperID"
                            else SYNTHETIC_IOS_CERTIFICATE_SHA256
                        ),
                        "designatedRequirementDataSHA256": _digest(
                            f"{identifier}:designated-requirement-data"
                        ),
                    },
                    "signature": {
                        "trustProfile": (
                            "developerIDApplication"
                            if profile == "macOSDeveloperID"
                            else "iosArchiveConstructionOnly"
                        ),
                        "requireHardenedRuntime": profile == "macOSDeveloperID",
                        "requireSecureTimestamp": profile == "macOSDeveloperID",
                    },
                    "entitlements": {"mode": "absent"},
                })
            objects.append({
                "path": graph_object["path"],
                "member": {
                    key: graph_object["member"][key]
                    for key in ("path", "type", "mode", "bytes", "sha1", "sha256", "symlinkTarget")
                },
                "ownerBundlePath": graph_object["ownerBundlePath"],
                "bundleMainFor": graph_object["bundleMainFor"],
                "declaredExecutableIDs": list(graph_object["declaredExecutableIDs"]),
                "signerClass": "firstParty",
                "architectures": architectures,
            })
        artifacts.append({
            "artifact": dict(graph_artifact["artifact"]),
            "subjectRoot": graph_artifact["subjectRoot"],
            "verificationProfile": profile,
            "thirdPartyAllowlist": [],
            "objects": objects,
        })
    return {
        "schemaVersion": "maccompanion.signing-policy.v0.1",
        "policyID": "synthetic-release-policy",
        "policyRevision": 1,
        "product": "Mac Companion",
        "release": {
            "version": release["release"]["version"],
            "buildNumber": release["release"]["buildNumber"],
            "channel": release["release"]["channel"],
            "targets": sorted(release["release"]["targets"]),
        },
        "source": {"revision": release["source"]["revision"], "dirty": False},
        "artifactSBOM": dict(artifact_sbom_reference),
        "signedCodeGraph": dict(graph_reference),
        "officialSigners": [
            {
                "platform": platform,
                "trustProfile": "developerIDApplication" if platform == "macOS" else "iosArchiveConstructionOnly",
                "teamIdentifier": SYNTHETIC_TEAM_ID,
                "leafCertificateSHA256": (
                    SYNTHETIC_MAC_CERTIFICATE_SHA256
                    if platform == "macOS"
                    else SYNTHETIC_IOS_CERTIFICATE_SHA256
                ),
            }
            for platform in sorted(release["release"]["targets"])
        ],
        "declaredExecutables": sorted(
            [
                {
                    key: executable[key]
                    for key in ("id", "role", "platform", "bundleIdentifier", "artifactID", "relativePath")
                }
                for executable in release["executables"]
            ],
            key=lambda item: item["id"],
        ),
        "artifacts": sorted(artifacts, key=lambda item: item["artifact"]["id"]),
    }


def write_fixture_policy(
    root: Path,
    release: dict[str, Any],
    graph: dict[str, Any],
    graph_reference: dict[str, Any],
) -> str:
    policy = generate_fixture_policy(
        release=release,
        graph=graph,
        graph_reference=graph_reference,
        artifact_sbom_reference=release["sbom"]["document"],
    )
    raw = canonical_bytes(policy)
    relative_path = "verification/signing-policy.json"
    path = root / relative_path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(raw)
    reference = {
        "path": relative_path,
        "sha256": hashlib.sha256(raw).hexdigest(),
        "bytes": len(raw),
    }
    release["validation"] = [
        record for record in release["validation"]
        if record.get("id") != "signing-policy-contract"
    ]
    release["validation"].append({
        "id": "signing-policy-contract",
        "status": "passed",
        "evidence": reference,
    })
    return reference["sha256"]
