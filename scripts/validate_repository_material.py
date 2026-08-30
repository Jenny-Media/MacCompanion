#!/usr/bin/env python3

from __future__ import annotations

import base64
import binascii
import json
import os
import posixpath
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath
from typing import Any


REPOSITORY = Path(__file__).resolve().parents[1]
FIXTURE_INDEX = REPOSITORY / "Tests" / "System" / "RepositoryMaterial" / "manifest.json"
MAX_BYTES = 8 * 1024 * 1024
FORBIDDEN_CREDENTIAL_SUFFIXES = {
    ".cer",
    ".der",
    ".key",
    ".mobileprovision",
    ".p12",
    ".p8",
    ".pem",
    ".provisionprofile",
}
FORBIDDEN_DATABASE_SUFFIXES = {".db", ".sqlite", ".sqlite3"}
PRIVATE_KEY = re.compile(
    b"-----BEGIN " + b"(?:ENCRYPTED |RSA |EC |OPENSSH )?" + b"PRIVATE KEY-----"
)
CERTIFICATE = re.compile(b"-----BEGIN " + b"CERTIFICATE-----")
CONTENT_PATTERNS: tuple[tuple[str, re.Pattern[bytes]], ...] = (
    (
        "githubCredential",
        re.compile(rb"\b(?:gh[pousr]_[A-Za-z0-9]{30,255}|github_pat_[A-Za-z0-9_]{40,255})\b"),
    ),
    (
        "openAICredential",
        re.compile(rb"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{20,255}\b"),
    ),
    ("awsCredential", re.compile(rb"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("slackCredential", re.compile(rb"\bxox[baprs]-[A-Za-z0-9-]{20,255}\b")),
    ("stripeCredential", re.compile(rb"\b(?:sk|rk)_live_[A-Za-z0-9]{20,255}\b")),
    ("googleCredential", re.compile(rb"\bAIza[0-9A-Za-z_-]{35}\b")),
    (
        "trackedSigningIdentity",
        re.compile(rb"\bDEVELOPMENT_TEAM\s*=\s*[A-Z0-9]{10}\s*;"),
    ),
    (
        "trackedSigningIdentity",
        re.compile(rb"\bPROVISIONING_PROFILE_SPECIFIER\s*=\s*[^;\r\n]{1,200};"),
    ),
    (
        "trackedSigningIdentity",
        re.compile(rb"\bCODE_SIGN_IDENTITY\s*=\s*\"?[A-Za-z][^;\r\n\"]{2,100}\"?\s*;"),
    ),
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


def exact_keys(value: Any, keys: set[str]) -> bool:
    return isinstance(value, dict) and set(value) == keys


def safe_fixture_path(value: Any) -> bool:
    if not isinstance(value, str) or not value or "\\" in value:
        return False
    path = PurePosixPath(value)
    return not path.is_absolute() and all(
        part not in {"", ".", ".."} for part in path.parts
    )


def inspect(path_text: str, content: bytes) -> list[str]:
    failures: list[str] = []
    path = PurePosixPath(path_text)
    lower_name = path.name.lower()
    lower_parts = {part.lower() for part in path.parts}
    suffix = PurePosixPath(lower_name).suffix
    if suffix in FORBIDDEN_CREDENTIAL_SUFFIXES:
        failures.append("forbiddenCredentialFile")
    if suffix in FORBIDDEN_DATABASE_SUFFIXES:
        failures.append("forbiddenDataStore")
    if lower_name == ".env" or (
        lower_name.startswith(".env.") and lower_name != ".env.example"
    ):
        failures.append("forbiddenEnvironmentFile")
    if "secrets" in lower_parts or ".secrets" in lower_parts:
        failures.append("forbiddenSecretDirectory")
    if PRIVATE_KEY.search(content):
        failures.append("privateKeyMaterial")
    if CERTIFICATE.search(content):
        failures.append("certificateMaterial")
    for code, pattern in CONTENT_PATTERNS:
        if pattern.search(content):
            failures.append(code)
    return sorted(set(failures))


def validate_fixtures() -> tuple[int, list[str]]:
    with FIXTURE_INDEX.open("r", encoding="utf-8") as handle:
        index = json.load(handle, object_pairs_hook=object_without_duplicates)
    if not exact_keys(index, {"profile", "cases"}) or index.get(
        "profile"
    ) != "maccompanion.repository-material-fixtures.v0" or not isinstance(
        index.get("cases"), list
    ):
        return 0, ["fixtureIndexSchema"]
    failures: list[str] = []
    seen: set[str] = set()
    for case in index["cases"]:
        if not exact_keys(case, {"id", "path", "contentBase64", "expectedCodes"}):
            failures.append("fixtureCaseSchema")
            continue
        case_id = case["id"]
        path = case["path"]
        encoded = case["contentBase64"]
        expected = case["expectedCodes"]
        if (
            not isinstance(case_id, str)
            or re.fullmatch(r"[a-z0-9-]{1,64}", case_id) is None
            or case_id in seen
            or not safe_fixture_path(path)
            or not isinstance(encoded, str)
            or not isinstance(expected, list)
            or expected != sorted(set(expected))
            or any(not isinstance(code, str) or not code for code in expected)
        ):
            failures.append("fixtureCaseValue")
            continue
        seen.add(case_id)
        try:
            content = base64.b64decode(encoded, validate=True)
        except (ValueError, binascii.Error):
            failures.append("fixtureContentEncoding")
            continue
        actual = inspect(path, content)
        if actual != expected:
            failures.append(
                f"fixtureMismatch:{case_id}:expected={expected}:actual={actual}"
            )
    return len(seen), failures


def git_inventory() -> list[str]:
    completed = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=REPOSITORY,
        capture_output=True,
        timeout=20,
        check=False,
    )
    if completed.returncode != 0:
        raise ValueError("git inventory failed")
    raw_paths = completed.stdout.split(b"\0")
    paths = {os.fsdecode(path) for path in raw_paths if path}
    deleted = subprocess.run(
        ["git", "ls-files", "-z", "--deleted"],
        cwd=REPOSITORY,
        capture_output=True,
        timeout=20,
        check=False,
    )
    if deleted.returncode != 0:
        raise ValueError("git deleted inventory failed")
    deleted_paths = {
        os.fsdecode(path) for path in deleted.stdout.split(b"\0") if path
    }
    # The live scan follows the working tree, including untracked material.
    # Deleted tracked paths remain covered by the immutable history scan but
    # have no live file to resolve or inspect.
    return sorted(paths - deleted_paths)


def history_inventory() -> list[tuple[str, str, str]]:
    commits = subprocess.run(
        ["git", "rev-list", "--all"],
        cwd=REPOSITORY,
        capture_output=True,
        text=True,
        timeout=20,
        check=False,
    )
    if commits.returncode != 0:
        raise ValueError("git history enumeration failed")
    entries: set[tuple[str, str, str]] = set()
    for commit in commits.stdout.splitlines():
        if re.fullmatch(r"[0-9a-f]{40}", commit) is None:
            raise ValueError("git history returned an invalid commit identifier")
        tree = subprocess.run(
            ["git", "ls-tree", "-r", "-z", "--full-tree", commit],
            cwd=REPOSITORY,
            capture_output=True,
            timeout=20,
            check=False,
        )
        if tree.returncode != 0:
            raise ValueError(f"git tree enumeration failed for {commit}")
        for record in tree.stdout.split(b"\0"):
            if not record:
                continue
            try:
                metadata, raw_path = record.split(b"\t", maxsplit=1)
                mode, object_type, raw_oid = metadata.split(b" ", maxsplit=2)
            except ValueError as error:
                raise ValueError("git tree returned a malformed record") from error
            if object_type != b"blob":
                continue
            oid = raw_oid.decode("ascii")
            if re.fullmatch(r"[0-9a-f]{40,64}", oid) is None:
                raise ValueError("git tree returned an invalid blob identifier")
            entries.add((mode.decode("ascii"), oid, os.fsdecode(raw_path)))
    return sorted(entries, key=lambda item: (item[2], item[1], item[0]))


def git_blob(oid: str) -> bytes:
    size_result = subprocess.run(
        ["git", "cat-file", "-s", oid],
        cwd=REPOSITORY,
        capture_output=True,
        text=True,
        timeout=20,
        check=False,
    )
    if size_result.returncode != 0 or not size_result.stdout.strip().isdigit():
        raise ValueError(f"git blob size failed for {oid}")
    size = int(size_result.stdout.strip())
    if size > MAX_BYTES:
        raise OverflowError
    content_result = subprocess.run(
        ["git", "cat-file", "blob", oid],
        cwd=REPOSITORY,
        capture_output=True,
        timeout=20,
        check=False,
    )
    if content_result.returncode != 0 or len(content_result.stdout) != size:
        raise ValueError(f"git blob read failed for {oid}")
    return content_result.stdout


def validate_history() -> tuple[int, list[str]]:
    failures: list[str] = []
    entries = history_inventory()
    blob_cache: dict[str, bytes | None] = {}
    for mode, oid, path in entries:
        if oid not in blob_cache:
            try:
                blob_cache[oid] = git_blob(oid)
            except OverflowError:
                blob_cache[oid] = None
        content = blob_cache[oid]
        label = f"history:{oid[:12]}:{path}"
        if content is None:
            failures.append(f"{label}:unscannedOversizeBlob")
            continue
        if mode == "120000":
            target = os.fsdecode(content)
            normalized = posixpath.normpath(
                posixpath.join(posixpath.dirname(path), target)
            )
            if target.startswith("/") or normalized == ".." or normalized.startswith("../"):
                failures.append(f"{label}:historicalSymlinkEscapesRepository")
        for code in inspect(path, content):
            failures.append(f"{label}:{code}")
    return len(entries), failures


def validate_live_files() -> tuple[int, list[str]]:
    failures: list[str] = []
    paths = git_inventory()
    repository = REPOSITORY.resolve()
    for relative in paths:
        path = REPOSITORY / relative
        try:
            resolved = path.resolve(strict=True)
            resolved.relative_to(repository)
        except (OSError, ValueError):
            failures.append(f"{relative}:symlinkOrPathEscapesRepository")
            continue
        if not resolved.is_file():
            failures.append(f"{relative}:notRegularFile")
            continue
        size = resolved.stat().st_size
        if size > MAX_BYTES:
            failures.append(f"{relative}:unscannedOversizeFile")
            continue
        content = resolved.read_bytes()
        for code in inspect(relative, content):
            failures.append(f"{relative}:{code}")
    return len(paths), failures


def main() -> int:
    try:
        fixture_count, failures = validate_fixtures()
        file_count, live_failures = validate_live_files()
        history_count, history_failures = validate_history()
        failures.extend(live_failures)
        failures.extend(history_failures)
        if failures:
            for failure in failures:
                print(failure)
            return 1
        print(
            f"validated {file_count} repository file(s), {history_count} historical "
            f"blob-path(s), and "
            f"{fixture_count} repository-material fixture(s)"
        )
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"repository material validation failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
