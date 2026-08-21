#!/usr/bin/env python3

from __future__ import annotations

import copy
import hashlib
import json
import os
import tempfile
from pathlib import Path
from typing import Any

from artifact_sbom import canonical_bytes, load_json
from signing_policy import (
    MAX_ENTITLEMENT_CHILDREN,
    MAX_ENTITLEMENT_KEY_BYTES,
    MAX_ENTITLEMENT_KEYS,
    MAX_ENTITLEMENT_NODES,
    MAX_ENTITLEMENT_STRING_BYTES,
    MAX_ENTITLEMENT_TOP_LEVEL_KEYS,
    MAX_ENTITLEMENT_TOTAL_STRING_BYTES,
    MAX_POLICY_BYTES,
    SAFE_INTEGER,
    SigningPolicyError,
    load_pinned_policy,
)


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "Tests" / "System" / "SigningPolicy" / "manifest.json"
OFFICIAL_TEAM = "ABCDE12345"
MAC_CERTIFICATE = hashlib.sha256(b"synthetic Developer ID Application certificate").hexdigest()
IOS_CERTIFICATE = hashlib.sha256(b"synthetic Apple Distribution certificate").hexdigest()
THIRD_PARTY_TEAM = "ZYXWV98765"
THIRD_PARTY_CERTIFICATE = hashlib.sha256(b"synthetic third-party certificate").hexdigest()


def digest(label: str) -> str:
    return hashlib.sha256(label.encode("utf-8")).hexdigest()


def sha1(label: str) -> str:
    return hashlib.sha1(label.encode("utf-8")).hexdigest()


def reference(path: str, label: str) -> dict[str, Any]:
    return {"path": path, "sha256": digest(label), "bytes": 100 + len(label)}


def member(path: str, label: str) -> dict[str, Any]:
    return {
        "path": path,
        "type": "regularFile",
        "mode": "0755",
        "bytes": 4096 + len(label),
        "sha1": sha1(label),
        "sha256": digest(label),
        "symlinkTarget": None,
    }


def identity(identifier: str, profile: str, *, third_party: bool = False) -> dict[str, Any]:
    team = THIRD_PARTY_TEAM if third_party else OFFICIAL_TEAM
    certificate = (
        THIRD_PARTY_CERTIFICATE
        if third_party
        else MAC_CERTIFICATE if profile == "macOSDeveloperID" else IOS_CERTIFICATE
    )
    code_directory_sha256 = digest(f"{identifier} CodeDirectory")
    return {
        "signingIdentifier": identifier,
        "teamIdentifier": team,
        "codeDirectories": [{
            "hashType": "sha256",
            "cdhash": code_directory_sha256[:40],
            "codeDirectorySHA256": code_directory_sha256,
        }],
        "leafCertificateSHA256": certificate,
        "designatedRequirementDataSHA256": digest(f"{identifier} requirement data"),
    }


def architecture(
    identifier: str,
    name: str,
    cpu_type: int,
    cpu_subtype: int,
    profile: str,
    *,
    third_party: bool = False,
    entitlements: dict[str, Any] | None = None,
) -> dict[str, Any]:
    mac = profile == "macOSDeveloperID"
    return {
        "cpuType": cpu_type,
        "cpuSubtype": cpu_subtype,
        "sliceSHA256": digest(f"{identifier} {name} slice"),
        "identity": identity(identifier, profile, third_party=third_party),
        "signature": {
            "trustProfile": "developerIDApplication" if mac else "iosArchiveConstructionOnly",
            "requireHardenedRuntime": mac,
            "requireSecureTimestamp": mac,
        },
        "entitlements": entitlements or {"mode": "absent"},
    }


