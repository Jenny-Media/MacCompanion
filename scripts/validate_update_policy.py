#!/usr/bin/env python3

from __future__ import annotations

import copy
import json
import os
import tempfile
from pathlib import Path
from typing import Any

from update_policy import (
    MAX_POLICY_BYTES,
    SPARKLE_ARCHIVE_SHA256,
    SPARKLE_EXCLUDED_XPC_SERVICES,
    SPARKLE_LICENSE_SHA256,
    SPARKLE_MANIFEST_SHA256,
    SPARKLE_REPOSITORY,
    SPARKLE_REVISION,
    SPARKLE_RUNTIME_EXECUTABLES,
    SPARKLE_VERSION,
    UpdatePolicyError,
    canonical_bytes,
    load_policy,
    validate_policy,
    write_new_policy,
)


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "Tests" / "System" / "UpdatePolicy" / "manifest.json"


def base_policy() -> dict[str, Any]:
    return {
        "channels": [
            {
                "automaticChecks": True,
                "automaticDownloads": False,
                "automaticInstalls": False,
                "feedAuthorityRef": "official-beta-feed",
                "name": "beta",
            },
            {
                "automaticChecks": True,
                "automaticDownloads": False,
                "automaticInstalls": False,
                "feedAuthorityRef": "official-stable-feed",
                "name": "stable",
            },
        ],
        "dependency": {
            "archiveSHA256": SPARKLE_ARCHIVE_SHA256,
            "binaryTarget": "Sparkle",
            "licenseSHA256": SPARKLE_LICENSE_SHA256,
            "manifestSHA256": SPARKLE_MANIFEST_SHA256,
            "packageRequirement": "exactVersion",
            "repository": SPARKLE_REPOSITORY,
            "revision": SPARKLE_REVISION,
            "version": SPARKLE_VERSION,
        },
        "privacy": {
            "customFeedParameters": False,
            "sendsSystemProfile": False,
            "systemProfilingInfoPlist": False,
            "upstreamPrivacyManifestPresent": False,
        },
        "product": "Mac Companion",
        "rotation": {
            "allowDeveloperIDAndEd25519Together": False,
            "externalKeyCustody": True,
            "feedFallback": False,
            "updaterDowngrade": False,
        },
        "runtime": {
            "cancelOnForegroundLoss": True,
            "closeNetworkAdmissionBeforeInstall": True,
            "confirmationLifetimeMilliseconds": 300_000,
            "drainBoundedWorkBeforeInstall": True,
            "exactAgentVersionMatch": True,
            "refuseUnlessControlInactive": True,
            "requireForegroundConfirmation": True,
            "stopAgentBeforeInstall": True,
        },
        "schemaVersion": "maccompanion.update-policy.v0.2",
        "security": {
            "archiveSignature": "ed25519",
            "deltaUpdates": False,
            "developerIDValidation": True,
            "httpsOnly": True,
            "installerPackages": False,
            "notarizedReplacement": True,
            "signedFeed": True,
            "verifyBeforeExtraction": True,
            "wholeBundleReplacement": True,
        },
        "topology": {
            "applicationSandboxed": False,
            "embeddedRuntimeExecutables": SPARKLE_RUNTIME_EXECUTABLES,
            "excludedXPCServices": SPARKLE_EXCLUDED_XPC_SERVICES,
            "releaseToolsEmbedded": False,
            "resignNestedCodeDuringArchiveExport": True,
        },
    }


