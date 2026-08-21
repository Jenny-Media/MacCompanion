#!/usr/bin/env python3

from __future__ import annotations

import copy
import hashlib
import json
import tempfile
from pathlib import Path
from typing import Any

from artifact_sbom import canonical_bytes, load_json
from signed_code_verification import (
    MAX_BUNDLE_BYTES,
    SignedCodeVerificationError,
    load_bundle,
    validate_bundle,
)


REPOSITORY = Path(__file__).resolve().parents[1]
FIXTURE_ROOT = REPOSITORY / "Tests" / "System" / "SignedCodeVerification"


def _context(root: Path, *, ios: bool = False) -> dict[str, Any]:
    platform = "iOS" if ios else "macOS"
    role = "iosApp" if ios else "macApp"
    artifact_id = "ios-archive" if ios else "mac-application"
    relative_path = (
        "Payload/Mac Companion.app/Mac Companion"
        if ios
        else "Mac Companion.app/Contents/MacOS/Mac Companion"
    )
    release = {
        "release": {"version": "1.0.0-beta.1", "buildNumber": "100", "targets": [platform]},
        "source": {
            "revision": "0123456789abcdef0123456789abcdef01234567",
            "dirty": False,
        },
    }
    artifact = {
        "id": artifact_id,
        "kind": "iosArchive" if ios else "macApplication",
        "platform": platform,
        "path": f"artifacts/{artifact_id}.zip",
        "sha256": "4" * 64,
        "bytes": 4096,
    }
    executable = {
        "id": "ios-app" if ios else "mac-menu-app",
        "role": role,
        "platform": platform,
        "bundleIdentifier": "com.example.maccompanion.ios" if ios else "com.example.maccompanion",
        "artifactID": artifact_id,
        "relativePath": relative_path,
        "signed": True,
        "verificationBundle": {
            "path": "verification/signed-code-verification.json",
            "sha256": "0" * 64,
            "bytes": 1,
        },
    }
    member = {
        "path": executable["relativePath"],
        "type": "regularFile",
        "mode": "0755",
        "bytes": 18,
        "sha1": "ba90b9a4cf270c12eefb97334395519af277bdd4",
        "sha256": "6f1af2dfc4d7f16dacf404b1f6c9fd4a65cfffb8edde6dcf957463a0e41fb1ed",
        "symlinkTarget": None,
    }
    evidence: dict[str, dict[str, Any]] = {}
    for label in (
        "designatedRequirement",
        "entitlements",
        "codesignVerification",
        "platformAssessment",
    ):
        content = f"{label} fixture evidence\n".encode("utf-8")
        relative_path = f"verification/{label}.txt"
        path = root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        evidence[label] = {
            "path": relative_path,
            "sha256": hashlib.sha256(content).hexdigest(),
            "bytes": len(content),
        }
    bundle = {
        "schemaVersion": "maccompanion.signed-code-verification.v0.1",
        "evidenceLevel": "constructionCorrelation",
        "product": "Mac Companion",
        "release": copy.deepcopy(release["release"]),
        "source": copy.deepcopy(release["source"]),
        "created": "2026-08-21T12:10:00Z",
        "artifactSBOM": {
            "path": "supply-chain/artifact-sbom-index.json",
            "sha256": "5" * 64,
            "bytes": 1024,
        },
        "artifact": copy.deepcopy(artifact),
        "executable": {
            key: executable[key]
            for key in ("id", "role", "platform", "bundleIdentifier", "artifactID", "relativePath")
        },
        "artifactMember": {
            key: member[key]
            for key in ("path", "type", "mode", "bytes", "sha1", "sha256", "symlinkTarget")
        },
        "codeIdentity": {
            "signingIdentifier": executable["bundleIdentifier"],
            "teamIdentifier": "ABCDE12345",
            "cdhash": "1" * 40,
            "certificateSHA256": "2" * 64,
        },
        "reportedChecks": {
            "codesignVerify": True,
            "platformAssessment": "iosProvisioningReported" if ios else "gatekeeperAccepted",
        },
        "evidence": evidence,
    }
    return {
        "release": release,
        "artifact": artifact,
        "executable": executable,
        "member": member,
        "bundle": bundle,
    }