def mac_artifact() -> dict[str, Any]:
    outer_path = "Mac Companion.app/Contents/MacOS/Mac Companion"
    framework_path = "Mac Companion.app/Contents/Frameworks/Fixture.framework/Versions/A/Fixture"
    outer = {
        "path": outer_path,
        "member": member(outer_path, "mac outer"),
        "ownerBundlePath": "Mac Companion.app",
        "bundleMainFor": "Mac Companion.app",
        "declaredExecutableIDs": ["mac-app"],
        "signerClass": "firstParty",
        "architectures": [
            architecture("com.example.maccompanion", "x86_64", 0x01000007, 3, "macOSDeveloperID", entitlements={"mode": "exact", "entries": []}),
            architecture("com.example.maccompanion", "arm64", 0x0100000C, 0, "macOSDeveloperID", entitlements={"mode": "exact", "entries": []}),
        ],
    }
    framework = {
        "path": framework_path,
        "member": member(framework_path, "mac framework"),
        "ownerBundlePath": "Mac Companion.app/Contents/Frameworks/Fixture.framework",
        "bundleMainFor": "Mac Companion.app/Contents/Frameworks/Fixture.framework",
        "declaredExecutableIDs": [],
        "signerClass": "thirdParty",
        "architectures": [
            architecture("org.example.Fixture", "arm64", 0x0100000C, 0, "macOSDeveloperID", third_party=True),
        ],
    }
    objects = sorted([outer, framework], key=lambda item: item["path"])
    artifact = {
        "id": "mac-application",
        "kind": "macApplication",
        "platform": "macOS",
        "path": "artifacts/mac-application.zip",
        "sha256": digest("mac archive"),
        "bytes": 12000,
    }
    return {
        "artifact": artifact,
        "subjectRoot": "Mac Companion.app",
        "verificationProfile": "macOSDeveloperID",
        "thirdPartyAllowlist": [{"path": framework_path, "memberSHA256": framework["member"]["sha256"]}],
        "objects": objects,
    }


def ios_artifact() -> dict[str, Any]:
    outer_path = "Products/Applications/Mac Companion.app/Mac Companion"
    entitlements = {
        "mode": "exact",
        "entries": [
            {"key": "application-identifier", "value": {"type": "string", "value": f"{OFFICIAL_TEAM}.com.example.maccompanion.ios"}},
            {"key": "com.apple.developer.team-identifier", "value": {"type": "string", "value": OFFICIAL_TEAM}},
            {"key": "get-task-allow", "value": {"type": "boolean", "value": False}},
        ],
    }
    outer = {
        "path": outer_path,
        "member": member(outer_path, "ios outer"),
        "ownerBundlePath": "Products/Applications/Mac Companion.app",
        "bundleMainFor": "Products/Applications/Mac Companion.app",
        "declaredExecutableIDs": ["ios-app"],
        "signerClass": "firstParty",
        "architectures": [
            architecture("com.example.maccompanion.ios", "arm64", 0x0100000C, 0, "iosArchiveConstructionOnly", entitlements=entitlements),
        ],
    }
    artifact = {
        "id": "ios-archive",
        "kind": "iosArchive",
        "platform": "iOS",
        "path": "artifacts/ios-archive.zip",
        "sha256": digest("ios archive"),
        "bytes": 10000,
    }
    return {
        "artifact": artifact,
        "subjectRoot": "Products/Applications/Mac Companion.app",
        "verificationProfile": "iosArchiveConstructionOnly",
        "thirdPartyAllowlist": [],
        "objects": [outer],
    }


