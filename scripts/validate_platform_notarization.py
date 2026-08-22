#!/usr/bin/env python3

from __future__ import annotations

import copy
import json
from typing import Any, Callable

from artifact_sbom import canonical_bytes
from platform_notarization import (
    MAX_RAW_BYTES,
    PlatformNotarizationError,
    compose_phase,
    compose_record,
    parse_accepted_info,
    parse_accepted_log,
    validate_record,
)


APP_ID = "12345678-1234-1234-1234-123456789abc"
DMG_ID = "abcdefab-cdef-abcd-efab-cdefabcdefab"
APP_DIGEST = "1a" * 32
DMG_DIGEST = "2b" * 32


def raw_json(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")


def upload(file_name: str, digest: str, byte_count: int) -> dict[str, Any]:
    return {"fileName": file_name, "bytes": byte_count, "sha256": digest}


def info(submission_id: str, name: str, created: str) -> bytes:
    return raw_json({
        "createdDate": created,
        "id": submission_id,
        "name": name,
        "status": "Accepted",
    })


def log(
    submission_id: str,
    name: str,
    digest: str,
    uploaded: str,
    *,
    issues: Any = None,
) -> bytes:
    return raw_json({
        "archiveFilename": name,
        "issues": issues,
        "jobId": submission_id.upper(),
        "logFormatVersion": 1,
        "sha256": digest,
        "status": "Accepted",
        "statusCode": 0,
        "statusSummary": "Ready for distribution",
        "ticketContents": [{
            "arch": "arm64",
            "cdhash": "3c" * 20,
            "digestAlgorithm": "SHA-256",
            "path": "Mac Companion.app/Contents/MacOS/Mac Companion",
        }],
        "uploadDate": uploaded,
    })


def inputs() -> tuple[dict[str, Any], dict[str, Any]]:
    app_upload = upload("MacCompanion-1.0.0-notary.zip", APP_DIGEST, 1_000_000)
    dmg_upload = upload("MacCompanion-1.0.0.dmg", DMG_DIGEST, 1_200_000)
    return (
        {
            "upload": app_upload,
            "info_raw": info(APP_ID, app_upload["fileName"], "2026-08-22T18:00:00.125Z"),
            "info_path": "notarization/application-info.json",
            "log_raw": log(
                APP_ID,
                app_upload["fileName"],
                APP_DIGEST,
                "2026-08-22T18:00:02Z",
            ),
            "log_path": "notarization/application-log.json",
        },
        {
            "upload": dmg_upload,
            "info_raw": info(DMG_ID, dmg_upload["fileName"], "2026-08-22T18:05:00Z"),
            "info_path": "notarization/disk-image-info.json",
            "log_raw": log(
                DMG_ID,
                dmg_upload["fileName"],
                DMG_DIGEST,
                "2026-08-22T18:05:03.5Z",
            ),
            "log_path": "notarization/disk-image-log.json",
        },
    )


def require_failure(operation: Callable[[], Any], expected: str) -> None:
    try:
        operation()
    except PlatformNotarizationError as error:
        if expected not in str(error):
            raise RuntimeError(
                f"expected notarization failure containing {expected!r}, got {error!r}"
            ) from error
    else:
        raise RuntimeError(f"expected notarization failure containing {expected!r}")


def main() -> int:
    application_inputs, disk_image_inputs = inputs()
    application = compose_phase(phase="applicationArchive", **application_inputs)
    disk_image = compose_phase(phase="diskImage", **disk_image_inputs)
    release = {"version": "1.0.0", "buildNumber": "100", "targets": ["macOS"]}
    source = {"revision": "4d" * 20, "dirty": False}
    record = compose_record(
        release=release,
        source=source,
        created="2026-08-22T18:06:00Z",
        application_phase=application,
        disk_image_phase=disk_image,
    )
    if (
        record["platformAcceptanceEligible"] is not False
        or [item["phase"] for item in record["phases"]]
        != ["applicationArchive", "diskImage"]
        or record["phases"][0]["log"]["sha256"] != APP_DIGEST
        or record["phases"][1]["log"]["sha256"] != DMG_DIGEST
        or any(item["platformAcceptanceEligible"] is not False for item in record["phases"])
    ):
        raise RuntimeError("two-phase notarization record is incomplete")
    parsed = validate_record(
        record,
        release=release,
        source=source,
        application_inputs=application_inputs,
        disk_image_inputs=disk_image_inputs,
    )
    if canonical_bytes(parsed) != canonical_bytes(record):
        raise RuntimeError("two-phase notarization record did not round trip")

    changed_inputs = copy.deepcopy(application_inputs)
    changed_inputs["upload"]["sha256"] = "5e" * 32
    require_failure(
        lambda: compose_phase(phase="applicationArchive", **changed_inputs),
        "does not bind an accepted upload",
    )

    warning_inputs = copy.deepcopy(application_inputs)
    warning_inputs["log_raw"] = log(
        APP_ID,
        warning_inputs["upload"]["fileName"],
        APP_DIGEST,
        "2026-08-22T18:00:02Z",
        issues=[{"severity": "warning", "message": "review me"}],
    )
    require_failure(
        lambda: compose_phase(phase="applicationArchive", **warning_inputs),
        "contains issues",
    )

    changed_log = json.loads(application_inputs["log_raw"])
    changed_log["unexpected"] = True
    require_failure(
        lambda: parse_accepted_log(
            raw_json(changed_log),
            phase="applicationArchive",
            upload=application_inputs["upload"],
            submission_id=APP_ID,
            raw_path="notarization/changed-log.json",
        ),
        "not closed",
    )

    duplicate_info = (
        b'{"createdDate":"2026-08-22T18:00:00Z","id":"'
        + APP_ID.encode("ascii")
        + b'","id":"'
        + APP_ID.encode("ascii")
        + b'","name":"MacCompanion-1.0.0-notary.zip","status":"Accepted"}'
    )
    require_failure(
        lambda: parse_accepted_info(
            duplicate_info,
            phase="applicationArchive",
            upload=application_inputs["upload"],
            raw_path="notarization/duplicate-info.json",
        ),
        "duplicate-safe",
    )

    changed = copy.deepcopy(record)
    changed["platformAcceptanceEligible"] = True
    require_failure(
        lambda: validate_record(
            changed,
            release=release,
            source=source,
            application_inputs=application_inputs,
            disk_image_inputs=disk_image_inputs,
        ),
        "identity or gate state",
    )
    changed = copy.deepcopy(record)
    changed["unresolvedGates"] = changed["unresolvedGates"][:-1]
    require_failure(
        lambda: validate_record(
            changed,
            release=release,
            source=source,
            application_inputs=application_inputs,
            disk_image_inputs=disk_image_inputs,
        ),
        "identity or gate state",
    )
    changed = copy.deepcopy(record)
    changed["phases"].reverse()
    require_failure(
        lambda: validate_record(
            changed,
            release=release,
            source=source,
            application_inputs=application_inputs,
            disk_image_inputs=disk_image_inputs,
        ),
        "exact recomposition",
    )

    same_submission = copy.deepcopy(disk_image)
    same_submission["submissionID"] = application["submissionID"]
    require_failure(
        lambda: compose_record(
            release=release,
            source=source,
            created="2026-08-22T18:06:00Z",
            application_phase=application,
            disk_image_phase=same_submission,
        ),
        "ordering is invalid",
    )

    not_accepted = copy.deepcopy(application)
    not_accepted["acceptedStatus"] = False
    require_failure(
        lambda: compose_record(
            release=release,
            source=source,
            created="2026-08-22T18:06:00Z",
            application_phase=not_accepted,
            disk_image_phase=disk_image,
        ),
        "not accepted",
    )

    early_inputs = copy.deepcopy(disk_image_inputs)
    early_inputs["info_raw"] = info(
        DMG_ID,
        early_inputs["upload"]["fileName"],
        "2026-08-22T17:59:00Z",
    )
    early_inputs["log_raw"] = log(
        DMG_ID,
        early_inputs["upload"]["fileName"],
        DMG_DIGEST,
        "2026-08-22T17:59:02Z",
    )
    early_disk = compose_phase(phase="diskImage", **early_inputs)
    require_failure(
        lambda: compose_record(
            release=release,
            source=source,
            created="2026-08-22T18:06:00Z",
            application_phase=application,
            disk_image_phase=early_disk,
        ),
        "did not follow application acceptance",
    )

    require_failure(
        lambda: parse_accepted_info(
            b"x" * (MAX_RAW_BYTES + 1),
            phase="applicationArchive",
            upload=application_inputs["upload"],
            raw_path="notarization/oversized-info.json",
        ),
        "size is outside",
    )

    print(
        "Validated two distinct accepted app-archive and disk-image notarization "
        "correlations, exact upload hashes, warning-free logs, temporal ordering, "
        "and immutable construction-only gate state."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
