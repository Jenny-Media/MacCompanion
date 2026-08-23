#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import re
import zipfile
from datetime import datetime
from pathlib import Path, PurePosixPath
from typing import Any

from artifact_sbom import (
    ArtifactSBOMError,
    digest_file,
    resolve_inside as resolve_artifact_path,
    validate_bundle as validate_artifact_bundle,
    validate_release_binding,
)
from mac_packaging_equivalence import (
    MacPackagingEquivalenceError,
    inspect_dmg,
    load_canonical_receipt_with_bytes,
    validate_receipt,
)
from mac_lifecycle_physical_evidence import (
    MacLifecyclePhysicalEvidenceError,
    load_canonical_record as load_mac_lifecycle_physical_record,
    validate_record as validate_mac_lifecycle_physical_record,
)
from mac_update_physical_evidence import (
    MacUpdatePhysicalEvidenceError,
    load_canonical_record as load_mac_update_physical_record,
    validate_record as validate_mac_update_physical_record,
)
from signed_code_verification import (
    SignedCodeVerificationError,
    load_bundle as load_signed_code_bundle,
    validate_bundle as validate_signed_code_bundle,
)
from signed_code_graph import (
    SignedCodeGraphError,
    load_graph as load_signed_code_graph,
    validate_graph as validate_signed_code_graph,
)
from signing_policy import (
    SigningPolicyDigestMismatch,
    SigningPolicyError,
    load_pinned_policy,
)
from signing_policy_binding import validate_policy_binding


class DuplicateKeyError(ValueError):
    pass


def closed_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKeyError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


IDENTIFIER = re.compile(r"^[a-z0-9](?:[a-z0-9.-]{0,62}[a-z0-9])?$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
GIT_SHA = re.compile(r"^[0-9a-f]{40}$")
VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$")
PROFILE_VERSION = re.compile(r"^[0-9]+\.[0-9]+$")
MAC_USER_INITIATED_UPDATE_CHECK_PROFILE = (
    "maccompanion.user-initiated-full-update-check.v1"
)
MAC_INFO_PLIST_MEMBER = "Mac Companion.app/Contents/Info.plist"
MAX_MAC_INFO_PLIST_BYTES = 1024 * 1024
BUILD = re.compile(r"^(?:0|[1-9][0-9]{0,17})$")
MAC_BUNDLE_ID = re.compile(
    r"^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$"
)
UTC_TIME = re.compile(
    r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
)
NOTARY_ID = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)

LEVELS = {"unsignedConstruction", "signedCandidate", "promotionReady"}
CHANNELS = {"development", "internal", "beta", "stable"}
TARGETS = {"macOS", "iOS"}
ARTIFACT_KINDS = {
    "macApplication",
    "macDiskImage",
    "sparkleArchive",
    "iosArchive",
    "other",
}
EXECUTABLE_ROLES = {"macApp", "agent", "cli", "iosApp", "other"}
PLATFORMS = {"macOS", "iOS"}
STATUSES = {"passed", "failed"}
PUBLICATION_TARGETS = {"sparkle", "testFlightOrAppStore"}

ROOT_FIELDS = {
    "schemaVersion",
    "evidenceLevel",
    "product",
    "release",
    "compatibility",
    "source",
    "toolchain",
    "validation",
    "artifacts",
    "executables",
    "notarization",
    "sbom",
    "physicalScenarios",
    "promotion",
}
EVIDENCE_FIELDS = {"path", "sha256", "bytes"}


def add(errors: set[str], code: str) -> None:
    errors.add(code)


def closed_object(
    value: Any,
    fields: set[str],
    errors: set[str],
    *,
    nullable: bool = False,
) -> dict[str, Any] | None:
    if value is None and nullable:
        return None
    if not isinstance(value, dict):
        add(errors, "invalidType")
        return None
    if set(value) != fields:
        if set(value) - fields:
            add(errors, "unknownField")
        if fields - set(value):
            add(errors, "missingField")
    return value


def bounded_string(value: Any, errors: set[str], maximum: int = 128) -> str | None:
    if not isinstance(value, str) or not value or len(value) > maximum:
        add(errors, "invalidString")
        return None
    return value


def relative_path(value: Any, errors: set[str], *, nullable: bool = False) -> None:
    if value is None and nullable:
        return
    text = bounded_string(value, errors, 512)
    if text is None:
        return
    path = PurePosixPath(text)
    segments = text.split("/")
    if (
        path.is_absolute()
        or "\\" in text
        or any(segment in {"", ".", ".."} for segment in segments)
        or any(ord(character) < 32 or ord(character) == 127 for character in text)
    ):
        add(errors, "unsafePath")


def identifier(value: Any, errors: set[str]) -> str | None:
    text = bounded_string(value, errors, 64)
    if text is not None and not IDENTIFIER.fullmatch(text):
        add(errors, "invalidIdentifier")
        return None
    return text


def digest(value: Any, errors: set[str]) -> None:
    if not isinstance(value, str) or not SHA256.fullmatch(value):
        add(errors, "invalidDigest")
    elif len(set(value)) == 1:
        add(errors, "placeholderDigest")


def evidence_reference(
    value: Any,
    errors: set[str],
    *,
    nullable: bool = False,
) -> dict[str, Any] | None:
    obj = closed_object(value, EVIDENCE_FIELDS, errors, nullable=nullable)
    if obj is None:
        return None
    relative_path(obj.get("path"), errors)
    digest(obj.get("sha256"), errors)
    size = obj.get("bytes")
    if not isinstance(size, int) or isinstance(size, bool) or size <= 0:
        add(errors, "invalidByteCount")
    return obj


def scan_for_secrets(value: Any, errors: set[str]) -> None:
    forbidden_keys = {
        "secret",
        "password",
        "privatekey",
        "apikey",
        "credential",
        "credentials",
        "provisioningprofile",
    }
    forbidden_suffixes = (
        ".p8",
        ".p12",
        ".mobileprovision",
        ".provisionprofile",
    )
    if isinstance(value, dict):
        for key, child in value.items():
            normalized = re.sub(r"[^a-z]", "", key.lower())
            if normalized in forbidden_keys:
                add(errors, "forbiddenSecretField")
            scan_for_secrets(child, errors)
    elif isinstance(value, list):
        for child in value:
            scan_for_secrets(child, errors)
    elif isinstance(value, str):
        lowered = value.lower()
        if "-----begin" in lowered and "private key-----" in lowered:
            add(errors, "forbiddenSecretMaterial")
        if lowered.endswith(forbidden_suffixes):
            add(errors, "forbiddenSecretMaterial")