def base_policy(variant: str) -> dict[str, Any]:
    if variant not in {"mac", "ios", "combined"}:
        raise ValueError("unknown signing-policy fixture variant")
    targets = ["macOS"] if variant == "mac" else ["iOS"] if variant == "ios" else ["iOS", "macOS"]
    artifacts = []
    executables = []
    if variant in {"ios", "combined"}:
        artifacts.append(ios_artifact())
        executables.append({
            "id": "ios-app", "role": "iosApp", "platform": "iOS",
            "bundleIdentifier": "com.example.maccompanion.ios",
            "artifactID": "ios-archive",
            "relativePath": "Products/Applications/Mac Companion.app/Mac Companion",
        })
    if variant in {"mac", "combined"}:
        artifacts.append(mac_artifact())
        executables.append({
            "id": "mac-app", "role": "macApp", "platform": "macOS",
            "bundleIdentifier": "com.example.maccompanion",
            "artifactID": "mac-application",
            "relativePath": "Mac Companion.app/Contents/MacOS/Mac Companion",
        })
    return {
        "schemaVersion": "maccompanion.signing-policy.v0.1",
        "policyID": "synthetic-release-policy",
        "policyRevision": 1,
        "product": "Mac Companion",
        "release": {"version": "1.0.0-beta.1", "buildNumber": "100", "channel": "beta", "targets": targets},
        "source": {"revision": "0123456789abcdef0123456789abcdef01234567", "dirty": False},
        "artifactSBOM": reference("supply-chain/artifact-sbom-index.json", "artifact SBOM"),
        "signedCodeGraph": reference("verification/signed-code-graph.json", "signed code graph"),
        "officialSigners": [
            {
                "platform": platform,
                "trustProfile": "developerIDApplication" if platform == "macOS" else "iosArchiveConstructionOnly",
                "teamIdentifier": OFFICIAL_TEAM,
                "leafCertificateSHA256": MAC_CERTIFICATE if platform == "macOS" else IOS_CERTIFICATE,
            }
            for platform in targets
        ],
        "declaredExecutables": sorted(executables, key=lambda item: item["id"]),
        "artifacts": sorted(artifacts, key=lambda item: item["artifact"]["id"]),
    }


def _set_first_entitlements(
    policy: dict[str, Any], entries: list[dict[str, Any]]
) -> None:
    policy["artifacts"][0]["objects"][0]["architectures"][0]["entitlements"] = {
        "mode": "exact",
        "entries": entries,
    }


def _boolean_entry(key: str) -> dict[str, Any]:
    return {"key": key, "value": {"type": "boolean", "value": True}}


def _array_entry(key: str, children: int, *, string: str | None = None) -> dict[str, Any]:
    value = (
        {"type": "string", "value": string}
        if string is not None
        else {"type": "boolean", "value": True}
    )
    return {
        "key": key,
        "value": {"type": "array", "values": [copy.deepcopy(value) for _ in range(children)]},
    }


