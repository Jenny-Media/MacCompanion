#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import plistlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path, PurePosixPath
from typing import Any


REPOSITORY = Path(__file__).resolve().parents[1]
POLICY_PATH = REPOSITORY / "spec" / "privacy-manifest" / "v0" / "policy.json"
FIXTURE_INDEX = REPOSITORY / "Tests" / "System" / "PrivacyManifest" / "manifest.json"
PACKAGE_PATH = REPOSITORY / "Packages" / "MacCompanionKit"

CATEGORY_REASONS = {
    "NSPrivacyAccessedAPICategoryFileTimestamp": {"DDA9.1", "C617.1", "3B52.1", "0A2A.1"},
    "NSPrivacyAccessedAPICategorySystemBootTime": {"35F9.1", "8FFB.1", "3D61.1"},
    "NSPrivacyAccessedAPICategoryDiskSpace": {"85F4.1", "E174.1", "7D9E.1", "B728.1"},
    "NSPrivacyAccessedAPICategoryActiveKeyboards": {"3EC4.1", "54BD.1"},
    "NSPrivacyAccessedAPICategoryUserDefaults": {"CA92.1", "1C8F.1", "C56D.1", "AC6B.1"},
}
SDK_ONLY_REASONS = {"0A2A.1", "C56D.1"}

API_PATTERNS = {
    "systemUptime": ("NSPrivacyAccessedAPICategorySystemBootTime", re.compile(r"\bsystemUptime\b")),
    "mach_absolute_time": ("NSPrivacyAccessedAPICategorySystemBootTime", re.compile(r"\bmach_absolute_time\s*\(")),
    "systemSize": ("NSPrivacyAccessedAPICategoryDiskSpace", re.compile(r"\.systemSize\b")),
    "systemFreeSize": ("NSPrivacyAccessedAPICategoryDiskSpace", re.compile(r"\.systemFreeSize\b")),
    "volumeTotalCapacityKey": ("NSPrivacyAccessedAPICategoryDiskSpace", re.compile(r"\.volumeTotalCapacityKey\b")),
    "volumeAvailableCapacityKey": ("NSPrivacyAccessedAPICategoryDiskSpace", re.compile(r"\.volumeAvailableCapacity(?:ForImportantUsage|ForOpportunisticUsage)?Key\b")),
    "activeInputModes": ("NSPrivacyAccessedAPICategoryActiveKeyboards", re.compile(r"\bactiveInputModes\b")),
    "UserDefaults": ("NSPrivacyAccessedAPICategoryUserDefaults", re.compile(r"\bUserDefaults\b")),
    "stat": ("NSPrivacyAccessedAPICategoryFileTimestamp", re.compile(r"\bstat\s*\(")),
    "stat64": ("NSPrivacyAccessedAPICategoryFileTimestamp", re.compile(r"\bstat64\s*\(")),
    "fstat": ("NSPrivacyAccessedAPICategoryFileTimestamp", re.compile(r"\bfstat\s*\(")),
    "fstat64": ("NSPrivacyAccessedAPICategoryFileTimestamp", re.compile(r"\bfstat64\s*\(")),
    "lstat": ("NSPrivacyAccessedAPICategoryFileTimestamp", re.compile(r"\blstat\s*\(")),
    "lstat64": ("NSPrivacyAccessedAPICategoryFileTimestamp", re.compile(r"\blstat64\s*\(")),
    "fstatat": ("NSPrivacyAccessedAPICategoryFileTimestamp", re.compile(r"\bfstatat\s*\(")),
    "fstatat64": ("NSPrivacyAccessedAPICategoryFileTimestamp", re.compile(r"\bfstatat64\s*\(")),
    "statfs": ("NSPrivacyAccessedAPICategoryDiskSpace", re.compile(r"\bstatfs\s*\(")),
    "fstatfs": ("NSPrivacyAccessedAPICategoryDiskSpace", re.compile(r"\bfstatfs\s*\(")),
    "statvfs": ("NSPrivacyAccessedAPICategoryDiskSpace", re.compile(r"\bstatvfs\s*\(")),
    "fstatvfs": ("NSPrivacyAccessedAPICategoryDiskSpace", re.compile(r"\bfstatvfs\s*\(")),
    "getattrlist": ("NSPrivacyAccessedAPICategoryFileTimestamp", re.compile(r"\bgetattrlist\s*\(")),
    "fgetattrlist": ("NSPrivacyAccessedAPICategoryFileTimestamp", re.compile(r"\bfgetattrlist\s*\(")),
    "getattrlistat": ("NSPrivacyAccessedAPICategoryFileTimestamp", re.compile(r"\bgetattrlistat\s*\(")),
    "getattrlistbulk": ("NSPrivacyAccessedAPICategoryFileTimestamp", re.compile(r"\bgetattrlistbulk\s*\(")),
    "getdirentriesattr": ("NSPrivacyAccessedAPICategoryFileTimestamp", re.compile(r"\bgetdirentriesattr\s*\(")),
    "contentModificationDateKey": ("NSPrivacyAccessedAPICategoryFileTimestamp", re.compile(r"\.contentModificationDateKey\b")),
    "creationDateKey": ("NSPrivacyAccessedAPICategoryFileTimestamp", re.compile(r"\.creationDateKey\b")),
    "NSFileCreationDate": ("NSPrivacyAccessedAPICategoryFileTimestamp", re.compile(r"\bNSFileCreationDate\b")),
    "NSFileModificationDate": ("NSPrivacyAccessedAPICategoryFileTimestamp", re.compile(r"\bNSFileModificationDate\b")),
}