def validate_release(value: Any, errors: set[str]) -> tuple[set[str], str | None]:
    obj = closed_object(
        value,
        {"version", "buildNumber", "channel", "targets"},
        errors,
    )
    if obj is None:
        return set(), None
    version = obj.get("version")
    if not isinstance(version, str) or not VERSION.fullmatch(version):
        add(errors, "invalidVersion")
    build = obj.get("buildNumber")
    if not isinstance(build, str) or not BUILD.fullmatch(build):
        add(errors, "invalidBuildNumber")
    channel = obj.get("channel")
    if channel not in CHANNELS:
        add(errors, "invalidChannel")
        channel = None
    targets_value = obj.get("targets")
    targets: set[str] = set()
    if not isinstance(targets_value, list) or not 1 <= len(targets_value) <= 2:
        add(errors, "invalidTargets")
    else:
        for target in targets_value:
            if target not in TARGETS:
                add(errors, "invalidTargets")
            elif target in targets:
                add(errors, "duplicateValue")
            targets.add(target)
    return targets, channel


def validate_source(value: Any, errors: set[str]) -> bool | None:
    obj = closed_object(value, {"revision", "dirty"}, errors)
    if obj is None:
        return None
    revision = obj.get("revision")
    if not isinstance(revision, str) or not GIT_SHA.fullmatch(revision):
        add(errors, "invalidRevision")
    elif len(set(revision)) == 1:
        add(errors, "placeholderRevision")
    dirty = obj.get("dirty")
    if not isinstance(dirty, bool):
        add(errors, "invalidType")
        return None
    return dirty


def validate_compatibility(
    value: Any,
    targets: set[str],
    errors: set[str],
) -> None:
    obj = closed_object(
        value,
        {
            "capabilityProtocol",
            "interactiveControl",
            "localIPC",
            "macUserInitiatedUpdateCheckProfile",
            "minimumMacOS",
            "minimumIOS",
        },
        errors,
    )
    if obj is None:
        return
    for key in ("capabilityProtocol", "interactiveControl", "localIPC"):
        version = obj.get(key)
        if not isinstance(version, str) or not PROFILE_VERSION.fullmatch(version):
            add(errors, "invalidCompatibility")
    update_profile = obj.get("macUserInitiatedUpdateCheckProfile")
    if "macOS" in targets:
        if (
            update_profile is not None
            and update_profile != MAC_USER_INITIATED_UPDATE_CHECK_PROFILE
        ):
            add(errors, "invalidCompatibility")
    elif update_profile is not None:
        add(errors, "inapplicableCompatibility")
    for target, key in (("macOS", "minimumMacOS"), ("iOS", "minimumIOS")):
        version = obj.get(key)
        if target in targets:
            if not isinstance(version, str) or not PROFILE_VERSION.fullmatch(version):
                add(errors, "invalidCompatibility")
        elif version is not None:
            add(errors, "inapplicableCompatibility")


def validate_toolchain(value: Any, errors: set[str]) -> None:
    obj = closed_object(
        value,
        {"xcodeVersion", "swiftVersion", "hostOSVersion", "sdkVersions"},
        errors,
    )
    if obj is None:
        return
    for key in ("xcodeVersion", "swiftVersion", "hostOSVersion"):
        bounded_string(obj.get(key), errors, 192)
    sdks = obj.get("sdkVersions")
    if not isinstance(sdks, list) or not 1 <= len(sdks) <= 8:
        add(errors, "invalidSDKs")
        return
    seen: set[str] = set()
    for sdk in sdks:
        text = bounded_string(sdk, errors, 64)
        if text is not None and text in seen:
            add(errors, "duplicateValue")
        if text is not None:
            seen.add(text)


def validate_records(
    value: Any,
    fields: set[str],
    errors: set[str],
    *,
    maximum: int,
    platform: bool = False,
) -> tuple[list[dict[str, Any]], dict[str, str]]:
    if not isinstance(value, list) or len(value) > maximum:
        add(errors, "invalidArray")
        return [], {}
    records: list[dict[str, Any]] = []
    statuses: dict[str, str] = {}
    for item in value:
        obj = closed_object(item, fields, errors)
        if obj is None:
            continue
        record_id = identifier(obj.get("id"), errors)
        if record_id is not None:
            if record_id in statuses:
                add(errors, "duplicateIdentifier")
            statuses[record_id] = obj.get("status", "")
        if obj.get("status") not in STATUSES:
            add(errors, "invalidStatus")
        if platform and obj.get("platform") not in PLATFORMS:
            add(errors, "invalidPlatform")
        evidence_reference(obj.get("evidence"), errors)
        records.append(obj)
    return records, statuses


def validate_artifacts(
    value: Any,
    targets: set[str],
    errors: set[str],
) -> tuple[dict[str, dict[str, Any]], set[str]]:
    if not isinstance(value, list) or len(value) > 32:
        add(errors, "invalidArray")
        return {}, set()
    artifacts: dict[str, dict[str, Any]] = {}
    kinds: set[str] = set()
    fields = {"id", "kind", "path", "sha256", "bytes"}
    for item in value:
        obj = closed_object(item, fields, errors)
        if obj is None:
            continue
        artifact_id = identifier(obj.get("id"), errors)
        if artifact_id is not None:
            if artifact_id in artifacts:
                add(errors, "duplicateIdentifier")
            artifacts[artifact_id] = obj
        kind = obj.get("kind")
        if kind not in ARTIFACT_KINDS:
            add(errors, "invalidArtifactKind")
        else:
            kinds.add(kind)
            if kind in {"macApplication", "macDiskImage", "sparkleArchive"}:
                if "macOS" not in targets:
                    add(errors, "artifactTargetMismatch")
            if kind == "iosArchive" and "iOS" not in targets:
                add(errors, "artifactTargetMismatch")
        relative_path(obj.get("path"), errors)
        digest(obj.get("sha256"), errors)
        size = obj.get("bytes")
        if not isinstance(size, int) or isinstance(size, bool) or size <= 0:
            add(errors, "invalidByteCount")
    return artifacts, kinds