def _mutate(context: dict[str, Any], mutation: str, root: Path) -> bytes:
    bundle = context["bundle"]
    if mutation == "executablePath":
        bundle["executable"]["relativePath"] = "Mac Companion.app/Contents/MacOS/Other"
    elif mutation == "memberDigest":
        bundle["artifactMember"]["sha256"] = "3" * 64
    elif mutation == "memberMode":
        bundle["artifactMember"]["mode"] = "0644"
    elif mutation == "signingIdentifier":
        bundle["codeIdentity"]["signingIdentifier"] = "com.example.other"
    elif mutation == "teamIdentifier":
        bundle["codeIdentity"]["teamIdentifier"] = "short"
    elif mutation == "cdhash":
        bundle["codeIdentity"]["cdhash"] = "not-a-hash"
    elif mutation == "codesignCheck":
        bundle["reportedChecks"]["codesignVerify"] = False
    elif mutation == "platformAssessment":
        bundle["reportedChecks"]["platformAssessment"] = "iosProvisioningReported"
    elif mutation == "duplicateEvidencePath":
        bundle["evidence"]["entitlements"] = copy.deepcopy(bundle["evidence"]["designatedRequirement"])
    elif mutation == "rawEvidenceDigest":
        path = root / bundle["evidence"]["entitlements"]["path"]
        path.write_bytes(path.read_bytes() + b"mutation")
    elif mutation == "rawEvidenceSymlink":
        path = root / bundle["evidence"]["entitlements"]["path"]
        saved = path.with_name(path.name + ".saved")
        path.rename(saved)
        path.symlink_to(saved.name)
    elif mutation == "unknownField":
        bundle["unexpected"] = True
    elif mutation in {"none", "validIOS", "nonCanonical", "duplicateKey", "oversized"}:
        pass
    else:
        raise ValueError(f"unknown signed-code mutation: {mutation}")
    raw = canonical_bytes(bundle)
    if mutation == "nonCanonical":
        raw = (json.dumps(bundle, indent=2, sort_keys=True) + "\n").encode("utf-8")
    elif mutation == "duplicateKey":
        raw = b'{"schemaVersion":"duplicate",' + raw[1:]
    elif mutation == "oversized":
        raw = b" " * (MAX_BUNDLE_BYTES + 1)
    return raw


def main() -> int:
    manifest = load_json(FIXTURE_ROOT / "manifest.json")
    if (
        not isinstance(manifest, dict)
        or set(manifest) != {"profile", "cases"}
        or manifest["profile"] != "maccompanion.signed-code-verification-fixtures.v0.1"
        or not isinstance(manifest["cases"], list)
    ):
        raise SignedCodeVerificationError("invalid signed-code fixture manifest")
    failures: list[str] = []
    seen: set[str] = set()
    for case in manifest["cases"]:
        identifier = case.get("id")
        if not isinstance(identifier, str) or identifier in seen:
            failures.append("duplicate or invalid fixture ID")
            continue
        seen.add(identifier)
        error_text: str | None = None
        try:
            with tempfile.TemporaryDirectory(prefix="maccompanion-signed-code-") as temporary:
                root = Path(temporary)
                context = _context(root, ios=case.get("mutation") == "validIOS")
                raw = _mutate(context, case.get("mutation"), root)
                path = root / "verification" / "signed-code-verification.json"
                path.write_bytes(raw)
                bundle, _ = load_bundle(path)
                validate_bundle(
                    bundle,
                    release_executable=context["executable"],
                    release_manifest=context["release"],
                    artifact_sbom_reference=context["bundle"]["artifactSBOM"],
                    artifact_binding=context["artifact"],
                    artifact_member=context["member"],
                    evidence_root=root,
                )
            valid = True
        except (SignedCodeVerificationError, OSError, ValueError, KeyError, TypeError) as error:
            valid = False
            error_text = str(error)
        expected = case.get("expect")
        if (expected == "valid") != valid:
            failures.append(
                f"{identifier}: expected {expected}, got {'valid' if valid else 'invalid'}: {error_text}"
            )
        expected_error = case.get("errorContains")
        if expected_error is not None and (
            valid or not isinstance(expected_error, str) or expected_error not in (error_text or "")
        ):
            failures.append(f"{identifier}: expected error containing {expected_error!r}, got {error_text!r}")
    if failures:
        for failure in failures:
            print(failure)
        return 1
    print(f"validated {len(seen)} signed-code verification fixture(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