class DuplicateKeyError(ValueError):
    pass


def closed_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKeyError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle, object_pairs_hook=closed_pairs)


def exact_keys(value: Any, expected: set[str]) -> bool:
    return isinstance(value, dict) and set(value) == expected


def safe_path(value: Any) -> bool:
    if not isinstance(value, str) or not value or "\\" in value:
        return False
    path = PurePosixPath(value)
    return not path.is_absolute() and all(part not in {"", ".", ".."} for part in path.parts)


def duplicate_plist_keys(path: Path) -> bool:
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError:
        return False
    for dictionary in root.iter("dict"):
        keys = [child.text for child in dictionary if child.tag == "key"]
        if len(keys) != len(set(keys)):
            return True
    return False


def validate_accessed_types(value: Any) -> tuple[list[dict[str, Any]], set[str]]:
    errors: set[str] = set()
    if not isinstance(value, list):
        return [], {"accessedTypesType"}
    normalized: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in value:
        if not exact_keys(item, {"NSPrivacyAccessedAPIType", "NSPrivacyAccessedAPITypeReasons"}):
            errors.add("accessedTypeSchema")
            continue
        category = item["NSPrivacyAccessedAPIType"]
        reasons = item["NSPrivacyAccessedAPITypeReasons"]
        if category not in CATEGORY_REASONS:
            errors.add("unknownCategory")
            continue
        if category in seen:
            errors.add("duplicateCategory")
        seen.add(category)
        if not isinstance(reasons, list) or not reasons or not all(isinstance(reason, str) for reason in reasons):
            errors.add("invalidReasons")
            continue
        if reasons != sorted(set(reasons)):
            errors.add("reasonOrderOrDuplicate")
        if any(reason not in CATEGORY_REASONS[category] for reason in reasons):
            errors.add("invalidReason")
        if any(reason in SDK_ONLY_REASONS for reason in reasons):
            errors.add("sdkOnlyReason")
        normalized.append({"category": category, "reasons": reasons})
    if [item.get("category") for item in normalized] != sorted(item.get("category") for item in normalized):
        errors.add("categoryOrder")
    return normalized, errors


def validate_manifest(path: Path, kind: str, expected: list[dict[str, Any]] | None = None) -> set[str]:
    errors: set[str] = set()
    if duplicate_plist_keys(path):
        errors.add("duplicatePlistKey")
    try:
        with path.open("rb") as handle:
            value = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException, ET.ParseError, ValueError):
        return errors | {"invalidPlist"}
    required = {"NSPrivacyTracking", "NSPrivacyTrackingDomains", "NSPrivacyCollectedDataTypes"}
    if kind == "ios":
        required.add("NSPrivacyAccessedAPITypes")
    if not exact_keys(value, required):
        errors.add("manifestSchema")
        return errors
    if value["NSPrivacyTracking"] is not False:
        errors.add("trackingMustBeFalse")
    if value["NSPrivacyTrackingDomains"] != []:
        errors.add("trackingDomainsMustBeEmpty")
    if value["NSPrivacyCollectedDataTypes"] != []:
        errors.add("collectedDataMustBeEmpty")
    if kind == "mac":
        return errors
    normalized, accessed_errors = validate_accessed_types(value["NSPrivacyAccessedAPITypes"])
    errors |= accessed_errors
    if expected is not None and normalized != expected:
        errors.add("accessedTypesMismatch")
    return errors