def validate_executables(
    value: Any,
    artifacts: dict[str, dict[str, Any]],
    targets: set[str],
    errors: set[str],
) -> tuple[set[str], list[dict[str, Any]]]:
    if not isinstance(value, list) or len(value) > 32:
        add(errors, "invalidArray")
        return set(), []
    fields = {
        "id",
        "role",
        "platform",
        "bundleIdentifier",
        "artifactID",
        "relativePath",
        "signed",
        "verificationBundle",
    }
    seen: set[str] = set()
    seen_subjects: set[tuple[Any, Any]] = set()
    roles: set[str] = set()
    records: list[dict[str, Any]] = []
    for item in value:
        obj = closed_object(item, fields, errors)
        if obj is None:
            continue
        executable_id = identifier(obj.get("id"), errors)
        if executable_id is not None:
            if executable_id in seen:
                add(errors, "duplicateIdentifier")
            seen.add(executable_id)
        role = obj.get("role")
        if role not in EXECUTABLE_ROLES:
            add(errors, "invalidExecutableRole")
        else:
            roles.add(role)
        if obj.get("platform") not in PLATFORMS:
            add(errors, "invalidPlatform")
        elif obj.get("platform") not in targets:
            add(errors, "executableTargetMismatch")
        bundle_identifier = obj.get("bundleIdentifier")
        if (
            not isinstance(bundle_identifier, str)
            or len(bundle_identifier) > 255
            or not MAC_BUNDLE_ID.fullmatch(bundle_identifier)
        ):
            add(errors, "invalidBundleIdentifier")
        artifact_id = obj.get("artifactID")
        subject = (artifact_id, obj.get("relativePath"))
        if subject in seen_subjects:
            add(errors, "duplicateExecutableSubject")
        seen_subjects.add(subject)
        if artifact_id not in artifacts:
            add(errors, "danglingReference")
        else:
            artifact_kind = artifacts[artifact_id].get("kind")
            if obj.get("platform") == "macOS" and artifact_kind != "macApplication":
                add(errors, "artifactPlatformMismatch")
            if obj.get("platform") == "iOS" and artifact_kind != "iosArchive":
                add(errors, "artifactPlatformMismatch")
        if role in {"macApp", "agent", "cli"} and obj.get("platform") != "macOS":
            add(errors, "rolePlatformMismatch")
        if role == "iosApp" and obj.get("platform") != "iOS":
            add(errors, "rolePlatformMismatch")
        relative_path(obj.get("relativePath"), errors)
        evidence_reference(obj.get("verificationBundle"), errors)
        if not isinstance(obj.get("signed"), bool):
            add(errors, "invalidType")
        records.append(obj)
    return roles, records


def validate_notarization(
    value: Any,
    artifact_ids: set[str],
    errors: set[str],
) -> dict[str, Any] | None:
    obj = closed_object(
        value,
        {"evidence", "acceptedSubmissionIDs", "stapledArtifactIDs"},
        errors,
        nullable=True,
    )
    if obj is None:
        return None
    evidence_reference(obj.get("evidence"), errors)
    submissions = obj.get("acceptedSubmissionIDs")
    if not isinstance(submissions, list) or len(submissions) != 2:
        add(errors, "invalidNotarySubmissions")
    else:
        seen_submissions: set[str] = set()
        for submission in submissions:
            if not isinstance(submission, str) or not NOTARY_ID.fullmatch(submission):
                add(errors, "invalidNotaryID")
            if submission in seen_submissions:
                add(errors, "duplicateValue")
            seen_submissions.add(submission)
    stapled = obj.get("stapledArtifactIDs")
    if not isinstance(stapled, list) or len(stapled) > 16:
        add(errors, "invalidArray")
    else:
        seen: set[str] = set()
        for artifact_id in stapled:
            if artifact_id not in artifact_ids:
                add(errors, "danglingReference")
            if artifact_id in seen:
                add(errors, "duplicateValue")
            seen.add(artifact_id)
    return obj


def validate_sbom(value: Any, errors: set[str]) -> dict[str, Any] | None:
    obj = closed_object(
        value,
        {"document", "licenses"},
        errors,
        nullable=True,
    )
    if obj is None:
        return None
    evidence_reference(obj.get("document"), errors)
    evidence_reference(obj.get("licenses"), errors)
    return obj


def validate_promotion(value: Any, errors: set[str]) -> dict[str, Any] | None:
    obj = closed_object(
        value,
        {
            "approvedAt",
            "approvalEvidence",
            "publicationTargets",
            "sparkleAppcastEvidence",
            "sparkleSignatureEvidence",
            "appStoreEvidence",
        },
        errors,
        nullable=True,
    )
    if obj is None:
        return None
    approved_at = obj.get("approvedAt")
    if not isinstance(approved_at, str) or not UTC_TIME.fullmatch(approved_at):
        add(errors, "invalidApprovalTime")
    else:
        try:
            datetime.strptime(approved_at, "%Y-%m-%dT%H:%M:%SZ")
        except ValueError:
            add(errors, "invalidApprovalTime")
    evidence_reference(obj.get("approvalEvidence"), errors)
    targets = obj.get("publicationTargets")
    if not isinstance(targets, list) or not 1 <= len(targets) <= 2:
        add(errors, "invalidPublicationTargets")
    else:
        seen: set[str] = set()
        for target in targets:
            if target not in PUBLICATION_TARGETS:
                add(errors, "invalidPublicationTargets")
            if target in seen:
                add(errors, "duplicateValue")
            seen.add(target)
    evidence_reference(obj.get("sparkleAppcastEvidence"), errors, nullable=True)
    evidence_reference(obj.get("sparkleSignatureEvidence"), errors, nullable=True)
    evidence_reference(obj.get("appStoreEvidence"), errors, nullable=True)
    return obj


