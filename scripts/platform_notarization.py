#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime
from typing import Any

from artifact_sbom import (
    ArtifactSBOMError,
    canonical_bytes,
    closed_pairs,
    parse_timestamp,
    safe_relative_path,
)


SCHEMA = "maccompanion.platform-notarization-evidence.v0.1"
PRODUCT = "Mac Companion"
EVIDENCE_LEVEL = "acceptedCorrelationConstructionOnly"
MAX_RAW_BYTES = 2 * 1024 * 1024
MAX_RECORD_BYTES = 4 * 1024 * 1024
MAX_UPLOAD_BYTES = 8 * 1024 * 1024 * 1024
MAX_TICKETS = 4096
SHA256 = re.compile(r"^[0-9a-f]{64}$")
UUID = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)
BUILD = re.compile(r"^(?:0|[1-9][0-9]{0,17})$")
VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$")
APPLE_TIME = re.compile(
    r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}"
    r"(?:\.[0-9]{1,9})?Z$"
)

ROOT_KEYS = {
    "schemaVersion",
    "product",
    "evidenceLevel",
    "release",
    "source",
    "created",
    "phases",
    "unresolvedGates",
    "platformAcceptanceEligible",
}
RELEASE_KEYS = {"version", "buildNumber", "targets"}
SOURCE_KEYS = {"revision", "dirty"}
PHASE_KEYS = {
    "phase",
    "subjectArtifactID",
    "mutationStage",
    "submissionID",
    "upload",
    "acceptedStatus",
    "info",
    "log",
    "platformAcceptanceEligible",
}
UPLOAD_KEYS = {"fileName", "bytes", "sha256"}
RAW_REFERENCE_KEYS = {"path", "bytes", "sha256"}
INFO_KEYS = {"createdDate", "id", "name", "status"}
LOG_KEYS = {
    "archiveFilename",
    "issues",
    "jobId",
    "logFormatVersion",
    "sha256",
    "status",
    "statusCode",
    "statusSummary",
    "ticketContents",
    "uploadDate",
}
INFO_SUMMARY_KEYS = {"createdDate", "name", "status", "raw"}
LOG_SUMMARY_KEYS = {
    "uploadDate",
    "archiveFilename",
    "status",
    "statusSummary",
    "statusCode",
    "sha256",
    "issueCount",
    "ticketCount",
    "raw",
}

PHASE_PROFILE = {
    "applicationArchive": {
        "artifactID": "mac-app",
        "suffix": ".zip",
        "mutationStage": "beforeApplicationStaple",
    },
    "diskImage": {
        "artifactID": "mac-dmg",
        "suffix": ".dmg",
        "mutationStage": "beforeDiskImageStaple",
    },
}

UNRESOLVED_GATES = sorted({
    "applicationStapleTransitionRequired",
    "postStapleArchiveConstructionRequired",
    "diskImageStapleTransitionRequired",
    "finalArtifactCorrelationRequired",
    "gatekeeperAssessmentRequired",
    "packagingEquivalenceRequired",
    "stableReleaseToolchainRequired",
    "physicalMatrixRequired",
    "humanPromotionApprovalRequired",
})


class PlatformNotarizationError(ValueError):
    pass


def _closed(value: Any, keys: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise PlatformNotarizationError(f"{label} is not closed")
    return value


def _parse_apple_time(value: Any, label: str) -> datetime:
    if not isinstance(value, str) or APPLE_TIME.fullmatch(value) is None:
        raise PlatformNotarizationError(f"{label} is not a bounded Apple UTC time")
    try:
        return datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as error:
        raise PlatformNotarizationError(f"{label} is not a real Apple UTC time") from error


def _parse_raw_json(raw: bytes, label: str) -> dict[str, Any]:
    if not 0 < len(raw) <= MAX_RAW_BYTES:
        raise PlatformNotarizationError(f"{label} size is outside the profile")
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=closed_pairs)
    except (UnicodeDecodeError, json.JSONDecodeError, ArtifactSBOMError) as error:
        raise PlatformNotarizationError(f"{label} is not duplicate-safe UTF-8 JSON") from error
    if not isinstance(value, dict):
        raise PlatformNotarizationError(f"{label} root is not an object")
    return value


