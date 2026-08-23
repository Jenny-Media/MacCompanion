#!/usr/bin/env python3

from __future__ import annotations

import copy
import hashlib
import json
import tempfile
from pathlib import Path
from typing import Any, Callable

from artifact_sbom import canonical_bytes
from ios_physical_evidence import (
    APP_IDENTIFIER,
    CASE_PROFILE,
    IOSPhysicalEvidenceError,
    SCHEMA,
    load_canonical_record,
    validate_record,
)


REPOSITORY = Path(__file__).resolve().parents[1]


def _reference(path: str, content: bytes) -> dict[str, Any]:
    return {"path": path, "sha256": hashlib.sha256(content).hexdigest(), "bytes": len(content)}


def _context(root: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    release = json.loads(
        (REPOSITORY / "Tests/System/ReleaseEvidence/valid-promotion-both-targets.json").read_text(
            encoding="utf-8"
        )
    )
    artifact = copy.deepcopy(next(item for item in release["artifacts"] if item["kind"] == "iosArchive"))
    cases: list[dict[str, Any]] = []
    for case_id, outcome, assertions in CASE_PROFILE:
        content = f"{case_id} iOS physical observation\n".encode("utf-8")
        relative = f"physical/ios/{case_id}.txt"
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        cases.append({
            "id": case_id,
            "outcome": outcome,
            "observedVersion": release["release"]["version"],
            "observedBuildNumber": release["release"]["buildNumber"],
            "assertions": list(assertions),
            "evidence": _reference(relative, content),
        })
    record = {
        "schemaVersion": SCHEMA,
        "product": "Mac Companion",
        "created": "2026-08-23T20:00:00Z",
        "device": {
            "model": "iPhone fixture", "architecture": "arm64",
            "iOSVersion": "26.4", "passcodeSet": True, "freshInstall": True,
        },
        "candidate": {
            "version": release["release"]["version"],
            "buildNumber": release["release"]["buildNumber"],
            "channel": release["release"]["channel"],
            "sourceRevision": release["source"]["revision"],
            "bundleIdentifier": APP_IDENTIFIER,
            "artifact": artifact,
        },
        "cases": cases,
    }
    return release, record


def _expect_failure(action: Callable[[], Any], phrase: str) -> None:
    try:
        action()
    except IOSPhysicalEvidenceError as error:
        if phrase not in str(error):
            raise RuntimeError(f"expected {phrase!r}, got {error!r}") from error
    else:
        raise RuntimeError(f"expected iOS physical-evidence failure containing {phrase!r}")


def main() -> int:
    from validate_release_evidence import verify_files

    with tempfile.TemporaryDirectory(prefix="maccompanion-ios-evidence-") as temporary:
        root = Path(temporary)
        release, record = _context(root)
        validate_record(record, release_manifest=release, evidence_root=root, verify_files=True)
        raw = canonical_bytes(record)
        record_path = root / "physical/ios-physical-evidence.json"
        record_path.write_bytes(raw)
        loaded, loaded_raw = load_canonical_record(record_path)
        if loaded != record or loaded_raw != raw:
            raise RuntimeError("canonical iOS physical record did not round trip")

        mutations: list[tuple[Callable[[dict[str, Any]], None], str]] = [
            (lambda value: value.__setitem__("unexpected", True), "not closed"),
            (lambda value: value["cases"].pop(), "wrong case set"),
            (lambda value: value["cases"].reverse(), "not exact"),
            (lambda value: value["cases"][0].__setitem__("outcome", "paired"), "not exact"),
            (lambda value: value["cases"][0].__setitem__("observedBuildNumber", "100"), "not exact"),
            (lambda value: value["cases"][1]["assertions"].pop(), "not exact"),
            (lambda value: value["candidate"].__setitem__("buildNumber", "102"), "does not match"),
            (lambda value: value["candidate"].__setitem__("bundleIdentifier", "example.substitute"), "does not match"),
            (lambda value: value["device"].__setitem__("passcodeSet", False), "posture"),
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
        evidence_path.write_bytes(b"mutated iOS observation\n")
        _expect_failure(
            lambda: validate_record(record, release_manifest=release, evidence_root=root, verify_files=True),
            "binding mismatch",
        )
        evidence_path.write_bytes(original)

        pretty = root / "physical/pretty-ios.json"
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

        record_reference = _reference("physical/ios-physical-evidence.json", raw)
        release["physicalScenarios"] = [
            {"id": case_id, "platform": "iOS", "status": "passed", "evidence": copy.deepcopy(record_reference)}
            for case_id in ("physical-pairing", "local-network-denial", "background-reconnect")
        ]
        manifest_path = root / "release-evidence.json"
        manifest_path.write_bytes(canonical_bytes(release))
        if "invalidIOSPhysicalEvidence" in verify_files(release, manifest_path):
            raise RuntimeError("release verifier rejected exact iOS physical evidence")
        release["physicalScenarios"][1]["evidence"] = copy.deepcopy(
            _reference("physical/ios/local-network-denial.txt", original)
        )
        if "invalidIOSPhysicalEvidence" not in verify_files(release, manifest_path):
            raise RuntimeError("release verifier accepted divergent iOS evidence")

    print("validated 16 iOS physical-evidence case(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