def validate_manifest(value: Any) -> set[str]:
    errors: set[str] = set()
    scan_for_secrets(value, errors)
    root = closed_object(value, ROOT_FIELDS, errors)
    if root is None:
        return errors

    if root.get("schemaVersion") != "0.2":
        add(errors, "invalidSchemaVersion")
    level = root.get("evidenceLevel")
    if level not in LEVELS:
        add(errors, "invalidEvidenceLevel")
        level = None
    if root.get("product") != "Mac Companion":
        add(errors, "invalidProduct")

    targets, channel = validate_release(root.get("release"), errors)
    validate_compatibility(root.get("compatibility"), targets, errors)
    dirty = validate_source(root.get("source"), errors)
    validate_toolchain(root.get("toolchain"), errors)
    validation, validation_statuses = validate_records(
        root.get("validation"),
        {"id", "status", "evidence"},
        errors,
        maximum=64,
    )
    if not validation:
        add(errors, "missingValidation")
    artifacts, artifact_kinds = validate_artifacts(
        root.get("artifacts"), targets, errors
    )
    executable_roles, executables = validate_executables(
        root.get("executables"), artifacts, targets, errors
    )
    notarization = validate_notarization(
        root.get("notarization"), set(artifacts), errors
    )
    sbom = validate_sbom(root.get("sbom"), errors)
    scenarios, scenario_statuses = validate_records(
        root.get("physicalScenarios"),
        {"id", "platform", "status", "evidence"},
        errors,
        maximum=64,
        platform=True,
    )
    promotion = validate_promotion(root.get("promotion"), errors)

    if level == "unsignedConstruction":
        if artifacts or executables or scenarios:
            add(errors, "unsignedEvidenceBroadened")
        if notarization is not None or sbom is not None or promotion is not None:
            add(errors, "unsignedEvidenceBroadened")
        if any(record.get("id") == "signing-policy-contract" for record in validation):
            add(errors, "unsignedEvidenceBroadened")
        return errors

    if level in {"signedCandidate", "promotionReady"}:
        policy_records = [
            record for record in validation
            if record.get("id") == "signing-policy-contract"
        ]
        if not policy_records:
            add(errors, "missingSigningPolicy")
        elif len(policy_records) != 1 or policy_records[0].get("status") != "passed":
            add(errors, "invalidSigningPolicy")
        if dirty is not False:
            add(errors, "dirtySignedCandidate")
        if any(status != "passed" for status in validation_statuses.values()):
            add(errors, "failedValidation")
        if sbom is None:
            add(errors, "missingSBOM")
        if any(record.get("signed") is not True for record in executables):
            add(errors, "unsignedExecutable")

        if "macOS" in targets:
            if not {"macApplication", "macDiskImage", "sparkleArchive"}.issubset(
                artifact_kinds
            ):
                add(errors, "missingMacArtifacts")
            if not {"macApp", "agent"}.issubset(executable_roles):
                add(errors, "missingMacExecutables")
            if notarization is None:
                add(errors, "missingAcceptedNotarization")
            else:
                stapled = set(notarization.get("stapledArtifactIDs", []))
                required_stapled = {
                    artifact_id
                    for artifact_id, artifact in artifacts.items()
                    if artifact.get("kind") in {"macApplication", "macDiskImage"}
                }
                if not required_stapled.issubset(stapled):
                    add(errors, "missingStapling")
        elif notarization is not None:
            add(errors, "unexpectedNotarization")

        if "iOS" in targets:
            if "iosArchive" not in artifact_kinds:
                add(errors, "missingIOSArtifact")
            if "iosApp" not in executable_roles:
                add(errors, "missingIOSExecutable")

    if level == "signedCandidate":
        if promotion is not None:
            add(errors, "prematurePromotion")
        return errors

    if level == "promotionReady":
        if channel not in {"beta", "stable"}:
            add(errors, "invalidPromotionChannel")
        required_scenarios: set[str] = set()
        expected_publication: set[str] = set()
        if "macOS" in targets:
            required_scenarios.update(
                {
                    "clean-install",
                    "upgrade",
                    "rollback",
                    "permission-revocation",
                    "complete-uninstall",
                    "quarantine-launch",
                }
            )
            expected_publication.add("sparkle")
        if "iOS" in targets:
            required_scenarios.update(
                {
                    "physical-pairing",
                    "local-network-denial",
                    "background-reconnect",
                }
            )
            expected_publication.add("testFlightOrAppStore")
        if not required_scenarios.issubset(scenario_statuses):
            add(errors, "missingPhysicalScenario")
        scenario_platforms = {
            scenario.get("id"): scenario.get("platform") for scenario in scenarios
        }
        expected_scenario_platforms = {
            scenario: "macOS"
            for scenario in {
                "clean-install",
                "upgrade",
                "rollback",
                "permission-revocation",
                "complete-uninstall",
                "quarantine-launch",
            }
        }
        expected_scenario_platforms.update(
            {
                scenario: "iOS"
                for scenario in {
                    "physical-pairing",
                    "local-network-denial",
                    "background-reconnect",
                }
            }
        )
        if any(
            scenario_platforms.get(scenario)
            != expected_scenario_platforms[scenario]
            for scenario in required_scenarios
        ):
            add(errors, "scenarioPlatformMismatch")
        if any(
            scenario_statuses.get(scenario) != "passed"
            for scenario in required_scenarios
        ):
            add(errors, "failedPhysicalScenario")
        if any(status != "passed" for status in scenario_statuses.values()):
            add(errors, "failedPhysicalScenario")
        if promotion is None:
            add(errors, "missingPromotion")
        else:
            publication = set(promotion.get("publicationTargets", []))
            if publication != expected_publication:
                add(errors, "publicationTargetMismatch")
            if "macOS" in targets and (
                promotion.get("sparkleAppcastEvidence") is None
                or promotion.get("sparkleSignatureEvidence") is None
            ):
                add(errors, "missingSparkleEvidence")
            if "iOS" in targets and promotion.get("appStoreEvidence") is None:
                add(errors, "missingAppStoreEvidence")
        return errors

    return errors


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=closed_pairs)