def _raw_reference(path: str, raw: bytes) -> dict[str, Any]:
    try:
        safe_relative_path(path, "notarization raw evidence path")
    except ArtifactSBOMError as error:
        raise PlatformNotarizationError("notarization raw evidence path is unsafe") from error
    if not 0 < len(raw) <= MAX_RAW_BYTES:
        raise PlatformNotarizationError("notarization raw evidence size is outside the profile")
    return {
        "path": path,
        "bytes": len(raw),
        "sha256": hashlib.sha256(raw).hexdigest(),
    }


def _validate_raw_reference(value: Any, label: str) -> dict[str, Any]:
    reference = _closed(value, RAW_REFERENCE_KEYS, label)
    try:
        safe_relative_path(reference.get("path"), f"{label} path")
    except ArtifactSBOMError as error:
        raise PlatformNotarizationError(f"{label} path is unsafe") from error
    if (
        not isinstance(reference.get("bytes"), int)
        or isinstance(reference.get("bytes"), bool)
        or not 0 < reference["bytes"] <= MAX_RAW_BYTES
        or not isinstance(reference.get("sha256"), str)
        or SHA256.fullmatch(reference["sha256"]) is None
    ):
        raise PlatformNotarizationError(f"{label} is invalid")
    return dict(reference)


def _upload(value: Any, phase: str) -> dict[str, Any]:
    upload = _closed(value, UPLOAD_KEYS, "notarization upload binding")
    file_name = upload.get("fileName")
    expected_suffix = PHASE_PROFILE[phase]["suffix"]
    if (
        not isinstance(file_name, str)
        or not file_name
        or len(file_name.encode("utf-8")) > 255
        or "/" in file_name
        or "\\" in file_name
        or any(ord(character) < 32 or ord(character) == 127 for character in file_name)
        or not file_name.lower().endswith(expected_suffix)
    ):
        raise PlatformNotarizationError("notarization upload name is outside its phase")
    byte_count = upload.get("bytes")
    digest = upload.get("sha256")
    if (
        not isinstance(byte_count, int)
        or isinstance(byte_count, bool)
        or not 0 < byte_count <= MAX_UPLOAD_BYTES
        or not isinstance(digest, str)
        or SHA256.fullmatch(digest) is None
        or len(set(digest)) == 1
    ):
        raise PlatformNotarizationError("notarization upload binding is invalid")
    return dict(upload)


def _submission_id(value: Any, label: str) -> str:
    if not isinstance(value, str):
        raise PlatformNotarizationError(f"{label} is not a UUID")
    normalized = value.lower()
    if UUID.fullmatch(normalized) is None:
        raise PlatformNotarizationError(f"{label} is not a UUID")
    return normalized


def parse_accepted_info(
    raw: bytes,
    *,
    phase: str,
    upload: dict[str, Any],
    raw_path: str,
) -> tuple[str, dict[str, Any]]:
    if phase not in PHASE_PROFILE:
        raise PlatformNotarizationError("notarization phase is unsupported")
    bound_upload = _upload(upload, phase)
    info = _closed(_parse_raw_json(raw, "notary info"), INFO_KEYS, "notary info")
    submission_id = _submission_id(info.get("id"), "notary info submission ID")
    _parse_apple_time(info.get("createdDate"), "notary info created date")
    if info.get("name") != bound_upload["fileName"]:
        raise PlatformNotarizationError("notary info name does not bind the upload")
    if info.get("status") != "Accepted":
        raise PlatformNotarizationError("notary info status is not Accepted")
    return submission_id, {
        "createdDate": info["createdDate"],
        "name": info["name"],
        "status": "Accepted",
        "raw": _raw_reference(raw_path, raw),
    }


