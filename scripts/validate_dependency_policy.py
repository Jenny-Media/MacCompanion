#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path, PurePosixPath
from typing import Any


REPOSITORY = Path(__file__).resolve().parents[1]
POLICY_PATH = REPOSITORY / "spec" / "dependency-policy" / "v0" / "policy.json"
FIXTURE_INDEX = REPOSITORY / "Tests" / "System" / "DependencyPolicy" / "manifest.json"
IGNORED_PARTS = {".build", ".swiftpm", "DerivedData"}


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
            "remoteDependenciesAllowed",
            "binaryTargetsAllowed",
            "buildToolPluginsAllowed",
            "packages",
        },
    ):
        return ["policySchema"]
    if value["profile"] != "maccompanion.swift-dependency-policy.v0":
        failures.append("policyProfile")
    for key in (
        "remoteDependenciesAllowed",
        "binaryTargetsAllowed",
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


def repository_bypass_failures() -> list[str]:
    failures: list[str] = []
    for path in REPOSITORY.rglob("Package.resolved"):
        if not any(part in IGNORED_PARTS for part in path.relative_to(REPOSITORY).parts):
            failures.append(f"remoteDependencyLockfileDenied:{path.relative_to(REPOSITORY)}")
    for project in REPOSITORY.rglob("project.pbxproj"):
        if not any(part in IGNORED_PARTS for part in project.relative_to(REPOSITORY).parts):
            if "XCRemoteSwiftPackageReference" in project.read_text(
                encoding="utf-8", errors="replace"
            ):
                failures.append(
                    f"xcodeRemoteDependencyDenied:{project.relative_to(REPOSITORY)}"
                )
    return failures


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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixtures-only", action="store_true")
    arguments = parser.parse_args()
    try:
        policy = load_json(POLICY_PATH)
        failures = validate_policy(policy)
        fixture_count, fixture_failures = validate_fixtures(policy)
        failures.extend(fixture_failures)
        package_count = 0
        if not arguments.fixtures_only and not failures:
            snapshot = live_snapshot()
            package_count = len(snapshot["packages"])
            failures.extend(compare(policy, snapshot))
            failures.extend(repository_bypass_failures())
        if failures:
            for failure in sorted(set(failures)):
                print(failure)
            return 1
        if arguments.fixtures_only:
            print(f"validated {fixture_count} dependency policy fixture(s)")
        else:
            print(
                f"validated {package_count} Swift package manifest(s) and "
                f"{fixture_count} dependency policy fixture(s): closed local-only graph"
            )
        return 0
    except (OSError, ValueError, json.JSONDecodeError, subprocess.SubprocessError) as error:
        print(f"dependency policy validation failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