def referenced_files(value: dict[str, Any]) -> list[dict[str, Any]]:
    references: list[dict[str, Any]] = []
    references.extend(
        record["evidence"]
        for record in value["validation"]
        if record.get("id") not in {"signed-code-graph-construction", "signing-policy-contract"}
    )
    references.extend(
        {
            "path": artifact["path"],
            "sha256": artifact["sha256"],
            "bytes": artifact["bytes"],
        }
        for artifact in value["artifacts"]
    )
    # Signed-code verification bundles and their transitive raw references are
    # intentionally excluded from this generic unbounded pass. Their dedicated
    # loader owns the 1 MiB cap, no-follow descriptor read, exact parsed-byte
    # reference comparison, and four 16 MiB raw-evidence caps.
    if value["notarization"] is not None:
        references.append(value["notarization"]["evidence"])
    if value["sbom"] is not None:
        references.append(value["sbom"]["document"])
        references.append(value["sbom"]["licenses"])
    references.extend(
        scenario["evidence"] for scenario in value["physicalScenarios"]
    )
    if value["promotion"] is not None:
        promotion = value["promotion"]
        references.append(promotion["approvalEvidence"])
        for key in (
            "sparkleAppcastEvidence",
            "sparkleSignatureEvidence",
            "appStoreEvidence",
        ):
            if promotion[key] is not None:
                references.append(promotion[key])
    return references


def _reference_matches(root: Path, reference: dict[str, Any]) -> bool:
    try:
        path = resolve_artifact_path(root, reference["path"], must_exist=True)
        if path.stat().st_size != reference["bytes"]:
            return False
        hasher = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                hasher.update(chunk)
        return hasher.hexdigest() == reference["sha256"]
    except (ArtifactSBOMError, OSError, KeyError, TypeError):
        return False


def _mac_user_initiated_update_check_profile(
    release_manifest: dict[str, Any],
    evidence_root: Path,
) -> str | None:
    matches = [
        artifact
        for artifact in release_manifest.get("artifacts", [])
        if isinstance(artifact, dict) and artifact.get("kind") == "macApplication"
    ]
    if len(matches) != 1:
        raise ValueError("release must contain exactly one Mac application archive")
    artifact = matches[0]
    archive_path = resolve_artifact_path(
        evidence_root,
        artifact["path"],
        must_exist=True,
    )
    before_digest, before_size = digest_file(archive_path)
    if (
        before_size != artifact.get("bytes")
        or before_digest != artifact.get("sha256")
    ):
        raise ValueError("Mac application archive binding mismatch")
    try:
        with zipfile.ZipFile(archive_path, "r") as archive:
            matches = [
                member
                for member in archive.infolist()
                if member.filename == MAC_INFO_PLIST_MEMBER
            ]
            if len(matches) != 1:
                raise ValueError("Mac application Info.plist is missing or ambiguous")
            member = matches[0]
            if not 0 < member.file_size <= MAX_MAC_INFO_PLIST_BYTES:
                raise ValueError("Mac application Info.plist is outside the size bound")
            with archive.open(member, "r") as handle:
                raw = handle.read(MAX_MAC_INFO_PLIST_BYTES + 1)
    except (OSError, RuntimeError, zipfile.BadZipFile, KeyError) as error:
        raise ValueError("cannot inspect Mac application Info.plist") from error
    if len(raw) != member.file_size or len(raw) > MAX_MAC_INFO_PLIST_BYTES:
        raise ValueError("Mac application Info.plist size changed during inspection")
    try:
        info = plistlib.loads(raw)
    except plistlib.InvalidFileException as error:
        raise ValueError("Mac application Info.plist is invalid") from error
    if not isinstance(info, dict):
        raise ValueError("Mac application Info.plist root is invalid")
    profile = info.get("MacCompanionUpdateUserInitiatedCheckProfile")
    if profile is None or profile == "":
        normalized_profile = None
    elif profile == MAC_USER_INITIATED_UPDATE_CHECK_PROFILE:
        normalized_profile = profile
    else:
        raise ValueError("Mac application update-check profile is invalid")
    after_digest, after_size = digest_file(archive_path)
    if (after_size, after_digest) != (before_size, before_digest):
        raise ValueError("Mac application archive changed during profile inspection")
    return normalized_profile