def parse_accepted_log(
    raw: bytes,
    *,
    phase: str,
    upload: dict[str, Any],
    submission_id: str,
    raw_path: str,
) -> dict[str, Any]:
    if phase not in PHASE_PROFILE:
        raise PlatformNotarizationError("notarization phase is unsupported")
    bound_upload = _upload(upload, phase)
    normalized_submission = _submission_id(submission_id, "notary log submission ID")
    log = _closed(_parse_raw_json(raw, "notary log"), LOG_KEYS, "notary log")
    if _submission_id(log.get("jobId"), "notary log job ID") != normalized_submission:
        raise PlatformNotarizationError("notary log job does not match the submission")
    _parse_apple_time(log.get("uploadDate"), "notary log upload date")
    if (
        log.get("logFormatVersion") != 1
        or log.get("archiveFilename") != bound_upload["fileName"]
        or log.get("status") != "Accepted"
        or log.get("statusSummary") != "Ready for distribution"
        or log.get("statusCode") != 0
        or log.get("sha256") != bound_upload["sha256"]
    ):
        raise PlatformNotarizationError("notary log does not bind an accepted upload")
    issues = log.get("issues")
    if issues not in (None, []):
        raise PlatformNotarizationError("accepted notary log contains issues")
    tickets = log.get("ticketContents")
    if (
        not isinstance(tickets, list)
        or not 0 < len(tickets) <= MAX_TICKETS
        or any(not isinstance(item, dict) or not item for item in tickets)
    ):
        raise PlatformNotarizationError("accepted notary log ticket set is invalid")
    return {
        "uploadDate": log["uploadDate"],
        "archiveFilename": log["archiveFilename"],
        "status": "Accepted",
        "statusSummary": "Ready for distribution",
        "statusCode": 0,
        "sha256": log["sha256"],
        "issueCount": 0,
        "ticketCount": len(tickets),
        "raw": _raw_reference(raw_path, raw),
    }


def compose_phase(
    *,
    phase: str,
    upload: dict[str, Any],
    info_raw: bytes,
    info_path: str,
    log_raw: bytes,
    log_path: str,
) -> dict[str, Any]:
    if phase not in PHASE_PROFILE:
        raise PlatformNotarizationError("notarization phase is unsupported")
    bound_upload = _upload(upload, phase)
    submission_id, info = parse_accepted_info(
        info_raw,
        phase=phase,
        upload=bound_upload,
        raw_path=info_path,
    )
    log = parse_accepted_log(
        log_raw,
        phase=phase,
        upload=bound_upload,
        submission_id=submission_id,
        raw_path=log_path,
    )
    if _parse_apple_time(log["uploadDate"], "notary log upload date") < _parse_apple_time(
        info["createdDate"], "notary info created date"
    ):
        raise PlatformNotarizationError("notary phase timestamps are reversed")
    profile = PHASE_PROFILE[phase]
    return {
        "phase": phase,
        "subjectArtifactID": profile["artifactID"],
        "mutationStage": profile["mutationStage"],
        "submissionID": submission_id,
        "upload": bound_upload,
        "acceptedStatus": True,
        "info": info,
        "log": log,
        "platformAcceptanceEligible": False,
    }