def validate_policy(policy: Any) -> set[str]:
    errors: set[str] = set()
    if not exact_keys(policy, {"profile", "appleDocumentationReviewedOn", "requiredReasonPlatforms", "collectionAssessment", "targets", "sourceInventory"}):
        return {"policySchema"}
    if policy["profile"] != "maccompanion.apple-privacy-manifest.v0":
        errors.add("policyProfile")
    if not isinstance(policy["appleDocumentationReviewedOn"], str) or re.fullmatch(
        r"20[0-9]{2}-[0-9]{2}-[0-9]{2}", policy["appleDocumentationReviewedOn"]
    ) is None:
        errors.add("documentationReviewDate")
    if policy["requiredReasonPlatforms"] != ["iOS", "iPadOS", "tvOS", "visionOS", "watchOS"]:
        errors.add("requiredReasonPlatforms")
    assessment = policy["collectionAssessment"]
    if not exact_keys(assessment, {"developerCollection", "tracking", "trackingDomains"}) or assessment != {"developerCollection": False, "tracking": False, "trackingDomains": []}:
        errors.add("collectionAssessment")
    targets = policy["targets"]
    if not isinstance(targets, list) or not targets:
        return errors | {"policyTargets"}
    ids: list[str] = []
    for target in targets:
        if not exact_keys(target, {"id", "platform", "bundleOwner", "requiredReasonReporting", "manifest", "swiftEntryTargets", "accessedAPITypes"}):
            errors.add("policyTargetSchema")
            continue
        ids.append(target["id"] if isinstance(target["id"], str) else "")
        if target["platform"] not in {"iOS", "macOS"}:
            errors.add("targetPlatform")
        if target["bundleOwner"] not in {"self", "mac-containing-app"}:
            errors.add("targetBundleOwner")
        if not safe_path(target["manifest"]):
            errors.add("policyManifestPath")
        entries = target["swiftEntryTargets"]
        if not isinstance(entries, list) or not all(isinstance(item, str) and item for item in entries) or entries != sorted(set(entries)):
            errors.add("swiftEntryTargets")
        _, accessed_errors = validate_accessed_types(target["accessedAPITypes"])
        errors |= {"policy" + code[0].upper() + code[1:] for code in accessed_errors}
        if target["platform"] == "iOS" and target["requiredReasonReporting"] is not True:
            errors.add("iosReportingRequired")
        if target["platform"] == "macOS" and target["requiredReasonReporting"] is not False:
            errors.add("macReportingUnexpected")
    if ids != ["ios-app", "mac-agent-service", "mac-containing-app"]:
        errors.add("targetOrderOrDuplicate")
    by_id = {
        target["id"]: target
        for target in targets
        if isinstance(target, dict) and isinstance(target.get("id"), str)
    }
    if by_id.get("ios-app", {}).get("bundleOwner") != "self":
        errors.add("iosBundleOwner")
    if by_id.get("mac-containing-app", {}).get("bundleOwner") != "self":
        errors.add("macContainingBundleOwner")
    if by_id.get("mac-agent-service", {}).get("bundleOwner") != "mac-containing-app":
        errors.add("macAgentBundleOwner")
    inventory = policy["sourceInventory"]
    if not isinstance(inventory, list):
        return errors | {"sourceInventory"}
    keys: list[tuple[str, str]] = []
    for record in inventory:
        if not exact_keys(record, {"api", "category", "path", "count", "platforms"}):
            errors.add("sourceRecordSchema")
            continue
        keys.append((record["path"], record["api"]))
        if record["category"] not in CATEGORY_REASONS or not safe_path(record["path"]):
            errors.add("sourceRecordValue")
        if not isinstance(record["count"], int) or isinstance(record["count"], bool) or record["count"] <= 0:
            errors.add("sourceRecordCount")
        if record["platforms"] != ["macOS"]:
            errors.add("sourceRecordPlatforms")
    if keys != sorted(set(keys)):
        errors.add("sourceRecordOrderOrDuplicate")
    return errors


