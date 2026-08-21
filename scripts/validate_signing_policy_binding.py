#!/usr/bin/env python3

from __future__ import annotations

import copy
from pathlib import Path
from typing import Any

from artifact_sbom import load_json
from signing_policy import SigningPolicyError
from signing_policy_binding import validate_policy_binding
from validate_signing_policy import MANIFEST as POLICY_MANIFEST, base_policy, digest, member


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "Tests" / "System" / "SigningPolicy" / "binding-manifest.json"


def contexts(policy: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any], dict[str, Any]]:
    release = {
        "release": copy.deepcopy(policy["release"]),
        "source": copy.deepcopy(policy["source"]),
        "executables": [
            {
                **copy.deepcopy(executable),
                "signed": True,
                "verificationBundle": {"path": f"verification/{executable['id']}.json", "sha256": digest(executable["id"]), "bytes": 100},
            }
            for executable in policy["declaredExecutables"]
        ],
    }
    graph_artifacts = []
    for artifact_policy in policy["artifacts"]:
        objects = []
        bundles_by_path: dict[str, dict[str, str]] = {}
        for object_policy in artifact_policy["objects"]:
            bundle_main = object_policy["bundleMainFor"]
            if bundle_main is not None:
                bundles_by_path[bundle_main] = {
                    "path": bundle_main,
                    "bundleIdentifier": object_policy["architectures"][0]["identity"]["signingIdentifier"],
                }
            objects.append({
                "path": object_policy["path"],
                "ownerBundlePath": object_policy["ownerBundlePath"],
                "bundleMainFor": object_policy["bundleMainFor"],
                "inDistributionSubject": True,
                "member": copy.deepcopy(object_policy["member"]),
                "machO": {
                    "format": "thin" if len(object_policy["architectures"]) == 1 else "fat64",
                    "architectures": [
                        {
                            "cpuType": architecture["cpuType"],
                            "cpuSubtype": architecture["cpuSubtype"],
                            "sliceSHA256": architecture["sliceSHA256"],
                        }
                        for architecture in object_policy["architectures"]
                    ],
                },
                "declaredExecutableIDs": copy.deepcopy(object_policy["declaredExecutableIDs"]),
            })
        graph_artifacts.append({
            "artifact": copy.deepcopy(artifact_policy["artifact"]),
            "subjectRoot": artifact_policy["subjectRoot"],
            "platformAcceptanceEligible": False,
            "bundles": sorted(bundles_by_path.values(), key=lambda item: item["path"]),
            "machOObjects": objects,
        })
    graph = {
        "release": {
            "version": release["release"]["version"],
            "buildNumber": release["release"]["buildNumber"],
            "targets": copy.deepcopy(release["release"]["targets"]),
        },
        "source": copy.deepcopy(release["source"]),
        "artifactSBOM": copy.deepcopy(policy["artifactSBOM"]),
        "artifacts": graph_artifacts,
    }
    return release, graph, copy.deepcopy(policy["artifactSBOM"]), copy.deepcopy(policy["signedCodeGraph"])


