#!/usr/bin/env python3

from __future__ import annotations

import copy
import hashlib
import tempfile
from pathlib import Path

from platform_codesign_inspection import (
    PlatformCodesignInspectionError,
    correlate_codesign_inspection,
    parse_entitlements_inspection_output,
    parse_identity_inspection_output,
)
from platform_signing_fixed_tools import inspect_fixed_tool
from platform_signing_subjects import derive_codesign_architecture_inspection_plans
from validate_platform_signing_subjects import reconstruct


CODE_DIRECTORY_SHA256 = "a" * 64
LEAF_CERTIFICATE_SHA256 = "b" * 64


def fixture_result(invocation, *, passed: bool = True) -> dict:
    return {
        "invocationID": invocation.invocation_id,
        "tool": invocation.tool.public_record(),
        "argv": [invocation.tool.path, *invocation.arguments],
        "environment": {
            "HOME": "/private/fixed",
            "TMPDIR": "/private/fixed",
            "LANG": "C",
            "LC_ALL": "C",
        },
        "timeoutSeconds": invocation.timeout_seconds,
        "outputLimitBytesPerStream": 1024 * 1024,
        "startedAt": "2026-08-22T12:00:00.000Z",
        "completedAt": "2026-08-22T12:00:01.000Z",
        "durationMilliseconds": 1000,
        "termination": "exited",
        "returnCode": 0 if passed else 1,
        "toolUnchanged": True,
        "stdout": {
            "path": f"{invocation.invocation_id}.stdout",
            "bytes": 1,
            "sha256": hashlib.sha256(b"fixture").hexdigest(),
        },
        "stderr": {
            "path": f"{invocation.invocation_id}.stderr",
            "bytes": 1,
            "sha256": hashlib.sha256(b"fixture").hexdigest(),
        },
        "passed": passed,
    }


def identity_stderr(plan, *, timestamp: bool = True) -> bytes:
    lines = [
        f"Executable={plan.owned_source_path}",
        "Identifier=media.jenny.maccompanion.fixture",
        "Format=Mach-O thin (arm64e)",
        "CodeDirectory v=20500 size=321 flags=0x10000(runtime) hashes=3+7 location=embedded",
        f"CandidateCDHashFull sha256={CODE_DIRECTORY_SHA256}",
        f"CDHash={CODE_DIRECTORY_SHA256[:40]}",
        "Signature=size=9123",
        "Authority=Developer ID Application: Jenny Media LLC (ABCDE12345)",
        "Authority=Developer ID Certification Authority",
        "Authority=Apple Root CA",
        "TeamIdentifier=ABCDE12345",
    ]
    if timestamp:
        lines.append("Timestamp=Aug 22, 2026 at 12:00:00 PM")
    lines.extend([
        "Sealed Resources=none",
        "Internal requirements count=1 size=172",
    ])
    return ("\n".join(lines) + "\n").encode("utf-8")


def require_failure(operation, expected: str) -> None:
    try:
        operation()
    except PlatformCodesignInspectionError as error:
        if expected not in str(error):
            raise RuntimeError(
                f"expected inspection failure containing {expected!r}, got {error!r}"
            ) from error
    else:
        raise RuntimeError(f"expected inspection failure containing {expected!r}")