def observed_source_inventory() -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    source_root = PACKAGE_PATH / "Sources"
    for path in sorted(source_root.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        for api, (category, pattern) in API_PATTERNS.items():
            count = len(pattern.findall(text))
            if count:
                records.append({
                    "api": api,
                    "category": category,
                    "path": path.relative_to(REPOSITORY).as_posix(),
                    "count": count,
                    "platforms": ["macOS"] if whole_file_mac_guard(text) else [],
                })
    return sorted(records, key=lambda item: (item["path"], item["api"]))


def whole_file_mac_guard(text: str) -> bool:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    return bool(lines) and lines[0] == "#if os(macOS)" and lines[-1] == "#endif"


def target_graph() -> dict[str, set[str]]:
    command = ["swift", "package"]
    if os.environ.get("MACCOMPANION_DISABLE_SWIFTPM_SANDBOX") == "1":
        command.append("--disable-sandbox")
    command += ["--package-path", str(PACKAGE_PATH), "dump-package"]
    environment = os.environ.copy()
    environment.setdefault("CLANG_MODULE_CACHE_PATH", "/private/tmp/maccompanion-clang-cache")
    environment.setdefault("SWIFTPM_MODULECACHE_OVERRIDE", "/private/tmp/maccompanion-swiftpm-cache")
    result = subprocess.run(command, check=True, capture_output=True, text=True, env=environment)
    package = json.loads(result.stdout, object_pairs_hook=closed_pairs)
    graph: dict[str, set[str]] = {}
    for target in package.get("targets", []):
        dependencies: set[str] = set()
        for wrapper in target.get("dependencies", []):
            by_name = wrapper.get("byName") if isinstance(wrapper, dict) else None
            if isinstance(by_name, list) and by_name and isinstance(by_name[0], str):
                dependencies.add(by_name[0])
        graph[target["name"]] = dependencies
    return graph


def closure(graph: dict[str, set[str]], roots: list[str]) -> tuple[set[str], set[str]]:
    missing = {root for root in roots if root not in graph}
    reached: set[str] = set()
    pending = list(roots)
    while pending:
        target = pending.pop()
        if target in reached or target not in graph:
            continue
        reached.add(target)
        pending.extend(graph[target] - reached)
    return reached, missing


def module_for_path(path: str) -> str:
    parts = PurePosixPath(path).parts
    source_index = parts.index("Sources")
    return parts[source_index + 1]


def validate_fixtures() -> tuple[int, set[str]]:
    failures: set[str] = set()
    index = load_json(FIXTURE_INDEX)
    if not exact_keys(index, {"profile", "cases"}) or index.get("profile") != "maccompanion.apple-privacy-manifest-fixtures.v0":
        return 0, {"fixtureIndexSchema"}
    cases = index["cases"]
    if not isinstance(cases, list):
        return 0, {"fixtureIndexCases"}
    seen: set[str] = set()
    for case in cases:
        if not exact_keys(case, {"path", "kind", "expectedCodes"}) or case["kind"] not in {"ios", "mac"} or not safe_path(case["path"]):
            failures.add("fixtureCaseSchema")
            continue
        if (
            not isinstance(case["expectedCodes"], list)
            or not all(isinstance(code, str) and code for code in case["expectedCodes"])
            or case["expectedCodes"] != sorted(set(case["expectedCodes"]))
        ):
            failures.add("fixtureExpectedCodes")
            continue
        if case["path"] in seen:
            failures.add("fixtureDuplicatePath")
        seen.add(case["path"])
        observed = sorted(validate_manifest(FIXTURE_INDEX.parent / case["path"], case["kind"]))
        if observed != case["expectedCodes"]:
            failures.add(f"fixtureMismatch:{case['path']}:expected={case['expectedCodes']}:observed={observed}")
    return len(cases), failures


def main() -> int:
    try:
        policy = load_json(POLICY_PATH)
        errors = validate_policy(policy)
        fixture_count, fixture_errors = validate_fixtures()
        errors |= fixture_errors
        if errors:
            raise ValueError(", ".join(sorted(errors)))

        for target in policy["targets"]:
            expected = [
                {"category": item["NSPrivacyAccessedAPIType"], "reasons": item["NSPrivacyAccessedAPITypeReasons"]}
                for item in target["accessedAPITypes"]
            ]
            kind = "ios" if target["requiredReasonReporting"] else "mac"
            errors |= validate_manifest(REPOSITORY / target["manifest"], kind, expected)

        targets_by_id = {target["id"]: target for target in policy["targets"]}
        for target in policy["targets"]:
            owner_id = target["bundleOwner"]
            if owner_id == "self":
                continue
            owner = targets_by_id.get(owner_id)
            if owner is None:
                errors.add("missingBundleOwner")
                continue
            if (REPOSITORY / target["manifest"]).read_bytes() != (
                REPOSITORY / owner["manifest"]
            ).read_bytes():
                errors.add("bundleOwnerManifestMismatch")

        observed = observed_source_inventory()
        expected_inventory = policy["sourceInventory"]
        # A non-guarded occurrence is still macOS-only when its module is outside
        # the iOS closure; resolve those platform annotations after graph loading.
        graph = target_graph()
        ios_targets = [target for target in policy["targets"] if target["platform"] == "iOS"]
        ios_roots = sorted({root for target in ios_targets for root in target["swiftEntryTargets"]})
        ios_closure, missing = closure(graph, ios_roots)
        if missing:
            errors.add("missingSwiftEntryTarget")
        for record in observed:
            if not record["platforms"]:
                module = module_for_path(record["path"])
                if module in ios_closure:
                    errors.add("iosCoveredAPIReachable")
                else:
                    record["platforms"] = ["macOS"]
        if observed != expected_inventory:
            errors.add("sourceInventoryMismatch")
        if errors:
            raise ValueError(", ".join(sorted(errors)))
        print(
            f"validated {len(policy['targets'])} target privacy manifest(s), "
            f"{fixture_count} privacy manifest fixture(s), and "
            f"{len(observed)} required-reason API source record(s)"
        )
        return 0
    except (OSError, ValueError, json.JSONDecodeError, subprocess.CalledProcessError) as error:
        print(f"privacy manifest validation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