def verify_files(
    value: dict[str, Any],
    manifest_path: Path,
    *,
    verify_platform_packaging: bool = False,
    expected_signing_policy_sha256: str | None = None,
) -> set[str]:
    errors: set[str] = set()
    if (
        expected_signing_policy_sha256 is not None
        and value.get("evidenceLevel") not in {"signedCandidate", "promotionReady"}
    ):
        add(errors, "unexpectedSigningPolicyPin")
    root = manifest_path.resolve(strict=True).parent
    seen: set[tuple[str, str, int]] = set()
    for reference in referenced_files(value):
        identity = (
            reference["path"],
            reference["sha256"],
            reference["bytes"],
        )
        if identity in seen:
            continue
        seen.add(identity)
        candidate = root / reference["path"]
        try:
            resolved = candidate.resolve(strict=True)
        except OSError:
            add(errors, "missingEvidenceFile")
            continue
        if root not in resolved.parents or not resolved.is_file():
            add(errors, "evidencePathEscape")
            continue
        if resolved.stat().st_size != reference["bytes"]:
            add(errors, "evidenceSizeMismatch")
        hasher = hashlib.sha256()
        with resolved.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                hasher.update(chunk)
        if hasher.hexdigest() != reference["sha256"]:
            add(errors, "evidenceDigestMismatch")
    index: dict[str, Any] | None = None
    composition: dict[str, Any] | None = None
    index_path: Path | None = None
    if value.get("evidenceLevel") in {"signedCandidate", "promotionReady"} and value.get("sbom") is not None:
        document = value["sbom"]["document"]
        if PurePosixPath(document["path"]).name != "artifact-sbom-index.json":
            add(errors, "invalidArtifactSBOM")
        else:
            try:
                index_path = resolve_artifact_path(root, document["path"], must_exist=True)
                index, composition = validate_artifact_bundle(index_path, evidence_root=root, verify_archives=True)
                validate_release_binding(value, index, composition)
                if "macOS" in value.get("release", {}).get("targets", []):
                    try:
                        observed_profile = _mac_user_initiated_update_check_profile(
                            value,
                            root,
                        )
                    except (OSError, ValueError, KeyError, TypeError):
                        add(errors, "invalidMacUpdateCheckConfiguration")
                    else:
                        expected_profile = value.get("compatibility", {}).get(
                            "macUserInitiatedUpdateCheckProfile"
                        )
                        if observed_profile != expected_profile:
                            add(errors, "invalidMacUpdateCheckConfiguration")
                confirmed_digest = hashlib.sha256(index_path.read_bytes()).hexdigest()
                if index_path.stat().st_size != document["bytes"] or confirmed_digest != document["sha256"]:
                    raise ArtifactSBOMError("artifact SBOM index changed during verification")
            except (ArtifactSBOMError, OSError, ValueError, TypeError, json.JSONDecodeError, DuplicateKeyError):
                add(errors, "invalidArtifactSBOM")
        if index is not None and composition is not None:
            signed_code_structurally_valid = True
            signed_code_graph_valid = True
            signing_policy_valid = False
            graph: dict[str, Any] | None = None
            composition_by_id = {
                artifact["id"]: {entry["path"]: entry for entry in artifact["entries"]}
                for artifact in composition["artifacts"]
            }
            artifact_by_id = {artifact["id"]: artifact for artifact in index["artifacts"]}
            for executable in value.get("executables", []):
                try:
                    reference = executable["verificationBundle"]
                    candidate_bundle_path = root / reference["path"]
                    resolved_bundle_path = resolve_artifact_path(
                        root,
                        reference["path"],
                        must_exist=True,
                    )
                    if candidate_bundle_path.absolute() != resolved_bundle_path:
                        raise SignedCodeVerificationError("verification bundle path contains a symlink")
                    bundle, bundle_raw = load_signed_code_bundle(candidate_bundle_path)
                    if (
                        len(bundle_raw) != reference["bytes"]
                        or hashlib.sha256(bundle_raw).hexdigest() != reference["sha256"]
                    ):
                        raise SignedCodeVerificationError("verification bundle reference mismatch")
                    member = composition_by_id[executable["artifactID"]][executable["relativePath"]]
                    validate_signed_code_bundle(
                        bundle,
                        release_executable=executable,
                        release_manifest=value,
                        artifact_sbom_reference=document,
                        artifact_binding=artifact_by_id[executable["artifactID"]],
                        artifact_member=member,
                        evidence_root=root,
                    )
                except (
                    ArtifactSBOMError,
                    SignedCodeVerificationError,
                    OSError,
                    KeyError,
                    TypeError,
                    ValueError,
                ):
                    signed_code_structurally_valid = False
                    add(errors, "invalidSignedCodeVerification")
            graph_records = [
                record
                for record in value.get("validation", [])
                if isinstance(record, dict) and record.get("id") == "signed-code-graph-construction"
            ]
            if not graph_records:
                signed_code_graph_valid = False
                add(errors, "missingSignedCodeGraph")
            elif len(graph_records) != 1 or graph_records[0].get("status") != "passed":
                signed_code_graph_valid = False
                add(errors, "invalidSignedCodeGraph")
            else:
                try:
                    graph_reference = graph_records[0]["evidence"]
                    graph_candidate = root / graph_reference["path"]
                    graph_resolved = resolve_artifact_path(root, graph_reference["path"], must_exist=True)
                    if graph_candidate.absolute() != graph_resolved:
                        raise SignedCodeGraphError("signed-code graph path contains a symlink")
                    graph, graph_raw = load_signed_code_graph(graph_candidate)
                    if (
                        len(graph_raw) != graph_reference["bytes"]
                        or hashlib.sha256(graph_raw).hexdigest() != graph_reference["sha256"]
                    ):
                        raise SignedCodeGraphError("signed-code graph reference mismatch")
                    validate_signed_code_graph(
                        graph,
                        index=index,
                        composition=composition,
                        release_manifest=value,
                        artifact_sbom_reference=document,
                        evidence_root=root,
                    )
                except (
                    ArtifactSBOMError,
                    SignedCodeGraphError,
                    OSError,
                    KeyError,
                    TypeError,
                    ValueError,
                ):
                    signed_code_graph_valid = False
                    add(errors, "invalidSignedCodeGraph")
            policy_records = [
                record
                for record in value.get("validation", [])
                if isinstance(record, dict) and record.get("id") == "signing-policy-contract"
            ]
            if not policy_records:
                add(errors, "missingSigningPolicy")
            elif len(policy_records) != 1 or policy_records[0].get("status") != "passed":
                add(errors, "invalidSigningPolicy")
            elif expected_signing_policy_sha256 is None:
                add(errors, "signingPolicyDigestPinRequired")
            else:
                policy_reference = policy_records[0]["evidence"]
                if policy_reference.get("sha256") != expected_signing_policy_sha256:
                    add(errors, "signingPolicyDigestMismatch")
                elif graph is not None and signed_code_graph_valid:
                    try:
                        policy_candidate = root / policy_reference["path"]
                        policy_resolved = resolve_artifact_path(root, policy_reference["path"], must_exist=True)
                        if policy_candidate.absolute() != policy_resolved:
                            raise SigningPolicyError("signing-policy path contains a symlink")
                        policy, policy_raw = load_pinned_policy(
                            policy_candidate,
                            expected_signing_policy_sha256,
                        )
                        if (
                            len(policy_raw) != policy_reference["bytes"]
                            or hashlib.sha256(policy_raw).hexdigest() != policy_reference["sha256"]
                        ):
                            raise SigningPolicyDigestMismatch("signing-policy reference mismatch")
                        validate_policy_binding(
                            policy,
                            release_manifest=value,
                            signed_code_graph=graph,
                            artifact_sbom_reference=document,
                            signed_code_graph_reference=graph_records[0]["evidence"],
                        )
                        signing_policy_valid = True
                    except SigningPolicyDigestMismatch:
                        add(errors, "signingPolicyDigestMismatch")
                    except (
                        ArtifactSBOMError,
                        SigningPolicyError,
                        OSError,
                        KeyError,
                        TypeError,
                        ValueError,
                    ):
                        add(errors, "invalidSigningPolicy")
            if signed_code_structurally_valid and signed_code_graph_valid and signing_policy_valid and value.get("executables"):
                # Canonical correlation and retained raw outputs are
                # construction evidence. Acceptance still requires a future
                # release-only lane to rerun and interpret Apple signing tools
                # against the exact extracted candidate.
                add(errors, "signedCodePlatformVerificationRequired")
        has_mac = "macOS" in value.get("release", {}).get("targets", [])
        if value.get("evidenceLevel") == "promotionReady" and has_mac:
            scenario_by_id = {
                scenario.get("id"): scenario
                for scenario in value.get("physicalScenarios", [])
                if isinstance(scenario, dict)
            }
            lifecycle_scenarios = (
                "clean-install",
                "permission-revocation",
                "complete-uninstall",
                "quarantine-launch",
            )
            lifecycle_references = [
                scenario_by_id.get(scenario, {}).get("evidence")
                if isinstance(scenario_by_id.get(scenario), dict)
                else None
                for scenario in lifecycle_scenarios
            ]
            lifecycle_reference = lifecycle_references[0]
            if (
                not isinstance(lifecycle_reference, dict)
                or any(reference != lifecycle_reference for reference in lifecycle_references[1:])
                or PurePosixPath(lifecycle_reference.get("path", "")).name
                != "mac-lifecycle-physical-evidence.json"
            ):
                add(errors, "invalidMacLifecyclePhysicalEvidence")
            else:
                try:
                    lifecycle_path = resolve_artifact_path(
                        root,
                        lifecycle_reference["path"],
                        must_exist=True,
                    )
                    lifecycle, lifecycle_raw = load_mac_lifecycle_physical_record(
                        lifecycle_path
                    )
                    if (
                        len(lifecycle_raw) != lifecycle_reference["bytes"]
                        or hashlib.sha256(lifecycle_raw).hexdigest()
                        != lifecycle_reference["sha256"]
                    ):
                        raise MacLifecyclePhysicalEvidenceError(
                            "lifecycle matrix reference mismatch"
                        )
                    validate_mac_lifecycle_physical_record(
                        lifecycle,
                        release_manifest=value,
                        evidence_root=root,
                        verify_files=True,
                    )
                except (
                    ArtifactSBOMError,
                    MacLifecyclePhysicalEvidenceError,
                    OSError,
                    KeyError,
                    TypeError,
                    ValueError,
                    json.JSONDecodeError,
                    DuplicateKeyError,
                ):
                    add(errors, "invalidMacLifecyclePhysicalEvidence")
            upgrade = scenario_by_id.get("upgrade")
            rollback = scenario_by_id.get("rollback")
            upgrade_reference = upgrade.get("evidence") if isinstance(upgrade, dict) else None
            rollback_reference = rollback.get("evidence") if isinstance(rollback, dict) else None
            if (
                not isinstance(upgrade_reference, dict)
                or upgrade_reference != rollback_reference
                or PurePosixPath(upgrade_reference.get("path", "")).name
                != "mac-update-physical-evidence.json"
            ):
                add(errors, "invalidMacUpdatePhysicalEvidence")
            else:
                try:
                    matrix_path = resolve_artifact_path(
                        root,
                        upgrade_reference["path"],
                        must_exist=True,
                    )
                    matrix, matrix_raw = load_mac_update_physical_record(matrix_path)
                    if (
                        len(matrix_raw) != upgrade_reference["bytes"]
                        or hashlib.sha256(matrix_raw).hexdigest()
                        != upgrade_reference["sha256"]
                    ):
                        raise MacUpdatePhysicalEvidenceError(
                            "update matrix reference mismatch"
                        )
                    validate_mac_update_physical_record(
                        matrix,
                        release_manifest=value,
                        evidence_root=root,
                        verify_files=True,
                    )
                except (
                    ArtifactSBOMError,
                    MacUpdatePhysicalEvidenceError,
                    OSError,
                    KeyError,
                    TypeError,
                    ValueError,
                    json.JSONDecodeError,
                    DuplicateKeyError,
                ):
                    add(errors, "invalidMacUpdatePhysicalEvidence")

        packaging_records = [
            record
            for record in value.get("validation", [])
            if isinstance(record, dict) and record.get("id") == "mac-packaging-equivalence"
        ]
        if not has_mac:
            if packaging_records:
                add(errors, "unexpectedMacPackagingEquivalence")
            return errors
        if not packaging_records:
            add(errors, "missingMacPackagingEquivalence")
            return errors
        if len(packaging_records) != 1 or packaging_records[0].get("status") != "passed":
            add(errors, "invalidMacPackagingEquivalence")
            return errors
        record = packaging_records[0]
        receipt_reference = record.get("evidence")
        if (
            not isinstance(receipt_reference, dict)
            or PurePosixPath(receipt_reference.get("path", "")).name
            != "mac-packaging-equivalence.json"
            or index is None
            or composition is None
            or index_path is None
        ):
            add(errors, "invalidMacPackagingEquivalence")
            return errors
        try:
            receipt_path = resolve_artifact_path(
                root,
                receipt_reference["path"],
                must_exist=True,
            )
            receipt, receipt_raw = load_canonical_receipt_with_bytes(receipt_path)
            if (
                hashlib.sha256(receipt_raw).hexdigest() != receipt_reference["sha256"]
                or len(receipt_raw) != receipt_reference["bytes"]
            ):
                raise MacPackagingEquivalenceError("packaging receipt reference mismatch")
            artifact_reference = value["sbom"]["document"]
            validate_receipt(
                receipt,
                index=index,
                composition=composition,
                artifact_sbom_reference=artifact_reference,
                release_manifest=value,
            )
            if not verify_platform_packaging:
                add(errors, "macPackagingEquivalencePlatformVerificationRequired")
                return errors
            dmg_artifacts = [
                artifact
                for artifact in value.get("artifacts", [])
                if isinstance(artifact, dict) and artifact.get("kind") == "macDiskImage"
            ]
            if len(dmg_artifacts) != 1:
                raise MacPackagingEquivalenceError(
                    "release artifacts must contain exactly one macDiskImage"
                )
            dmg_artifact = dmg_artifacts[0]
            dmg_path = resolve_artifact_path(root, dmg_artifact["path"], must_exist=True)
            observed_entries, observed_layout = inspect_dmg(
                dmg_path,
                expected_sha256=dmg_artifact["sha256"],
                expected_bytes=dmg_artifact["bytes"],
                allow_readonly_mount=True,
            )
            validate_receipt(
                receipt,
                index=index,
                composition=composition,
                artifact_sbom_reference=artifact_reference,
                release_manifest=value,
                observed_dmg_entries=observed_entries,
                observed_dmg_layout=observed_layout,
            )
            # Re-run exact archive verification and rehash every packaging
            # root reference after the platform operation closes the TOCTOU
            # window across the receipt, index, ZIPs, and DMG.
            final_index, final_composition = validate_artifact_bundle(
                index_path,
                evidence_root=root,
                verify_archives=True,
            )
            validate_release_binding(value, final_index, final_composition)
            if final_index != index or final_composition != composition:
                raise MacPackagingEquivalenceError("artifact SBOM changed during platform verification")
            if not all(
                _reference_matches(root, reference)
                for reference in (artifact_reference, receipt_reference, dmg_artifact)
            ):
                raise MacPackagingEquivalenceError("packaging reference changed during verification")
        except (
            ArtifactSBOMError,
            MacPackagingEquivalenceError,
            OSError,
            ValueError,
            TypeError,
            KeyError,
            json.JSONDecodeError,
            DuplicateKeyError,
        ):
            add(errors, "invalidMacPackagingEquivalence")
    return errors