def mutate(policy: dict[str, Any], mutation: str) -> None:
    artifacts = policy["artifacts"]
    mac = next((item for item in artifacts if item["artifact"]["platform"] == "macOS"), None)
    ios = next((item for item in artifacts if item["artifact"]["platform"] == "iOS"), None)
    if mutation == "unknownRoot":
        policy["accepted"] = True
    elif mutation == "dirtySource":
        policy["source"]["dirty"] = True
    elif mutation == "targetOrder":
        policy["release"]["targets"].reverse()
    elif mutation == "artifactProfile":
        assert ios is not None
        ios["verificationProfile"] = "macOSDeveloperID"
    elif mutation == "artifactOrder":
        artifacts.reverse()
    elif mutation == "duplicateArtifact":
        duplicate = copy.deepcopy(artifacts[0])
        artifacts.append(duplicate)
    elif mutation == "objectOrder":
        assert mac is not None
        mac["objects"].reverse()
    elif mutation == "duplicateObject":
        assert mac is not None
        mac["objects"].append(copy.deepcopy(mac["objects"][0]))
        mac["objects"].sort(key=lambda item: item["path"])
    elif mutation == "memberPath":
        assert mac is not None
        mac["objects"][0]["member"]["path"] = "different/path"
    elif mutation == "memberType":
        assert mac is not None
        mac["objects"][0]["member"]["type"] = "symlink"
    elif mutation == "declaredExecutable":
        assert mac is not None
        mac["objects"][0]["declaredExecutableIDs"] = ["missing-executable"]
    elif mutation == "firstPartySigner":
        assert mac is not None
        first_party = next(item for item in mac["objects"] if item["signerClass"] == "firstParty")
        first_party["architectures"][0]["identity"]["teamIdentifier"] = THIRD_PARTY_TEAM
    elif mutation == "officialSignerOmission":
        policy["officialSigners"].pop()
    elif mutation == "officialSignerDuplicatePlatform":
        policy["officialSigners"][1] = copy.deepcopy(policy["officialSigners"][0])
    elif mutation == "officialSignerSharedLeaf":
        assert ios is not None
        ios_signer = next(
            item for item in policy["officialSigners"] if item["platform"] == "iOS"
        )
        ios_signer["leafCertificateSHA256"] = MAC_CERTIFICATE
        for object_value in ios["objects"]:
            if object_value["signerClass"] == "firstParty":
                for architecture_value in object_value["architectures"]:
                    architecture_value["identity"]["leafCertificateSHA256"] = MAC_CERTIFICATE
    elif mutation == "thirdPartyAllowlist":
        assert mac is not None
        mac["thirdPartyAllowlist"] = []
    elif mutation == "architectureOrder":
        assert mac is not None
        first_party = next(item for item in mac["objects"] if item["signerClass"] == "firstParty")
        first_party["architectures"].reverse()
    elif mutation == "duplicateArchitecture":
        assert mac is not None
        first_party = next(item for item in mac["objects"] if item["signerClass"] == "firstParty")
        first_party["architectures"].append(copy.deepcopy(first_party["architectures"][0]))
    elif mutation == "signatureProfile":
        assert mac is not None
        mac["objects"][0]["architectures"][0]["signature"]["requireSecureTimestamp"] = False
    elif mutation == "codeDirectoryMismatch":
        assert mac is not None
        mac["objects"][0]["architectures"][0]["identity"]["codeDirectories"][0]["cdhash"] = "f" * 40
    elif mutation == "entitlementShape":
        assert mac is not None
        mac["objects"][0]["architectures"][0]["entitlements"] = {"mode": "absent", "entries": []}
    elif mutation == "entitlementNull":
        assert mac is not None
        mac["objects"][0]["architectures"][0]["entitlements"] = {"mode": "exact", "entries": [{"key": "example", "value": None}]}
    elif mutation == "entitlementBoolInt":
        assert mac is not None
        mac["objects"][0]["architectures"][0]["entitlements"] = {"mode": "exact", "entries": [{"key": "example", "value": {"type": "integer", "value": True}}]}
    elif mutation == "entitlementKeyOrder":
        assert mac is not None
        mac["objects"][0]["architectures"][0]["entitlements"] = {"mode": "exact", "entries": [
            {"key": "z-key", "value": {"type": "boolean", "value": True}},
            {"key": "a-key", "value": {"type": "boolean", "value": True}},
        ]}
    elif mutation == "entitlementDepth":
        assert mac is not None
        node: dict[str, Any] = {"type": "boolean", "value": True}
        for _ in range(6):
            node = {"type": "array", "values": [node]}
        mac["objects"][0]["architectures"][0]["entitlements"] = {"mode": "exact", "entries": [{"key": "nested", "value": node}]}
    elif mutation == "entitlementStringBound":
        assert mac is not None
        mac["objects"][0]["architectures"][0]["entitlements"] = {"mode": "exact", "entries": [{"key": "value", "value": {"type": "string", "value": "x" * 1025}}]}
    elif mutation == "entitlementTopLevelBound":
        _set_first_entitlements(
            policy,
            [_boolean_entry(f"key-{index:03d}") for index in range(MAX_ENTITLEMENT_TOP_LEVEL_KEYS)],
        )
    elif mutation == "entitlementTopLevelExceeded":
        _set_first_entitlements(
            policy,
            [_boolean_entry(f"key-{index:03d}") for index in range(MAX_ENTITLEMENT_TOP_LEVEL_KEYS + 1)],
        )
    elif mutation in {"entitlementAggregateKeysBound", "entitlementAggregateKeysExceeded"}:
        outer_count = MAX_ENTITLEMENT_CHILDREN
        inner_count = MAX_ENTITLEMENT_KEYS // outer_count - 1
        _set_first_entitlements(policy, [
            {
                "key": f"outer-{outer:03d}",
                "value": {
                    "type": "dictionary",
                    "entries": [
                        _boolean_entry(f"inner-{inner:03d}")
                        for inner in range(
                            inner_count
                            + (
                                1
                                if mutation == "entitlementAggregateKeysExceeded"
                                and outer == 0
                                else 0
                            )
                        )
                    ],
                },
            }
            for outer in range(outer_count)
        ])
    elif mutation in {"entitlementAggregateNodesBound", "entitlementAggregateNodesExceeded"}:
        children = MAX_ENTITLEMENT_NODES // MAX_ENTITLEMENT_TOP_LEVEL_KEYS - 1
        entries = [
            _array_entry(f"node-{index:03d}", children)
            for index in range(MAX_ENTITLEMENT_TOP_LEVEL_KEYS)
        ]
        if mutation == "entitlementAggregateNodesExceeded":
            entries[0] = _array_entry("node-000", children + 1)
        _set_first_entitlements(policy, entries)
    elif mutation in {"entitlementTotalStringBound", "entitlementTotalStringExceeded"}:
        string_value = "x" * MAX_ENTITLEMENT_STRING_BYTES
        string_count = MAX_ENTITLEMENT_TOTAL_STRING_BYTES // MAX_ENTITLEMENT_STRING_BYTES
        entries = []
        remaining = string_count
        index = 0
        while remaining:
            count = min(remaining, MAX_ENTITLEMENT_CHILDREN)
            entries.append(_array_entry(f"string-{index:03d}", count, string=string_value))
            remaining -= count
            index += 1
        if mutation == "entitlementTotalStringExceeded":
            entries.append(_array_entry(f"string-{index:03d}", 1, string="x"))
        _set_first_entitlements(policy, entries)
    elif mutation == "entitlementChildBound":
        _set_first_entitlements(
            policy, [_array_entry("children", MAX_ENTITLEMENT_CHILDREN)]
        )
    elif mutation == "entitlementChildExceeded":
        _set_first_entitlements(
            policy, [_array_entry("children", MAX_ENTITLEMENT_CHILDREN + 1)]
        )
    elif mutation == "entitlementKeyBytesBound":
        _set_first_entitlements(policy, [_boolean_entry("k" * MAX_ENTITLEMENT_KEY_BYTES)])
    elif mutation == "entitlementKeyBytesExceeded":
        _set_first_entitlements(policy, [_boolean_entry("k" * (MAX_ENTITLEMENT_KEY_BYTES + 1))])
    elif mutation == "entitlementStringBytesBound":
        _set_first_entitlements(policy, [{
            "key": "value",
            "value": {"type": "string", "value": "x" * MAX_ENTITLEMENT_STRING_BYTES},
        }])
    elif mutation == "entitlementSafeIntegerBound":
        _set_first_entitlements(policy, [{
            "key": "value", "value": {"type": "integer", "value": SAFE_INTEGER},
        }])
    elif mutation == "entitlementSafeIntegerExceeded":
        _set_first_entitlements(policy, [{
            "key": "value", "value": {"type": "integer", "value": SAFE_INTEGER + 1},
        }])
    elif mutation == "entitlementNonNFC":
        _set_first_entitlements(policy, [{
            "key": "value", "value": {"type": "string", "value": "e\u0301"},
        }])
    elif mutation == "entitlementControlText":
        _set_first_entitlements(policy, [{
            "key": "value", "value": {"type": "string", "value": "line\nbreak"},
        }])
    elif mutation == "entitlementUnknownType":
        _set_first_entitlements(policy, [{
            "key": "value", "value": {"type": "data", "value": "AAAA"},
        }])
    elif mutation == "entitlementNestedKeyOrder":
        _set_first_entitlements(policy, [{
            "key": "nested",
            "value": {
                "type": "dictionary",
                "entries": [_boolean_entry("z-key"), _boolean_entry("a-key")],
            },
        }])
    elif mutation == "iosAcceptanceProfile":
        assert ios is not None
        ios["verificationProfile"] = "iosAppStore"
    elif mutation == "iosExportedSubject":
        assert ios is not None
        ios["subjectRoot"] = "Payload/Mac Companion.app"
    elif mutation == "developmentChannel":
        policy["release"]["channel"] = "development"
    elif mutation == "otherRole":
        policy["declaredExecutables"][0]["role"] = "other"
    elif mutation == "rolePlatform":
        policy["declaredExecutables"][0]["role"] = (
            "iosApp" if policy["declaredExecutables"][0]["platform"] == "macOS" else "macApp"
        )
    elif mutation == "unknownRole":
        policy["declaredExecutables"][0]["role"] = "iosExtension"
    else:
        raise ValueError(f"unknown signing-policy mutation: {mutation}")


