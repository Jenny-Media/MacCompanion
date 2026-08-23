#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from update_policy import (
    SPARKLE_ARCHIVE_SHA256,
    SPARKLE_LICENSE_SHA256,
    SPARKLE_MANIFEST_SHA256,
    SPARKLE_REPOSITORY,
    SPARKLE_REVISION,
    SPARKLE_VERSION,
)


REPOSITORY = Path(__file__).resolve().parents[1]
FIXTURE_INDEX = REPOSITORY / "Tests" / "System" / "SBOM" / "manifest.json"
POLICY_PATH = REPOSITORY / "spec" / "dependency-policy" / "v0" / "policy.json"
ROOT_KEYS = {
    "SPDXID",
    "comment",
    "creationInfo",
    "dataLicense",
    "documentDescribes",
    "documentNamespace",
    "name",
    "packages",
    "relationships",
    "spdxVersion",
}
PACKAGE_KEYS = {
    "SPDXID",
    "comment",
    "copyrightText",
    "downloadLocation",
    "filesAnalyzed",
    "licenseConcluded",
    "licenseDeclared",
    "name",
    "primaryPackagePurpose",
    "supplier",
    "versionInfo",
}
RELATIONSHIP_KEYS = {"relatedSpdxElement", "relationshipType", "spdxElementId"}
TIMESTAMP = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
REVISION = re.compile(r"^[0-9a-f]{40}$")
DOCUMENT_NAME = re.compile(
    r"^Mac-Companion-(?P<version>[0-9A-Za-z][0-9A-Za-z.+-]{0,63})-"
    r"(?P<build>[1-9][0-9]{0,17})-source-dependencies$"
)
COMMENT = re.compile(
    r"^Source dependency inventory for targets (ios|macos|ios,macos) at Git revision "
    r"([0-9a-f]{40}) \(dirty=(false|true)\)\. This is not artifact composition or license evidence\.$"
)


class DuplicateKeyError(ValueError):
    pass


def object_without_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKeyError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle, object_pairs_hook=object_without_duplicates)


def exact_keys(value: Any, keys: set[str]) -> bool:
    return isinstance(value, dict) and set(value) == keys


def validate_package(
    value: Any,
    expected_id: str,
    expected_name: str,
    expected_purpose: str,
    expected_comment: str,
    expected_supplier: str = "Organization: Jenny Media LLC",
    expected_download_location: str = "NOASSERTION",
    expected_version: str | None = None,
) -> list[str]:
    failures: list[str] = []
    if not exact_keys(value, PACKAGE_KEYS):
        return ["packageSchema"]
    expected_constants = {
        "SPDXID": expected_id,
        "name": expected_name,
        "supplier": expected_supplier,
        "downloadLocation": expected_download_location,
        "filesAnalyzed": False,
        "licenseConcluded": "NOASSERTION",
        "licenseDeclared": "NOASSERTION",
        "copyrightText": "NOASSERTION",
        "primaryPackagePurpose": expected_purpose,
        "comment": expected_comment,
    }
    if any(value[key] != expected for key, expected in expected_constants.items()):
        failures.append("packageBoundary")
    version = value["versionInfo"]
    if not isinstance(version, str) or not re.fullmatch(r"[0-9A-Za-z][0-9A-Za-z.+-]{0,63}", version):
        failures.append("packageVersion")
    elif expected_version is not None and version != expected_version:
        failures.append("packageVersion")
    return failures