def mutate(value: dict[str, Any], mutation: str) -> None:
    if mutation == "floatingDependency":
        value["dependency"].pop("revision")
        value["dependency"]["requirement"] = "from: 2.9.6"
    elif mutation == "oldSparkle":
        value["dependency"]["version"] = "2.9.5"
    elif mutation == "archiveDigest":
        value["dependency"]["archiveSHA256"] = "0" * 64
    elif mutation == "manifestDigest":
        value["dependency"]["manifestSHA256"] = "0" * 64
    elif mutation == "licenseDigest":
        value["dependency"]["licenseSHA256"] = "0" * 64
    elif mutation == "versionRange":
        value["dependency"]["packageRequirement"] = "upToNextMajor"
    elif mutation == "sharedFeed":
        value["channels"][1]["feedAuthorityRef"] = value["channels"][0]["feedAuthorityRef"]
    elif mutation == "feedURL":
        value["channels"][0]["feedURL"] = "https://updates.example.invalid/beta.xml"
    elif mutation == "automaticDownload":
        value["channels"][0]["automaticDownloads"] = True
    elif mutation == "automaticInstall":
        value["channels"][0]["automaticInstalls"] = True
    elif mutation == "systemProfile":
        value["privacy"]["sendsSystemProfile"] = True
    elif mutation == "systemProfilingInfoPlist":
        value["privacy"]["systemProfilingInfoPlist"] = True
    elif mutation == "customFeedParameters":
        value["privacy"]["customFeedParameters"] = True
    elif mutation == "upstreamPrivacyManifest":
        value["privacy"]["upstreamPrivacyManifestPresent"] = True
    elif mutation == "unsignedFeed":
        value["security"]["signedFeed"] = False
    elif mutation == "extractBeforeVerify":
        value["security"]["verifyBeforeExtraction"] = False
    elif mutation == "deltaUpdate":
        value["security"]["deltaUpdates"] = True
    elif mutation == "controlInstall":
        value["runtime"]["refuseUnlessControlInactive"] = False
    elif mutation == "agentRunning":
        value["runtime"]["stopAgentBeforeInstall"] = False
    elif mutation == "sandboxedTopology":
        value["topology"]["applicationSandboxed"] = True
    elif mutation == "embeddedXPC":
        value["topology"]["excludedXPCServices"] = ["Installer.xpc"]
    elif mutation == "releaseTools":
        value["topology"]["releaseToolsEmbedded"] = True
    elif mutation == "missingRuntimeExecutable":
        value["topology"]["embeddedRuntimeExecutables"].pop()
    elif mutation == "extraRuntimeExecutable":
        value["topology"]["embeddedRuntimeExecutables"].append("bin/sign_update")
    elif mutation == "noNestedResigning":
        value["topology"]["resignNestedCodeDuringArchiveExport"] = False
    elif mutation == "longConfirmation":
        value["runtime"]["confirmationLifetimeMilliseconds"] = 3_600_000
    elif mutation == "simultaneousRotation":
        value["rotation"]["allowDeveloperIDAndEd25519Together"] = True
    elif mutation == "feedFallback":
        value["rotation"]["feedFallback"] = True
    elif mutation == "secretField":
        value["privateKey"] = "not-a-real-key"
    elif mutation in {"noncanonical", "duplicateKey", "symlink", "hardlink", "oversized"}:
        return
    else:
        raise ValueError(f"unknown mutation: {mutation}")


def exercise_file_loader(value: dict[str, Any], mutation: str | None) -> bool:
    with tempfile.TemporaryDirectory(prefix="maccompanion-update-policy-") as temporary:
        root = Path(temporary)
        path = root / "policy.json"
        if mutation == "symlink":
            target = root / "target.json"
            target.write_bytes(canonical_bytes(value))
            path.symlink_to(target)
        elif mutation == "hardlink":
            target = root / "target.json"
            target.write_bytes(canonical_bytes(value))
            os.link(target, path)
        elif mutation == "oversized":
            path.write_bytes(b" " * (MAX_POLICY_BYTES + 1))
        elif mutation == "noncanonical":
            path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
        elif mutation == "duplicateKey":
            raw = canonical_bytes(value).decode("utf-8")
            path.write_text(raw.replace('{"channels":', '{"product":"Mac Companion","channels":', 1), encoding="utf-8")
        else:
            path.write_bytes(canonical_bytes(value))
        try:
            load_policy(path)
            return True
        except UpdatePolicyError:
            return False


def main() -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if manifest.get("profile") != "maccompanion.update-policy-fixtures.v0.2":
        raise SystemExit("invalid update-policy fixture profile")
    cases = manifest.get("cases")
    if not isinstance(cases, list) or not cases:
        raise SystemExit("missing update-policy fixtures")
    seen: set[str] = set()
    for case in cases:
        identifier = case.get("id")
        mutation = case.get("mutation")
        accepted = case.get("accepted")
        if not isinstance(identifier, str) or identifier in seen or not isinstance(accepted, bool):
            raise SystemExit("invalid update-policy fixture manifest")
        seen.add(identifier)
        value = copy.deepcopy(base_policy())
        if mutation is not None:
            mutate(value, mutation)
        actual = exercise_file_loader(value, mutation)
        if actual != accepted:
            raise SystemExit(f"fixture {identifier}: expected accepted={accepted}, got {actual}")

    with tempfile.TemporaryDirectory(prefix="maccompanion-update-policy-write-") as temporary:
        path = Path(temporary) / "policy.json"
        write_new_policy(path, base_policy())
        if path.stat().st_mode & 0o777 != 0o600:
            raise SystemExit("update policy writer did not use mode 0600")
        load_policy(path)
        try:
            write_new_policy(path, base_policy())
        except FileExistsError:
            pass
        else:
            raise SystemExit("update policy writer overwrote an existing policy")

    validate_policy(base_policy())
    print(f"Validated {len(cases)} update-policy fixtures and exclusive writer behavior.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