def main() -> None:
    manifest = load_json(MANIFEST)
    if not isinstance(manifest, dict) or set(manifest) != {"profile", "cases"} or manifest["profile"] != "maccompanion.signing-policy-fixtures.v0.1" or not isinstance(manifest["cases"], list):
        raise SigningPolicyError("invalid signing-policy fixture manifest")
    seen: set[str] = set()
    special = {"independentPin", "placeholderPin", "uppercasePin", "noncanonical", "duplicateKey", "invalidUTF8", "invalidSurrogate", "symlink", "hardlink", "oversized"}
    for case in manifest["cases"]:
        if not isinstance(case, dict) or set(case) != {"id", "variant", "mutation", "accepted"}:
            raise SigningPolicyError("invalid signing-policy fixture case")
        case_id = case["id"]
        if not isinstance(case_id, str) or not case_id or case_id in seen or not isinstance(case["accepted"], bool):
            raise SigningPolicyError("invalid or duplicate signing-policy fixture ID")
        seen.add(case_id)
        policy = base_policy(case["variant"])
        mutation = case["mutation"]
        if mutation is not None and mutation not in special:
            mutate(policy, mutation)
        raw = canonical_bytes(policy)
        expected = hashlib.sha256(raw).hexdigest()
        if mutation == "independentPin":
            expected = hashlib.sha256(b"different trusted policy").hexdigest()
        elif mutation == "placeholderPin":
            expected = "0" * 64
        elif mutation == "uppercasePin":
            expected = expected.upper()
        elif mutation == "noncanonical":
            raw = json.dumps(policy, ensure_ascii=False, indent=2).encode("utf-8") + b"\n"
            expected = hashlib.sha256(raw).hexdigest()
        elif mutation == "duplicateKey":
            raw = raw.replace(b'{"artifactSBOM":', b'{"product":"Mac Companion","artifactSBOM":', 1)
            expected = hashlib.sha256(raw).hexdigest()
        elif mutation == "invalidUTF8":
            raw = b"\xff" + raw
            expected = hashlib.sha256(raw).hexdigest()
        elif mutation == "invalidSurrogate":
            raw = raw.replace(b'"product":"Mac Companion"', b'"product":"\\ud800"', 1)
            expected = hashlib.sha256(raw).hexdigest()
        elif mutation == "oversized":
            raw = b" " * (MAX_POLICY_BYTES + 1)
            expected = hashlib.sha256(raw).hexdigest()
        with tempfile.TemporaryDirectory(prefix="maccompanion-signing-policy-") as temporary:
            root = Path(temporary)
            path = root / "policy.json"
            path.write_bytes(raw)
            if mutation == "symlink":
                target = root / "target.json"
                path.rename(target)
                os.symlink(target.name, path)
            elif mutation == "hardlink":
                os.link(path, root / "second-link.json")
            accepted = True
            try:
                load_pinned_policy(path, expected)
            except SigningPolicyError:
                accepted = False
        if accepted != case["accepted"]:
            raise SigningPolicyError(f"fixture {case_id} expected accepted={case['accepted']}, got {accepted}")
    print(f"validated {len(seen)} signing-policy fixture(s)")


if __name__ == "__main__":
    main()