def validate_fixture_corpus() -> int:
    repository = Path(__file__).resolve().parents[1]
    fixture_root = repository / "Tests" / "System" / "ReleaseEvidence"
    index = load_json(fixture_root / "manifest.json")
    failures: list[str] = []
    seen: set[str] = set()
    cases = index.get("cases") if isinstance(index, dict) else None
    if not isinstance(cases, list) or not cases:
        raise ValueError("release evidence fixture index must contain cases")

    for case in cases:
        relative = case["path"]
        if relative in seen:
            raise ValueError(f"duplicate release evidence fixture: {relative}")
        seen.add(relative)
        path = (fixture_root / relative).resolve()
        if fixture_root.resolve() not in path.parents or not path.is_file():
            raise ValueError(f"unsafe or missing release evidence fixture: {relative}")
        try:
            value = load_json(path)
            errors = validate_manifest(value)
        except (json.JSONDecodeError, DuplicateKeyError):
            errors = {"invalidJSON"}

        expected = case["expect"]
        expected_errors = set(case.get("errors", []))
        if expected == "valid" and errors:
            failures.append(f"{relative}: expected valid, got {sorted(errors)}")
        elif expected == "invalid":
            if not errors:
                failures.append(f"{relative}: expected invalid, got valid")
            elif not expected_errors.issubset(errors):
                failures.append(
                    f"{relative}: missing expected errors "
                    f"{sorted(expected_errors - errors)}; got {sorted(errors)}"
                )
        else:
            if expected not in {"valid", "invalid"}:
                failures.append(f"{relative}: invalid expectation {expected}")

    if failures:
        for failure in failures:
            print(failure)
        return 1
    print(f"validated {len(seen)} release evidence fixture(s)")
    return 0


