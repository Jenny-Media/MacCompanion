#!/usr/bin/env python3

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import plistlib
import re
import stat
import subprocess
import sys
from pathlib import Path, PurePosixPath
from typing import Any

from update_policy import (
    SPARKLE_ARCHIVE_SHA256,
    SPARKLE_LICENSE_SHA256,
    SPARKLE_MANIFEST_SHA256,
    SPARKLE_REPOSITORY,
    SPARKLE_REVISION,
    SPARKLE_VERSION,
)


REPOSITORY = Path(__file__).resolve().parents[1]
POLICY_PATH = REPOSITORY / "spec" / "dependency-policy" / "v0" / "policy.json"
FIXTURE_INDEX = REPOSITORY / "Tests" / "System" / "DependencyPolicy" / "manifest.json"
XCODE_FIXTURE_INDEX = REPOSITORY / "Tests" / "System" / "DependencyPolicy" / "xcode-manifest.json"
IGNORED_PARTS = {".build", ".swiftpm", "DerivedData"}
SANITIZER_PATH = "scripts/strip_sparkle_xpc_services.sh"
SANITIZER_SHA256 = "e1037af8274debb51fafa5118f6d8563030ba7bb63290fe5994daff71408ce5d"
LOCKFILE_PATH = "MacCompanion.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"


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


def exact_keys(value: Any, expected: set[str]) -> bool:
    return isinstance(value, dict) and set(value) == expected


def safe_repository_path(value: Any) -> bool:
    if not isinstance(value, str) or not value or "\\" in value:
        return False
    path = PurePosixPath(value)
    return not path.is_absolute() and path.parts and all(
        part not in {"", ".", ".."} for part in path.parts
    )


def validate_policy(value: Any) -> list[str]:
    failures: list[str] = []
    if not exact_keys(
        value,
        {
            "profile",
            "unlistedRemoteDependenciesAllowed",
            "unlistedBinaryTargetsAllowed",
            "buildToolPluginsAllowed",
            "packages",
            "xcodePackages",
        },
    ):
        return ["policySchema"]
    if value["profile"] != "maccompanion.swift-dependency-policy.v1":
        failures.append("policyProfile")
    for key in (
        "unlistedRemoteDependenciesAllowed",
        "unlistedBinaryTargetsAllowed",
        "buildToolPluginsAllowed",
    ):
        if value[key] is not False:
            failures.append("policyMustDenyExternalCode")
    packages = value["packages"]
    if not isinstance(packages, list) or not packages:
        return failures + ["policyPackages"]
    seen_paths: set[str] = set()
    previous_path: str | None = None
    for package in packages:
        if not exact_keys(
            package,
            {"path", "name", "identity", "toolsVersion", "localDependencies"},
        ):
            failures.append("policyPackageSchema")
            continue
        path = package["path"]
        if not safe_repository_path(path):
            failures.append("policyPackagePath")
            continue
        if path in seen_paths:
            failures.append("policyDuplicatePackagePath")
        seen_paths.add(path)
        if previous_path is not None and path <= previous_path:
            failures.append("policyPackageOrder")
        previous_path = path
        if not isinstance(package["name"], str) or not package["name"]:
            failures.append("policyPackageName")
        if (
            not isinstance(package["identity"], str)
            or not package["identity"]
            or package["identity"] != package["identity"].lower()
        ):
            failures.append("policyPackageIdentity")
        if not isinstance(package["toolsVersion"], str) or not package["toolsVersion"]:
            failures.append("policyToolsVersion")
        dependencies = package["localDependencies"]
        if (
            not isinstance(dependencies, list)
            or any(not safe_repository_path(item) for item in dependencies)
            or dependencies != sorted(set(dependencies))
        ):
            failures.append("policyLocalDependencies")
    for package in packages:
        if isinstance(package, dict):
            for dependency in package.get("localDependencies", []):
                if dependency not in seen_paths:
                    failures.append("policyLocalDependencyNotPackage")
    xcode_packages = value["xcodePackages"]
    if not isinstance(xcode_packages, list) or len(xcode_packages) != 1:
        failures.append("policyXcodePackages")
    else:
        admitted = xcode_packages[0]
        expected = {
            "archiveBuildSanitizerPath": SANITIZER_PATH,
            "archiveBuildSanitizerSHA256": SANITIZER_SHA256,
            "archiveSHA256": SPARKLE_ARCHIVE_SHA256,
            "binaryTarget": "Sparkle",
            "consumerTarget": "MacCompanion",
            "identity": "sparkle",
            "licenseSHA256": SPARKLE_LICENSE_SHA256,
            "lockfilePath": LOCKFILE_PATH,
            "manifestSHA256": SPARKLE_MANIFEST_SHA256,
            "name": "Sparkle",
            "product": "Sparkle",
            "repository": SPARKLE_REPOSITORY,
            "requirement": "exactVersion",
            "resolvedRevision": SPARKLE_REVISION,
            "version": SPARKLE_VERSION,
        }
        if admitted != expected:
            failures.append("policyXcodePackageAuthority")
    return sorted(set(failures))