def validate_document(value: Any) -> list[str]:
    failures: list[str] = []
    if not exact_keys(value, ROOT_KEYS):
        return ["documentSchema"]
    constants = {
        "SPDXID": "SPDXRef-DOCUMENT",
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "documentDescribes": ["SPDXRef-Package-MacCompanion"],
    }
    if any(value[key] != expected for key, expected in constants.items()):
        failures.append("documentBoundary")
    name_match = (
        DOCUMENT_NAME.fullmatch(value["name"])
        if isinstance(value["name"], str)
        else None
    )
    if name_match is None:
        failures.append("documentName")
    namespace = value["documentNamespace"]
    if not isinstance(namespace, str):
        failures.append("documentNamespace")
    else:
        parsed = urlparse(namespace)
        if (
            parsed.scheme != "https"
            or parsed.netloc != "spdx.org"
            or not re.fullmatch(
                r"/spdxdocs/mac-companion-[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}",
                parsed.path,
            )
            or parsed.params
            or parsed.query
            or parsed.fragment
        ):
            failures.append("documentNamespace")
    creation = value["creationInfo"]
    if not exact_keys(creation, {"created", "creators"}):
        failures.append("creationInfoSchema")
    else:
        created = creation["created"]
        if not isinstance(created, str) or TIMESTAMP.fullmatch(created) is None:
            failures.append("creationTimestamp")
        else:
            try:
                datetime.strptime(created, "%Y-%m-%dT%H:%M:%SZ")
            except ValueError:
                failures.append("creationTimestamp")
        if creation["creators"] != [
            "Organization: Jenny Media LLC",
            "Tool: Mac Companion source SBOM generator-0.1",
        ]:
            failures.append("creatorBoundary")
    comment = value["comment"]
    match = COMMENT.fullmatch(comment) if isinstance(comment, str) else None
    if match is None:
        failures.append("scopeComment")
    elif REVISION.fullmatch(match.group(2)) is None:
        failures.append("sourceRevision")
    if (
        name_match is not None
        and match is not None
        and isinstance(creation, dict)
        and isinstance(creation.get("created"), str)
        and TIMESTAMP.fullmatch(creation["created"]) is not None
    ):
        seed = "\n".join(
            [
                "maccompanion-source-sbom-v0.1",
                name_match.group("version"),
                name_match.group("build"),
                creation["created"],
                match.group(2),
                match.group(3),
                match.group(1),
                hashlib.sha256(POLICY_PATH.read_bytes()).hexdigest(),
            ]
        )
        expected_namespace = (
            "https://spdx.org/spdxdocs/mac-companion-"
            f"{uuid.uuid5(uuid.NAMESPACE_URL, seed)}"
        )
        if namespace != expected_namespace:
            failures.append("namespaceBinding")
    packages = value["packages"]
    if not isinstance(packages, list) or len(packages) != 3:
        failures.append("packageSet")
        packages = []
    if packages:
        failures.extend(
            validate_package(
                packages[0],
                "SPDXRef-Package-MacCompanion",
                "Mac Companion",
                "APPLICATION",
                "First-party release source graph; artifact composition is not asserted.",
            )
        )
        failures.extend(
            validate_package(
                packages[2],
                "SPDXRef-Package-Sparkle",
                "Sparkle",
                "LIBRARY",
                (
                    f"External binary Swift package at revision {SPARKLE_REVISION}; "
                    f"upstream manifest SHA-256 {SPARKLE_MANIFEST_SHA256}, archive "
                    f"SHA-256 {SPARKLE_ARCHIVE_SHA256}, and license SHA-256 "
                    f"{SPARKLE_LICENSE_SHA256}; legal conclusion is not asserted."
                ),
                expected_supplier="Organization: Sparkle Project",
                expected_download_location=SPARKLE_REPOSITORY,
                expected_version=SPARKLE_VERSION,
            )
        )
        failures.extend(
            validate_package(
                packages[1],
                "SPDXRef-Package-MacCompanionKit",
                "MacCompanionKit",
                "LIBRARY",
                "First-party in-repository Swift package; no external package dependency.",
            )
        )
        if all(isinstance(package, dict) for package in packages):
            if packages[0].get("versionInfo") != packages[1].get("versionInfo"):
                failures.append("versionMismatch")
            if name_match is not None and packages[0].get("versionInfo") != name_match.group(
                "version"
            ):
                failures.append("documentVersionMismatch")
    expected_relationships = [
        {
            "spdxElementId": "SPDXRef-DOCUMENT",
            "relationshipType": "DESCRIBES",
            "relatedSpdxElement": "SPDXRef-Package-MacCompanion",
        },
        {
            "spdxElementId": "SPDXRef-Package-MacCompanion",
            "relationshipType": "CONTAINS",
            "relatedSpdxElement": "SPDXRef-Package-MacCompanionKit",
        },
        {
            "spdxElementId": "SPDXRef-Package-MacCompanionKit",
            "relationshipType": "DEPENDS_ON",
            "relatedSpdxElement": "NONE",
        },
        {
            "spdxElementId": "SPDXRef-Package-MacCompanion",
            "relationshipType": "DEPENDS_ON",
            "relatedSpdxElement": "SPDXRef-Package-Sparkle",
        },
    ]
    relationships = value["relationships"]
    if (
        not isinstance(relationships, list)
        or any(not exact_keys(item, RELATIONSHIP_KEYS) for item in relationships)
        or relationships != expected_relationships
    ):
        failures.append("relationshipBoundary")
    return sorted(set(failures))


def validate_fixtures() -> tuple[int, list[str]]:
    index = load_json(FIXTURE_INDEX)
    if not exact_keys(index, {"profile", "cases"}) or index.get(
        "profile"
    ) != "maccompanion.source-sbom-fixtures.v0" or not isinstance(
        index.get("cases"), list
    ):
        return 0, ["fixtureIndexSchema"]
    failures: list[str] = []
    seen: set[str] = set()
    for case in index["cases"]:
        if not exact_keys(case, {"path", "expectedCodes"}):
            failures.append("fixtureCaseSchema")
            continue
        relative = case["path"]
        expected = case["expectedCodes"]
        if (
            not isinstance(relative, str)
            or not re.fullmatch(r"[a-z0-9-]+\.json", relative)
            or relative in seen
            or not isinstance(expected, list)
            or expected != sorted(set(expected))
            or any(not isinstance(code, str) or not code for code in expected)
        ):
            failures.append("fixtureCaseValue")
            continue
        seen.add(relative)
        path = FIXTURE_INDEX.parent / relative
        if not path.is_file():
            failures.append("fixtureMissing")
            continue
        actual = validate_document(load_json(path))
        if actual != expected:
            failures.append(
                f"fixtureMismatch:{relative}:expected={expected}:actual={actual}"
            )
    return len(seen), failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("documents", nargs="*", type=Path)
    arguments = parser.parse_args()
    try:
        count, failures = validate_fixtures()
        for document in arguments.documents:
            codes = validate_document(load_json(document))
            failures.extend(f"{document}:{code}" for code in codes)
        if failures:
            for failure in failures:
                print(failure)
            return 1
        suffix = f" and {len(arguments.documents)} document(s)" if arguments.documents else ""
        print(f"validated {count} source SBOM fixture(s){suffix}")
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"source SBOM validation failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