def validate_paths(
    paths: list[Path],
    *,
    verify_file_contents: bool,
    verify_platform_packaging: bool,
    schema_only: bool,
    expected_signing_policy_sha256: str | None,
) -> int:
    failed = False
    for path in paths:
        try:
            value = load_json(path)
            errors = validate_manifest(value)
            if (
                not errors
                and value.get("evidenceLevel") in {"signedCandidate", "promotionReady"}
                and not verify_file_contents
                and not schema_only
            ):
                add(errors, "signedCandidateFileVerificationRequired")
            if not errors and verify_file_contents:
                errors.update(
                    verify_files(
                        value,
                        path,
                        verify_platform_packaging=verify_platform_packaging,
                        expected_signing_policy_sha256=expected_signing_policy_sha256,
                    )
                )
        except (OSError, json.JSONDecodeError, DuplicateKeyError) as error:
            print(f"{path}: invalidJSON: {error}")
            failed = True
            continue
        if errors:
            print(f"{path}: invalid: {', '.join(sorted(errors))}")
            failed = True
        else:
            suffix = "schema-valid only" if schema_only else "valid release evidence manifest"
            print(f"{path}: {suffix}")
    return 1 if failed else 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate Mac Companion release evidence v0.2"
    )
    parser.add_argument(
        "manifest",
        nargs="*",
        type=Path,
        help="manifest paths; omit to validate the repository conformance corpus",
    )
    parser.add_argument(
        "--schema-only",
        action="store_true",
        help="validate structure only and label the result as non-acceptance evidence",
    )
    parser.add_argument(
        "--verify-files",
        action="store_true",
        help="verify every referenced file relative to each manifest",
    )
    parser.add_argument(
        "--verify-platform-packaging",
        action="store_true",
        help="explicitly authorize read-only DMG mount and package reinspection",
    )
    parser.add_argument(
        "--expected-signing-policy-sha256",
        help="independent protected SHA-256 pin for exactly one signed manifest",
    )
    arguments = parser.parse_args()
    if arguments.schema_only and (arguments.verify_files or arguments.verify_platform_packaging):
        parser.error("--schema-only cannot be combined with file or platform verification")
    if arguments.verify_platform_packaging and not arguments.verify_files:
        parser.error("--verify-platform-packaging requires --verify-files")
    if arguments.expected_signing_policy_sha256 is not None:
        if (
            not arguments.verify_files
            or arguments.schema_only
            or len(arguments.manifest) != 1
        ):
            parser.error("--expected-signing-policy-sha256 requires --verify-files and exactly one manifest")
        if (
            SHA256.fullmatch(arguments.expected_signing_policy_sha256) is None
            or len(set(arguments.expected_signing_policy_sha256)) == 1
        ):
            parser.error("--expected-signing-policy-sha256 must be a non-placeholder lowercase SHA-256")
    if arguments.manifest:
        return validate_paths(
            arguments.manifest,
            verify_file_contents=arguments.verify_files,
            verify_platform_packaging=arguments.verify_platform_packaging,
            schema_only=arguments.schema_only,
            expected_signing_policy_sha256=arguments.expected_signing_policy_sha256,
        )
    if arguments.verify_files:
        parser.error("--verify-files requires at least one manifest path")
    if arguments.verify_platform_packaging:
        parser.error("--verify-platform-packaging requires --verify-files and a manifest path")
    if arguments.schema_only:
        parser.error("--schema-only requires at least one manifest path")
    if arguments.expected_signing_policy_sha256 is not None:
        parser.error("--expected-signing-policy-sha256 requires --verify-files and exactly one manifest")
    return validate_fixture_corpus()


if __name__ == "__main__":
    raise SystemExit(main())