def validate_snapshot_schema(value: Any) -> list[str]:
    if not exact_keys(value, {"profile", "packages"}):
        return ["snapshotSchema"]
    if value["profile"] != "maccompanion.swift-dependency-observation.v0":
        return ["snapshotProfile"]
    if not isinstance(value["packages"], list):
        return ["snapshotPackages"]
    failures: list[str] = []
    for package in value["packages"]:
        if not exact_keys(
            package,
            {"path", "name", "toolsVersion", "dependencies", "externalArtifacts"},
        ):
            failures.append("snapshotPackageSchema")
            continue
        if not all(
            isinstance(package[key], str) and package[key]
            for key in ("path", "name", "toolsVersion")
        ):
            failures.append("snapshotPackageValue")
        if not isinstance(package["dependencies"], list):
            failures.append("snapshotDependencies")
        else:
            for dependency in package["dependencies"]:
                if not isinstance(dependency, dict) or dependency.get("kind") not in {
                    "local",
                    "remote",
                    "unknown",
                }:
                    failures.append("snapshotDependencySchema")
                    continue
                expected = (
                    {"kind", "identity", "path"}
                    if dependency["kind"] == "local"
                    else {"kind", "identity", "location"}
                )
                if set(dependency) != expected or any(
                    not isinstance(dependency[key], str) or not dependency[key]
                    for key in expected - {"kind"}
                ):
                    failures.append("snapshotDependencySchema")
        if not isinstance(package["externalArtifacts"], list):
            failures.append("snapshotExternalArtifacts")
        else:
            for artifact in package["externalArtifacts"]:
                if not exact_keys(artifact, {"kind", "name"}) or artifact.get(
                    "kind"
                ) not in {"binaryTarget", "buildToolPlugin"} or not isinstance(
                    artifact.get("name"), str
                ) or not artifact["name"]:
                    failures.append("snapshotExternalArtifactSchema")
    return sorted(set(failures))


def compare(policy: dict[str, Any], snapshot: dict[str, Any]) -> list[str]:
    failures = validate_snapshot_schema(snapshot)
    if failures:
        return failures
    expected = {package["path"]: package for package in policy["packages"]}
    observed: dict[str, dict[str, Any]] = {}
    for package in snapshot["packages"]:
        path = package["path"]
        if path in observed:
            failures.append("duplicatePackagePath")
            continue
        observed[path] = package
    for path in sorted(set(expected) - set(observed)):
        failures.append("missingPackage")
    for path in sorted(set(observed) - set(expected)):
        failures.append("unexpectedPackage")
    for path in sorted(set(expected) & set(observed)):
        wanted = expected[path]
        actual = observed[path]
        if actual["name"] != wanted["name"]:
            failures.append("packageNameMismatch")
        if actual["toolsVersion"] != wanted["toolsVersion"]:
            failures.append("toolsVersionMismatch")
        actual_local: set[str] = set()
        seen_edges: set[tuple[str, str, str]] = set()
        for dependency in actual["dependencies"]:
            if dependency["kind"] != "local":
                failures.append("remoteDependencyDenied")
                continue
            edge = (dependency["kind"], dependency["identity"], dependency["path"])
            if edge in seen_edges:
                failures.append("duplicateDependency")
                continue
            seen_edges.add(edge)
            dependency_path = dependency["path"]
            candidate = (REPOSITORY / path / dependency_path).resolve()
            try:
                relative = candidate.relative_to(REPOSITORY.resolve()).as_posix()
            except ValueError:
                failures.append("localDependencyEscapesRepository")
                continue
            actual_local.add(relative)
            destination = expected.get(relative)
            if destination is not None and dependency["identity"] != destination["identity"]:
                failures.append("localDependencyIdentityMismatch")
        wanted_local = set(wanted["localDependencies"])
        if actual_local - wanted_local:
            failures.append("unexpectedLocalDependency")
        if wanted_local - actual_local:
            failures.append("missingLocalDependency")
        if actual["externalArtifacts"]:
            failures.append("externalArtifactDenied")
    return sorted(set(failures))


