#!/usr/bin/env python3

from __future__ import annotations

import copy
import hashlib
import subprocess
import sys
import tempfile
from pathlib import Path

from artifact_sbom import canonical_bytes, generate, load_json
from validate_artifact_sbom import write_layout_archive, write_signed_code_fixture
from validate_release_evidence import referenced_files, validate_manifest


ROOT = Path(__file__).resolve().parents[1]
VALIDATOR = ROOT / "scripts" / "validate_release_evidence.py"
MANIFEST = ROOT / "Tests" / "System" / "ReleaseEvidence" / "valid-signed-mac-candidate.json"
UNSIGNED_MANIFEST = (
    ROOT / "Tests" / "System" / "ReleaseEvidence" / "valid-unsigned-construction.json"
)
PIN = hashlib.sha256(b"synthetic independently protected policy pin").hexdigest()
ARTIFACT_FIXTURE = ROOT / "Tests" / "System" / "ArtifactSBOM" / "valid-mac-app.json"


def run(arguments: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(VALIDATOR), *arguments],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )


def complete_signed_fixture(root: Path) -> tuple[Path, str]:
    release = load_json(MANIFEST)
    next(
        item for item in release["executables"] if item["role"] == "macApp"
    )["bundleIdentifier"] = "example.maccompanion.fixture"
    layout = load_json(ARTIFACT_FIXTURE)
    for artifact in release["artifacts"]:
        path = root / artifact["path"]
        if artifact["kind"] in {"macApplication", "sparkleArchive"}:
            write_layout_archive(path, layout)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"synthetic signing-policy CLI disk image")
        artifact["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        artifact["bytes"] = path.stat().st_size

    candidate = {
        "schemaVersion": "maccompanion.artifact-sbom.v0.1",
        "product": "Mac Companion",
        "release": {
            "version": release["release"]["version"],
            "buildNumber": release["release"]["buildNumber"],
            "targets": copy.deepcopy(release["release"]["targets"]),
        },
        "source": copy.deepcopy(release["source"]),
        "created": "2026-08-21T12:00:00Z",
        "artifacts": [
            {
                "id": artifact["id"],
                "kind": artifact["kind"],
                "path": artifact["path"],
            }
            for artifact in release["artifacts"]
            if artifact["kind"] in {"macApplication", "sparkleArchive"}
        ],
    }
    index, composition, spdx = generate(candidate, root)
    supply_chain = root / "supply-chain"
    supply_chain.mkdir()
    composition_raw = canonical_bytes(composition)
    spdx_raw = canonical_bytes(spdx)
    index_raw = canonical_bytes(index)
    (supply_chain / "artifact-composition.json").write_bytes(composition_raw)
    (supply_chain / "artifact-sbom.spdx.json").write_bytes(spdx_raw)
    (supply_chain / "artifact-sbom-index.json").write_bytes(index_raw)
    release["sbom"]["document"] = {
        "path": "supply-chain/artifact-sbom-index.json",
        "sha256": hashlib.sha256(index_raw).hexdigest(),
        "bytes": len(index_raw),
    }
    signing_policy_pin = write_signed_code_fixture(root, release, composition)
    for reference in referenced_files(release):
        path = root / reference["path"]
        if path.exists():
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"x")
        reference["sha256"] = hashlib.sha256(b"x").hexdigest()
        reference["bytes"] = 1
    if errors := validate_manifest(release):
        raise RuntimeError(f"complete CLI fixture is structurally invalid: {sorted(errors)}")
    manifest_path = root / "release-evidence.json"
    manifest_path.write_bytes(canonical_bytes(release))
    return manifest_path, signing_policy_pin


def semantic_errors(result: subprocess.CompletedProcess[str]) -> set[str]:
    if result.returncode != 1 or result.stderr:
        raise RuntimeError(
            "signing-policy CLI semantic case did not fail through validation: "
            f"exit={result.returncode} stdout={result.stdout!r} stderr={result.stderr!r}"
        )
    marker = ": invalid: "
    lines = [line for line in result.stdout.splitlines() if marker in line]
    if len(lines) != 1:
        raise RuntimeError(f"signing-policy CLI emitted an ambiguous result: {result.stdout!r}")
    return set(lines[0].split(marker, 1)[1].split(", "))


def main() -> None:
    parser_errors = [
        ["--expected-signing-policy-sha256", PIN, str(MANIFEST)],
        ["--verify-files", "--expected-signing-policy-sha256", PIN.upper(), str(MANIFEST)],
        ["--verify-files", "--expected-signing-policy-sha256", "0" * 64, str(MANIFEST)],
        ["--verify-files", "--expected-signing-policy-sha256", PIN, str(MANIFEST), str(MANIFEST)],
        ["--schema-only", "--expected-signing-policy-sha256", PIN, str(MANIFEST)],
        ["--verify-files", "--expected-signing-policy-sha256", PIN],
    ]
    for arguments in parser_errors:
        result = run(arguments)
        if result.returncode != 2:
            raise RuntimeError(
                f"signing-policy CLI misuse did not fail as an argument error: {arguments}: "
                f"exit={result.returncode} stdout={result.stdout!r} stderr={result.stderr!r}"
            )
    with tempfile.TemporaryDirectory(prefix="maccompanion-signing-policy-cli-") as temporary:
        complete_manifest, correct_pin = complete_signed_fixture(Path(temporary))
        correct_errors = semantic_errors(run([
            "--verify-files",
            "--expected-signing-policy-sha256",
            correct_pin,
            str(complete_manifest),
        ]))
        if correct_errors != {
            "missingMacPackagingEquivalence",
            "signedCodePlatformVerificationRequired",
        }:
            raise RuntimeError(f"correct external policy pin returned {sorted(correct_errors)}")
        wrong_errors = semantic_errors(run([
            "--verify-files",
            "--expected-signing-policy-sha256",
            PIN,
            str(complete_manifest),
        ]))
        if wrong_errors != {
            "missingMacPackagingEquivalence",
            "signingPolicyDigestMismatch",
        }:
            raise RuntimeError(f"wrong external policy pin returned {sorted(wrong_errors)}")
        omitted_errors = semantic_errors(run(["--verify-files", str(complete_manifest)]))
        if omitted_errors != {
            "missingMacPackagingEquivalence",
            "signingPolicyDigestPinRequired",
        }:
            raise RuntimeError(f"omitted external policy pin returned {sorted(omitted_errors)}")
    unsigned = run([
        "--verify-files",
        "--expected-signing-policy-sha256",
        PIN,
        str(UNSIGNED_MANIFEST),
    ])
    if unsigned.returncode != 1 or "unexpectedSigningPolicyPin" not in unsigned.stdout:
        raise RuntimeError("external signing-policy pin was accepted for an unsigned manifest")
    print(f"validated {len(parser_errors) + 4} signing-policy CLI contract case(s)")


if __name__ == "__main__":
    main()