def mutate(
    policy: dict[str, Any],
    release: dict[str, Any],
    graph: dict[str, Any],
    sbom_reference: dict[str, Any],
    graph_reference: dict[str, Any],
    mutation: str,
) -> None:
    if mutation == "outsideSubject":
        graph["artifacts"][0]["machOObjects"].append({
            "path": "dSYMs/Mac Companion.app.dSYM/Contents/Resources/DWARF/Mac Companion",
            "ownerBundlePath": None,
            "bundleMainFor": None,
            "inDistributionSubject": False,
            "member": member("dSYMs/Mac Companion.app.dSYM/Contents/Resources/DWARF/Mac Companion", "dsym"),
            "machO": {"format": "thin", "architectures": [{"cpuType": 0x0100000C, "cpuSubtype": 0, "sliceSHA256": digest("dsym slice")}]},
            "declaredExecutableIDs": [],
        })
    elif mutation == "releaseVersion":
        release["release"]["version"] = "1.0.1"
    elif mutation == "releaseChannel":
        release["release"]["channel"] = "stable"
    elif mutation == "source":
        release["source"]["revision"] = "f" * 40
    elif mutation == "sbomReference":
        sbom_reference["sha256"] = digest("different sbom")
    elif mutation == "graphReference":
        graph_reference["sha256"] = digest("different graph")
    elif mutation == "graphRelease":
        graph["release"]["buildNumber"] = "101"
    elif mutation == "declaredBundleIdentifier":
        release["executables"][0]["bundleIdentifier"] = "com.example.different"
    elif mutation == "missingDeclaredExecutable":
        release["executables"].pop()
    elif mutation == "artifactOmission":
        graph["artifacts"].pop()
    elif mutation == "artifactAddition":
        duplicate = copy.deepcopy(graph["artifacts"][0])
        duplicate["artifact"]["id"] = "invented-artifact"
        graph["artifacts"].append(duplicate)
    elif mutation == "artifactDigest":
        graph["artifacts"][0]["artifact"]["sha256"] = digest("different artifact")
    elif mutation == "subjectRoot":
        graph["artifacts"][0]["subjectRoot"] = "Different.app"
    elif mutation == "objectOmission":
        graph["artifacts"][0]["machOObjects"].pop()
    elif mutation == "objectAddition":
        duplicate = copy.deepcopy(graph["artifacts"][0]["machOObjects"][0])
        duplicate["path"] += ".copy"
        duplicate["member"]["path"] = duplicate["path"]
        graph["artifacts"][0]["machOObjects"].append(duplicate)
        graph["artifacts"][0]["machOObjects"].sort(key=lambda item: item["path"])
    elif mutation == "memberMode":
        graph["artifacts"][0]["machOObjects"][0]["member"]["mode"] = "0644"
    elif mutation == "memberDigest":
        graph["artifacts"][0]["machOObjects"][0]["member"]["sha256"] = digest("different member")
    elif mutation == "ownerBundle":
        graph["artifacts"][0]["machOObjects"][0]["ownerBundlePath"] = None
    elif mutation == "bundleMain":
        graph["artifacts"][0]["machOObjects"][0]["bundleMainFor"] = None
    elif mutation == "declaredMapping":
        declared = next(
            item
            for artifact in graph["artifacts"]
            for item in artifact["machOObjects"]
            if item["declaredExecutableIDs"]
        )
        declared["declaredExecutableIDs"] = []
    elif mutation == "declaredSigningIdentifier":
        declared = next(
            item
            for artifact in policy["artifacts"]
            for item in artifact["objects"]
            if item["declaredExecutableIDs"]
        )
        for architecture in declared["architectures"]:
            architecture["identity"]["signingIdentifier"] = "com.example.different"
    elif mutation == "bundleMainSigningIdentifier":
        bundle_main = next(
            item
            for artifact in policy["artifacts"]
            for item in artifact["objects"]
            if item["bundleMainFor"] is not None and not item["declaredExecutableIDs"]
        )
        for architecture in bundle_main["architectures"]:
            architecture["identity"]["signingIdentifier"] = "com.example.different-framework"
    elif mutation == "architectureOmission":
        graph["artifacts"][0]["machOObjects"][0]["machO"]["architectures"].pop()
    elif mutation == "architectureAddition":
        graph["artifacts"][0]["machOObjects"][0]["machO"]["architectures"].append({"cpuType": 7, "cpuSubtype": 3, "sliceSHA256": digest("invented slice")})
    elif mutation == "architectureSubtype":
        graph["artifacts"][0]["machOObjects"][0]["machO"]["architectures"][0]["cpuSubtype"] += 1
    elif mutation == "sliceDigest":
        graph["artifacts"][0]["machOObjects"][0]["machO"]["architectures"][0]["sliceSHA256"] = digest("different slice")
    elif mutation == "platformEligible":
        graph["artifacts"][0]["platformAcceptanceEligible"] = True
    else:
        raise ValueError(f"unknown signing-policy binding mutation: {mutation}")


def main() -> None:
    if not POLICY_MANIFEST.is_file():
        raise SigningPolicyError("signing-policy structural fixture corpus is absent")
    manifest = load_json(MANIFEST)
    if not isinstance(manifest, dict) or set(manifest) != {"profile", "cases"} or manifest["profile"] != "maccompanion.signing-policy-binding-fixtures.v0.1" or not isinstance(manifest["cases"], list):
        raise SigningPolicyError("invalid signing-policy binding fixture manifest")
    seen: set[str] = set()
    for case in manifest["cases"]:
        if not isinstance(case, dict) or set(case) != {"id", "variant", "mutation", "accepted"}:
            raise SigningPolicyError("invalid signing-policy binding fixture case")
        case_id = case["id"]
        if not isinstance(case_id, str) or not case_id or case_id in seen or not isinstance(case["accepted"], bool):
            raise SigningPolicyError("invalid or duplicate signing-policy binding fixture ID")
        seen.add(case_id)
        policy = base_policy(case["variant"])
        release, graph, sbom_reference, graph_reference = contexts(policy)
        if case["mutation"] is not None:
            mutate(policy, release, graph, sbom_reference, graph_reference, case["mutation"])
        accepted = True
        try:
            validate_policy_binding(
                policy,
                release_manifest=release,
                signed_code_graph=graph,
                artifact_sbom_reference=sbom_reference,
                signed_code_graph_reference=graph_reference,
            )
        except SigningPolicyError:
            accepted = False
        if accepted != case["accepted"]:
            raise SigningPolicyError(f"binding fixture {case_id} expected accepted={case['accepted']}, got {accepted}")
    print(f"validated {len(seen)} signing-policy binding fixture(s)")


if __name__ == "__main__":
    main()