def main() -> int:
    codesign = inspect_fixed_tool("apple.codesign", "/usr/bin/codesign")
    with tempfile.TemporaryDirectory(prefix="maccompanion-codesign-inspection-") as value:
        root = Path(value)
        _, _, graph, _, subjects = reconstruct(root, "mac")
        plans = derive_codesign_architecture_inspection_plans(
            graph=graph,
            reconstructed=subjects,
            codesign_tool=codesign,
        )
        plan = plans[0]
        identity_result = fixture_result(plan.identity_invocation)
        requirement_stdout = (
            'designated => identifier "media.jenny.maccompanion.fixture" and anchor apple generic\n'
        ).encode("utf-8")
        identity = parse_identity_inspection_output(
            plan,
            identity_result,
            requirement_stdout,
            identity_stderr(plan),
            [LEAF_CERTIFICATE_SHA256, "c" * 64, "d" * 64],
        )
        if (
            identity["status"] != "passed"
            or identity["displayFacts"]["secureTimestampPresent"] is not True
            or identity["certificateSHA256"][0] != LEAF_CERTIFICATE_SHA256
        ):
            raise RuntimeError("identity inspection parser omitted fixed facts")

        entitlement_result = fixture_result(plan.entitlements_invocation)
        entitlements = parse_entitlements_inspection_output(
            plan,
            entitlement_result,
            b"",
            f"Executable={plan.owned_source_path}\n".encode("utf-8"),
        )
        embedded = {
            "signingIdentifier": "media.jenny.maccompanion.fixture",
            "teamIdentifier": "ABCDE12345",
            "codeDirectories": [{
                "hashType": "sha256",
                "cdhash": CODE_DIRECTORY_SHA256[:40],
                "codeDirectorySHA256": CODE_DIRECTORY_SHA256,
            }],
            "entitlements": {"mode": "absent"},
        }
        correlated = correlate_codesign_inspection(
            embedded_facts=embedded,
            identity_inspection=identity,
            entitlements_inspection=entitlements,
        )
        if (
            correlated["leafCertificateSHA256"] != LEAF_CERTIFICATE_SHA256
            or correlated["certificateCount"] != 3
            or correlated["entitlementsMatched"] is not True
        ):
            raise RuntimeError("codesign inspection correlation is incomplete")

        no_timestamp = parse_identity_inspection_output(
            plan,
            identity_result,
            requirement_stdout,
            identity_stderr(plan, timestamp=False),
            [LEAF_CERTIFICATE_SHA256],
        )
        if no_timestamp["displayFacts"]["secureTimestampPresent"] is not False:
            raise RuntimeError("absent secure timestamp was invented")

        failed_result = fixture_result(plan.identity_invocation, passed=False)
        if parse_identity_inspection_output(
            plan,
            failed_result,
            b"candidate-controlled stdout",
            b"candidate-controlled stderr",
            [],
        ) != {
            "status": "failed",
            "reason": "nonzeroExit",
            "displayFacts": None,
            "certificateSHA256": [],
        }:
            raise RuntimeError("failed identity output was interpreted")

        require_failure(
            lambda: parse_identity_inspection_output(
                plan,
                identity_result,
                b'# designated => identifier "fixture"\n',
                identity_stderr(plan),
                [LEAF_CERTIFICATE_SHA256],
            ),
            "explicit designated requirement",
        )
        require_failure(
            lambda: parse_identity_inspection_output(
                plan,
                identity_result,
                requirement_stdout,
                identity_stderr(plan).replace(
                    b"Signature=size=9123",
                    b"Signature=adhoc",
                ),
                [LEAF_CERTIFICATE_SHA256],
            ),
            "identity facts are invalid",
        )
        require_failure(
            lambda: parse_identity_inspection_output(
                plan,
                identity_result,
                requirement_stdout,
                identity_stderr(plan),
                [],
            ),
            "certificate inventory",
        )
        changed_result = copy.deepcopy(identity_result)
        changed_result["argv"] = ["/usr/bin/codesign", "substituted"]
        require_failure(
            lambda: parse_identity_inspection_output(
                plan,
                changed_result,
                requirement_stdout,
                identity_stderr(plan),
                [LEAF_CERTIFICATE_SHA256],
            ),
            "differs from its fixed plan",
        )
        require_failure(
            lambda: parse_entitlements_inspection_output(
                plan,
                entitlement_result,
                b"",
                f"Executable={plan.owned_source_path}\nwarning\n".encode("utf-8"),
            ),
            "closed grammar",
        )
        changed_embedded = copy.deepcopy(embedded)
        changed_embedded["codeDirectories"][0]["codeDirectorySHA256"] = "e" * 64
        require_failure(
            lambda: correlate_codesign_inspection(
                embedded_facts=changed_embedded,
                identity_inspection=identity,
                entitlements_inspection=entitlements,
            ),
            "disagrees",
        )

    print(
        "Validated fixed per-architecture codesign display/requirement/entitlement "
        "grammars and independent embedded-fact correlation."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
