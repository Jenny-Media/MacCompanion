#!/usr/bin/env python3

from __future__ import annotations

import copy
import hashlib
import json
import tempfile
from pathlib import Path
from typing import Any, Callable

from artifact_sbom import canonical_bytes
from mac_lifecycle_physical_evidence import (
    APP_IDENTIFIER,
    ARTIFACT_ORDER,
    CASE_PROFILE,
    MacLifecyclePhysicalEvidenceError,
    SCHEMA,
    UPDATE_CHECK_PROFILE,
    load_canonical_record,
    validate_record,
)


REPOSITORY = Path(__file__).resolve().parents[1]


def _reference(path: str, content: bytes) -> dict[str, Any]:
    return {"path": path, "sha256": hashlib.sha256(content).hexdigest(), "bytes": len(content)}


def _context(root: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    release = json.loads(
        (REPOSITORY / "Tests/System/ReleaseEvidence/valid-signed-mac-candidate.json").read_text(
            encoding="utf-8"
        )
    )
    release["release"]["channel"] = "beta"
    release["compatibility"]["macUserInitiatedUpdateCheckProfile"] = UPDATE_CHECK_PROFILE
    candidate_artifacts: list[dict[str, Any]] = []
    for kind in ARTIFACT_ORDER:
        candidate_artifacts.append(copy.deepcopy(next(item for item in release["artifacts"] if item["kind"] == kind)))
    cases: list[dict[str, Any]] = []
    for case_id, outcome, fresh_user, assertions in CASE_PROFILE:
        content = f"{case_id} lifecycle observation\n".encode("utf-8")
        relative = f"physical/lifecycle/{case_id}.txt"
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        removed = outcome == "productRemoved"
        cases.append({
            "id": case_id,
            "outcome": outcome,
            "observedVersion": None if removed else release["release"]["version"],
            "observedBuildNumber": None if removed else release["release"]["buildNumber"],
            "freshUser": fresh_user,
            "assertions": list(assertions),
            "evidence": _reference(relative, content),
        })
    record = {
        "schemaVersion": SCHEMA,
        "product": "Mac Companion",
        "created": "2026-08-23T19:00:00Z",
        "machine": {"hardwareModel": "Mac fixture", "architecture": "arm64", "macOSVersion": "26.4"},
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
    except MacLifecyclePhysicalEvidenceError as error:
        if phrase not in str(error):
            raise RuntimeError(f"expected {phrase!r}, got {error!r}") from error
    else:
        raise RuntimeError(f"expected lifecycle-evidence failure containing {phrase!r}")


def main() -> int:
    from validate_release_evidence import verify_files

    with tempfile.TemporaryDirectory(prefix="maccompanion-lifecycle-matrix-") as temporary:
        root = Path(temporary)
        release, record = _context(root)
        validate_record(record, release_manifest=release, evidence_root=root, verify_files=True)
        raw = canonical_bytes(record)
        matrix_path = root / "physical/mac-lifecycle-physical-evidence.json"
        matrix_path.write_bytes(raw)
        loaded, loaded_raw = load_canonical_record(matrix_path)
        if loaded != record or loaded_raw != raw:
            raise RuntimeError("canonical lifecycle matrix did not round trip")

        mutations: list[tuple[Callable[[dict[str, Any]], None], str]] = [
            (lambda value: value.__setitem__("unexpected", True), "not closed"),
            (lambda value: value["cases"].pop(), "wrong case set"),
            (lambda value: value["cases"].reverse(), "not exact"),
            (lambda value: value["cases"][0].__setitem__("outcome", "productRemoved"), "not exact"),
            (lambda value: value["cases"][0].__setitem__("observedBuildNumber", None), "not exact"),
            (lambda value: value["cases"][1].__setitem__("freshUser", False), "not exact"),
            (lambda value: value["cases"][2]["assertions"].pop(), "not exact"),
            (lambda value: value["candidate"].__setitem__("buildNumber", "101"), "does not match"),
            (lambda value: value["candidate"].__setitem__("updateCheckProfile", None), "does not match"),
            (lambda value: value["cases"][1].__setitem__("evidence", copy.deepcopy(value["cases"][0]["evidence"])), "distinct"),
        ]
        for mutation, phrase in mutations:
            changed = copy.deepcopy(record)
            mutation(changed)
            _expect_failure(
                lambda selected=changed: validate_record(
                    selected, release_manifest=release, evidence_root=root, verify_files=True
                ),
                phrase,
            )

        evidence_path = root / record["cases"][0]["evidence"]["path"]
        original = evidence_path.read_bytes()
        evidence_path.write_bytes(b"mutated lifecycle observation\n")
        _expect_failure(
            lambda: validate_record(record, release_manifest=release, evidence_root=root, verify_files=True),
            "binding mismatch",
        )
        evidence_path.write_bytes(original)

        pretty = root / "physical/pretty-lifecycle.json"
        pretty.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        _expect_failure(lambda: load_canonical_record(pretty), "not canonical")

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

        release["evidenceLevel"] = "promotionReady"
        matrix_reference = _reference("physical/mac-lifecycle-physical-evidence.json", raw)
        release["physicalScenarios"] = [
            {"id": case_id, "platform": "macOS", "status": "passed", "evidence": copy.deepcopy(matrix_reference)}
            for case_id in ("clean-install", "permission-revocation", "complete-uninstall", "quarantine-launch")
        ]
        manifest_path = root / "release-evidence.json"
        manifest_path.write_bytes(canonical_bytes(release))
        if "invalidMacLifecyclePhysicalEvidence" in verify_files(release, manifest_path):
            raise RuntimeError("release verifier rejected exact lifecycle evidence")
        release["physicalScenarios"][1]["evidence"] = copy.deepcopy(
            _reference("physical/lifecycle/permission-revocation.txt", original)
        )
        if "invalidMacLifecyclePhysicalEvidence" not in verify_files(release, manifest_path):
            raise RuntimeError("release verifier accepted divergent lifecycle evidence")

    print("validated 16 Mac lifecycle physical-evidence case(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