def dependency_records(raw_dependencies: Any, package_path: Path) -> list[dict[str, str]]:
    records: list[dict[str, str]] = []
    if not isinstance(raw_dependencies, list):
        return [{"kind": "unknown", "identity": "invalid", "location": "invalid"}]
    for wrapper in raw_dependencies:
        if not isinstance(wrapper, dict) or len(wrapper) != 1:
            records.append(
                {"kind": "unknown", "identity": "invalid", "location": "invalid"}
            )
            continue
        kind, entries = next(iter(wrapper.items()))
        if not isinstance(entries, list):
            entries = []
        for entry in entries:
            if not isinstance(entry, dict):
                records.append(
                    {"kind": "unknown", "identity": "invalid", "location": kind}
                )
                continue
            identity = str(entry.get("identity") or "unknown")
            if kind == "fileSystem":
                raw_path = str(entry.get("path") or "")
                dependency_path = Path(raw_path)
                if dependency_path.is_absolute():
                    try:
                        raw_path = os.path.relpath(dependency_path, package_path)
                    except ValueError:
                        pass
                records.append(
                    {"kind": "local", "identity": identity, "path": raw_path}
                )
            else:
                location = str(
                    entry.get("location")
                    or entry.get("url")
                    or entry.get("package")
                    or kind
                )
                records.append(
                    {"kind": "remote" if kind in {"sourceControl", "registry"} else "unknown", "identity": identity, "location": location}
                )
    return sorted(records, key=lambda item: json.dumps(item, sort_keys=True))


