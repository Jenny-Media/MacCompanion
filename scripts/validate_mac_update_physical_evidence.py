#!/usr/bin/env python3

from __future__ import annotations

import copy
import hashlib
import json
import tempfile
from pathlib import Path
from typing import Any, Callable

from artifact_sbom import canonical_bytes
from mac_update_physical_evidence import (
    APP_IDENTIFIER,
    ARTIFACT_ORDER,
    CASE_PROFILE,
    MacUpdatePhysicalEvidenceError,
    SCHEMA,
    UPDATE_CHECK_PROFILE,
    load_canonical_record,
    validate_record,
)


def _reference(path: str, content: bytes) -> dict[str, Any]:
    return {
        "path": path,
        "sha256": hashlib.sha256(content).hexdigest(),
        "bytes": len(content),
    }


def _context(root: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    artifacts = [
        {
            "id": artifact_id,
            "kind": kind,
            "path": f"artifacts/{artifact_id}",
            "sha256": digest,
            "bytes": byte_count,
        }
        for artifact_id, kind, digest, byte_count in (
            ("mac-app", "macApplication", "1a" * 32, 1_000_000),
            ("mac-dmg", "macDiskImage", "2b" * 32, 1_200_000),
            ("sparkle-archive", "sparkleArchive", "3c" * 32, 1_000_000),
        )
    ]
    release = {
        "release": {
            "version": "1.0.0-beta.2",
            "buildNumber": "102",
            "channel": "beta",
            "targets": ["macOS"],
        },
        "source": {
            "revision": "4d" * 20,
            "dirty": False,
        },
        "compatibility": {
            "macUserInitiatedUpdateCheckProfile": UPDATE_CHECK_PROFILE,
        },
        "artifacts": artifacts,
    }
    source_content = b"signed source candidate inspection\n"
    source_path = root / "physical" / "source-installation.txt"
    source_path.parent.mkdir(parents=True)
    source_path.write_bytes(source_content)
    source = {
        "version": "1.0.0-beta.1",
        "buildNumber": "101",
        "bundleIdentifier": APP_IDENTIFIER,
        "teamIdentifier": "ABCDE12345",
        "evidence": _reference("physical/source-installation.txt", source_content),
    }
    cases: list[dict[str, Any]] = []
    for case_id, outcome, fresh_user in CASE_PROFILE:
        content = f"{case_id} physical observation\n".encode("utf-8")
        relative = f"physical/cases/{case_id}.txt"
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        candidate_running = outcome == "candidateRunning"
        cases.append({
            "id": case_id,
            "outcome": outcome,
            "observedVersion": release["release"]["version"] if candidate_running else source["version"],
            "observedBuildNumber": release["release"]["buildNumber"] if candidate_running else source["buildNumber"],
            "freshUser": fresh_user,
            "evidence": _reference(relative, content),
        })
    candidate_artifacts = []
    for kind in ARTIFACT_ORDER:
        artifact = next(item for item in artifacts if item["kind"] == kind)
        candidate_artifacts.append(copy.deepcopy(artifact))
    record = {
        "schemaVersion": SCHEMA,
        "product": "Mac Companion",
        "created": "2026-08-23T18:00:00Z",
        "machine": {
            "hardwareModel": "Mac fixture",
            "architecture": "arm64",
            "macOSVersion": "26.4",
        },
        "sourceInstallation": source,
        "candidate": {
            "version": release["release"]["version"],
            "buildNumber": release["release"]["buildNumber"],
            "channel": release["release"]["channel"],
            "sourceRevision": release["source"]["revision"],
            "bundleIdentifier": APP_IDENTIFIER,
            "updateCheckProfile": UPDATE_CHECK_PROFILE,
            "artifacts": candidate_artifacts,
        },
        "cases": cases,
    }
    return release, record


def _expect_failure(action: Callable[[], Any], phrase: str) -> None:
    try:
        action()
    except MacUpdatePhysicalEvidenceError as error:
        if phrase not in str(error):
            raise RuntimeError(f"expected {phrase!r}, got {error!r}") from error
    else:
        raise RuntimeError(f"expected update-matrix failure containing {phrase!r}")


def main() -> int:
    from validate_release_evidence import verify_files

    with tempfile.TemporaryDirectory(prefix="maccompanion-update-matrix-") as temporary:
        root = Path(temporary)
        release, record = _context(root)
        validated = validate_record(
            record,
            release_manifest=release,
            evidence_root=root,
            verify_files=True,
        )
        raw = canonical_bytes(validated)
        matrix_path = root / "physical" / "mac-update-physical-evidence.json"
        matrix_path.write_bytes(raw)
        loaded, loaded_raw = load_canonical_record(matrix_path)
        if loaded != record or loaded_raw != raw:
            raise RuntimeError("canonical update matrix did not round trip")

        mutations: list[tuple[str, Callable[[dict[str, Any]], None], str]] = [
            ("unknown root", lambda value: value.__setitem__("unexpected", True), "not closed"),
            ("missing case", lambda value: value["cases"].pop(), "wrong case set"),
            ("case order", lambda value: value["cases"].reverse(), "closed outcome"),
            ("wrong outcome", lambda value: value["cases"][0].__setitem__("outcome", "candidateRunning"), "closed outcome"),
            ("wrong observed build", lambda value: value["cases"][0].__setitem__("observedBuildNumber", "102"), "closed outcome"),
            ("false clean user", lambda value: value["cases"][-2].__setitem__("freshUser", False), "closed outcome"),
            ("candidate substitution", lambda value: value["candidate"].__setitem__("buildNumber", "103"), "does not match"),
            ("profile removal", lambda value: value["candidate"].__setitem__("updateCheckProfile", None), "does not match"),
            ("source not older", lambda value: value["sourceInstallation"].__setitem__("buildNumber", "102"), "not older"),
            ("duplicate evidence", lambda value: value["cases"][1].__setitem__("evidence", copy.deepcopy(value["cases"][0]["evidence"])), "distinct"),
        ]
        for _, mutation, phrase in mutations:
            changed = copy.deepcopy(record)
            mutation(changed)
            _expect_failure(
                lambda selected=changed: validate_record(
                    selected,
                    release_manifest=release,
                    evidence_root=root,
                    verify_files=True,
                ),
                phrase,
            )

        evidence_path = root / record["cases"][0]["evidence"]["path"]
        original = evidence_path.read_bytes()
        evidence_path.write_bytes(b"mutated physical observation\n")
        _expect_failure(
            lambda: validate_record(record, release_manifest=release, evidence_root=root, verify_files=True),
            "binding mismatch",
        )
        evidence_path.write_bytes(original)

        pretty_path = root / "physical" / "pretty.json"
        pretty_path.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        _expect_failure(lambda: load_canonical_record(pretty_path), "not canonical")

        target = root / record["cases"][0]["evidence"]["path"]
        saved = target.with_suffix(".saved")
        target.rename(saved)
        target.symlink_to(saved.name)
        try:
            _expect_failure(
                lambda: validate_record(record, release_manifest=release, evidence_root=root, verify_files=True),
                "symlink",
            )
        finally:
            target.unlink()
            saved.rename(target)

        repository = Path(__file__).resolve().parents[1]
        promotion = json.loads(
            (
                repository
                / "Tests"
                / "System"
                / "ReleaseEvidence"
                / "valid-signed-mac-candidate.json"
            ).read_text(encoding="utf-8")
        )
        promotion["evidenceLevel"] = "promotionReady"
        promotion["release"] = copy.deepcopy(release["release"])
        promotion["source"] = copy.deepcopy(release["source"])
        promotion["compatibility"][
            "macUserInitiatedUpdateCheckProfile"
        ] = UPDATE_CHECK_PROFILE
        promotion["artifacts"] = copy.deepcopy(release["artifacts"])
        matrix_reference = _reference(
            "physical/mac-update-physical-evidence.json",
            raw,
        )
        promotion["physicalScenarios"] = [
            {
                "id": case_id,
                "platform": "macOS",
                "status": "passed",
                "evidence": copy.deepcopy(matrix_reference),
            }
            for case_id in ("upgrade", "rollback")
        ]
        manifest_path = root / "release-evidence.json"
        manifest_path.write_bytes(canonical_bytes(promotion))
        integration_errors = verify_files(promotion, manifest_path)
        if "invalidMacUpdatePhysicalEvidence" in integration_errors:
            raise RuntimeError("release verifier rejected the exact update matrix")

        mismatched = copy.deepcopy(record)
        mismatched["candidate"]["buildNumber"] = "103"
        mismatched_raw = canonical_bytes(mismatched)
        matrix_path.write_bytes(mismatched_raw)
        mismatched_reference = _reference(
            "physical/mac-update-physical-evidence.json",
            mismatched_raw,
        )
        for scenario in promotion["physicalScenarios"]:
            scenario["evidence"] = copy.deepcopy(mismatched_reference)
        mismatch_errors = verify_files(promotion, manifest_path)
        if "invalidMacUpdatePhysicalEvidence" not in mismatch_errors:
            raise RuntimeError("release verifier accepted a substituted update matrix")

    print("validated 16 Mac update physical-evidence case(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