def compose_record(
    *,
    release: dict[str, Any],
    source: dict[str, Any],
    created: str,
    application_phase: dict[str, Any],
    disk_image_phase: dict[str, Any],
) -> dict[str, Any]:
    release = _closed(release, RELEASE_KEYS, "notarization release")
    source = _closed(source, SOURCE_KEYS, "notarization source")
    try:
        parse_timestamp(created)
    except ArtifactSBOMError as error:
        raise PlatformNotarizationError("notarization record time is invalid") from error
    if (
        not isinstance(release.get("version"), str)
        or VERSION.fullmatch(release["version"]) is None
        or not isinstance(release.get("buildNumber"), str)
        or BUILD.fullmatch(release["buildNumber"]) is None
        or release.get("targets") != ["macOS"]
        or not isinstance(source.get("revision"), str)
        or re.fullmatch(r"[0-9a-f]{40}", source["revision"]) is None
        or source.get("dirty") is not False
    ):
        raise PlatformNotarizationError("notarization release or source binding is invalid")
    application = _closed(application_phase, PHASE_KEYS, "application notarization phase")
    disk_image = _closed(disk_image_phase, PHASE_KEYS, "disk-image notarization phase")
    if (
        application.get("phase") != "applicationArchive"
        or disk_image.get("phase") != "diskImage"
        or application.get("subjectArtifactID") != "mac-app"
        or disk_image.get("subjectArtifactID") != "mac-dmg"
        or application.get("mutationStage") != "beforeApplicationStaple"
        or disk_image.get("mutationStage") != "beforeDiskImageStaple"
        or application.get("platformAcceptanceEligible") is not False
        or disk_image.get("platformAcceptanceEligible") is not False
        or application.get("submissionID") == disk_image.get("submissionID")
    ):
        raise PlatformNotarizationError("two-phase notarization ordering is invalid")
    for phase in (application, disk_image):
        bound_upload = _upload(phase.get("upload"), phase["phase"])
        _submission_id(phase.get("submissionID"), "notary phase submission ID")
        if phase.get("acceptedStatus") is not True:
            raise PlatformNotarizationError("notary phase is not accepted")
        info = _closed(phase.get("info"), INFO_SUMMARY_KEYS, "notary info summary")
        log = _closed(phase.get("log"), LOG_SUMMARY_KEYS, "notary log summary")
        _parse_apple_time(info.get("createdDate"), "notary info created date")
        _parse_apple_time(log.get("uploadDate"), "notary log upload date")
        if (
            info.get("name") != bound_upload["fileName"]
            or info.get("status") != "Accepted"
            or log.get("archiveFilename") != bound_upload["fileName"]
            or log.get("status") != "Accepted"
            or log.get("statusSummary") != "Ready for distribution"
            or log.get("statusCode") != 0
            or log.get("sha256") != bound_upload["sha256"]
            or log.get("issueCount") != 0
            or not isinstance(log.get("ticketCount"), int)
            or isinstance(log.get("ticketCount"), bool)
            or not 0 < log["ticketCount"] <= MAX_TICKETS
        ):
            raise PlatformNotarizationError("notary phase summary is invalid")
        _validate_raw_reference(info.get("raw"), "notary info raw reference")
        _validate_raw_reference(log.get("raw"), "notary log raw reference")
    if _parse_apple_time(
        disk_image["info"]["createdDate"], "disk-image notary created date"
    ) <= _parse_apple_time(
        application["log"]["uploadDate"], "application notary upload date"
    ):
        raise PlatformNotarizationError("disk-image notarization did not follow application acceptance")
    record = {
        "schemaVersion": SCHEMA,
        "product": PRODUCT,
        "evidenceLevel": EVIDENCE_LEVEL,
        "release": dict(release),
        "source": dict(source),
        "created": created,
        "phases": [dict(application), dict(disk_image)],
        "unresolvedGates": UNRESOLVED_GATES,
        "platformAcceptanceEligible": False,
    }
    if len(canonical_bytes(record)) > MAX_RECORD_BYTES:
        raise PlatformNotarizationError("notarization record exceeds the canonical size bound")
    return record


def validate_record(
    value: Any,
    *,
    release: dict[str, Any],
    source: dict[str, Any],
    application_inputs: dict[str, Any],
    disk_image_inputs: dict[str, Any],
) -> dict[str, Any]:
    root = _closed(value, ROOT_KEYS, "platform notarization record")
    if (
        root.get("schemaVersion") != SCHEMA
        or root.get("product") != PRODUCT
        or root.get("evidenceLevel") != EVIDENCE_LEVEL
        or root.get("platformAcceptanceEligible") is not False
        or root.get("unresolvedGates") != UNRESOLVED_GATES
    ):
        raise PlatformNotarizationError("platform notarization identity or gate state is invalid")
    phases = root.get("phases")
    if not isinstance(phases, list) or len(phases) != 2:
        raise PlatformNotarizationError("platform notarization phase set is invalid")
    expected_application = compose_phase(phase="applicationArchive", **application_inputs)
    expected_disk_image = compose_phase(phase="diskImage", **disk_image_inputs)
    expected = compose_record(
        release=release,
        source=source,
        created=root["created"],
        application_phase=expected_application,
        disk_image_phase=expected_disk_image,
    )
    if canonical_bytes(root) != canonical_bytes(expected):
        raise PlatformNotarizationError("platform notarization record differs from exact recomposition")
    return root