def dump_package(package_path: Path) -> dict[str, Any]:
    command = ["swift", "package", "--package-path", str(package_path)]
    if os.environ.get("MACCOMPANION_DISABLE_SWIFTPM_SANDBOX") == "1":
        command.append("--disable-sandbox")
    command.append("dump-package")
    completed = subprocess.run(
        command,
        cwd=REPOSITORY,
        env=os.environ.copy(),
        text=True,
        capture_output=True,
        timeout=30,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip().splitlines()
        reason = detail[-1] if detail else f"exit {completed.returncode}"
        raise ValueError(f"manifest evaluation failed for {package_path}: {reason}")
    return json.loads(completed.stdout, object_pairs_hook=object_without_duplicates)


def live_snapshot() -> dict[str, Any]:
    manifests = sorted(
        path
        for path in REPOSITORY.rglob("Package.swift")
        if not any(part in IGNORED_PARTS for part in path.relative_to(REPOSITORY).parts)
    )
    packages: list[dict[str, Any]] = []
    for manifest in manifests:
        package_path = manifest.parent
        raw = dump_package(package_path)
        tools = raw.get("toolsVersion")
        tools_version = tools.get("_version") if isinstance(tools, dict) else None
        targets = raw.get("targets") if isinstance(raw.get("targets"), list) else []
        artifacts: list[dict[str, str]] = []
        for target in targets:
            if not isinstance(target, dict):
                continue
            target_type = target.get("type")
            if target_type == "binary":
                artifacts.append(
                    {"kind": "binaryTarget", "name": str(target.get("name") or "unknown")}
                )
            elif target_type == "plugin":
                artifacts.append(
                    {"kind": "buildToolPlugin", "name": str(target.get("name") or "unknown")}
                )
        packages.append(
            {
                "path": package_path.relative_to(REPOSITORY).as_posix(),
                "name": raw.get("name"),
                "toolsVersion": tools_version,
                "dependencies": dependency_records(raw.get("dependencies"), package_path),
                "externalArtifacts": sorted(artifacts, key=lambda item: (item["kind"], item["name"])),
            }
        )
    return {
        "profile": "maccompanion.swift-dependency-observation.v0",
        "packages": packages,
    }


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def expected_xcode_state() -> dict[str, Any]:
    return {
        "consumers": [{"product": "Sparkle", "target": "MacCompanion"}],
        "infoPlist": {
            "MacCompanionUpdateAuthorityProfile": (
                "$(MACCOMPANION_UPDATE_AUTHORITY_PROFILE)"
            ),
            "MacCompanionUpdateChannel": "$(MACCOMPANION_UPDATE_CHANNEL)",
            "MacCompanionUpdateFeedURL": "$(MACCOMPANION_UPDATE_FEED_URL)",
            "NSBonjourServices": ["_maccompanion._tcp"],
            "NSLocalNetworkUsageDescription": (
                "Let your paired devices find and connect directly to this Mac on "
                "your local network. Mac Companion does not use a vendor relay."
            ),
            "SUAllowsAutomaticUpdates": False,
            "SUAutomaticallyUpdate": False,
            "SUEnableAutomaticChecks": False,
            "SUEnableSystemProfiling": False,
            "SUPublicEDKey": "$(MACCOMPANION_SPARKLE_PUBLIC_ED_KEY)",
            "SURequireSignedFeed": True,
            "SUSendProfileInfo": False,
            "SUVerifyUpdateBeforeExtraction": True,
        },
        "lock": {
            "identity": "sparkle",
            "kind": "remoteSourceControl",
            "location": SPARKLE_REPOSITORY,
            "originHashValid": True,
            "revision": SPARKLE_REVISION,
            "version": SPARKLE_VERSION,
        },
        "lockfilePaths": [LOCKFILE_PATH],
        "packages": {
            "MacCompanionKit": {"path": "Packages/MacCompanionKit"},
            "Sparkle": {
                "exactVersion": SPARKLE_VERSION,
                "url": SPARKLE_REPOSITORY,
            },
        },
        "postBuildScripts": [
            {
                "basedOnDependencyAnalysis": False,
                "name": "Strip unused Sparkle XPC services",
                "script": f'/bin/zsh "${{SRCROOT}}/{SANITIZER_PATH}"\n',
            }
        ],
        "projectRemoteReferences": [
            {
                "exactRequirementCount": 1,
                "path": "MacCompanion.xcodeproj/project.pbxproj",
                "remoteReferenceCount": 1,
                "repositoryCount": 1,
                "sparkleProductBindingCount": 1,
                "versionCount": 1,
            }
        ],
        "sanitizer": {
            "path": SANITIZER_PATH,
            "regularSingleLink": True,
            "sha256": SANITIZER_SHA256,
        },
        "settings": {
            "ENABLE_APP_SANDBOX": False,
            "GENERATE_INFOPLIST_FILE": False,
            "INFOPLIST_FILE": "Apps/MacCompanionMac/Info.plist",
        },
    }


def _xcodegen_spec() -> dict[str, Any]:
    completed = subprocess.run(
        [
            "xcodegen",
            "dump",
            "--spec",
            "project.yml",
            "--type",
            "json",
            "--no-env",
        ],
        cwd=REPOSITORY,
        capture_output=True,
        check=False,
        text=True,
        timeout=30,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip().splitlines()
        reason = detail[-1] if detail else f"exit {completed.returncode}"
        raise ValueError(f"XcodeGen spec evaluation failed: {reason}")
    return json.loads(completed.stdout, object_pairs_hook=object_without_duplicates)


def _lock_state(lockfile: Path) -> dict[str, Any]:
    value = load_json(lockfile)
    if not exact_keys(value, {"originHash", "pins", "version"}):
        return {"schema": "invalid"}
    pins = value["pins"]
    if value["version"] != 3 or not isinstance(pins, list) or len(pins) != 1:
        return {"schema": "invalid"}
    pin = pins[0]
    if not exact_keys(pin, {"identity", "kind", "location", "state"}) or not exact_keys(
        pin.get("state"), {"revision", "version"}
    ):
        return {"schema": "invalid"}
    origin_hash = value["originHash"]
    return {
        "identity": pin["identity"],
        "kind": pin["kind"],
        "location": pin["location"],
        "originHashValid": isinstance(origin_hash, str)
        and re.fullmatch(r"[0-9a-f]{64}", origin_hash) is not None,
        "revision": pin["state"]["revision"],
        "version": pin["state"]["version"],
    }


def live_xcode_state() -> dict[str, Any]:
    spec = _xcodegen_spec()
    targets = spec.get("targets") if isinstance(spec.get("targets"), dict) else {}
    consumers: list[dict[str, str]] = []
    for target_name, target in targets.items():
        if not isinstance(target_name, str) or not isinstance(target, dict):
            continue
        dependencies = target.get("dependencies")
        if not isinstance(dependencies, list):
            continue
        for dependency in dependencies:
            if isinstance(dependency, dict) and dependency.get("package") == "Sparkle":
                consumers.append(
                    {
                        "product": str(dependency.get("product") or ""),
                        "target": target_name,
                    }
                )
    consumers.sort(key=lambda item: (item["target"], item["product"]))

    lockfiles = sorted(
        path
        for path in REPOSITORY.rglob("Package.resolved")
        if not any(part in IGNORED_PARTS for part in path.relative_to(REPOSITORY).parts)
    )
    lockfile_paths = [path.relative_to(REPOSITORY).as_posix() for path in lockfiles]
    lock = _lock_state(lockfiles[0]) if len(lockfiles) == 1 else {"schema": "invalid"}

    remote_references: list[dict[str, Any]] = []
    for project in sorted(REPOSITORY.rglob("project.pbxproj")):
        if any(part in IGNORED_PARTS for part in project.relative_to(REPOSITORY).parts):
            continue
        content = project.read_text(encoding="utf-8", errors="replace")
        reference_count = content.count("isa = XCRemoteSwiftPackageReference;")
        if reference_count == 0:
            continue
        remote_references.append(
            {
                "exactRequirementCount": content.count("kind = exactVersion;"),
                "path": project.relative_to(REPOSITORY).as_posix(),
                "remoteReferenceCount": reference_count,
                "repositoryCount": content.count(
                    f'repositoryURL = "{SPARKLE_REPOSITORY}";'
                ),
                "sparkleProductBindingCount": len(
                    re.findall(
                        r"isa = XCSwiftPackageProductDependency;\s+package = .*?"
                        r"XCRemoteSwiftPackageReference \"Sparkle\".*?;\s+"
                        r"productName = Sparkle;",
                        content,
                        flags=re.DOTALL,
                    )
                ),
                "versionCount": content.count(f"version = {SPARKLE_VERSION};"),
            }
        )

    sanitizer = REPOSITORY / SANITIZER_PATH
    try:
        metadata = sanitizer.lstat()
        sanitizer_state = {
            "path": SANITIZER_PATH,
            "regularSingleLink": stat.S_ISREG(metadata.st_mode)
            and not sanitizer.is_symlink()
            and metadata.st_nlink == 1,
            "sha256": _sha256(sanitizer),
        }
    except OSError:
        sanitizer_state = {
            "path": SANITIZER_PATH,
            "regularSingleLink": False,
            "sha256": "unavailable",
        }

    mac_target = targets.get("MacCompanion") if isinstance(targets, dict) else None
    mac_target = mac_target if isinstance(mac_target, dict) else {}
    settings_wrapper = mac_target.get("settings")
    settings_wrapper = settings_wrapper if isinstance(settings_wrapper, dict) else {}
    settings = settings_wrapper.get("base")
    settings = settings if isinstance(settings, dict) else {}
    info_plist_path = REPOSITORY / "Apps" / "MacCompanionMac" / "Info.plist"
    try:
        info_plist = plistlib.loads(info_plist_path.read_bytes())
    except (OSError, plistlib.InvalidFileException, ValueError):
        info_plist = {}
    return {
        "consumers": consumers,
        "infoPlist": {
            "MacCompanionUpdateAuthorityProfile": info_plist.get(
                "MacCompanionUpdateAuthorityProfile"
            ),
            "MacCompanionUpdateChannel": info_plist.get(
                "MacCompanionUpdateChannel"
            ),
            "MacCompanionUpdateFeedURL": info_plist.get(
                "MacCompanionUpdateFeedURL"
            ),
            "NSBonjourServices": info_plist.get("NSBonjourServices"),
            "NSLocalNetworkUsageDescription": info_plist.get(
                "NSLocalNetworkUsageDescription"
            ),
            "SUAllowsAutomaticUpdates": info_plist.get(
                "SUAllowsAutomaticUpdates"
            ),
            "SUAutomaticallyUpdate": info_plist.get("SUAutomaticallyUpdate"),
            "SUEnableAutomaticChecks": info_plist.get(
                "SUEnableAutomaticChecks"
            ),
            "SUEnableSystemProfiling": info_plist.get("SUEnableSystemProfiling"),
            "SUPublicEDKey": info_plist.get("SUPublicEDKey"),
            "SURequireSignedFeed": info_plist.get("SURequireSignedFeed"),
            "SUSendProfileInfo": info_plist.get("SUSendProfileInfo"),
            "SUVerifyUpdateBeforeExtraction": info_plist.get(
                "SUVerifyUpdateBeforeExtraction"
            ),
        },
        "lock": lock,
        "lockfilePaths": lockfile_paths,
        "packages": spec.get("packages"),
        "postBuildScripts": mac_target.get("postBuildScripts"),
        "projectRemoteReferences": remote_references,
        "sanitizer": sanitizer_state,
        "settings": {
            "ENABLE_APP_SANDBOX": settings.get("ENABLE_APP_SANDBOX"),
            "GENERATE_INFOPLIST_FILE": settings.get("GENERATE_INFOPLIST_FILE"),
            "INFOPLIST_FILE": settings.get("INFOPLIST_FILE"),
        },
    }


def compare_xcode_state(value: Any) -> list[str]:
    expected = expected_xcode_state()
    if not isinstance(value, dict):
        return ["xcodeStateSchema"]
    failures: list[str] = []
    codes = {
        "consumers": "xcodePackageConsumerMismatch",
        "infoPlist": "xcodePackageInfoPlistMismatch",
        "lock": "xcodePackageLockMismatch",
        "lockfilePaths": "xcodePackageLockfileMismatch",
        "packages": "xcodePackageDeclarationMismatch",
        "postBuildScripts": "xcodePackageSanitizerPhaseMismatch",
        "projectRemoteReferences": "xcodeRemoteReferenceMismatch",
        "sanitizer": "xcodePackageSanitizerMismatch",
        "settings": "xcodePackageSettingsMismatch",
    }
    if set(value) != set(expected):
        failures.append("xcodeStateSchema")
    for key, code in codes.items():
        if value.get(key) != expected[key]:
            failures.append(code)
    return sorted(set(failures))


def validate_fixtures(policy: dict[str, Any]) -> tuple[int, list[str]]:
    index = load_json(FIXTURE_INDEX)
    if not exact_keys(index, {"profile", "cases"}) or index.get(
        "profile"
    ) != "maccompanion.swift-dependency-policy-fixtures.v0" or not isinstance(
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
        expected_codes = case["expectedCodes"]
        if (
            not safe_repository_path(relative)
            or relative in seen
            or not isinstance(expected_codes, list)
            or expected_codes != sorted(set(expected_codes))
            or any(not isinstance(code, str) or not code for code in expected_codes)
        ):
            failures.append("fixtureCaseValue")
            continue
        seen.add(relative)
        path = FIXTURE_INDEX.parent / relative
        if not path.is_file() or path.parent != FIXTURE_INDEX.parent:
            failures.append("fixturePath")
            continue
        actual_codes = compare(policy, load_json(path))
        if actual_codes != expected_codes:
            failures.append(
                f"fixtureMismatch:{relative}:expected={expected_codes}:actual={actual_codes}"
            )
    return len(seen), failures


def mutate_xcode_state(value: dict[str, Any], mutation: str) -> None:
    if mutation == "versionRange":
        value["packages"]["Sparkle"].pop("exactVersion")
        value["packages"]["Sparkle"]["from"] = SPARKLE_VERSION
    elif mutation == "repository":
        value["packages"]["Sparkle"]["url"] = "https://example.invalid/Sparkle"
    elif mutation == "revision":
        value["lock"]["revision"] = "0" * 40
    elif mutation == "extraPackage":
        value["packages"]["Other"] = {
            "exactVersion": "1.0.0",
            "url": "https://example.invalid/Other",
        }
    elif mutation == "consumer":
        value["consumers"][0]["target"] = "MacCompanionIOS"
    elif mutation == "extraLockfile":
        value["lockfilePaths"].append("Package.resolved")
    elif mutation == "sanitizerDigest":
        value["sanitizer"]["sha256"] = "0" * 64
    elif mutation == "missingSanitizerPhase":
        value["postBuildScripts"] = []
    elif mutation == "systemProfile":
        value["infoPlist"]["SUSendProfileInfo"] = True
    elif mutation == "sandboxed":
        value["settings"]["ENABLE_APP_SANDBOX"] = True
    elif mutation == "extraRemoteReference":
        value["projectRemoteReferences"][0]["remoteReferenceCount"] = 2
    else:
        raise ValueError(f"unknown Xcode dependency mutation: {mutation}")


def validate_xcode_fixtures() -> tuple[int, list[str]]:
    index = load_json(XCODE_FIXTURE_INDEX)
    if not exact_keys(index, {"profile", "cases"}) or index.get(
        "profile"
    ) != "maccompanion.xcode-dependency-policy-fixtures.v1" or not isinstance(
        index.get("cases"), list
    ):
        return 0, ["xcodeFixtureIndexSchema"]
    failures: list[str] = []
    seen: set[str] = set()
    for case in index["cases"]:
        if not exact_keys(case, {"accepted", "id", "mutation"}):
            failures.append("xcodeFixtureCaseSchema")
            continue
        identifier = case["id"]
        mutation = case["mutation"]
        accepted = case["accepted"]
        if (
            not isinstance(identifier, str)
            or not identifier
            or identifier in seen
            or (mutation is not None and not isinstance(mutation, str))
            or not isinstance(accepted, bool)
        ):
            failures.append("xcodeFixtureCaseValue")
            continue
        seen.add(identifier)
        value = copy.deepcopy(expected_xcode_state())
        if mutation is not None:
            mutate_xcode_state(value, mutation)
        actual = not compare_xcode_state(value)
        if actual != accepted:
            failures.append(f"xcodeFixtureMismatch:{identifier}")
    return len(seen), failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixtures-only", action="store_true")
    arguments = parser.parse_args()
    try:
        policy = load_json(POLICY_PATH)
        failures = validate_policy(policy)
        fixture_count, fixture_failures = validate_fixtures(policy)
        failures.extend(fixture_failures)
        xcode_fixture_count, xcode_fixture_failures = validate_xcode_fixtures()
        failures.extend(xcode_fixture_failures)
        package_count = 0
        if not arguments.fixtures_only and not failures:
            snapshot = live_snapshot()
            package_count = len(snapshot["packages"])
            failures.extend(compare(policy, snapshot))
            failures.extend(compare_xcode_state(live_xcode_state()))
        if failures:
            for failure in sorted(set(failures)):
                print(failure)
            return 1
        if arguments.fixtures_only:
            print(
                f"validated {fixture_count} package-manifest and "
                f"{xcode_fixture_count} Xcode dependency policy fixture(s)"
            )
        else:
            print(
                f"validated {package_count} Swift package manifest(s) and "
                f"{fixture_count} package-manifest plus {xcode_fixture_count} "
                "Xcode dependency policy fixture(s): closed graph with one exact "
                "Sparkle binary authority"
            )
        return 0
    except (OSError, ValueError, json.JSONDecodeError, subprocess.SubprocessError) as error:
        print(f"dependency policy validation failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
